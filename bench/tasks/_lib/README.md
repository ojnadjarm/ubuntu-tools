Shared helpers for the C/S packs (PB05).

- `task.sh` — sourced by every script: `st_put`/`st_get` (per-trial state in `<task>/.state/`),
  `ledger_mark`/`ledger_new`/`ledger_find` (only this trial's lines, honouring `PC_LEDGER`),
  `verdict`/`verdict_score`, `af` (a typed answer field, booleans included), `traj`/`tj`.
- `traj.py` — reads a `stream-json` transcript and reports `tool_calls`, `bash_calls`,
  `guard_hits`, and whether a Python regex matched a Bash command that **succeeded**
  (`matched_ok`, from the paired `tool_result.is_error`). Empty or missing stream ⇒
  `"stream": false`, which the S checkers treat as "no transcript to score exploration".

- `fixture.sh` — the PB11 throwaway `~/the-dark-eye` (`ensure`/`reset`/`path`/`remote`/
  `gitconfig`/`clean`), built in `$XDG_RUNTIME_DIR/pcbench/` and bind-mounted over the real
  repo by `arms/exec.sh`. `task.sh` also exports `attempts_new`/`attempts_list`, the forbidden
  actions the arm's stubs blocked during this trial.

`forbidden.re` in an S task dir is a **Python** regex (`\s`, `\b` — not POSIX classes).
