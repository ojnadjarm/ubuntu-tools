#!/usr/bin/env bash
# org local overlay (T2017): org.local.json seats and floors merge into org.seats() and staff.load() on fixtures only.
set -uo pipefail
LIB="$(cd "$(dirname "$(readlink -f "$0")")/../../lib" && pwd)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
. "$HOME/agents/bin/tests/lib/assert.sh"
unset ORG_FILE STAFF_FILE ORG_LOCAL_FILE HARNESS_HOME
export HARNESS_CONFIG="$T/cfg/config.env"
mkdir -p "$T/cfg"
seat() { printf '{"id": "%s", "name": "%s", "role": "%s", "parent": %s, "wake": "%s", "match": null}' "$@"; }
cat >"$T/org.json" <<EOF
{"seats": [
  $(seat owner Owner owner null po-inbox),
  $(seat orchestrator Orch ceo '"owner"' channel),
  $(seat mooblox Moo po '"orchestrator"' po-inbox),
  $(seat discord Disc po '"orchestrator"' po-inbox)
]}
EOF
floor() { printf '{"id": "%s", "name": "%s", "teams": ["%s"]}' "$@"; }
cat >"$T/staff.json" <<EOF
{"teams": [], "hidden": [], "floors": [$(floor operations Ops ops), $(floor personal Personal pers)]}
EOF
export ORG_FILE="$T/org.json" STAFF_FILE="$T/staff.json"
py() { python3 -c "import sys, json; sys.path.insert(0, '$LIB'); import org, staff
$1" 2>&1; }
seats='print(" ".join(s["id"] for s in org.seats()))'
floors='print(" ".join(f["id"] for f in staff.load()["floors"]))'
local_file() { printf '{"seats": [%s], "floors": [%s]}' "$1" "$2" >"$3"; }

export ORG_LOCAL_FILE="$T/none.json"
is 'no local file: seats equal the plain file' "$(py "$seats")" 'owner orchestrator mooblox discord'
is 'no local file: staff equals the plain file' "$(py 'print(staff.load() == json.load(open("'"$T"'/staff.json")))')" True

export ORG_LOCAL_FILE="$T/after.json"
local_file "$(seat workproj Workproj po '"orchestrator"' pull | sed 's/^{/{"after": "mooblox", /')" \
           "$(floor work 'Work projects' workproj | sed 's/^{/{"after": "operations", /')" "$ORG_LOCAL_FILE"
is 'local seat lands after its after seat' "$(py "$seats")" 'owner orchestrator mooblox workproj discord'
is 'merged seat carries no after key' "$(py 'print([s for s in org.seats() if s["id"] == "workproj"][0].get("after", "none"))')" none
is 'local floor lands after its after floor' "$(py "$floors")" 'operations work personal'
is 'merged floor carries no after key' "$(py 'print(staff.load()["floors"][1].get("after", "none"))')" none

export ORG_LOCAL_FILE="$T/last.json"
local_file "$(seat workproj Workproj po '"orchestrator"' pull | sed 's/^{/{"after": "nobody", /'), $(seat second Second po '"orchestrator"' pull)" \
           "$(floor work W workproj | sed 's/^{/{"after": "nowhere", /'), $(floor more M more)" "$ORG_LOCAL_FILE"
is 'unknown or missing after: seats last' "$(py "$seats")" 'owner orchestrator mooblox discord workproj second'
is 'unknown or missing after: floors last' "$(py "$floors")" 'operations personal work more'

export ORG_LOCAL_FILE="$T/same.json"
local_file "$(seat mooblox Replaced po '"orchestrator"' pull | sed 's/^{/{"after": "discord", /')" \
           "$(floor operations Replaced ops2 | sed 's/^{/{"after": "personal", /')" "$ORG_LOCAL_FILE"
is 'a local seat with a tracked id replaces it in place' "$(py "$seats"' ; print(org.seats()[2]["name"])')" 'owner orchestrator mooblox discord
Replaced'
is 'a local floor with a tracked id replaces it in place' "$(py "$floors"' ; print(staff.load()["floors"][0]["name"])')" 'operations personal
Replaced'

local_file "$(seat workproj W po '"orchestrator"' pull | sed 's/^{/{"after": "mooblox", /')" "$(floor work W workproj)" "$T/cfg/org.local.json"
unset ORG_LOCAL_FILE
is 'ORG_FILE set, ORG_LOCAL_FILE unset: no seat merge from the config folder' "$(py "$seats")" 'owner orchestrator mooblox discord'
is 'STAFF_FILE set, ORG_LOCAL_FILE unset: no floor merge from the config folder' "$(py "$floors")" 'operations personal'
export ORG_LOCAL_FILE="$T/cfg/org.local.json"
is 'selftest: the same file merges when named' "$(py "$seats")" 'owner orchestrator mooblox workproj discord'
is 'an explicit seats path: no merge' "$(py 'print(" ".join(s["id"] for s in org.seats("'"$T"'/org.json")))')" 'owner orchestrator mooblox discord'
is 'an explicit staff path: no merge' "$(py 'print(" ".join(f["id"] for f in staff.load("'"$T"'/staff.json")["floors"]))')" 'operations personal'

export ORG_LOCAL_FILE="$T/bad.json"
local_file "$(seat workproj W boss '"orchestrator"' pull)" "" "$ORG_LOCAL_FILE"
is 'a local seat with a bad role raises' "$(py "$seats" | tail -1)" "ValueError: seat workproj: role boss not in ('owner', 'ceo', 'po', 'manager')"
exit "$bad"
