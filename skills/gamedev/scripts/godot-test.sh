#!/usr/bin/env bash
# Run a Godot project's GUT tests headless (CI style): JUnit XML out, exit code 0 only when all pass.
set -euo pipefail
usage() { echo "usage: godot-test.sh [--junit FILE] [--dir res://test] [PROJECT_DIR]   (no project = the sample fixture)"; exit 0; }

here=$(cd "$(dirname "$0")/.." && pwd)
gut=${GUT_DIR:-$HOME/opt/gamedev/gut-9.7.1/gut}
junit="" tdir=res://test proj=""
while [ $# -gt 0 ]; do
	case $1 in
		--junit) junit=$2; shift 2 ;;
		--dir) tdir=$2; shift 2 ;;
		-h|--help) usage ;;
		*) proj=$1; shift ;;
	esac
done
if [ -z "$proj" ]; then
	proj=$(mktemp -d "${TMPDIR:-/tmp}/godot-test.XXXX")
	trap 'rm -rf "$proj"' EXIT
	cp -r "$here/fixture-test/." "$proj/"
fi
proj=$(cd "$proj" && pwd)
junit=${junit:-$proj/junit.xml}
[ -d "$proj/addons/gut" ] || { mkdir -p "$proj/addons"; cp -r "$gut" "$proj/addons/gut"; echo "TEST vendored GUT into $proj/addons/gut"; }
godot --headless --path "$proj" --import > /dev/null 2>&1 || true
set +e
godot --headless --audio-driver Dummy --path "$proj" -s addons/gut/gut_cmdln.gd -gdir="$tdir" -ginclude_subdirs -gdisable_colors -gexit \
	-gjunit_xml_file="$junit" > "$proj/gut.log" 2>&1
rc=$?
set -e
grep -E "^\s*(Tests|Passing|Failing|Pending|Asserts|Time)\b|FAILED|---- All tests passed" "$proj/gut.log" | sed 's/^\s*/TEST /'
echo "TEST junit=$junit rc=$rc"
exit $rc
