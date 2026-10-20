# motion-video reference: production line (mv-new, build.sh, mv-review, mv-report, mv-otio)

```bash
mv-new <name> --kind promo|explainer|3d|film [--brand brand.json]   # -> ~/agent-work/motion/<name>: template + brand.json + build.sh (film, T619: 3 Blender shots cut on downbeats + titles + sfx + mix, VMAF + review gated)
mv-new <name> --kind trailer --game <cpp-vulkan dir>        # T640 film build whose plates are 3 replay windows (round GAME pickup/win ticks) of build/dev/game + input/trailer.json, captured via cpp-vk-run.sh --size WxH (kiosk shell) --capture-every; game --audio-out cut per window as SFX under the music; 30 s 1080p60 (draft 320x180 3 s 12 fps, tests/mv-trailer.test.sh)
cd ~/agent-work/motion/<name> && ./build.sh                     # [Kokoro VO] -> 16:9 + 9:16 renders -> mix + captions -> film LUT -> h264 -> mv-review
mv-review out/<name>-16x9.mp4 [--out dir] [--scopes] [--no-pse] # contact sheet 1 fps + LUFS/true peak + black/frozen + legal Y 16-235 (>0.1 % of a frame FAILs; mv-encode limits to it) + photosensitive flashes (any 1 s with > 3 general or saturated-red flashes over >= 25 % of the screen FAILs, timecodes printed; ITU-R BT.1702/WCAG 2.3.1); --scopes: waveform+vectorscope PNG; exit 1 on FAIL
mv-report out/                                                  # T641 one self-contained <name>.report.html per review.json: checks FAIL first; LUFS M/S, flashes/s, VMAF/s lanes with build.json cuts + cues.json marks on one timecode axis; sheet thumbs link to video#t=S; build step times; a missing JSON = lane omitted + note (film build.sh runs it last)
```
- Kinds: promo = Remotion `Main` (+ `LottieCard`), 3d = Remotion `Camera3D`, explainer = Motion Canvas (`MV_SIZE=1080x1920` per aspect).
- Brand tokens: `brand.json` (fonts, palette) is the only place colours/fonts live; `src/brand.ts` exports `FONTS`, `PALETTE`.
- `build.sh` env: `COMP NAME LUT=film VO_AT=1.0 MUSIC ASPECTS="16x9:1920:1080 9x16:1080:1920" SFX="f@sec@db f@cue:NAME[+ms][@db] ..." (cue names from vo/cues.json, T545) PRESET`; refuses at load >= 16; writes `out/build.json` (per aspect render_s, mix_s, encode_s, review PASS|FAIL, reasons) and exits 1 naming each aspect whose mv-review FAILed (T534). Both build.sh (this and film/trailer) end in `mv_finish` (`scripts/mvlib.sh`, T676): build.json `review` + `fails`, one `creative-ci.jsonl` line (tool `mv-build`, gamedev ci-lib `ci_log` schema) so a red build shows in `pc failures`.
- `mv-otio out/` (film, T646): build.json `.edit`, written only when the build ran with `MV_EDIT=1` (T720; default 0 skips edit_media and leaves `.edit` null) (graded plates, alpha title, music bed, SFX at their cues, kept in `out/edit/`) -> `<name>.otio` + `.kdenlive` (+ `.fcpxml` at FCP rates) on absolute paths; retime a shot in Kdenlive, or `melt out/<name>.kdenlive -consumer avformat:cut.mp4`.
- VO: put a Kokoro `vo.unit.json` in the project; `{marks}` drive scene cuts (`src/cues.ts` pattern in the T478 reel).
- Lottie: `@remotion/lottie` + `lottie-web` are in the template; drop After Effects/bodymovin JSON in `public/lottie/`, see `LottieCard`.
- Motion Canvas footage inside Remotion: `mv-render mc` (PNG sequence -> x264 crf 10) into `public/`, then `<OffthreadVideo>`.
- Reference project: `~/agent-work/motion/T478/reel` (+ `diagram`), reel in `~/drop/T478/`.

