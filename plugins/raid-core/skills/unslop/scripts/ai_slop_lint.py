#!/usr/bin/env python3
"""Mechanical AI-slop linter for prose and copy.

The cheap first gate. Catches the deterministic tells — banned vocabulary,
conjunctive filler, often-empty phrases, banned openers, em dashes / double
hyphens, emoji piling. The judgment tells (rule of three, tone, rhythm) it
cannot see; read references/ai-slop-checklist.md for those.

Word lists are parsed from references/ai-slop-checklist.md so there is a single
source of truth. Edit the lists there, not here.

Usage:
    python3 ai_slop_lint.py draft.md          # lint a file
    pbpaste | python3 ai_slop_lint.py -        # lint stdin
    python3 ai_slop_lint.py a.md b.md          # lint several

Exit code 0 = clean, 1 = violations found, 2 = usage / setup error.
"""

import re
import sys
from pathlib import Path

CHECKLIST = Path(__file__).resolve().parent.parent / "references" / "ai-slop-checklist.md"

# Emoji-ish codepoint ranges (pictographs, symbols, dingbats, supplemental).
EMOJI = re.compile(
    "["
    "\U0001F300-\U0001FAFF"
    "\U00002600-\U000027BF"
    "\U0001F1E6-\U0001F1FF"
    "\U00002190-\U000021FF"
    "\U00002B00-\U00002BFF"
    "\U0000FE00-\U0000FE0F"
    "]"
)


def parse_list(name, text):
    """Pull a comma-separated list from a <!-- lint:NAME --> ... block."""
    m = re.search(rf"<!--\s*lint:{name}\s*-->(.*?)<!--\s*/lint:{name}\s*-->", text, re.S)
    if not m:
        raise ValueError(f"missing lint:{name} block in {CHECKLIST.name}")
    return [w.strip().lower() for w in m.group(1).replace("\n", " ").split(",") if w.strip()]


def load_rules():
    text = CHECKLIST.read_text(encoding="utf-8")
    return {
        "banned-vocab": parse_list("banned-vocab", text),
        "filler": parse_list("filler", text),
        "openers": parse_list("openers", text),
        "phrases": parse_list("phrases", text),
    }


def lint(content, rules):
    """Return a list of (line_no, rule, message) tuples."""
    hits = []
    word_res = {
        w: re.compile(rf"\b{re.escape(w)}\b", re.I)
        for w in rules["banned-vocab"] + rules["filler"]
    }
    banned = set(rules["banned-vocab"])
    phrase_res = {
        p: re.compile(rf"\b{re.escape(p)}\b", re.I) for p in rules["phrases"]
    }

    for i, line in enumerate(content.splitlines(), 1):
        stripped = line.strip().lower()

        for w, rx in word_res.items():
            if rx.search(line):
                kind = "banned word" if w in banned else "conjunctive filler"
                hits.append((i, kind, f"{kind!r}: {w!r}"))

        for p, rx in phrase_res.items():
            if rx.search(line):
                hits.append((i, "empty phrase", f"'empty phrase': {p!r}"))

        for op in rules["openers"]:
            if stripped.startswith(op):
                hits.append((i, "banned opener", f"line opens with {op!r}"))

        if "—" in line:
            hits.append((i, "em dash", "em dash (—) — restructure with comma/period/parens"))
        if "--" in line:
            hits.append((i, "double hyphen", "literal '--' — not a valid em-dash substitute"))

        if len(EMOJI.findall(line)) >= 2:
            hits.append((i, "emoji piling", "2+ emoji on one line"))

    return hits


def main(argv):
    paths = argv[1:]
    if not paths:
        print(__doc__.strip().split("\n\n")[0])
        print("\nGive a file path, or '-' to read stdin.", file=sys.stderr)
        return 2

    try:
        rules = load_rules()
    except (OSError, ValueError) as e:
        print(f"lint setup error: {e}", file=sys.stderr)
        return 2

    total = 0
    for p in paths:
        label = "<stdin>" if p == "-" else p
        try:
            content = sys.stdin.read() if p == "-" else Path(p).read_text(encoding="utf-8")
        except OSError as e:
            print(f"lint setup error: {label}: {e}", file=sys.stderr)
            return 2
        hits = lint(content, rules)
        if hits:
            print(f"\n{label}: {len(hits)} issue(s)")
            for line_no, _, msg in hits:
                print(f"  {label}:{line_no}: {msg}")
        else:
            print(f"{label}: clean")
        total += len(hits)

    if total:
        print(f"\n{total} issue(s) total. Fix the mechanical tells, then read the "
              "judgment section of ai-slop-checklist.md.")
        return 1
    print("\nNo mechanical AI-slop tells. Still read the judgment section before shipping.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
