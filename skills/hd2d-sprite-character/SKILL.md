---
name: hd2d-sprite-character
description: Build HD-2D battle sprites (Octopath / FF Brave Exvius look) for any character from a short spec - palette ramps, body/armour kind (plate knight, gladiator, robed caster, upright beast), head (FFBE anime face and hair, lion, falcon, bear), weapon (glowing longsword, scimitar, staff), off hand (shield, spell orb), cape under the pauldrons, battle stance (low guard, high guard, caster, brawler) - ray-marched SDF to pixel art with outlines, normal map and emissive mask per frame, ready for planes in a Blender diorama. Use for "HD-2D character", "2D HD sprite", "FFBE sprite", "Brave Exvius style", "Octopath sprite", "new hero sprite like Gamelyn", "party sprites", "pixel knight/mage/beast". Not for walk-cycle sheets for Godot (/pixel-avatar) or the 3D set (guide hd2d-sprite-scene).
---

# hd2d-sprite-character: one spec file per character -> 8-frame lit battle idle

Origin: T1414 (Tiny Epic Narrator, Gamelyn approved by the owner 2026-10-28, then the whole party). Guides:
`guide hd2d-sprite-character` (this skill), `guide hd2d-sprite-scene` (the Blender diorama and its pitfalls).

## Workflow
```bash
S=~/.claude/skills/hd2d-sprite-character
$S/scripts/new-character mira knight <dir>                          # copy a template: knight | gladiator | caster | beast
python3 $S/scripts/sprite.py <dir>/mira.py /tmp/mira --frames 0 --sheet /tmp/mira.png   # 1 frame, ~3 s: iterate here
python3 $S/scripts/sprite.py <dir>/mira.py <sprites>/mira --cell 176                    # 8 frames: a##, e## (emissive), n## (normal)
bash $S/tests/selftest.sh                                           # Gamelyn pixel checksum + every template renders
```
1. Copy the closest template from `chars/` (gamelyn = knight, gakata = gladiator, ojo = caster, tier = beast + riders).
2. Restyle in this order: `RAMPS` (8-9 steps, dark navy to near-white), `MATS`, then `SPEC` keys, then `extra()`.
3. Read one zoomed sheet (`--sheet`, x3 nearest) per change; never a loop of screenshots.
4. In a scene: same `scale` (1.6) for every character, plane pixel = `HERO_PX = 1.12 / 1.6` of the 3.5 screen-px grid, yaw -0.6
   for the party facing left, cell 176 (240 for a big beast with a familiar).
5. Vendor `scripts/*.py` and the spec files into the project (`arte/hd2d/pixel/`, `personajes/`) so the repo builds alone.

## Spec contract (`character.py` docstring)
| Key | Meaning |
|---|---|
| `RAMPS`, `MATS` | ramps by name; `mats` entries `(ramp, {kind: metal/skin/cloth/emis, bias, wrap, gamma, glow})`; `glow` 0..1 writes the emissive mask (any kind) |
| `stance` | `stances.STANCES`: `low_guard` (owner's pick for a two-handed knight), `high_guard`, `caster`, `brawler`; `pose(ph, p)` tweaks |
| `body` | `kind` plate/gladiator/robe/beast, `height`, `width`, `head_lift`, `emblem` (stamp), `hand` size, `pauldron` side |
| `head` | `kind` anime (`ponytail`, `iris` 3 hex, `bangs`, `spikes`, `locks`, `hair_lines`) / lion / falcon / bear (`iris`) |
| `weapon`, `offhand`, `cape` | `sword` (hands 2, length, rune, edge), `scimitar` (curve, edge_side), `staff` (up, down); `shield` (r), `orb`; cape `length` |
| `extra(m, p, A)` | one-off parts (imps riding, a fairy); `A` = anchors (pel, chest, neck, head, sh) |
| `hand_mat` | material the hands copy (default `steel`) |

Material names the parts expect: `steel dsteel gold dgold leather trim cape cape_in skin hair hair_h hair_s blade blade_f blade_e gem`
(knight); `fur fur_l fur_s mane mane_s kilt kilt_s nose mouth claw` (beasts); `robe robe_in plate sash wood gem_e feather feather_l beak beak_d` (caster).

## Look rules (owner-approved, T1414)
- FFBE face: skin only on the lower ~40% of the head, bangs to the eye line, eyes taller than wide with lash cap, coloured iris and glint, V chin, no nose.
- Cape is born under the pauldrons (3 units below the neck, clipped flat at neck-1.4), never from the head; gold clasps.
- A glowing blade keeps its colour only with a saturated ramp (top step `#a8e0ff`, no near-white) and emission = albedo squared in the scene shader.
- Detail without growing the hero: raise `scale` and the cell, shrink the plane pixel by the same ratio.
- Match the reference's quality, not its design: keep each character's own look (owner rejected a horned redesign).
