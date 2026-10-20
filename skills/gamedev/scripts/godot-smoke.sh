#!/usr/bin/env bash
# Export a Godot project to a Linux binary and run it offscreen for N seconds, printing SMOKE fps lines.
set -euo pipefail
usage() { echo "usage: godot-smoke.sh [--display wayland|xwayland|xvfb] [--seconds N] [--renderdoc DIR] [--no-export] [PROJECT_DIR]"; exit 0; }

here=$(cd "$(dirname "$0")/.." && pwd)
display=wayland seconds=5 rdc="" export=1 proj=""
while [ $# -gt 0 ]; do
	case $1 in
		--display) display=$2; shift 2 ;;
		--seconds) seconds=$2; shift 2 ;;
		--renderdoc) rdc=$2; shift 2 ;;
		--no-export) export=0; shift ;;
		-h|--help) usage ;;
		*) proj=$1; shift ;;
	esac
done
if [ -z "$proj" ]; then
	proj=$(mktemp -d "${TMPDIR:-/tmp}/godot-smoke.XXXX")
	cp -r "$here/fixture/." "$proj/"
fi
cd "$proj"
bin=$(sed -n 's/^export_path="\(.*\)"/\1/p' export_presets.cfg | head -1)
if [ "$export" = 1 ]; then
	mkdir -p "$(dirname "$bin")"
	godot --headless --path . --import >/dev/null 2>&1 || true
	godot --headless --path . --export-release Linux "$bin" > export.log 2>&1 || { tail -20 export.log; exit 1; }
	echo "SMOKE exported $proj/$bin ($(du -h "$bin" | cut -f1))"
fi

export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)} SMOKE_SECONDS=$seconds
run=(./"$bin" --audio-driver Dummy)
wp=""
cleanup() { [ -n "$wp" ] && kill "$wp" 2>/dev/null; true; }
trap cleanup EXIT
if [ "$display" != xvfb ]; then
	sock=wl-smoke-$$
	xw=(); [ "$display" = xwayland ] && xw=(--xwayland)
	weston --backend=headless --renderer=gl --width=1280 --height=720 --socket=$sock --idle-time=0 "${xw[@]}" > weston.log 2>&1 &
	wp=$!
	for _ in $(seq 400); do
		if [ "$display" = xwayland ]; then grep -q "listening on display" weston.log && break
		else [ -S "$XDG_RUNTIME_DIR/$sock" ] && break; fi
		sleep 0.05
	done
	if [ "$display" = xwayland ]; then
		export DISPLAY=$(grep -o "listening on display :[0-9]*" weston.log | grep -o ":[0-9]*")
		run+=(--display-driver x11)
	else
		export WAYLAND_DISPLAY=$sock
		run+=(--display-driver wayland)
	fi
fi
if [ -n "$rdc" ]; then
	[ "$display" = wayland ] && { echo "SMOKE renderdoc has no Wayland WSI: use --display xwayland" >&2; exit 2; }
	mkdir -p "$rdc"
	shim=$HOME/opt/gamedev/rd-trigger.so
	[ -f "$shim" ] || cc -O2 -shared -fPIC -I "$HOME/opt/gamedev/renderdoc_1.46/include" "$here/scripts/rd-trigger.c" -o "$shim"
	run=(env LD_PRELOAD="$shim" renderdoccmd capture -w -c "$rdc/smoke" "${run[@]}")
fi
[ "$display" = xvfb ] && run=(xvfb-run -a -s "-screen 0 1280x720x24" "${run[@]}")
# Line-buffered so a hung run still leaves its last stage in run.log (a pipe block-buffers Godot's stdout).
{ timeout $((seconds + 60)) stdbuf -oL -eL "${run[@]}" 2>&1 || echo "SMOKE exit=$?"; } | tee run.log | grep -E "^SMOKE|^RDCAP triggered|^Vulkan|^OpenGL|ERROR" || true
grep -q "^SMOKE exit=124" run.log && echo "SMOKE timeout after $((seconds + 60)) s, killed; last output: $(grep -v "^SMOKE exit=" run.log | tail -1)"
[ -n "$rdc" ] && ls "$rdc"/*.rdc
exit 0
