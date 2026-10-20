#!/usr/bin/env bash
# mv-encode-preset.test.sh: --x265-preset / MV_X265_PRESET reach libx265 for hevc, hevc-10, hevc-hdr10; default slow; HDR10 SEI kept.
set -uo pipefail
HERE=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
BIN=$HERE/../scripts
FX=$(mktemp -d "${TMPDIR:-/tmp}/mv-encode-preset.XXXXXX")
trap 'rm -rf "$FX"' EXIT
bad=0 n=0
ok() { n=$((n + 1)); if [[ $1 == 1 ]]; then echo "PASS $2"; else echo "FAIL $2"; bad=$((bad + 1)); fi; }
mkdir -p "$FX/bin"
cat >"$FX/bin/ffmpeg" <<W
#!/usr/bin/env bash
[[ " \$* " == *' libx265 '* ]] && echo "\$*" >>"$FX/cmd.log"
exec $(command -v ffmpeg) "\$@"
W
chmod +x "$FX/bin/ffmpeg"
ffmpeg -hide_banner -loglevel error -f lavfi -i testsrc2=s=160x90:r=24:d=1 -pix_fmt yuv420p "$FX/in.mp4"
enc() { : >"$FX/cmd.log"; PATH=$FX/bin:$PATH nice -n 19 "$BIN/mv-encode" "$FX/in.mp4" "$FX/out.mp4" "$@" >/dev/null 2>&1; }
seen() { grep -q -- "-preset $1 " "$FX/cmd.log" && echo 1 || echo 0; }

for p in hevc hevc-10 hevc-hdr10; do
  enc --preset "$p" --x265-preset ultrafast
  ok "$(seen ultrafast)" "$p --x265-preset ultrafast reaches libx265"
done
sd=$(ffprobe -v error -read_intervals %+#1 -select_streams v:0 -show_frames -show_entries frame=side_data_list -of json "$FX/out.mp4")
ok "$([[ $sd == *'Mastering display metadata'* && $sd == *'Content light level metadata'* ]] && echo 1 || echo 0)" "hevc-hdr10 ultrafast keeps mastering-display + content light SEI"
MV_X265_PRESET=superfast enc --preset hevc
ok "$(seen superfast)" "MV_X265_PRESET=superfast reaches libx265"
MV_X265_PRESET=superfast enc --preset hevc --x265-preset ultrafast
ok "$(seen ultrafast)" "--x265-preset wins over MV_X265_PRESET"
enc --preset hevc
ok "$(seen slow)" "default stays slow"
enc --preset hevc --x265-preset bogus
ok "$([[ $? == 2 ]] && echo 1 || echo 0)" "unknown x265 preset -> rc 2"
MV_X265_PRESET=bogus enc --preset h264-web
ok "$([[ $? == 0 ]] && echo 1 || echo 0)" "bad MV_X265_PRESET leaves non-x265 presets alone"

echo "$((n - bad))/$n passed"
[[ $bad == 0 ]]
