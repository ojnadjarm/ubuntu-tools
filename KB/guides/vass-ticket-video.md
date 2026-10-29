# VASS ticket antes/después video in Spanish from a shot list

Ticket: T1430 · Last verified: 2026-10-29 by re-rendering the JIRA-29 antes video through the skill alone (122 s wall) and the offline selftest (34/34)

## When to use
Every VASS ticket ships a Spanish "antes" video (bug replicated) and a "después" video (fixed), per the owner rule in the
VASS memory `vass-repro-and-fix-videos`. Use this for the campus front (:8446), Moodle back pages (:8445) or a WS JSON
side-by-side view. Not for game or promo videos (/motion-video) or English explainers (/kokoro-narration + explainer-engine).

## The path we took
Survey: /kokoro-narration (edge Álvaro voice, word timings), /motion-video (`mv-encode`, `mv-review`), /drop-link and the
T1383/T1424/T1429 Playwright scripts already existed. The skill chains them instead of copying them.

| Piece | Job |
|---|---|
| `shotlist.mjs` | schema check, narration unit (one edge clip per step, `{hl}` cue), error redaction |
| `ws.php` | runs one external function as a user inside the container; prints only the `pick` fields |
| `shoot.mjs` | headless Chromium `--mute-audio`; logs in to the front by e-mail and the back as admin before recording; each step: action, wait, line starts, highlight/overlay at `{hl}`, still, hold for the clip |
| `assemble.py` | trims the head to the first line, mixes clips at their marks, captions from word timings, `mv-encode h264-web --burn`, review gate, stills, `guion-<phase>.md`, `index.html` |
| `vass-video` | the CLI: narration → ws → recording → assemble → `drop-link` |

## Exact commands
```bash
V=~/.claude/skills/vass-ticket-video/scripts/vass-video
$V --check ~/agent-work/research/<date>/<T>/<ticket>-antes.json
$V ~/agent-work/research/<date>/<T>/<ticket>-antes.json            # ~/drop/<ticket>/<ticket>-antes.mp4 + links
$V shots.json --out ~/drop/<ticket>/try --name trial --work /tmp/w  # scratch output, keep intermediates
~/.claude/skills/vass-ticket-video/tests/selftest.test.sh                # offline, ~11 s
```
Config keys (config.env; documented in `config.example.env`): `VASS_STUDENT_PASSWORD`, `VASS_MOODLE_PASSWORD` (default
`MOODLE_ADMIN_PASSWORD`), `VASS_FRONT_URL`, `VASS_MOODLE_URL` (default `https://<tailnet-fqdn>:8446` / `:8445`),
`VASS_MOODLE_CONTAINER`. Shot lists name test users, so they belong in `~/agent-work`, never in a tracked file.

Owner rule (2026-10-29, corrected): the antes video sits on the same ticket, so después does not show or re-explain the old
error. It goes straight to the change working, and its length scales with the change: a small fix gets a very short video
showing only the one screen that is now right; a big change takes as long as it needs (no length limit). By default a después list has
no `steps`: an optional `recall` and `say` (one line per antes step, `null` drops a step); its own `steps` are fine too. The CLI reads `guion-antes.md` (its `Shot list:` line) and reuses the
antes steps without their overlays. See SKILL.md for the format. Every report gives the direct https `.mp4` link.

## Pitfalls (measured)
- Speed: JIRA-29 antes took 396 s by hand in T1429 (explore → 3 recordings → link) and 122 s through the skill. Of that,
  narration was 19 s, ws 0 s, recording 69 s (real time: 54 s of clips plus page loads) and assemble 34 s, including mv-review.
- `mws` refuses the VASS env ("Vass and 4.5 are never touched"). `ws` steps use `docker exec -i <container> php -- '<job>' < ws.php`
  (6.6 s for 2 calls). `call_external_function` from CLI fails with "session has been logged out"; `ws.php` calls the class directly.
- Playwright errors dump request headers with the session JWT and the Moodle wstoken (T1429 printed one). The scripts print only
  the first line, redacted, and `unrouteAll` before closing a context: closing with a pending `route.fetch` throws exactly that dump.
- The newest npx Playwright (1.64, `e41f203…`) has no installed browser; `shoot.mjs` picks the first build whose Chromium exists.
- render_narration needs `"speed"` in the unit even for edge (KeyError otherwise). Edge needs network.
- mv-review fails every screen recording on `frozen` (8-10×) and `levels Y 10-249 brng 0.0023` (white UI). The assemble gate
  accepts only those two; anything else (black, flashes, loudness) still fails.
- Playwright's video starts at page creation, so the first 3.8 s were a "Cargando perfil…" spinner. Assemble trims to 0.4 s
  before the first line.
- Local editions are all past `secondcalldate`, so results cards say "último Simulacro"; seed Simulacro attempts and say so.
- Only `en` is installed locally: back pages show English strings (T1427). Live classes need `$LIVECLASS_JWT_SECRET` in config.php;
  Vimeo does not play headless, so use a YouTube URL (T1424).
- 2026-10-29: the VASS `config.php` was mode 600 after a restore from backup (ctime 09:55). Moodle pages died with "Permission
  denied" while `login/token.php` and the WS still answered from opcache, so the front kept working. The back login now fails
  fast with "Moodle login page broken".
- Flaky front: 1 of 6 live runs timed out on a 30 s `wait` (front slow, then fine on re-run). The error names the step and
  saves `fail.png` in the work dir.
- Después proof (mechanics): the JIRA-29 después list (2 kept steps, 1 dropped) rendered 12.7 s against
  antes 54 s, in 40 s wall. Dropping antes step 1 broke the next step's `click` until dropped steps' actions ran silently (`pre`).
- Measure the antes/después pair on the same data: seed first (dev DB is fine), record antes, apply the fix, then re-run the
  same shot list with `"phase": "despues"`.

## Links
- Code: `~/agents/skills/vass-ticket-video/` (SKILL.md, scripts/)
- Tests: `~/agents/skills/vass-ticket-video/tests/selftest.test.sh` (schema, unit, redaction, assemble on a synthetic recording)
- Design / results: `~/agent-work/research/2026-10-29/T1430/` (JIRA-29 shot list, proof run), T1429 report `~/agent-work/briefs/T1429-report.md`
