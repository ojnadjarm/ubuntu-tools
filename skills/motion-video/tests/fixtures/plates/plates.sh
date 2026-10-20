# plates.sh: sourced by the seven Blender-plate motion tests (T856, T898) once HERE and FX are set; `plates <test> [input...]` sets
# P (the plates dir the asserts read) and BL (1 = render with Blender into P first). Recorded plates (fixtures/plates/<test>)
# unless MV_BLENDER_FULL=1 (default on Sundays), no manifest, or a manifest sha other than shot.py + mv-render + the test +
# inputs + the blender package version (STALE); make.sh records them through MV_PLATES_INTO. MV_PLATES overrides the plates
# root (sandbox runs). With no Blender, valid plates are used even on a full run; otherwise SKIP names the reason.
plates() {
  local name=$1 rec why full=${MV_BLENDER_FULL:-$([[ $(date +%u) == 7 ]] && echo 1 || echo 0)}
  PL_SHA=$({ cat "$HERE/../templates/blender/shot.py" "$HERE/../scripts/mv-render" "$HERE/$name.test.sh" "${@:2}"
    dpkg-query -W -f '${Version}' blender 2>/dev/null; } | sha256sum | cut -c1-16)
  P=${MV_PLATES:-$HERE/fixtures/plates}/$name BL=1
  rec=$(awk '$1 == "sha" { print $2 }' "$P/manifest" 2>/dev/null)
  if [[ -n ${MV_PLATES_INTO:-} ]]; then why="recording into $MV_PLATES_INTO"
  elif [[ -z $rec ]]; then why="no plates"
  elif [[ $rec != "$PL_SHA" ]]; then why="STALE fixture (re-record: make.sh)"
  elif [[ $full == 1 ]] && blender --version >/dev/null 2>&1; then why="full run (MV_BLENDER_FULL or Sunday)"
  else echo "plates $name $rec$( ((full)) && echo ' (full run, no blender)')"; BL=0; return 0; fi
  blender --version >/dev/null 2>&1 || { echo "SKIP $name: $why and no blender"; exit 0; }
  echo "$name: $why: Blender path"
  P=${MV_PLATES_INTO:-$FX/plates}
  mkdir -p "$P"
  printf 'sha %s\ntest %s\nmade %s\n' "$PL_SHA" "$name" "$(date -Is)" >"$P/manifest"
}
# keep SRC DST [MODE]: save a frame as PIL loads it (8-bit), converted to MODE (L, RGB), A (alpha as L) or M (alpha > 127, 1-bit).
keep() {
  mkdir -p "$(dirname "$2")"
  python3 -I -c 'import sys
from PIL import Image
im, m = Image.open(sys.argv[1]), (sys.argv[3:] or [""])[0]
if m in ("A", "M"):
    im = im.getchannel("A")
if m == "M":
    im = im.point(lambda v: 255 * (v > 127)).convert("1", dither=Image.Dither.NONE)
elif m not in ("", "A"):
    im = im.convert(m)
im.save(sys.argv[2], optimize=True)' "$@"
}
# val NAME: a recorded value file of the plates, empty when missing.
val() { cat "$P/$1" 2>/dev/null; }
