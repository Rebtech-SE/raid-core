#!/usr/bin/env python3
"""Export a frontend-slides HTML deck to PDF, one page per slide.

Usage:
    python3 export-pdf.py <deck.html> [output.pdf]

Prints the deck with the Chrome, Chromium or Edge already on the machine, in
headless mode. No Node, no npm install, no third-party Python packages. Set
CHROME=/path/to/browser when it is not found automatically.

Decks built by this skill already carry `@media print` rules that lay every
slide out as its own page (viewport-base.css and deck-stage.js). This script
prints a temporary copy with three additions: the page size pinned to the
design size, every slide marked active so reveal animations reach their final
state, and a <base> so relative images still resolve. The deck itself is not
modified.

The export is checked before it is reported as done: the PDF page count must
equal the deck's slide count. On a mismatch the script exits 1 and says so,
rather than handing over a PDF with missing or split slides. It does NOT catch
content that overflows a slide: .slide is a fixed 1920x1080 box with
overflow: hidden, so overflow is clipped on screen and in print alike.
"""

import os
import re
import selectors
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

TIMEOUT = 120  # seconds per browser run

CANDIDATES = [
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    "/Applications/Chromium.app/Contents/MacOS/Chromium",
    "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge",
    "google-chrome",
    "google-chrome-stable",
    "chromium",
    "chromium-browser",
    "microsoft-edge",
    r"C:\Program Files\Google\Chrome\Application\chrome.exe",
    r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
]

# Waits for fonts, marks every slide active, and records the slide count where
# --dump-dom can read it. Runs on both passes (count and print).
INJECT_SCRIPT = """
<script>
window.addEventListener('load', function () {
  var stage = document.querySelector('deck-stage');
  var slides = stage ? Array.prototype.slice.call(stage.children).filter(function (el) {
    return el.tagName === 'SECTION' || el.classList.contains('slide');
  }) : Array.prototype.slice.call(document.querySelectorAll('.slide'));
  slides.forEach(function (s) {
    s.classList.add('active', 'visible');
    s.setAttribute('data-deck-active', '');
  });
  document.documentElement.setAttribute('data-export-slide-count', String(slides.length));
});
</script>
"""


def find_browser():
    env = os.environ.get("CHROME")
    if env:
        return env
    for c in CANDIDATES:
        if os.path.isabs(c) and os.path.exists(c):
            return c
        found = shutil.which(c)
        if found:
            return found
    return None


def design_size(html):
    """deck-stage decks declare their canvas; everything else is 1920x1080."""
    m = re.search(r"<deck-stage\b[^>]*>", html, re.I)
    if m:
        w = re.search(r'\bwidth\s*=\s*"?(\d+)', m.group(0))
        h = re.search(r'\bheight\s*=\s*"?(\d+)', m.group(0))
        if w and h:
            return int(w.group(1)), int(h.group(1))
    return 1920, 1080


def inject(html, deck_dir, width, height):
    style = (
        "<style>@media print {"
        f"@page {{ size: {width}px {height}px; margin: 0; }}"
        "html { -webkit-print-color-adjust: exact; print-color-adjust: exact; }"
        "}</style>"
    )
    base = f'<base href="{deck_dir.as_uri()}/">'
    head = re.search(r"<head\b[^>]*>", html, re.I)
    if head:
        i = head.end()
        html = html[:i] + base + html[i:]
    else:
        html = base + html
    close = re.search(r"</head\s*>", html, re.I)
    tail = style + INJECT_SCRIPT
    if close:
        return html[: close.start()] + tail + html[close.start() :]
    return html + tail


def browser_cmd(browser, profile, extra, url):
    return [
        browser,
        "--headless=new",
        "--disable-gpu",
        "--no-first-run",
        "--no-default-browser-check",
        "--hide-scrollbars",
        "--allow-file-access-from-files",
        "--run-all-compositor-stages-before-draw",
        "--virtual-time-budget=15000",
        f"--user-data-dir={profile}",
        *extra,
        url,
    ]


def stop(proc):
    """Headless Chrome can finish its work and then never exit (seen on Chrome
    153, macOS), so every run ends by stopping it rather than waiting on it."""
    if proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(5)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait()


def dump_dom(browser, profile, url):
    proc = subprocess.Popen(
        browser_cmd(browser, profile, ["--dump-dom"], url),
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
    )
    buf = b""
    deadline = time.monotonic() + TIMEOUT
    sel = selectors.DefaultSelector()
    sel.register(proc.stdout, selectors.EVENT_READ)
    try:
        while time.monotonic() < deadline:
            if not sel.select(timeout=1):
                if proc.poll() is not None:
                    break
                continue
            chunk = proc.stdout.read1(65536)
            if not chunk:
                break
            buf += chunk
            if re.search(rb"</html\s*>\s*$", buf, re.I):
                break
    finally:
        sel.close()
        stop(proc)
    return buf.decode("utf-8", "replace")


def print_pdf(browser, profile, url, pdf):
    proc = subprocess.Popen(
        browser_cmd(browser, profile, ["--no-pdf-header-footer", f"--print-to-pdf={pdf}"], url),
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    deadline = time.monotonic() + TIMEOUT
    last_size = -1
    try:
        while time.monotonic() < deadline:
            done = proc.poll() is not None
            if pdf.is_file():
                size = pdf.stat().st_size
                # Complete once it ends in %%EOF and has stopped growing.
                if size and size == last_size and pdf.read_bytes()[-1024:].rstrip().endswith(b"%%EOF"):
                    return True
                last_size = size
            elif done:
                return False
            time.sleep(0.5)
        return False
    finally:
        stop(proc)


def pdf_page_count(path):
    data = Path(path).read_bytes()
    return len(re.findall(rb"/Type\s*/Page(?![a-zA-Z])", data))


def main(argv):
    if len(argv) < 2 or argv[1] in ("-h", "--help"):
        print(__doc__.strip())
        return 0 if len(argv) >= 2 else 2
    deck = Path(argv[1]).expanduser().resolve()
    if not deck.is_file():
        print(f"error: {deck} not found", file=sys.stderr)
        return 2
    out = Path(argv[2]).expanduser().resolve() if len(argv) > 2 else deck.with_suffix(".pdf")

    browser = find_browser()
    if not browser:
        print(
            "error: no Chrome, Chromium or Edge found. Install one, or set CHROME=/path/to/browser.",
            file=sys.stderr,
        )
        return 1

    html = deck.read_text(encoding="utf-8")
    width, height = design_size(html)

    with tempfile.TemporaryDirectory(prefix="frontend-slides-pdf-") as tmp:
        tmp = Path(tmp)
        printable = tmp / "deck.html"
        printable.write_text(inject(html, deck.parent, width, height), encoding="utf-8")
        url = printable.as_uri()

        dom = dump_dom(browser, tmp / "profile-count", url)
        m = re.search(r'data-export-slide-count="(\d+)"', dom)
        if not m:
            print("error: could not load the deck to count its slides.", file=sys.stderr)
            return 1
        slides = int(m.group(1))
        if slides == 0:
            print(
                'error: no slides found. Slides must be `class="slide"` elements, '
                "or the children of <deck-stage>.",
                file=sys.stderr,
            )
            return 1

        pdf_tmp = tmp / "deck.pdf"
        if not print_pdf(browser, tmp / "profile-print", url, pdf_tmp):
            print(f"error: the browser did not produce a PDF within {TIMEOUT}s.", file=sys.stderr)
            return 1

        pages = pdf_page_count(pdf_tmp)
        if pages != slides:
            print(
                f"error: the PDF has {pages} pages but the deck has {slides} slides. "
                "The deck's print layout is broken: check that viewport-base.css "
                "(its @media print block) is included in full and that no slide "
                "uses display:none or its own page breaks.",
                file=sys.stderr,
            )
            return 1

        out.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(str(pdf_tmp), out)

    size_mb = out.stat().st_size / 1_000_000
    print(f"exported {slides} slides ({width}x{height}) -> {out} ({size_mb:.1f} MB)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
