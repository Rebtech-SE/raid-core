---
name: frontend-slides
description: "Use when building, revising or converting a slide deck -- a workshop, steering-group, handover or proposal presentation, or a PPTX to turn into HTML. Produces one self-contained animated HTML deck on a fixed 16:9 stage, in the Rebtech house style by default or a chosen preset or bold template, with PDF export and no public hosting."
---

# Frontend Slides

Create zero-dependency, animation-rich HTML presentations that run entirely in the browser.

Use decisions already supplied: content, outline, purpose, density, and selected style. Reuse approved designs without another discovery round; ask only for missing consequential choices. Visual comparisons remain the default when the style is unresolved or alternatives are requested. Decks are shared as files (the HTML or a PDF), never published to a public host -- an engagement deck carries the customer's architecture and figures. Decks made on a Rebtech engagement use the Rebtech house style unless the user asks otherwise.

## Core Principles

1. **Zero Dependencies**, Single HTML files with inline CSS/JS. No npm, no build tools.
2. **Show, Don't Tell**, Generate visual previews, not abstract choices. People discover what they want by seeing it.
3. **Distinctive Design**, No generic "AI slop." Every presentation must feel custom-crafted.
4. **Progressive Disclosure**, Read lightweight style indexes first. For bold templates, use small preview cards for style previews and load the full `design.md` only after the user picks that template.
5. **Fixed 16:9 Stage (NON-NEGOTIABLE)**, Every deck uses a 1920×1080 slide canvas scaled as a whole to the viewport. Slides must stay 16:9 on every screen, including phones. Do not reflow slide content to fit the device.

## Fixed Stage Rules

These invariants apply to EVERY slide in EVERY presentation:

- Every deck has a viewport wrapper that fills the browser window.
- Every slide is authored inside a fixed 1920×1080 stage.
- The stage scales uniformly to fit the viewport. It may letterbox/pillarbox; it must not re-layout content.
- Do not use responsive breakpoints to rearrange slide content for phones.
- Use fixed internal slide measurements at the 1920×1080 design size.
- Slide visibility must be controlled by `.active` / `.visible` using `visibility`, `opacity`, and `pointer-events` from `viewport-base.css`. Do not use `display: none` / `display: block` for slide switching; later layout classes such as `.slide-content { display: flex; }` can override them and make every slide visible at once.
- Use `clamp()` only for non-slide UI outside the stage, or for small fallback previews where a full stage is impractical.
- Include `prefers-reduced-motion` support
- Never negate CSS functions directly (`-clamp()`, `-min()`, `-max()` are silently ignored), use `calc(-1 * clamp(...))` instead

**When generating, read `viewport-base.css` and include its full contents in every presentation.**

### Content Density Modes

Use the supplied reading/speaking purpose, or ask if that material choice is missing:

| Density mode | Best for | Design behavior |
| ------------- | -------- | --------------- |
| **Low density / speaker-led** | Public talks, keynote-style sharing, live explanation | One idea per slide, large type, strong visual hierarchy, generous negative space, 1-3 bullets max, more slides if needed |
| **High density / reading-first** | Reports, handouts, async review, detailed internal docs | More self-contained slides, structured grids/tables/annotations, 4-8 bullets or 4-6 cards when readable, tighter but still intentional spacing |

Baseline limits still apply: no scrolling, no overflow, no overlapping panels, and no text below comfortable reading size. If content exceeds the selected density mode, split it into more slides instead of shrinking until it becomes cramped.

---

## Phase 0: Detect Mode

Determine what the user wants:

- **Mode A: New Presentation**, Create from scratch. Go to Phase 1.
- **Mode B: PPT Conversion**, Convert a .pptx file. Go to Phase 4.
- **Mode C: Enhancement**, Improve an existing HTML presentation. Read it, understand it, enhance. **Follow Mode C modification rules below.**

### Mode C: Modification Rules

When enhancing existing presentations, fixed-stage fitting is the biggest risk:

1. **Before adding content:** Count existing elements, check against density limits
2. **Adding images:** Fit them inside the 1920×1080 slide canvas. If slide already has max content, split into two slides
3. **Adding text:** Max 4-6 bullets per slide. Exceeds limits? Split into continuation slides
4. **After ANY modification, verify:** the slide stage remains 16:9, no text overflows its card, no panels overlap, and screenshots look correct at 1280×720 plus one phone viewport
5. **Proactively reorganize:** If modifications will cause overflow, automatically split content and inform the user. Don't wait to be asked

**When adding images to existing slides:** Move image to a new slide or reduce other content first. Never add images without checking if existing content already fills the 1920×1080 slide stage.

---

## Phase 5: Delivery

1. **Clean up**, Delete `.frontend-slides/slide-previews/` if it exists
2. **Open**, Use `open [filename].html` to launch in browser
3. **Summarize**, Tell the user:
   - File location, style name, slide count
   - Navigation: Arrow keys, Space, swipe/tap if enabled
   - How to customize: `:root` CSS variables for colors, font link for typography, `.reveal` class for animations
   - Inline text editing is available: Hover top-left corner or press E to enter edit mode, click any text to edit, Ctrl+S to save
   - Offer the natural post-draft actions: ask for revisions, edit text directly in the browser, or export/share

---

## Supporting Files

| File                                               | Purpose                                                              | When to Read              |
| -------------------------------------------------- | -------------------------------------------------------------------- | ------------------------- |
| [STYLE_PRESETS.md](STYLE_PRESETS.md)               | Rebtech house style (the default) + 12 curated visual presets        | Phase 2 (style selection) |
| [bold-template-pack/selection-index.json](bold-template-pack/selection-index.json) | Compact bold template metadata for candidate selection | Phase 2 (style selection) |
| [bold-template-pack/templates/*/preview.md](bold-template-pack/templates/) | Lightweight style cards for shortlisted bold title previews | Phase 2 after shortlisting |
| [bold-template-pack/templates/*/design.md](bold-template-pack/templates/) | Detailed design-system docs for the selected bold template only | Phase 3 after user selection |
| [viewport-base.css](viewport-base.css)             | Mandatory fixed-stage CSS, copy into every presentation             | Phase 3 (generation)      |
| [html-template.md](html-template.md)               | HTML structure, JS features, code quality standards                  | Phase 3 (generation)      |
| [animation-patterns.md](animation-patterns.md)     | CSS/JS animation snippets and effect-to-feeling guide                | Phase 3 (generation)      |
| [assets/rebtech-logo.svg](assets/rebtech-logo.svg) | Rebtech logo to inline in house-style decks                          | Phase 3 (generation)      |
| [scripts/extract-pptx.py](scripts/extract-pptx.py) | PPTX content extraction (needs optional `python-pptx`)               | Phase 4 (conversion)      |
| [scripts/export-pdf.py](scripts/export-pdf.py)     | Export to PDF via local headless Chrome; checks page count           | Phase 6 (export)          |

## Task references

Read the reference for the task at hand; do not load every recipe.

- [Style discovery](references/style-discovery.md): unresolved content/style choices or requested visual alternatives.
- [Generation](references/generation.md): creating the HTML deck in the chosen style.
- [Powerpoint conversion](references/powerpoint-conversion.md): extracting and converting a PPTX while preserving its content.
- [Share and export](references/share-and-export.md): PDF export, or any request to share or host a deck.
