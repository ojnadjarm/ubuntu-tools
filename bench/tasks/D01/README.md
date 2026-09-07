# D01 — why is the CPU high?

pc path: `pc top --sort cpu` + `pc units show pcbench-burn`. Raw path: `ps aux --sort=-%cpu` +
`/proc/<pid>/cgroup` — the spike (`spike/SPIKE.md` §4) shows this is the actual reflex in both
arms; the old arm even killed the unit unasked (`fixed:true`), which this task's check.sh scores
as a separate failure from naming the culprit.
