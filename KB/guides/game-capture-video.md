# Game capture video: frame-exact gameplay plates from a browser game, cut with Moodle screens, VO and captions

Ticket: T1408 (on T1404) · Last verified: 2026-10-27 by a full capture of 17 plates + 3 Moodle stills and a 143 s 1080p60 render

## When to use
A gameplay, demo or trailer video of Mooblox (or any three.js/WebGL browser game) recorded headless at 1080p60 with no dropped
frames, cut in Remotion with voice-over and captions. Not for desktop screen recordings (`desktop` skill) or pure motion graphics
(`/motion-video` alone).

## The path we took
| Part | Tool | Why |
|---|---|---|
| Plates | mooblox `client/tools/trailer/capture.mjs` (T1404): virtual 60 fps clock, CDP screenshot per frame, ffmpeg x264 CRF 12 | frame-exact at any CPU load |
| Shot list | `--shots <file>`: `shots.mjs` (trailer), `gameplay.mjs` (T1408); each shot = url, until, settle, frames, setup, rig, keys, each, writes, teardown | data, not code, per video |
| Friendly names | `RENAME` export: session rewrites fixture names in pages and ajax JSON | no fixture renames in the DB |
| Moodle side | same tool, `moodle-*` shots as the teacher, `--stills` | same login and rename path |
| VO | `/kokoro-narration` af_heart 0.92 | house voice |
| Edit | Remotion (`/motion-video` film cache node_modules), `tools/timeline.py` → `timeline.json` | VO cue lengths drive cuts |
| Mix | `mv-mix` VO + CC0 bed, −16 LUFS; ffmpeg mux x264 slow CRF 16 | house pipeline |

## Exact commands
```bash
cd ~/projects/personal/mooblox/client
SITE=https://<tailnet-fqdn>:8452
node tools/trailer/capture.mjs ~/agent-work/motion/<T>/plates --site $SITE --user <kid> --password <pw> \
  --shots tools/trailer/gameplay.mjs --only hub,aerial,unlock          # one mp4 per shot, timings in stdout
node tools/trailer/capture.mjs <dir> --site $SITE --user <teacher> --password <pw> --shots tools/trailer/gameplay.mjs \
  --only moodle-rocks --stills                                          # PNG stills
~/agent-work/motion/T1408/build.sh                                      # timeline → vo track → mv-mix → remotion → mux → mv-review
```
Reference project: `~/agent-work/motion/T1408` (tools/timeline.py, edit/src/Main.tsx split screen, tools/page.py drop page).

## Pitfalls (measured)
- Capture wall time ≈ 7.5× real: aerial 1500 fr 186 s, props 1200 fr 185 s, unlock 960 fr 128-130 s, hub 540 fr 75 s, 270-fr panel shots 35-42 s.
- VO is longer than the action: plates played at < 0.6× look like slow motion. Capture camera-only shots long (aerial 25 s, props 20 s).
- Haze follows the kid's island and props draw only on the live island: teleport the kid into the zone you orbit, or it is flat fog.
- Aerial first frames show flat impostors: settle 900 frames before recording.
- Gates exist only for sections closed at page load; open one with `gate.set(false, '', 'Open!')` (0.9 s swing).
- The Guide NPC trails the kid and dithers away when it stands in the sight line: hide it (`m.guide.avatar.root.visible = false`).
  A kid on a bridge deck reads blue-grey from the haze; that is the game's look, not a fade (3 unlock re-captures, ~2 min each, to learn this).
- Panels hold still: mv-review flagged 4 frozen spans (2.6-3.9 s); a 4% push-in on full-frame shots leaves only the end card.
- Remotion's picture carries sRGB transfer: the mux needs `-bsf:v h264_metadata=transfer_characteristics=1` for a clean bt709 tag.
- Drop page: a 4-column script table needs `min-width: 0` under 700 px or `resp-check` fails 400 px (−124 px margin).
- Ajax JSON escapes non-ASCII as `\uXXXX` (course index "Étape"): RENAME must replace the escaped form too.
- Moodle stills: zoom 1.4 and hide the course index drawer by injected CSS (drawer skeleton shows otherwise; no preference written).
- Writes are faked by default; a shot that must write lists them in `writes` and reverts in `teardown` (check the DB value after: cm 965 back to 0).
- T1404: `holdTimers` for panels, warp block 204, embedded iframe is blank ~1.4 s virtual time.
- `wait-for` has no `--timeout`; a killed capture can leave a hung node + ffmpeg: `pgrep -af '[t]ools/trailer/capture'` before the next run.
- Remotion 143 s 1080p60 + mux: 6-7 min at concurrency 6; use `--gl=angle`; `--gl=swangle` while a capture holds the GPU.

## Links
- Code: `~/projects/personal/mooblox/client/tools/trailer/` (capture.mjs, session.mjs, shots.mjs, gameplay.mjs)
- Project: `~/agent-work/motion/T1408`; result `~/drop/T1408/index.html`
- Guides: `guide motion-video`, `guide kokoro-narration-word-timings`
