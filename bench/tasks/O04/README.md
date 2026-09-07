# O04 — how full is the disk and is it healthy?

pc path: `pc status --fresh --json` (`.sections.resources.disk_root` for fullness,
`.sections.disk.smart` for health). Raw path: `df /` + `smartctl -H /dev/nvme0n1` — two
commands, needs root for the second.

Quirk (found while validating this task): `.sections.disk.percent_used` is the NVMe
SMART wear-level attribute ("percentage used" over the drive's life), not filesystem
fullness — an oracle that reads it fails the ±1 check against `df /`. Filesystem fullness
is `.sections.resources.disk_root` ("N% used, ..."). Worth a quirks.md line.
