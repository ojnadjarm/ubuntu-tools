#!/usr/bin/env bash
# cpp-vk-run.sh passes the sync + best-practices validation settings to the binary (stub weston and binary, no GPU); hazard sed applies.
set -u
G=$(cd "$(dirname "$0")/.." && pwd)
RUN=$G/scripts/cpp-vk-run.sh
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/xdg"; chmod 700 "$T/xdg"
cat > "$T/game" <<'SH'
#!/bin/sh
echo "ARGS $*"
echo "SYNC=${VK_KHRONOS_VALIDATION_VALIDATE_SYNC:-unset} BP=${VK_KHRONOS_VALIDATION_VALIDATE_BEST_PRACTICES:-unset}"
SH
chmod +x "$T/game"
fails=0
check() {  # name expected-env-line cpp-vk-run args...
	local name=$1 want=$2 got; shift 2
	got=$(env -u VK_KHRONOS_VALIDATION_VALIDATE_SYNC -u VK_KHRONOS_VALIDATION_VALIDATE_BEST_PRACTICES \
		PATH="$G/tests/fixtures/stub-bin:$PATH" XDG_RUNTIME_DIR="$T/xdg" "$RUN" --frames 3 "$@" "$T/game" 2>&1)
	if grep -qx "$want" <<< "$got"; then echo "ok   $name"
	else echo "FAIL $name: want '$want'"; echo "$got"; fails=$((fails + 1)); fi
}
check "validate exports sync + best practices" "SYNC=true BP=true"
check "--no-syncval exports none" "SYNC=unset BP=unset" --no-syncval
check "--no-validate exports none" "SYNC=unset BP=unset" --no-validate
check "--no-validate reaches binary" "ARGS --frames 3 --no-validate" --no-validate
src=$G/templates/cpp-vulkan/src/renderer.cpp
n=$(sed -f "$G/tests/fixtures/cpp-sync-hazard.sed" "$src" | diff "$src" - | grep -c '^>.*VK_PIPELINE_STAGE_2_NONE, 0,')
[ "$n" = 1 ] && echo "ok   hazard sed changes 1 line" || { echo "FAIL hazard sed: $n lines"; fails=$((fails + 1)); }
echo "cpp-sync.test: $fails failed"
exit $((fails > 0))
