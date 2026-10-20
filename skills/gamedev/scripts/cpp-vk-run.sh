#!/usr/bin/env bash
# cpp-vk-run.sh: run a native SDL3/Vulkan binary on the iGPU under headless weston, validation (sync + best practices) on, N frames; --size WxH: kiosk shell, the window fills that output; --x11: SDL on Xwayland (RenderDoc has no Wayland WSI).
set -uo pipefail
usage() { echo "usage: cpp-vk-run.sh [--frames N] [--no-validate] [--no-syncval] [--size WxH] [--x11] [--timeout S] BINARY [ARGS...]"; }
frames=120; validate=--validate; syncval=1; size=""; limit=60; x11=0
while [ $# -gt 0 ]; do
	case "$1" in
		--frames) frames=$2; shift 2 ;;
		--no-validate) validate=--no-validate; shift ;;
		--no-syncval) syncval=0; shift ;;
		--size) size=$2; shift 2 ;;
		--x11) x11=1; shift ;;
		--timeout) limit=$2; shift 2 ;;
		-h|--help) usage; exit 0 ;;
		*) break ;;
	esac
done
[ $# -ge 1 ] || { usage >&2; exit 2; }
bin=$(realpath "$1"); shift
if [ $validate = --validate ] && [ $syncval = 1 ]; then
	export VK_KHRONOS_VALIDATION_VALIDATE_SYNC=true VK_KHRONOS_VALIDATION_VALIDATE_BEST_PRACTICES=true
fi
export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
sock=wl-cppvk-$$; wlog=$(mktemp)
shell=(); w=1280; h=720; xw=()
[ $x11 = 1 ] && xw=(--xwayland)
[ -n "$size" ] && shell=(--shell=kiosk-shell.so) w=${size%x*} h=${size#*x}
weston --backend=headless --renderer=gl "${shell[@]}" --width=$w --height=$h --socket=$sock --idle-time=0 "${xw[@]}" > "$wlog" 2>&1 &
wp=$!
trap 'kill $wp 2>/dev/null; rm -f "$wlog"' EXIT
for _ in $(seq 400); do [ -S "$XDG_RUNTIME_DIR/$sock" ] && break; sleep 0.05; done
[ -S "$XDG_RUNTIME_DIR/$sock" ] || { echo "RUN weston did not start" >&2; cat "$wlog" >&2; exit 3; }
video=(WAYLAND_DISPLAY=$sock SDL_VIDEO_DRIVER=wayland)
if [ $x11 = 1 ]; then
	for _ in $(seq 400); do grep -q "listening on display" "$wlog" && break; sleep 0.05; done
	video=(DISPLAY="$(grep -o "listening on display :[0-9]*" "$wlog" | grep -o ":[0-9]*")" SDL_VIDEO_DRIVER=x11)
fi
env "${video[@]}" SDL_AUDIO_DRIVER=dummy timeout "$limit" "$bin" --frames "$frames" "$validate" "$@"
