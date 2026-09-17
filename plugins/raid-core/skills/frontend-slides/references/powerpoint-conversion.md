# Powerpoint Conversion

Read for extracting and converting a PPTX while preserving its content. Follow the scope and safety contract in the skill entry point.
In commands and code examples, resolve bundled paths from the directory containing the loaded SKILL.md; do not use the caller's working directory.

## Phase 4: PPT Conversion

When converting PowerPoint files:

1. **Extract content**, Run `SKILL_DIR="<absolute directory containing the loaded SKILL.md>"; python3 "$SKILL_DIR/scripts/extract-pptx.py" <input.pptx> <output_dir>` It needs `python-pptx`, the one optional dependency in this skill; without it the script stops with an install hint. Install it into the project's existing `.venv` (create one if none exists), never system-wide, and ask before installing anything on a customer's machine or build agent
2. **Check the extraction**, Verify slide titles, content, and images; surface ambiguous conversion choices without repeating approval of supplied content
3. **Style selection**, Reuse the selected style or read the style-discovery reference for an unresolved style
4. **Generate HTML**, Read [generation](generation.md) for the required template and animation guidance. Convert to chosen style, preserving all text, images (from assets/), slide order, and speaker notes (as HTML comments)

---
