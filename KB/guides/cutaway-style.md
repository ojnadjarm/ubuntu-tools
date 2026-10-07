# Cutaway plate art direction: draw a narrated technical-drawing plate (and the taste bar for any art direction)

Tickets: T71, T75, signatures T81, buttons T91, readouts T95/T97, sheet change T96, kit dedupe T100, skill split T101, legibility T109, straddled press T107, review T111 · Last verified:
2026-09-26 (T100: kit tests 7 pass, the site's full `npm run ci` with the button system and plate readouts on U01; earlier stills at
400/768/1366/1920/2560, perf probe, framing check 6 → 0 faults)

## When to use
- A learning-game plate, a technical-drawing or blueprint explainer, or a project that chose this look: skill `/cutaway-style` (a short
  router; the how-to lives in its `reference/*.md`) and the kit. This guide keeps the taste calibration, the history and the measured pitfalls.
- **This is not the default art direction.** It suits the learning games; other projects explore their own direction with mockups that the
  owner judges. For any visual work, the taste standard below still applies.

## The standard of taste (applies to every art direction)
The owner judged three T71 mockups and gave these verdicts. They are the calibration:
| Mockup | Verdict | Why |
|---|---|---|
| Cutaway plate | "insanely good … the visual, art and good taste quality I want … 10 times better" | a real tradition (NASA cutaways, patent blueprints, Byrne's Euclid), executed faithfully and densely |
| Rams plate | "good representation, not good art, but well designed … normal" | tidy and correct, but no tradition and no richness |
| Night bench | "a good attempt to represent 3D but not good quality" | faked depth (glow, bevels, dark stage) reads as cheap |

To reach the bar:
1. **Pick a real visual tradition** (a drafting style, a print technique, a school of illustration), and study its references before drawing.
2. **One coherent idea.** Every mark follows that tradition's grammar; if a mark has no meaning in it, it does not go in.
3. **Execute it with craft.** Put true detail on every part, use a line and type hierarchy, and restrict colour to meaning. Clean and correct
   is only the floor.
4. **Honest over impressive.** Flat and faithful beats a half-convincing imitation of 3D or of realism.
5. **Let the owner judge.** Build 2–3 directions as mockups and show them to him, and never ship a new direction he has not seen (skill
   `/research-swarm` for the fan-out).

## The path we took
- **T71**: three direction mockups; Cutaway plate won. **T75** moved its `src/plate/` into the kit `~/agents/kits/cutaway/` (tokens, `Ink`,
  geometry, `framing`, `Stage`, `OnDemand`, motion, a dial spring, parts) with a runnable starter ("The Regulator"); every new plate copies it.
- **T81**: title-block signatures (DRAWN / APPROVED; the owner chose `drawn: 'Claude', approved: 'Oscar Nadjar'`).
- **T91**: the button system. The owner chose B "hatched section" over A (title-block cells) and C (keyed labels) from
  `~/agents/research/2026-09-25/T91/mockups/buttons.html` (its `~/drop/t91/` copy is gone).
- **T95 → T97**: readouts. The owner rejected loose centred text rows under the gauges, and a free-text tally, as "lazy and out of tone". He
  first typed "B", then corrected it to "IS A": T95 built B, T97 switched to A, data plates. Cue layering (`Z.cue`) came in T95.
- **T96**: one transition language for sheet changes (site `src/site/sheet/`).
- **T100**: the kit's motion, loop and captions re-export the explainer-kit engine (duplicates gone); U01 imports the kit's `geom` and `parts/part`.
- **T101**: the 16.5 kB skill became a 3.6 kB router plus 5 reference files; this guide lost its how-to duplicates.

## Exact commands
```bash
guide cutaway                                   # this page + skill /cutaway-style
cd ~/agents/kits/cutaway && npm test            # kit: framing maths (7 tests)
cp -r ~/agents/kits/cutaway/starter ~/path/my-plate   # then the skill's reference/start-a-plate.md
node tools/fit-shots.ts left=slope,size         # per shot: what it cuts + nearest whole box on 5 desktop viewports
node tools/shot.mjs http://127.0.0.1:18975/ 2560 out/s 1,8,18   # prints the look gate per still
node tools/perf.mjs http://127.0.0.1:18975/
```

## Pitfalls (measured)
- **Sheet changes (T96):** measured before (Chromium, 400–2560, Pixel 7, 1× and 4× CPU, 72 runs): 8 blank and 75 white frames, the turn before
  the plate in 21/21 desktop forward runs, fonts finishing mid-turn in every run, first presses 37–43/50, a double press 2 navigations. After
  (1366/1920 at 1×, 10 trials per button): 0 blank, 0 white, 0 early turns, 10/10 presses, 1 navigation per double press. A leaf added at
  `pageswap` flashed one blank frame; without `preserveDrawingBuffer` 21 white frames → 0 with it. A clip-path turn stalled at 1920 (only
  transforms animate now). Guide `learning-site-homepage`.
- **A title block cut at the frame edge** (the T71 2560 px clip): the `wall` shot framed the sheet down to y = -900 and cut the block.
  `framingFaults` found 6 faults over 5 desktop viewports; moving the sheet bottom to -1300 and the open shot to (0, 15, 2300, 2670) brought it to 0.
- **Passing tests, empty look** (T75 dogfood, gradient plate): framing and perf green, but 0.6 % primary, 48 % bare, a 6×6 bare block; the
  owner-grade neuron plate reads 4.6–6.5 %. The richness rules took the rest shot 0.73 → 4.66 % primary; `look.mjs` now gates it.
- **Idle that was not idle**: the starter drew 180 frames in 3 s after the script ended (flow kept running while the audio clock reported
  playing); gated on `watching && playing` it draws 2.
- Stills taken after the script ended showed the wrong shot until the script was seeked to its end before hand control started.
- The first frame's draw (21–23 ms) is the load: `perf.mjs` reports it as `firstDraw`, outside `drawMax` (3.3 ms).
- Headless stills without the GPU flags fall back to software rendering. `node --test test/` fails (the directory is treated as a file).
- **Dynamic `LineSegments2` truncated**: three caches `geometry._maxInstanceCount` at the first draw, so only one leap arc and no detail ring showed.
- **Scale end labels clipped** (column "6") until padded 12 units each end.
- **Labels cut by narrated holds** were missed by the static framing test; `heldFaults` checks every held moment, and `fit-shots.ts` moved 4 of
  6 gradient shots.
- **Readouts (T97):** at the tuning shot 1 unit ≈ 0.62 px at 1920, so 14-unit labels read 8.7 px (now 18 → 11 px, values 30). A 104-unit plate
  at row pitch 318 met the next row's title (358 fits: rows 316 / −42). The gauge's dash-dot centre mark runs to r + 30 and crossed a plate set
  6 below (leave 22). Dotted leaders of 1.4-unit segments aliased into broken dashes (dashed material now). The tally box must stay 40 units
  from the plaque (`place.test.mjs`: "control plaque × part race").
- **Buttons (T91):** contrast ink/paper 13.5:1, blue hover 5.4:1, hatch 3.4:1; the T88 "Go to Tuning" chip was the box-in-box anti-pattern.
- **Perf, measured** (i5-12500H, Iris Xe, headless GPU flags) against the skill's budget:
  | Measure | Neuron (T71) | Starter (T75) |
  |---|---|---|
  | First paint over the https drop | 213–289 ms | 266–359 ms (dev) |
  | Load long task | 99–136 ms | 63–74 ms |
  | Plate build | 39–52 ms | 24–31 ms |
  | Playback rAF max / frames > 20 ms | 16.8 / 0 | 16.8 / 0 |
  | Draw CPU per frame p50 / max | 0.6 / 4.9 ms | 0.4 / 3.3 ms |
  | JS gzip | 192 kB | 184 kB |
  | Idle frames (3 s after settling) | — | 2 |

- **A sign on hatching is unreadable** (T109): the e6 "miss ±x" goal was drawn over the frame and gauge hatching, so the owner could not
  tell + from −. A paper ellipse behind the miss goal only (`GoalRing` `ground`) fixed it; the Fig. 6 plates were already on solid ground.
- **A press that straddles the end of a page turn** (T107): down on `<html>` under the overlay, up on the button, click on `<html>`, lost.
  `turn.js` now remembers the press and routes its click after the turn. Measured with real presses only.

## Links
- Code: `~/agents/kits/cutaway/` (kit), `~/agents/kits/cutaway/starter/` (template plate); readouts in the site repo
  `units/01-neuron/plate/parts/readout.ts`; sheet change `src/site/sheet/`
- Skill: `~/.claude/skills/cutaway-style/SKILL.md` + `reference/{start-a-plate,drawing-rules,parts-and-readouts,buttons,sheet-change}.md`
- Reference: `~/agents/research/2026-09-24/T71/mockups/cutaway-plate/` (the `~/drop/t71/` copy is gone)
- Design / results: `~/agents/research/2026-09-24/T71/` (directions.md, stack.md), `~/agents/research/2026-09-24/T75/findings.md`
