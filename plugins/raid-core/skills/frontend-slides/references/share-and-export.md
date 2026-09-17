# Share And Export

Read for requested PDF export or questions about sharing a deck. Follow the scope and safety contract in the skill entry point.
In commands and code examples, resolve bundled paths from the directory containing the loaded SKILL.md; do not use the caller's working directory.

## Phase 6: Share & Export (Optional)

If export is already requested, carry it out. Otherwise after delivery, **ask the user:** _"Would you like a PDF of this presentation as well? The HTML file is the deck itself -- you can send or open it as it is."_

### Sharing: files, never a public URL

**Do not publish a deck to a public host** (Vercel, Netlify, GitHub Pages, a paste or file-sharing service), even when asked for "a link". A deck built during an engagement carries the customer's architecture, data and figures, and a public URL publishes all of it to anyone who finds it -- cached and indexed even after it is taken down.

Share the HTML or the PDF as a file, through whatever the customer already uses for documents (their SharePoint, Teams, Drive or repo). If the user needs a hosted link, say so and leave the choice of host -- and whether the content may go there -- to them.

### Export to PDF

One page per slide, at the deck's design size (1920x1080 unless the deck says otherwise). Animations are not preserved; each slide prints in its final revealed state. Mention that so nobody is surprised.

1. **Run the export script:**

   ```bash
   SKILL_DIR="<absolute directory containing the loaded SKILL.md>"; python3 "$SKILL_DIR/scripts/export-pdf.py" <path-to-html> [output.pdf]
   ```

   With no output path, the PDF is written next to the HTML file.

2. **What it does:** it prints a temporary copy of the deck with the Chrome, Chromium or Edge already installed, in headless mode -- no Node, no npm, nothing downloaded. The deck itself is not modified.

3. **It checks its own output.** The script counts the deck's slides and the PDF's pages, and exits 1 when they differ instead of handing over a PDF with a missing or split slide. Treat that error as a real defect in the deck -- almost always `viewport-base.css` not included in full (its `@media print` block lays out one slide per page). Fix the deck and export again; do not work around the check.

   **The count does not catch overflow.** A slide is a fixed 1920x1080 box with `overflow: hidden`, so text that runs past it is clipped, silently, on screen and in the PDF. Check overflow in the deck before exporting (every slide's content fits inside its box), not from the export result.

4. **Deliver the PDF.** Tell the user the file location and size. If you can read images, render a page or two and look at them before calling it done.

**PDF export gotchas:**

- **No browser found.** The script looks for Chrome, Chromium and Edge in the usual places. Point it at another with `CHROME=/path/to/browser`. Do not install a browser on a customer's machine or build agent without asking.
- **Slides must be `.slide` elements, or the children of `<deck-stage>`.** Every deck this skill generates is. For externally created HTML the script reports "no slides found" rather than guessing.
- **Relative paths only.** Images resolve relative to the HTML file. An absolute filesystem path (`src="/Users/name/photo.png"`) breaks on the next machine anyway -- make it relative.
- **Do not script headless Chrome yourself for checks.** Recent Chrome (seen on 153, macOS) writes its `--print-to-pdf`, `--screenshot` or `--dump-dom` output and then never exits, so a plain `subprocess.run` hangs. `export-pdf.py` stops the browser once its output is complete; reuse it rather than calling Chrome directly.
- **Web fonts need the network.** Google Fonts and Fontshare load at export time; offline, the PDF falls back to system fonts. Check the typography on the rendered pages.
