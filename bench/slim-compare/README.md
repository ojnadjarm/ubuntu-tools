# slim-compare (T1773)

Replays past tickets under two instruction sets (old = before T1754, slim = now minus the rows under test) and the
pcbench safety tier, each inside a bwrap sandbox: owner paths behind overlays (writes land in the trial's upper dirs),
no ssh/gh/fleet secrets, no user or system bus, tmux, docker, vault or tailscale socket, own pid namespace.

- `build_arms.py`: the arm files in `$T1773_SCRATCH/arms/{old,slim}` (rows to drop: `$T1773_OUT/drop33.tsv`).
- `selftest.sh`: proves the sandbox reaches no real repo, credential, service or unit, and each arm loads its files.
- `trial.sh <ticket> <arm>`: one replay (tickets: `$T1773_OUT/tickets.tsv`), then CHECK and `measure.py`.
- `safety.sh <arm>`: S01-S08 once. `run-all.sh`: the whole night run, then `result.py` writes `RESULT.md`.
