---
name: vass-ticket-video
description: Spanish narrated antes/después video for a VASS ticket from a JSON shot list (front or back steps, highlights, WS side-by-side); edge Álvaro voice; mp4, stills and guion.md in ~/drop/<ticket>/ with a checked link. Use for "antes video", "después video", "repro video".
---

Triggers: VASS video, antes/después, replication video, fix video, ticket video, Marina video, campus front video.

# vass-ticket-video: shot list -> narrated mp4 in ~/drop/<ticket>/

```bash
V=~/.claude/skills/vass-ticket-video/scripts/vass-video
$V --check shots.json                                   # schema only, no browser
$V shots.json                                           # -> ~/drop/<ticket>/<ticket>-<phase>.mp4 + stills + guion-<phase>.md + index.html, links
$V shots.json --out ~/drop/<ticket>/try --name x --work /tmp/w   # scratch output, keep intermediates
~/.claude/skills/vass-ticket-video/tests/selftest.test.sh   # offline selftest (no browser, no network)
```

Shot list (keep it in `~/agent-work/research/<date>/<T>/`: it names test users, so never in a tracked file):
```json
{ "ticket": "jira29", "phase": "antes", "front_user": "<student-email>", "back_user": "admin",
  "steps": [
    { "go": "/results/summary", "wait": "text:Netas (último",
      "say": "En Resumen, la tarjeta de {hl}netas muestra menos cinco coma treinta y tres.",
      "highlight": ["Netas (último*"], "still": "resumen" },
    { "click": "link:Objetivos", "wait": "text:Netas (último", "say": "…", "highlight": ["Tu baremo"] },
    { "site": "back", "go": "/admin/settings.php?section=x", "wait": "css:#id_s_x", "say": "…" },
    { "ws": [ { "label": "Resumen", "fn": "local_results_get_results_summary", "user": "<student-email>", "args": {},
                "pick": ["current_netas", "current_order_number"] },
              { "label": "Objetivos", "fn": "local_results_get_objectives_view", "user": "<student-email>",
                "pick": ["current_netas"] } ], "say": "Los dos servicios devuelven valores distintos." },
    { "say": "{hl}Resumen y Objetivos no coinciden.", "overlay": { "title": "Netas", "cols": [
        { "label": "Resumen", "value": "-5,33", "note": "netas", "color": "#e11d48" },
        { "label": "Objetivos", "value": "-4,74", "note": "netas equivalentes" } ] } } ] }
```
- Per step, in order: `go` (path on `site` front|back, or a full URL) / `ws` view → `click` → `fill` [{sel, value}] → `wait`
  (selector or ms) → `settle` ms (default 1200) → the narration line starts → `highlight`/`overlay` at the `{hl}` word (or at once)
  → `still` screenshot near the end → the step lasts the clip + `hold` s (default 0.6).
- Selectors: `link:`, `button:`, `tab:` (exact accessible name), `text:`, `css:`. Highlight labels: exact text, `Prefix*`, or `css:`.
- `ws` runs the function as `user` in the Moodle container and shows only the `pick` fields (dotted paths); token-like
  fields are redacted. Write `say` in natural Spain Spanish, numbers in words ("menos cinco coma treinta y tres").
- Config (config.env, keys in `config.example.env`): `VASS_STUDENT_PASSWORD`, `VASS_MOODLE_PASSWORD` (default
  `MOODLE_ADMIN_PASSWORD`), `VASS_FRONT_URL`/`VASS_MOODLE_URL` (default `https://<tailnet-fqdn>:8446` / `:8445`), `VASS_MOODLE_CONTAINER`.
- Phases: narration (edge, ~10 s) → ws → recording (real time: the sum of the clips plus page loads) → assemble (~15 s) → links.
- Every report gives the direct https `.mp4` link (the `mp4:` line the CLI prints), not only the folder.

## Después (owner rule, 2026-10-29)
The después video assumes the viewer saw antes. It does not explain the issue again: it has at most one short `recall` line
(≤ 15 words), then shows the fix on the same steps and screens as antes, and it is never longer than antes. Write it without
`steps`; the CLI reads `guion-antes.md` (in `--out`, else `~/drop/<ticket>/`), finds its `Shot list:` and reuses those steps:
```json
{ "ticket": "jira29", "phase": "despues", "recall": "Antes, el Resumen mostraba las netas sin convertir.",
  "say": ["Ahora la tarjeta del Resumen {hl}muestra menos cuatro coma setenta y cuatro.", null, "Igual que en {hl}Objetivos.", null],
  "overrides": { "2": { "highlight": ["Netas (último*"] } } }
```
- `say`: one line per antes step; `null` drops that step (its go/click/fill/wait still run, silently, before the next one). Antes overlays are dropped because they show the bug; add new ones in `overrides` (by antes index).
- Refused: a recall over 15 words, more words than antes, a `say` list of the wrong length, or a missing `guion-antes.md`.

## Pitfalls
- Seed the data first (dev DB is fine): the skill films, it does not create attempts or fix code. Después: apply the fix, re-run with `"phase": "despues"`.
- `mws` refuses the VASS env: `ws` steps use `docker exec -i <container> php` with the skill's `ws.php` instead.
- Locally only `en` is installed: Moodle back pages show English strings; say so in the narration, or film the front.
- Live classes need `$LIVECLASS_JWT_SECRET` in config.php; Vimeo does not play headless (use a YouTube URL).
- mv-review fails screen recordings on `frozen` and `levels … brng <0.01`; assemble treats those as expected.
- Never print tokens: Playwright errors carry cookies and JWTs; the scripts print the first error line, redacted.
- A slow front can time out a `wait` (1 of 6 live runs on 2026-10-29): the error names the step and saves `fail.png` in the work dir; re-run.
- Full guide: `guide vass-ticket-video`.
