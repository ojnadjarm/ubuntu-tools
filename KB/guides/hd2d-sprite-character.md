# HD-2D battle sprite for any character (FF Brave Exvius / Octopath look) from a spec file

Ticket: T1414, T1431 · Last verified: 2026-10-30 (card-faithful Tier with scaled riders, Gakaza roar, Orawk eyeball, blade glint) by `tests/selftest.sh` (Gamelyn checksum unchanged, 7 specs render)

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
- Heroes follow the character cards, not the game log's equipment (owner 2026-10-29, reverting a log-based rework): the log turned the lion
  gladiator into a human and the falcon vizier into a sorceress, both wrong. Ask for the cards; describe all four back and get a yes first.
- A "golden sword" in a card read is a guess: the owner wanted plain steel blades (Gamelyn a two-handed steel greatsword with a gold grip,
  `width` 2.9, `length` 31, `grip_mat` 'gold', no rune; the lion's scimitar steel, not blue). Steel ramp `#0b0e15`..`#eef2f6`, glow only on the edge (0.15).
- Overlay lines carried no glow, so lightning drawn with `m.lines` stayed flat: lines now take a 5th value (emission); `gear.lightning`
  draws a white core over three offset halo lines with tol 1e9, re-seeded per frame so the arcs re-strike.
- The vizier read as "too simple" (owner 2026-10-29): a hooded robe hides the card's silhouette. What read at 1.6 scale: no hood
  (`hood` False), a Dracula collar as a cone shell cut to the back half and a flat top (rim band 1 unit), two stacked rotated boxes per
  pauldron (6.6 x 1.8 x 5.4 and 5.0 x 1.4 x 4.8, rot_z 0.5) with a 0.13 gold rim and two spikes, a scaled tabard box with a stamp in front.
  Rims at 0.2 made the near pauldron read as solid gold. Late-binding closures: a texture lambda that captures `top` breaks when `top` is
  reused later in `extra()` (broadcast error); give closure vars unique names.
- The staff clipped through the near pauldron and the pauldron read too thick (owner 2026-10-29): `spellcast` puts the hilt at x 11.2
  aiming (0.2, 1, 0.16), straight up through a pauldron reaching x ~16. What cleared it in all 8 frames: a spec `pose` moving the hilt
  out (+5.6 x, +1.2 z) and tilting the staff to (0.62, 1.0, 0.26); pauldron plates 5.2 x 0.9 x 5.0 and 3.9 x 0.7 x 4.4, spike tip at x 6.6.
  At 3.4 out the shaft still grazed the gold rim corner: check a x10 crop of the shoulder per frame, not the whole sheet.
- A sheath across the back or on the main-hand hip hides behind the hair and the staff arm at yaw -0.6: the off hip (x -6.8, forward 3.4)
  is the only place the hilt shows.
- Card riders drawn at 1x (~22 px tall) read as blobs at battle size (T1431): a `Scaled(m, c, k)` proxy in the spec (SDF evaluated at
  (P - c) / k + c, distance x k, overlay points mapped out) draws them 1.35-1.5x without re-tuning any offset.
- A rider on the far shoulder at sh + (1.4, 6, -1.4) hid behind the bear's head at yaw -0.6; out and forward, sh + (-2.4, 6.4, 1.6), it reads.
- A golden sheen as body texture read as tiger stripes: keep it to the crown (`fur_h` where y > 3k and sin > 0.3). Brown fur at bias 0.3
  read khaki; a darker red-brown ramp at bias 0.1 reads grizzly under warm torches.
- A monkey with 2x2 dark eyes and a white tooth line read as a skull: 1 px eyes and a dark V grin with one white tooth read friendly.
- A held prop other than the orb (Orawk's floating eyeball): `offhand=None` keeps the stance's `off` hand pose; draw the prop in `extra()`.
- Blade glint (`glint=True` on sword or scimitar): a 4-arm star stamp plus an emissive dot sliding up the edge for ph < 0.5. Opt-in, so the
  template Gamelyn checksum in the selftest stays; stances now pass `ph`.

## Links
- Skill: `~/agents/skills/hd2d-sprite-character` (linked into `~/.claude/skills`)
- Project use: RunarStudio/Tiny_Epic_Narrator `arte/hd2d/pixel/personajes/`, PR #3
- Tests: `bash ~/.claude/skills/hd2d-sprite-character/tests/selftest.sh` (~70 s)
