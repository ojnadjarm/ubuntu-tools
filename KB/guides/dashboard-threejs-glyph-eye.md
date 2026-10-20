# Build a three.js WebGL page that is alive but idles at ~1 % CPU (dashboard glyph eye)

Ticket: T52–T56 · Last verified: 2026-10-20 by T846 audit (`test -e` on every path, `GRACE_S`/`EASE_S`/`ASK`/23rem in source, 174 tests collected, :19998 200); 2026-10-19 by dashboard pytest 170 passed + `test_next.js` + `test_pronunciation_page.js` ok, `tools/perf.py`, `next-measure.js` at 1920, `test -e` on every path

## When to use
- A new animated web page, 3D hero or data "eye" on this machine: start from the dashboard's `/` front end (Swarm eye) or its lab.
- Measuring fps, first-screen KB and idle CPU of any WebGL page in headless Chrome here: reuse the T53 measure script.
- Not for the Dark Eye phone page (`~/the-dark-eye/body/src/remote-www/`): it ran the same eye at full 60 fps idle by
  owner rule and costs ~20 % of a core (T56b). Not for WebGPU/TSL scenes: see guide `threejs-tsl-perf.md`.

## The path we took
- Library: three.js r186 as a **vendored tree-shaken subset**, `static/next/vendor/three.sub.js`, 133 KB gzip, built once
  with esbuild from a one-line export list (the command is in the file's first comment). Full ESM was 417 KB gz; no build step at runtime.
- No EffectComposer at first (T52): glow baked into the glyph atlas, additive blend, bloom 0 ms. T53 added HDR, 13-tap bloom, AgX.
- WebGL2, not WebGPU: same 24-layer noise shader on the Iris Xe, 1080p 22.3 ms (WebGL2) vs 24.0 ms (WebGPU) GPU time,
  and the WebGPU/TSL bundle is 248.8 KB gz vs 133.8 KB (`research/2026-09-23/T53/art-direction.md`).
- Eye variants behind one import: `static/next/js/gl/eye.js` picks `js/gl/eyes/{oracle,swarm}.js`; each exports
  `create(ctx, U)` → `{draw, probe}`. The lab (`static/next/lab/eye.html?v=a|b|c`, `lab/ui.html`) was deleted in
  `~/agents` commit f36c714 (2026-10-19); read it back with `git -C ~/agents show f36c714^:dashboard/static/next/lab/eye.html`.
- Render on demand (`static/next/js/stage.js` + `gl/engine.js`): `director.step` returns the wanted fps — 60 for input,
  travel and morphs, 30 while data settles, 12 idle life (blinks, saccades), 6 for the Court orbit (180 s a turn), else 0
  until `life.nextAt`. `wake(ms)` keeps rAF alive; hidden tab 0 frames; `prefers-reduced-motion` draws one still.
- Alive grace (T56a): any input, screen change or data pulse keeps ambient motion at 60 fps for `GRACE_S` 30 s, then eases
  1 → 0 over `EASE_S` 5 s (smoothstep on a `tempo` that scales every clock), so the downshift is invisible.
- Registry: a new screen is one line in `static/next/js/screens.js`. Rules for the tree: `~/agents/dashboard/CLAUDE.md`.

## Exact commands
```bash
cd ~/agents/dashboard
python3 -m pytest tests -q && node tests/test_next.js && node tests/test_pronunciation_page.js   # 170 + 2 green (2026-10-19); 174 collected 2026-10-20
python3 tools/perf.py                                             # endpoint timings, raw/gzip bytes
SCREEN=eye W=1920 H=1080 node ~/agent-work/research/2026-09-23/T53/build/next-measure.js          # fps, first KB, idle/hidden CPU
SCREEN=eye W=400 H=860 DPR=2 THROTTLE=4 node ~/agent-work/research/2026-09-23/T53/build/next-measure.js   # phone proxy
node ~/agent-work/research/2026-09-23/T53/build/next-shot.js         # shots at 400/768/1366/1920/2560 (responsive hard rule)
systemctl --user restart agents-dashboard && curl -sI http://127.0.0.1:19998/ | head -1
```

## Pitfalls (measured)
- Court orbit drawing every frame cost 31–36 % (T52b), 40–45 % (T53a) of a core; capped at 6 fps / 180 s a turn: 3.7 % (T53b).
- Idle budget met: visible idle 1.0–1.4 % of a core, grace 19.6 % (1920) / 18.2 % (400), hidden 0 frames (T53b, T54, T56a).
- On this Iris Xe the cost scales with the frame rate only: resolution, bloom passes and GL calls (180 → 118) barely move
  it (T56b: 20.1 → 19.6 %). Cut frames, not pixels.
- `next-measure.js` starts its 30 s idle window 5 s after the pointer input, inside the 30 s alive grace (T56a), so `idleCpu`
  reads grace, not idle (2026-10-19: idleFps 59.8, 38 % of a core at load ~9). For true idle set `IDLE=70` and use the tail.
- Headless Chrome cannot really hide a tab: the measure script overrides `document.hidden` and fires `visibilitychange`.
- Screenshots without GPU flags use software WebGL (T52a had no fps numbers). Launch with
  `--enable-gpu --ignore-gpu-blocklist --use-angle=vulkan --enable-features=Vulkan`.
- CPU is summed over the whole browser process tree from `/proc/<pid>/stat` (utime + stime), not the page's JS profile.
- Reduced motion froze the eye staring at the pointer (T53a); the still frame must reset gaze and ignore input.
- "1 needs you" vs digest "Nothing needs you": the digest line itself was counted as an ask (T54). One server list
  (`system.verdict`, negation-aware) now feeds the headline, list and badges; test `tests/test_needs.py`.
- "pick A/B/C" pushes did not count as asks (F18, 2026-09-26): `ASK` matches decide, pick, choose, say go, needs you.
- Brand truncated at 400 px: a stacked lockup by container query below 23rem, never ellipsis (T54).

## Links
- Code: `~/agents/dashboard/static/next/` (`js/stage.js`, `js/gl/{engine,eye,life,creatures}.js`, `js/gl/eyes/swarm.js`, `vendor/three.sub.js`)
- Tests: `~/agents/dashboard/tests/{test_next.py,test_next.js,test_needs.py}`
- Design / results: `~/agent-work/research/2026-09-22/T52/spec.md`, `research/2026-09-23/T53/art-direction.md`, scripts in
  `research/2026-09-2{2,3}/T5{2,3,4,6}/build/`, history lines in `~/agents/dashboard/CLAUDE.md` · briefs `~/agent-work/briefs/T5{2,3,4,6}-*.md`
- Skill: `frontend-design` (design plan and quality floor before code)
