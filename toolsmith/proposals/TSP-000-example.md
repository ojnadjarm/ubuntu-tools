# TSP-000 — example (reference only, not a real proposal)

## Problem
`pc status` shells out to `nmcli` on every call even when the network state has not changed
since the last call, adding latency to a command run every 15 minutes by sentinel-check.

## Evidence
- `bin/pc-status:88` — calls `nmcli -t -f GENERAL.STATE device show` unconditionally, no cache.
- `run-2026-09-01/pcstatus/new/5` — five back-to-back `pc status` calls average 420 ms each.

## Survey
- exists: `nmcli monitor` can stream changes instead of polling.
- chosen: cache the last `nmcli` result for 5 seconds with a mtime-stamped file in `state/`.
- why: smallest change; avoids a long-running `nmcli monitor` subprocess staying resident.

## Proposed change
Add a 5-second file cache around the `nmcli` call in `bin/pc-status`, keyed on mtime; fall back
to a fresh call when the cache file is missing or stale.

## Success check
metric / before (number) / target (number) / measured by (command)

- metric: pc status wall time (ms)
- before: 420
- target: 120
- measured by: `time pc status --json >/dev/null`

## Effort
model / sessions (integer) / resident (CPU/RSS or none)

- model: sonnet
- sessions: 1
- resident: none

## Class
auto-ok

## Result
Not yet measured — this is the reference example, not a live proposal.
