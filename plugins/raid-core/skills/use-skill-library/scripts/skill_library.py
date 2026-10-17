#!/usr/bin/env python3
"""Find, install, check and publish skills on a Skill Library registry.

Talks to the registry's HTTP API with the standard library only. Configuration
comes from the environment so a token never lands in shell history:

  SKILL_LIBRARY_REGISTRY_URL  registry base URL (or --registry)
  SKILL_LIBRARY_TOKEN         personal bearer token (SKILL_LIBRARY_MCP_TOKEN also read)
  SKILL_LIBRARY_WORKSPACE     workspace id (or --workspace; default: the registry's own)

Commands:
  search [query]                       list installable skills
  info <slug>                          show a skill and its latest approved version
  install <slug> --dest <skills-dir>   install the latest approved version
  check <skill-dir>                    compare a local copy with the latest approved version
  publish <skill-dir> [--dry-run]      upload a skill as a draft for review
"""

import argparse
import base64
import hashlib
import io
import json
import os
import re
import shutil
import sys
import tempfile
import urllib.error
import urllib.parse
import urllib.request
import zipfile

SKIP_NAMES = {".git", ".DS_Store", "__pycache__", "node_modules", ".venv", "venv", ".skill-library.json"}
MAX_UPLOAD_BYTES = 10 * 1024 * 1024


class LibraryError(Exception):
    pass


# ---------------------------------------------------------------- HTTP client


class Registry:
    def __init__(self, base_url, token):
        if not base_url:
            raise LibraryError(
                "No registry URL. Set SKILL_LIBRARY_REGISTRY_URL or pass --registry."
            )
        parsed = urllib.parse.urlparse(base_url)
        if parsed.scheme not in ("http", "https") or not parsed.netloc:
            raise LibraryError(f"Registry URL is not an http(s) URL: {base_url}")
        self.base_url = base_url.rstrip("/")
        self.token = token

    def request(self, method, path, body=None, raw=False):
        headers = {"accept": "application/json"}
        data = None
        if body is not None:
            data = json.dumps(body).encode("utf-8")
            headers["content-type"] = "application/json"
        if self.token:
            headers["authorization"] = f"Bearer {self.token}"
        req = urllib.request.Request(self.base_url + path, data=data, headers=headers, method=method)
        try:
            with urllib.request.urlopen(req, timeout=60) as resp:
                payload = resp.read()
        except urllib.error.HTTPError as err:
            raise LibraryError(self._describe_error(err)) from None
        except urllib.error.URLError as err:
            raise LibraryError(f"Cannot reach {self.base_url}: {err.reason}") from None
        return payload if raw else json.loads(payload or b"{}")

    def _describe_error(self, err):
        try:
            message = json.loads(err.read() or b"{}").get("error", "")
        except ValueError:
            message = ""
        hint = ""
        if err.code in (401, 403):
            hint = (
                " Set SKILL_LIBRARY_TOKEN to your personal token (sign in to the registry's web UI;"
                " the Overview page's agent setup prompt carries it)."
                if not self.token
                else " The token was rejected or lacks the role for this action."
            )
        return f"HTTP {err.code}: {message or err.reason}.{hint}"

    def default_workspace(self):
        config = self.request("GET", "/api/config")
        workspace = config.get("branding", {}).get("defaultWorkspaceId")
        if not workspace:
            raise LibraryError("The registry names no default workspace. Pass --workspace.")
        return workspace


def quote(value):
    return urllib.parse.quote(value, safe="")


def package_id(workspace, slug):
    return f"{workspace}-{slug}"


def latest_approved(registry, workspace, slug):
    return registry.request("GET", f"/api/packages/{quote(package_id(workspace, slug))}/latest-approved")[
        "version"
    ]


# ---------------------------------------------------------------- frontmatter


def read_frontmatter(skill_md_text):
    """Parse the flat keys of a SKILL.md frontmatter, plus metadata.version.

    Enough YAML for name/description (plain, quoted, or folded) without a
    third-party parser; the registry runs the strict validation.
    """
    match = re.match(r"^---\r?\n(.*?)\r?\n---\r?\n", skill_md_text, re.S)
    if not match:
        raise LibraryError("SKILL.md has no YAML frontmatter.")
    lines = match.group(1).splitlines()
    fields, i, section = {}, 0, None
    while i < len(lines):
        line = lines[i]
        i += 1
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        indented = line[0] in " \t"
        key_match = re.match(r"^\s*([A-Za-z0-9_-]+):\s*(.*)$", line)
        if not key_match:
            continue
        key, value = key_match.groups()
        if not indented:
            section = key
        elif section != "metadata":
            continue
        else:
            key = f"metadata.{key}"
        if value in (">", ">-", "|", "|-", ">+", "|+"):
            block = []
            while i < len(lines) and (not lines[i].strip() or lines[i][0] in " \t"):
                block.append(lines[i].strip())
                i += 1
            joiner = "\n" if value.startswith("|") else " "
            value = joiner.join(part for part in block if part)
        elif len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
            value = value[1:-1]
        if value:
            fields[key] = value
    return fields


# ---------------------------------------------------------------- install


def safe_member_path(name):
    path = name.replace("\\", "/")
    parts = path.split("/")
    if path.startswith("/") or ".." in parts or re.match(r"^[A-Za-z]:", path):
        raise LibraryError(f"Refusing unsafe path in artifact: {name}")
    return path.rstrip("/")


def skill_root_of(paths):
    roots = {p[: -len("SKILL.md")].rstrip("/") or "." for p in paths if p.endswith("SKILL.md")}
    if len(roots) != 1:
        raise LibraryError("Artifact must contain exactly one SKILL.md.")
    return roots.pop()


def strip_root(path, root):
    return path if root == "." else path[len(root) + 1 :]


def expected_files(version):
    """Per-file sha256 digests the registry recorded when it validated this version."""
    validation = version.get("validation") or {}
    files = {f["path"]: f["digest"] for f in validation.get("files", []) if f.get("kind") == "file"}
    if not files:
        raise LibraryError("The registry returned no file digests for this version; cannot verify it.")
    return files, validation.get("skillRoot") or skill_root_of(files)


def read_verified_artifact(archive_bytes, version):
    """Return {relative path: bytes} for the skill, after checking every file digest."""
    expected, root = expected_files(version)
    found = {}
    with zipfile.ZipFile(io.BytesIO(archive_bytes)) as archive:
        for info in archive.infolist():
            path = safe_member_path(info.filename)
            if info.is_dir() or not path:
                continue
            if (info.external_attr >> 16) & 0o170000 == 0o120000:
                raise LibraryError(f"Refusing symlink in artifact: {path}")
            found[path] = archive.read(info)
    if set(found) != set(expected):
        raise LibraryError("Artifact file list does not match the registry's validation record.")
    for path, content in found.items():
        if hashlib.sha256(content).hexdigest() != expected[path]:
            raise LibraryError(f"Digest mismatch for {path}; refusing to install.")
    return {strip_root(path, root): content for path, content in found.items() if strip_root(path, root)}


def local_files(skill_dir):
    files = {}
    for current, dirs, names in os.walk(skill_dir):
        dirs[:] = sorted(d for d in dirs if d not in SKIP_NAMES)
        for name in sorted(names):
            if name in SKIP_NAMES or name.startswith(".env"):
                continue
            full = os.path.join(current, name)
            if os.path.islink(full):
                print(f"skipping symlink: {os.path.relpath(full, skill_dir)}", file=sys.stderr)
                continue
            with open(full, "rb") as handle:
                files[os.path.relpath(full, skill_dir).replace(os.sep, "/")] = handle.read()
    return files


def cmd_install(registry, workspace, args):
    version = latest_approved(registry, workspace, args.slug)
    digest = version["artifactDigest"]
    query = urllib.parse.urlencode({"packageId": package_id(workspace, args.slug), "versionId": version["id"]})
    archive = registry.request("GET", f"/api/artifacts/{quote(digest)}/download?{query}", raw=True)
    files = read_verified_artifact(archive, version)

    target = os.path.join(args.dest, args.slug)
    if os.path.exists(target):
        if local_files(target) == files:
            print(f"{args.slug} {version['version']} is already installed at {target}")
            return
        if not args.force:
            raise LibraryError(
                f"{target} exists and differs from the registry copy. Run `check` to see how,"
                " then re-run with --force to replace it."
            )
    os.makedirs(args.dest, exist_ok=True)
    staging = tempfile.mkdtemp(prefix=f".{args.slug}-", dir=args.dest)
    try:
        for path, content in files.items():
            full = os.path.join(staging, *path.split("/"))
            os.makedirs(os.path.dirname(full), exist_ok=True)
            with open(full, "wb") as handle:
                handle.write(content)
        if os.path.exists(target):
            shutil.rmtree(target)
        os.replace(staging, target)
    finally:
        if os.path.exists(staging):
            shutil.rmtree(staging)
    print(f"Installed {args.slug} {version['version']} ({len(files)} files) to {target}")


def cmd_check(registry, workspace, args):
    skill_dir = args.skill_dir.rstrip("/")
    slug = args.slug or os.path.basename(os.path.abspath(skill_dir))
    version = latest_approved(registry, workspace, slug)
    expected, root = expected_files(version)
    remote = {strip_root(p, root): d for p, d in expected.items()}
    local = {p: hashlib.sha256(c).hexdigest() for p, c in local_files(skill_dir).items()}
    changed = sorted(p for p in remote if p in local and local[p] != remote[p])
    missing = sorted(set(remote) - set(local))
    extra = sorted(set(local) - set(remote))
    print(f"{slug}: latest approved version {version['version']}")
    if not (changed or missing or extra):
        print("up to date: local files match the registry exactly")
        return
    for label, paths in (("differs", changed), ("only in registry", missing), ("only local", extra)):
        for path in paths:
            print(f"  {label}: {path}")
    print("Either the registry has a newer version or the local copy was edited. Review before replacing.")


# ---------------------------------------------------------------- search / info


def cmd_search(registry, workspace, args):
    query = f"?q={quote(args.query)}" if args.query else ""
    packages = registry.request("GET", f"/api/workspaces/{quote(workspace)}/packages{query}")["packages"]
    if args.json:
        print(json.dumps(packages, indent=2))
        return
    if not packages:
        print(f"No installable skills matched in workspace '{workspace}'.")
        return
    for pkg in packages:
        description = " ".join(pkg.get("description", "").split())
        print(f"{pkg['slug']}  -  {pkg.get('name', '')}\n    {description[:200]}")


def cmd_info(registry, workspace, args):
    pid = package_id(workspace, args.slug)
    pkg = registry.request("GET", f"/api/packages/{quote(pid)}")["package"]
    try:
        version = latest_approved(registry, workspace, args.slug)
    except LibraryError as err:
        version = {"error": str(err)}
    if args.json:
        print(json.dumps({"package": pkg, "latestApproved": version}, indent=2))
        return
    print(f"{pkg['slug']} ({pkg.get('name', '')})\n{pkg.get('description', '')}")
    if "error" in version:
        print(f"No approved version: {version['error']}")
        return
    files = [f["path"] for f in version.get("validation", {}).get("files", []) if f.get("kind") == "file"]
    print(f"latest approved: {version['version']}  approved {version.get('approvedAt', '?')}")
    print("files: " + ", ".join(files))


# ---------------------------------------------------------------- publish


def next_version(registry, workspace, slug):
    try:
        current = latest_approved(registry, workspace, slug)["version"]
    except LibraryError:
        return "1.0.0"
    parts = re.match(r"^(\d+)\.(\d+)\.(\d+)", current)
    if not parts:
        raise LibraryError(f"Latest version '{current}' is not semver; pass --version.")
    major, minor, patch = (int(n) for n in parts.groups())
    return f"{major}.{minor}.{patch + 1}"


def build_entries(name, files):
    entries = []
    for path, content in files.items():
        entry = {"path": f"{name}/{path}", "kind": "file"}
        try:
            entry["content"] = content.decode("utf-8")
        except UnicodeDecodeError:
            entry["content"] = base64.b64encode(content).decode("ascii")
            entry["encoding"] = "base64"
        entries.append(entry)
    return entries


def cmd_publish(registry, workspace, args):
    skill_dir = args.skill_dir.rstrip("/")
    files = local_files(skill_dir)
    if "SKILL.md" not in files:
        raise LibraryError(f"{skill_dir} has no SKILL.md at its root.")
    meta = read_frontmatter(files["SKILL.md"].decode("utf-8"))
    name, description = meta.get("name"), meta.get("description")
    if not name or not description:
        raise LibraryError("SKILL.md frontmatter needs both name and description.")
    if name != os.path.basename(os.path.abspath(skill_dir)):
        raise LibraryError(f"Frontmatter name '{name}' must match the directory name.")
    total = sum(len(c) for c in files.values())
    if total > MAX_UPLOAD_BYTES:
        raise LibraryError(f"Skill is {total} bytes; refusing to upload more than {MAX_UPLOAD_BYTES}.")
    version = args.version or meta.get("metadata.version") or next_version(registry, workspace, name)
    body = {
        "packageSlug": name,
        "packageName": args.name or name.replace("-", " ").title(),
        "description": description,
        "categories": args.category or [],
        "version": version,
        "entries": build_entries(name, files),
    }
    print(f"workspace: {workspace}\nslug: {name}\nversion: {version}\nfiles ({total} bytes):")
    for path in files:
        print(f"  {path}")
    if args.dry_run:
        print("dry run: nothing uploaded")
        return
    created = registry.request("POST", f"/api/workspaces/{quote(workspace)}/packages/upload", body)["version"]
    issues = created.get("validation", {}).get("issues", [])
    print(f"Uploaded {name} {created['version']} as {created.get('lifecycleState', 'draft')}.")
    for issue in issues:
        print(f"  {issue.get('severity')}: {issue.get('message')} ({issue.get('path', '')})")
    if any(issue.get("severity") == "error" for issue in issues):
        print("The draft has validation errors and cannot be approved. Fix them and publish a new version.")
    else:
        print("An editor approves it in the registry's web UI before it becomes installable.")


# ---------------------------------------------------------------- entry point


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--registry", default=os.environ.get("SKILL_LIBRARY_REGISTRY_URL"))
    parser.add_argument("--workspace", default=os.environ.get("SKILL_LIBRARY_WORKSPACE"))
    sub = parser.add_subparsers(dest="command", required=True)

    search = sub.add_parser("search")
    search.add_argument("query", nargs="?")
    search.add_argument("--json", action="store_true")
    info = sub.add_parser("info")
    info.add_argument("slug")
    info.add_argument("--json", action="store_true")
    install = sub.add_parser("install")
    install.add_argument("slug")
    install.add_argument("--dest", required=True, help="skills directory the agent host reads")
    install.add_argument("--force", action="store_true")
    check = sub.add_parser("check")
    check.add_argument("skill_dir")
    check.add_argument("--slug")
    publish = sub.add_parser("publish")
    publish.add_argument("skill_dir")
    publish.add_argument("--version")
    publish.add_argument("--name", help="display name (default: title-cased slug)")
    publish.add_argument("--category", action="append")
    publish.add_argument("--dry-run", action="store_true")

    args = parser.parse_args(argv)
    commands = {
        "search": cmd_search,
        "info": cmd_info,
        "install": cmd_install,
        "check": cmd_check,
        "publish": cmd_publish,
    }
    try:
        token = os.environ.get("SKILL_LIBRARY_TOKEN") or os.environ.get("SKILL_LIBRARY_MCP_TOKEN")
        registry = Registry(args.registry, token)
        workspace = args.workspace or registry.default_workspace()
        commands[args.command](registry, workspace, args)
    except LibraryError as err:
        print(f"error: {err}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
