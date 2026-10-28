#!/usr/bin/env python3
"""Read-only Kubernetes health report for the check-kubernetes-health skill.

Runs `kubectl get ... -o json` (never a mutating verb), scores nodes, workloads and pods
as OK / WARN / ALERT / UNKNOWN, and prints a text board or JSON.

Exit code is the worst status: 0 OK, 1 WARN, 2 ALERT, 3 UNKNOWN (a signal could not be
gathered). Scheduled runs notify on a non-zero exit.

Standard library only. `--input DIR` reads nodes.json / pods.json / workloads.json /
events.json from DIR instead of calling kubectl (used by the tests).
"""

import argparse
import json
import os
import subprocess  # nosec B404 - runs kubectl with fixed read-only arguments
import sys
from datetime import datetime, timezone

RANK = {"OK": 0, "WARN": 1, "ALERT": 2, "UNKNOWN": 3}
POD_ALERT_WAITING = {
    "CrashLoopBackOff",
    "ImagePullBackOff",
    "ErrImagePull",
    "CreateContainerConfigError",
    "CreateContainerError",
    "InvalidImageName",
    "RunContainerError",
}


class Unknown(Exception):
    """A signal could not be gathered (no access, no cluster, bad JSON)."""


def kubectl(args, context):
    cmd = ["kubectl"] + (["--context", context] if context else []) + args + ["-o", "json"]
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, timeout=60)  # nosec B603
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise Unknown(f"kubectl failed: {exc}") from exc
    if out.returncode != 0:
        raise Unknown(out.stderr.strip().splitlines()[-1] if out.stderr.strip() else "kubectl failed")
    return json.loads(out.stdout)


def gather(name, args, opts):
    """Return the items for one signal, or raise Unknown."""
    if opts.input:
        path = os.path.join(opts.input, f"{name}.json")
        if not os.path.exists(path):
            raise Unknown(f"no {name}.json in {opts.input}")
        with open(path, encoding="utf-8") as fh:
            return json.load(fh).get("items", [])
    return kubectl(args, opts.context).get("items", [])


def scope_args(opts):
    return ["-n", opts.namespace] if opts.namespace else ["-A"]


def parse_ts(value):
    if not value:
        return None
    return datetime.strptime(value, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)


def ref(obj):
    meta = obj.get("metadata", {})
    ns = meta.get("namespace")
    return f"{ns}/{meta.get('name')}" if ns else meta.get("name", "?")


def clip(text, limit=220):
    text = " ".join(str(text).split())
    return text if len(text) <= limit else text[: limit - 3] + "..."


def finding(status, kind, obj, reason, detail, nxt):
    return {"status": status, "kind": kind, "name": ref(obj), "reason": reason, "detail": clip(detail), "next": nxt}


def check_nodes(nodes):
    out = []
    for node in nodes:
        conds = {c.get("type"): c for c in node.get("status", {}).get("conditions", [])}
        ready = conds.get("Ready", {})
        name = node["metadata"]["name"]
        describe = f"kubectl describe node {name}"
        if ready.get("status") != "True":
            out.append(finding("ALERT", "Node", node, "NotReady", ready.get("message", "Ready condition not True"), describe))
        for pressure in ("MemoryPressure", "DiskPressure", "PIDPressure", "NetworkUnavailable"):
            if conds.get(pressure, {}).get("status") == "True":
                out.append(finding("WARN", "Node", node, pressure, conds[pressure].get("message", ""), describe))
        if node.get("spec", {}).get("unschedulable"):
            out.append(finding("WARN", "Node", node, "Cordoned", "node is unschedulable", describe))
    return out


def check_workloads(items):
    out = []
    for obj in items:
        kind, spec, st = obj.get("kind"), obj.get("spec", {}), obj.get("status", {})
        if kind == "DaemonSet":
            want, have = st.get("desiredNumberScheduled", 0), st.get("numberAvailable", 0)
        elif kind == "StatefulSet":
            want, have = spec.get("replicas", 1), st.get("readyReplicas", 0)
        else:
            want, have = spec.get("replicas", 1), st.get("availableReplicas", 0)
        if want and have < want:
            status = "ALERT" if have == 0 else "WARN"
            nxt = f"kubectl -n {obj['metadata'].get('namespace')} describe {kind.lower()} {obj['metadata']['name']}"
            out.append(finding(status, kind, obj, "Unavailable", f"{have}/{want} available", nxt))
    return out


def check_pods(pods, now, pending_minutes, restart_threshold):
    out = []
    for pod in pods:
        st, meta = pod.get("status", {}), pod["metadata"]
        logs = f"kubectl -n {meta.get('namespace')} logs {meta['name']} --previous"
        describe = f"kubectl -n {meta.get('namespace')} describe pod {meta['name']}"
        if st.get("phase") == "Failed":
            if st.get("reason") == "Evicted":
                out.append(finding("WARN", "Pod", pod, "Evicted", st.get("message", ""), describe))
            else:
                out.append(finding("ALERT", "Pod", pod, st.get("reason") or "Failed", st.get("message", ""), describe))
            continue
        container = []
        for cs in st.get("containerStatuses", []) + st.get("initContainerStatuses", []):
            state, name = cs.get("state", {}), cs.get("name")
            waiting, ended = state.get("waiting", {}), state.get("terminated", {})
            last = cs.get("lastState", {}).get("terminated", {})
            if waiting.get("reason") in POD_ALERT_WAITING:
                nxt = logs if waiting["reason"] == "CrashLoopBackOff" else describe
                container.append(finding("ALERT", "Pod", pod, waiting["reason"],
                                         f"container {name}: {waiting.get('message', '')}", nxt))
            elif ended.get("exitCode", 0) != 0 and st.get("phase") != "Succeeded":
                # Caught between restarts: the container just died and is not yet in back-off.
                container.append(finding("ALERT", "Pod", pod, "ContainerFailed",
                                         f"container {name} exited {ended['exitCode']} ({ended.get('reason', 'Error')}),"
                                         f" {cs.get('restartCount', 0)} restarts", logs))
            elif last.get("reason") == "OOMKilled":
                container.append(finding("WARN", "Pod", pod, "OOMKilled", f"container {name} was OOM-killed", logs))
            elif cs.get("restartCount", 0) >= restart_threshold:
                container.append(finding("WARN", "Pod", pod, "Restarting",
                                         f"container {name}: {cs['restartCount']} restarts", logs))
        out += container
        if st.get("phase") == "Pending" and not container:
            started = parse_ts(meta.get("creationTimestamp"))
            age = (now - started).total_seconds() / 60 if started else 0
            if age >= pending_minutes:
                sched = next((c for c in st.get("conditions", []) if c.get("type") == "PodScheduled"), {})
                why = sched.get("message") or sched.get("reason") or "not scheduled or not started"
                out.append(finding("WARN", "Pod", pod, "Pending", f"pending {int(age)} min: {why}", describe))
    return out


def attach_events(findings, events):
    """Add the newest Warning event message for each flagged object."""
    latest = {}
    for ev in events:
        if ev.get("type") != "Warning":
            continue
        obj = ev.get("involvedObject", {})
        key = f"{obj.get('namespace')}/{obj.get('name')}" if obj.get("namespace") else obj.get("name")
        when = ev.get("lastTimestamp") or ev.get("eventTime") or ""
        if key not in latest or when > latest[key][0]:
            latest[key] = (when, clip(f"{ev.get('reason')}: {ev.get('message', '')}"))
    for f in findings:
        if f["name"] in latest:
            f["event"] = latest[f["name"]][1]


def worst(items):
    return max((i["status"] for i in items), key=RANK.get, default="OK")


def run(opts):
    now = datetime.now(timezone.utc) if not opts.now else parse_ts(opts.now)
    dims, findings = {}, []
    checks = [
        ("Nodes", lambda: check_nodes(gather("nodes", ["get", "nodes"], opts))),
        ("Workloads", lambda: check_workloads(
            gather("workloads", ["get", "deployments,statefulsets,daemonsets"] + scope_args(opts), opts))),
        ("Pods", lambda: check_pods(gather("pods", ["get", "pods"] + scope_args(opts), opts),
                                    now, opts.pending_minutes, opts.restart_threshold)),
    ]
    for dim, check in checks:
        try:
            got = check()
            dims[dim] = {"status": worst(got)}
            findings += got
        except Unknown as exc:
            dims[dim] = {"status": "UNKNOWN", "error": str(exc)}
    try:
        attach_events(findings, gather("events", ["get", "events"] + scope_args(opts), opts))
    except Unknown:
        pass  # events only add context; missing them changes no status
    findings.sort(key=lambda f: (-RANK[f["status"]], f["kind"], f["name"]))
    statuses = {d["status"] for d in dims.values()}
    # An ALERT outranks UNKNOWN: a missing signal must never hide a failure we did see.
    overall = next(s for s in ("ALERT", "UNKNOWN", "WARN", "OK") if s in statuses or s == "OK")
    return {"context": opts.context or "current", "namespace": opts.namespace or "all",
            "checked_at": now.strftime("%Y-%m-%dT%H:%M:%SZ"), "overall": overall,
            "dimensions": dims, "findings": findings}


def render_text(report):
    lines = [f"Kubernetes health - context {report['context']} - namespace {report['namespace']}"
             f" - {report['checked_at']}"]
    for dim, d in report["dimensions"].items():
        extra = f"  ({d['error']})" if d.get("error") else ""
        lines.append(f"  {dim:<10}: [{d['status']}]{extra}")
    lines.append(f"  Overall   : [{report['overall']}]")
    if report["findings"]:
        lines += ["", "Needs attention:"]
        for f in report["findings"]:
            lines.append(f"  - [{f['status']}] {f['kind']} {f['name']}: {f['reason']} - {f['detail']}")
            if f.get("event"):
                lines.append(f"      last event: {f['event']}")
            lines.append(f"      next: {f['next']}")
    return "\n".join(lines)


def main(argv=None):
    p = argparse.ArgumentParser(description="Read-only Kubernetes health report.")
    p.add_argument("--context", help="kubeconfig context (default: current)")
    p.add_argument("--namespace", help="one namespace (default: all namespaces)")
    p.add_argument("--format", choices=["text", "json"], default="text")
    p.add_argument("--pending-minutes", type=int, default=5, help="flag pods pending this long")
    p.add_argument("--restart-threshold", type=int, default=5, help="flag containers with this many restarts")
    p.add_argument("--input", help=argparse.SUPPRESS)
    p.add_argument("--now", help=argparse.SUPPRESS)
    opts = p.parse_args(argv)
    report = run(opts)
    print(json.dumps(report, indent=2) if opts.format == "json" else render_text(report))
    return RANK[report["overall"]]


if __name__ == "__main__":
    sys.exit(main())
