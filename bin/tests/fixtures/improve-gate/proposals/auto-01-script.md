# FX-auto-01-script — fixture

## Proposed change
Cache the read-only `nmcli -t dev status` call in `bin/pc-status:54` for 5 s; test in `bin/tests/pc-status.test.sh`.

## Effort
- resident: none

## Class
auto-ok
