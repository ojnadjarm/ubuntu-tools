# Owner CV: edit, translate and rebuild the PDF (English and Spanish)

Ticket: T1423 (design T298–T302) · Last verified: 2026-10-28 by `build.sh --lang en|es --out <scratch>`: 1 page each,
pdftotext identical to ~/drop/cv/<name>-CV.pdf and <name>-CV-ES.pdf

## When to use
The owner asks for his CV, a CV change, or another language. Load skill /cv; it holds the owner's corrections.

## The path we took
Design C Schematic (an engineering drawing sheet, A4, HTML + local IBM Plex fonts) picked by the owner out of three
designs (T299). Headless Chrome prints it to PDF; pdftoppm renders page 1 for a check by eye. The source used to live
only in ~/drop/cv/designs, which the owner deleted; T1423 moved it into the skill.

## Exact commands
```bash
~/.claude/skills/cv/build.sh --lang en            # ~/drop/cv/<name>-CV.pdf + .png
~/.claude/skills/cv/build.sh --lang es            # ~/drop/cv/<name>-CV-ES.pdf + .png
~/.claude/skills/cv/build.sh --lang es --out <dir> # trial build
pdftotext ~/drop/cv/<name>-CV-ES.pdf - | grep -i experiencia
```

## Pitfalls (measured)
- `body { overflow: hidden }` on a fixed A4: overflowing text is clipped and the PDF still reports 1 page. The first
  literal Spanish draft pushed Education under the frame and Other work under the title block (T1423); only the PNG
  showed it. Always look at the PNG.
- Spanish fit came from shorter wording in both columns (two passes), not CSS changes; facts unchanged.
- Never restore or move the owner's trashed copy (~/.local/share/Trash/files/cv): his deletes are intentional.

## Links
- Code: ~/.claude/skills/cv/ (SKILL.md, build.sh, src/)
- Tests: build.sh exits 1 when the PDF is not 1 page; exit 2 on a bad --lang
