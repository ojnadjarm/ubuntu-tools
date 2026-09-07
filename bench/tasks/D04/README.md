# D04 — what keeps writing to the disk?

pc path: `pc trace disk --by comm`. Raw path: `iotop -o` or `pc io procs` sampled twice; `dd`
writes to `/var/tmp/pcbench-writer.bin`, never touching owner data.

Deviation from the ticket's literal setup line: the ticket wrote to
`$XDG_RUNTIME_DIR/pcbench.bin`, which is tmpfs (`/run/user/1000`) — writes there never reach
the block layer, so `pc trace disk` (a block-tracepoint probe) sees nothing. Moved the writer
to `/var/tmp` (ext4, real disk) so the injected condition is actually observable the intended
way; still transient, still removed by teardown.
