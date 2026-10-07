# D03 — did anything change in the kernel log?

pc path: `pc kernel dmesg --level err`. Raw path: `dmesg --level=err` or raw `journalctl -k`.
Answer `severity` is the enum `err|warn|info|none` (err = any priority <=3 line; TSP-014).
Nonce is per trial (`$RANDOM$RANDOM`), written to `$PCBENCH_TRIALDIR/.pcbench-d03-nonce` so
`check.sh` (a separate process) can read what `setup.sh` injected. `sudo -n` write to
`/dev/kmsg` is instant here (SPIKE §2).
