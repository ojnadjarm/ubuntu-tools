# char3d credits

Third-party assets used by char3d builds. One row per asset; CC0 or CC-BY only (CC-BY needs the attribution text). Tools that only run (Blender, MPFB code, Rigify, glTF-Validator) leave no licence on the output; they are listed so the chain is complete. Downloads: `~/.local/share/char3d/downloads/`; HDRIs: `~/.local/share/motion-video/hdri/LICENSES.csv` (sha256 per file).

| Asset | Source | Licence | Attribution | Used by |
|---|---|---|---|---|
| MPFB 2 add-on (code) | https://extensions.blender.org/add-ons/mpfb/ (`mpfb.zip`) | GPL-3.0-or-later, tool only; output models are not GPL (MPFB FAQ "Can I sell models") | not required | `body`, `face` (run in the `CHAR3D_BLENDER_RES` sandbox) |
| MakeHuman hm08 base mesh, macro targets, core skins (bundled with MPFB) | https://static.makehumancommunity.org/about/license.html | CC0-1.0 | not required | `body` |
| makehuman_system_assets (eyes high-poly, eyebrow001, eyelashes01, teeth_base, tongue01, skin old_caucasian_male) | https://static.makehumancommunity.org/assets/assetpacks/makehuman_system_assets.html (`sys.zip`) | CC0-1.0 | not required | `body`, `face` |
| faceunits01: 52 ARKit face units (Mika Suominen) | https://static.makehumancommunity.org/assets/assetpacks/faceunits01.html (`faceunits01.zip`) | CC0-1.0 per the asset-pack index (the pack page states none) | not required | `face`, `facerig`, glTF morph targets |
| visemes02: 15 Meta visemes | https://static.makehumancommunity.org/assets/assetpacks.html (`visemes02.zip`) | CC0-1.0 per the asset-pack index | not required | `face`, `motion` (talk) |
| Rigify (bundled with Blender 5.0.1) | `/usr/lib/blender/scripts/addons_core/rigify` | GPL-2.0-or-later, tool only; generated rigs are our data | not required | `rig` |
| studio_small_09 HDRI (Sergej Majboroda, 2k) | https://polyhaven.com/a/studio_small_09 | CC0-1.0 | not required ("You do not need to give credit") | `lookdev` storybook / studio rig |
| moonless_golf HDRI (Greg Zaal, 1k) | https://polyhaven.com/a/moonless_golf | CC0-1.0 | not required | `lookdev` moonlit / night rig |
| CMU Graphics Lab Motion Capture Database (cgspeed BVH) | https://mocap.cs.cmu.edu/ | free to copy, modify, redistribute | "The data used in this project was obtained from mocap.cs.cmu.edu. The database was created with funding from NSF EIA-0196217." | `motion` clips of type `mocap` only; not used by DarkSaddler (procedural clips) |
