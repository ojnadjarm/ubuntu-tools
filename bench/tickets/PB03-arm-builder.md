# PB03 — `pcbench arm build old|new`: the two toolboxes, rebuilt from a manifest

**Phase PB · Model: sonnet · Estimated agent time: 1.5 h · Depends on: PB01 (bwrap verdict, RECONSTRUCTION.diff), PB02 (the `arm` subcommand slot)**

## Goal
The "old toolbox" (2026-09-06 evening: 22 desktop `pc` subcommands, `toolbox.md` before PT16,
no `pc-cli.md`, no ledger/undo/doctor/explain, desktop skill without the "below the screen"
paragraph) and the "new toolbox" (the live tree, frozen at run time) are both produced by one
command from a manifest, so a run's arm is reproducible and the diff between arms is a file
the report links to. The `new` arm is a snapshot copy too — a run that spans hours must not
see `~/agents/bin` change under it.

## Ground rules
PLAN-PCBENCH §2.7. Copies only: nothing under `~/agents/bin`, `~/agents/KB`, `~/.claude`
changes. `pclib.sh` is shared by both arms (post-PT01 `pc-status` needs it) and is the one
declared leak. Never `git commit`/`push`.

## Context
- Manifest `~/agents/bench/arms/old.manifest`: the 22 script names, `pc` (copied, not linked —
  `readlink -f "$0"`), `pclib.sh`, `env.sh`, `a11y_tree.py ocr_find.py portal_shot.py rd_type.py
  spotify_api.py` (helpers the 22 scripts import), plus the doc edits as a stored `patch`
  (PB01's `RECONSTRUCTION.diff`, applied to a fresh copy of the live `toolbox.md`,
  `README-pc-control.md`, `skills/desktop/SKILL.md`; `pc-cli.md` deleted).
- `new` = `cp -a` of `~/agents/bin` (whole), `~/agents/KB`, the desktop skill, with a
  `MANIFEST.sha256` so `pcbench report` can say which `pc` the arm ran.
- Bind set (from PB01): `--bind $ARM/bin ~/agents/bin --bind $ARM/KB ~/agents/KB --bind
  $ARM/skills/desktop ~/.claude/skills/desktop`. `~/agents/log` stays real: the ledger and
  the audit log are shared on purpose (the checkers read them).
- The old `pc status` reads caches in `$XDG_RUNTIME_DIR/pc-status` — shared, harmless.

### Survey (research first)
- Exists: `baseline.sh` (tarball of user config, not selective), `git stash`-style tricks
  (no repo), `etckeeper` (`/etc` only), `bwrap` (chosen in PB01).
- Chosen: manifest + `cp`/`ln -s` + one stored patch; ~80 lines of bash inside `pcbench.d/arm.sh`.
- Why: the arms are two directory trees; nothing more general is needed.

## Steps
1. `pcbench arm build old` → `~/agents/bench/arms/old/{bin,KB,skills}` + `MANIFEST.sha256`;
   `pcbench arm build new` → same shape from the live tree; `pcbench arm diff` → `diff -rq`
   of the two plus the doc patch; `pcbench arm status`.
2. `pcbench arm exec <arm> -- <cmd>` runs a command inside the arm's bind set (the runner
   uses the same function): `pcbench arm exec old -- pc help` lists 22 commands; `pcbench arm
   exec old -- pc undo list` exits 127; `pcbench arm exec new -- pc doctor --quick` passes.
3. The old-arm docs: apply the patch, then grep-assert that none of `pc explain`, `pc undo`,
   `pc doctor`, `pc bench`, `pc-cli.md`, `--apply`, `changes.jsonl`, `pc top`, `pc trace`,
   `pc mutter`, `pc audio`, `pc docker`, `pc units`, `pc journal`, `pc kernel` survive in the
   old `toolbox.md`/skill/README.
4. Test `tests/pcbench-arm.test.sh`: build both into a temp `PCBENCH_HOME`, the grep-asserts,
   the three `exec` checks, and `pc status --brief` identical inside both arms (same machine).

## Success check
```bash
pcbench arm build old && pcbench arm build new && pcbench arm status
pcbench arm exec old -- pc help | grep -c '^  pc '          # 22
pcbench arm exec old -- pc explain tv; echo $?               # 127
grep -c 'pc explain\|pc undo\|--apply' ~/agents/bench/arms/old/KB/toolbox.md   # 0
diff <(pc status --brief) <(pcbench arm exec old -- pc status --brief)         # empty
bash ~/agents/bin/tests/run.sh
```

## Rollback
`rm -rf ~/agents/bench/arms`. Nothing shared was written.
