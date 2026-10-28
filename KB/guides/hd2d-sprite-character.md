# HD-2D battle sprite for any character (FF Brave Exvius / Octopath look) from a spec file

Ticket: T1414 · Last verified: 2026-10-28 by `tests/selftest.sh` (Gamelyn pixel checksum unchanged, 7 specs render incl. kobold, kobold_alzado, kobold_espectral) and 1080p renders of both sarcophagus variants (Tiny Epic Narrator)

## When to use
A new hero, monster rider or NPC in the HD-2D style next to Gamelyn: FFBE anime face, lamed armour, glowing weapon, battle idle.
Not for Godot walk sheets (/pixel-avatar) or the 3D set itself (guide hd2d-sprite-scene).

## The path we took
- Survey: /pixel-avatar (T702 SDF tracer, walk sheets) existed; the Gamelyn module (T1414) held every owner-approved detail but
  was one 250-line file. Chosen: split it into parts behind a spec, ported first and checked pixel-identical (8 frames x 3 maps, 0 px diff).
- Modules: `core/rig/hands` (tracer, unchanged but for `glow`), `parts` (bands, lames, blades), `body` (plate, gladiator, robe, beast +
  their arms), `heads` (anime, lion, falcon, bear), `gear` (cape, sword, scimitar, staff, shield, orb), `stances`, `character`
  (dispatch tables, open for new kinds without editing the builder), `sprite` (CLI). Spec files: `chars/*.py`.

## Exact commands
```bash
S=~/.claude/skills/hd2d-sprite-character
$S/scripts/new-character mira knight /tmp/chars
python3 $S/scripts/sprite.py /tmp/chars/mira.py /tmp/mira --frames 0 --sheet /tmp/mira.png
bash $S/tests/selftest.sh
```

## Pitfalls (measured)
- A glowing blade went white twice: an emissive near-white ramp, then albedo x (2.2, 3.2, 4.0). What kept it light blue in AgX:
  a saturated ramp topping at `#a8e0ff`, mask `glow` 0.55, and emission = albedo squared x 3 in the scene shader (non-glow pixels keep 0.2 x albedo).
- Standing in the god ray washes any sprite; Gamelyn at x 1.6 lost the blade colour, at x 1.9-2.0 it held.
- Parts placed at nominal radii end up inside a bigger body (bear harness straps at z 8.6 inside a z 10 belly): draw straps as texture bands on the body.
- Riders behind the head vanish at yaw -0.6: put them on the shoulders (x +/-10, forward 5).
- Warm torch light pushes a maroon ramp to salmon: start the fur ramp darker (top `#c05444`, bias 0).
- Party spacing: 0.5 m in depth between rows overlapped heads and feet; 2.5-3 m between rows at lens 58 reads cleanly.
- Old pose modules that monkey-patch `gamelyn.pose` break once Gamelyn is a spec; poses now live in `stances.py` + `SPEC['pose']`.

- Hands at scale 1.6 are ~6 px: a two-segment finger box read as a blob (owner: every pose looked odd). What reads: `hands._wrap`, a rounded
  fist box round the handle + back of hand + thumb cone, TWO knuckle seams (`hand_d`, thin texture bands); four seams turned to a checker,
  alternating finger materials with the outline pass turned to a black grid.
- `_selout` outlines hand pixels against any non-hand material only; seams come from the darker `hand_d`, not from outlines.
- Metal shading on a 6 px hand is env-reflection noise (dark navy speckle): hands are matte (`wrap` 0.55) on the armour ramp, `hand_bias` +0.5.
- Thumbs and palms must face the camera: in sprite space that is `hands.VIEW` (0.56, 0.3, 0.78) at yaw -0.6; a palm set to +z with the far
  paw at -x was edge-on and the four claws fused into one blade.
- Two-handed grip: hands 4.9 apart along a 9-unit grip (`grip`, `back`); 2.8 apart overlapped into one lump.
- Elbow cops of radius 2.2 next to the grip stole the read; 1.7 keeps the hands the focus. Gold cuffs larger than the fist (2.5) looked like a gold ball.
- Bigger `scale` (2.2) would add pixels but shrinks the fixed-size eye stamps: the approved FFBE face changes. Stay at 1.6.
- Kobold (T1414 v6): stance hilt coordinates are absolute, so a small body (`height` 0.88) needs its own stance (`skulk`, hilt y 14.6);
  borrowing `low_guard` put the hands above the head. A spear along +z (the facing) foreshortens to a stub at yaw 0.55: aim it (0.72, 0.2, 0.62).
- A short snout (cone to z 7.4) read as a dog; z 8.8 plus a jaw hanging open 0.9-1.2 with five needle teeth per side reads as a reptile.
  A pink frill membrane read as a hair bun: keep frills in the scale hue.
- Spectral variant: at 0.5 m the ghost washed to white three times in the scene (emission = albedo x 6, then a near-white ramp top,
  then Principled specular catching the moon). What held cyan: ramp topping at `#5adcc4`, emission colour = luminance x (0.12, 1.0, 0.8),
  strength 2.8 + 6 x mask, Specular IOR Level 0, alpha 0.68 fading over the bottom 20% of the plane, and a numpy-blurred alpha aura plane behind.
- Variant specs (`kobold_alzado`, `kobold_espectral`) load `kobold.py` by path next to them: copy the base with them.
- Heroes follow the game log, not a guessed species (T1414, 2026-10-28): Gakata had been a lion gladiator and Ojo Penetrante a falcon vizier;
  the log says knight with Knight's Cuirass + Lightning Staff and a sorceress. Read the log's equipment before picking a head or body kind.
- Overlay lines carried no glow, so lightning drawn with `m.lines` stayed flat: lines now take a 5th value (emission); `gear.lightning`
  draws a white core over three offset halo lines with tol 1e9, re-seeded per frame so the arcs re-strike.
- A sheath across the back or on the main-hand hip hides behind the hair and the staff arm at yaw -0.6: the off hip (x -6.8, forward 3.4)
  is the only place the hilt shows.

## Links
- Skill: `~/agents/skills/hd2d-sprite-character` (linked into `~/.claude/skills`)
- Project use: RunarStudio/Tiny_Epic_Narrator `arte/hd2d/pixel/personajes/`, PR #3
- Tests: `bash ~/.claude/skills/hd2d-sprite-character/tests/selftest.sh` (~70 s)
