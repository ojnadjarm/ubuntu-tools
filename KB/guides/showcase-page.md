# One showcase page for the motion-video and gamedev stacks

Ticket: T745, T865, T901, T903 · Last verified: 2026-10-20 (T947: code read of `cpp_report()`/`check()`, one `--check --drop ~/drop/T745` run, 3/10); before: 2026-10-20 (T901: --help + code read of `check()`, one `--check --drop ~/drop/T745` run); before: 2026-10-20 by `bin/tests/showcase-page.test.sh` 13/13 and `resp-check` 5/5 on the real page

## When to use
Show the owner the newest finished film and the newest playable C++ showcase on one page, with their numbers and open
flaws. Not for a single render's QC (use `mv-report`) or the dashboard.

## The path we took
- Existed: `mv-report` (one film's HTML), `resp-check`, `drop-link`; nothing joined the two stacks. Chosen: a small
  python CLI that only reads existing files and writes one `index.html` (no render, no copy).
- Motion: newest `~/agent-work/motion/*/out/build.json` whose `build.sh` header says `(film)`, `draft` false, project
  name not `demo|scratch|test|tmp*`. Its `<name>-16x9.mp4`, `.sheet.jpg`, `.report.html` are found in `~/drop/*/`
  by content (size + byte compare), so a renamed drop copy (`T694/hero-film.mp4`) still links. Shows cpu_s, top 3
  steps_cpu with share, review, VMAF/size per aspect.
- Gamedev: newest `~/drop/*/play.mp4` (+ `contact-sheet.jpg`), newest `~/agent-work/games/*/ci/summary.json`
  (cpp-ci stages), last row of `~/agents/state/gamedev-perf/perf-cpp.csv` (nightly template, per-pass p50).
- Follow-ups: open `- ` lines (no `~~`, no `(done`) of the newest `research/*/*/FOLLOWUPS.md` that name the drop's
  ticket, the project name (`-` or space) or, for gamedev, `perf-cpp.csv`.
- Every table row has an Age column: from the summary `date` / csv `date` when present, else file mtime.
- Check (T865): `--check --drop DIR [--max-age 24h] [--json]` rebuilds nothing; DIR is the page folder (its `index.html`), not the drop root. One `ok|FAIL` line each: the index, every linked media file (exists, non-empty, mtime within `--max-age`: `90m`, `24h`, `2d`), a film preview (an .mp4 other than play.mp4 + a `.sheet.jpg`), a game preview (`play.mp4` + `contact-sheet.jpg`), the game report (`game report: cpp-report.html` linked, T903), and 0 `FAIL` lines in the `layout.txt` beside the film mp4; then `showcase: N/M ok`. `--json`: `{checks: [{ok, what}], ok, total}`. rc 0 all ok, 1 a line failed, 2 usage.

## Exact commands
```bash
showcase-page --out ~/drop/T745                       # rebuild; links relative, so --out must sit inside ~/drop
drop-link ~/drop/T745/index.html                      # checked https link
resp-check https://<tailnet-fqdn>:8470/T745/ --sheet ~/drop/T745/resp.jpg
bash ~/agents/bin/tests/showcase-page.test.sh         # fixture tree, < 1 s
showcase-page --check --drop ~/drop/T745 [--max-age 24h] [--json]   # no rebuild: ok|FAIL per line, `showcase: N/M ok`, rc 0/1/2 (T865)
```
Override roots with `--drop --motion --games --perf --followups`; `--now <epoch>` fixes ages for tests.

## Pitfalls (measured)
- `resp-check` on the file path cannot load `../T694/*.mp4` outside the folder; check the served https URL.
- The game contact sheet (T693) is a tall 4-row grid, so at 1366+ the two columns end at different heights; fine.
- The nightly perf-cpp.csv row is the template cube scene, not showcase-v2: rows say "nightly"; showcase-v2's own
  perf p50 (1.2647 ms) is on its cpp-ci `perf` stage row.
- A film whose drop copy was re-encoded (not byte-equal) shows "not found in ~/drop": drop the file again.
- `--check --drop ~/drop/T745` (2026-10-20, T947): `showcase: 3/10 ok`, rc 1: the 5 linked media under `../T694/` and `../T693/` are gone, `layout.txt` is missing and no `cpp-report.html` is linked (T901 saw 3/9, before the game report line).
- cpp-report (T903): a build runs `skills/gamedev/scripts/cpp-report <ci dir> --out OUT/cpp-report.html` for the newest cpp-ci summary and links it beside the game preview; no summary -> `no cpp-report (no cpp-ci summary)`, a failure -> `cpp-report failed rc N` in the page, never a broken build. Without `--drop` it checks `~/drop/index.html` (`0/1 ok`).
- T865 verifier: the film/game preview lines say ok when the media are linked, even if the files are missing; the media lines carry the FAIL. A film built with `MV_LAYOUT=0` has no layout.txt, so its layout line always FAILs.
- New CLI: `~/agents/install.sh --links` (done 2026-10-20).

## Links
- Code: `~/agents/bin/showcase-page`
- Tests: `bash ~/agents/bin/tests/showcase-page.test.sh`
- Design: `~/agent-work/research/2026-10-20/T731/BACKLOG.md` §14; page `~/drop/T745/` + `resp.jpg`
