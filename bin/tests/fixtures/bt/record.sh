#!/usr/bin/env bash
# Re-records the pc-bt fixtures. The buds are recorded as CONNECTED: the live tree only ever
# shows them connected while the owner wears them, so the two calls `pc dbus --system` makes are
# recorded from the live adapter and the device object is patched to the connected shape
# (Connected/ServicesResolved true, RSSI, org.bluez.Battery1, MediaControl1 connected) — the
# same keys `buds-capture` sees on a healthy link (RUNBOOK-earbuds.md). Run by hand when bluez
# or the device object changes.
set -eu
d="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/resp"; mkdir -p "$d"
DEV=/org/bluez/hci0/dev_AC_80_0A_27_65_6C
key() { printf '%s\0' "$@" | sha1sum | cut -c1-16; }

# 1. the introspection pc dbus does to resolve ObjectManager.GetManagedObjects on /.
busctl --system introspect --no-pager org.bluez / >"$d/$(key --system introspect --no-pager org.bluez /)"

# 2. the managed-object tree: only the adapter and the buds (a device discovered mid-record is
#    transient), patched to the connected shape.
busctl --system call --json=short org.bluez / org.freedesktop.DBus.ObjectManager GetManagedObjects \
  | jq -c --arg dev "$DEV" '.data[0] |= with_entries(select(.key | startswith("/org/bluez")))
    | .data[0][$dev] |= (
      .["org.bluez.Device1"].Connected.data = true
    | .["org.bluez.Device1"].ServicesResolved.data = true
    | .["org.bluez.Device1"].RSSI = {"type":"n","data":-46}
    | .["org.bluez.Battery1"] = {"Percentage":{"type":"y","data":85}}
    | .["org.bluez.MediaControl1"].Connected.data = true)' \
  >"$d/$(key --system call --json=short org.bluez / org.freedesktop.DBus.ObjectManager GetManagedObjects)"

# 3. the last bluetoothd error (bin/journalctl re-stamps it to 120 s old at read time).
journalctl -u bluetooth -p err -n 1 -o json --no-pager >"$d/journal.json"

# 4. the bluez5 card. Crafted, not recorded: the card only exists while the buds are connected.
#    Profile list from RUNBOOK-earbuds.md ("Profiles offered"), active profile a2dp-sink.
jq -n '[{index: 42, name: "bluez_card.AC_80_0A_27_65_6C", driver: "bluez5",
  active_profile: "a2dp-sink",
  profiles: (["a2dp-sink","a2dp-sink-sbc","a2dp-sink-sbc_xq","headset-head-unit","headset-head-unit-cvsd","off"]
             | map({key:., value:{description:., available:true}}) | from_entries),
  properties: {"device.description": "WF-1000XM5", "api.bluez5.address": "AC:80:0A:27:65:6C"},
  ports: {}}]' >"$d/cards.json"

# 5. the one mutation the tests replay: Device1.Disconnect succeeds (empty reply) and the
#    Connected property reads false afterwards, so pc_apply can verify its own ledger entry.
: >"$d/$(key --system --timeout=15 call org.bluez "$DEV" org.bluez.Device1 Disconnect)"
printf '{"type":"b","data":false}\n' >"$d/$(key --system get-property --json=short org.bluez "$DEV" org.bluez.Device1 Connected)"
