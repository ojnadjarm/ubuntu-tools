# PB01 — spike: the two arms, headless flags, one hand-run trial of one task

**Phase PB · Model: opus · Estimated agent time: 2 h · Depends on: nothing (blocks PB02, PB03)**

## Goal
Settle, on this box, the four facts the whole suite rests on (PLAN-PCBENCH §2.7): (1) an
"old toolbox" arm can be presented to a fresh `claude -p` at the **real paths** (`~/agents/bin`,
`~/agents/KB`) through a per-process bind mount (`bwrap`), with the PATH-shim fallback if the
AppArmor userns policy refuses; (2) which of `--setting-sources`, `--append-system-prompt-file`,
`--json-schema`, `--disallowedTools Agent`, `--max-turns`, `--max-budget-usd`,
`--output-format stream-json --verbose` behave as PLAN §2.6 assumes in 2.1.263 (OAuth login,
no `--bare`); (3) the stream-json/`.jsonl` record shape the parser will read; (4) one complete
trial of D01 (CPU burner) in each arm, by hand, timed, with the checker run by hand — so PB02
builds against a real transcript pair, not a guess.

## Ground rules
Read PLAN-PCBENCH §2 first, then `~/agents/KB/toolbox.md` §2/§6, `~/agents/FLEET.md` §5.
Night rules: no window, no sound, TV untouched. Every injected condition is a
`systemd-run --user --unit pcbench-*` transient unit or a `pcbench-*` named object, lives
< 10 min, and is torn down before the report. Nothing under `~/agents/bin` or `~/agents/KB` is
modified — the old arm is a **copy** under `~/agents/bench/arms/old/`. Never `git commit`/`push`.
Scratch under `~/agents/bench/spike/` (delete before reporting, keep the two transcripts).

## Context
- `pc` resolves its script dir with `readlink -f "$0"`: a shim dir needs a **copy** of `pc`
  (not a symlink) plus symlinks to the 22 pre-PT02 scripts (`a11y-click click click-text clip
  drag find key mode move notify open scroll see selftest shot spotify status tree type wait
  wait-for win`) and `pclib.sh` (post-PT01 `pc-status` sources it).
- No pre-2026-09-07 copy of `toolbox.md` exists (backups tarballs and transcripts checked): the
  old docs arm is a reconstruction — PLAN §2.7 lists exactly what to strip.
- `claude -p` on this account authenticates by OAuth; `--bare` fails with "Not logged in".
- Trials run with cwd under `$HOME`, so `~/CLAUDE.md` (the orchestrator file) is an ancestor
  project memory. Measure whether `--setting-sources user` drops it while keeping the user hooks.

### Survey (research first)
- Exists: `bwrap` (bubblewrap, in Ubuntu main; used by flatpak), `unshare -rm` + `mount --bind`
  (needs userns too), `proot` (slow, ptrace), plain PATH shims + a system-prompt note (leaky:
  `~/CLAUDE.md` still points at the real `toolbox.md`).
- Chosen: `bwrap --dev-bind / / --bind $ARM/bin $HOME/agents/bin --bind $ARM/KB $HOME/agents/KB
  --bind $ARM/skills $HOME/.claude/skills/desktop …` — everything else (D-Bus, PipeWire, docker
  socket, `/run/user/1000`) stays live; other processes see the real dirs.
- Why: it is the only option where the *documentation* arm is faithful without touching shared
  files; the fallback exists if userns is restricted.

## Steps
1. `bwrap` probe: `bwrap --dev-bind / / --bind /tmp/x $HOME/agents/KB true` and, inside,
   `pc status --brief`, `busctl --user status`, `pactl info`, `docker ps` all answer. Record the
   AppArmor verdict (`sysctl kernel.apparmor_restrict_unprivileged_userns`, `dmesg | grep bwrap`).
   If refused, document the shim fallback and its leaks.
2. Flags probe with `--max-turns 2`: `claude -p "reply with the word ok" --output-format
   stream-json --verbose --setting-sources user --disallowedTools Agent --json-schema '{...}'`;
   confirm `result` keys (`num_turns duration_ms total_cost_usd usage modelUsage
   permission_denials structured_output session_id`) and that assistant records carry
   `tool_use` blocks and `usage`. Ask the model, in the probe, to quote the first heading of
   its project memory — to see whether `~/CLAUDE.md` loaded under each `--setting-sources` value.
3. Build `~/agents/bench/arms/old/{bin,KB,skills}` by hand once (PB03 automates): shim bin,
   `toolbox.md` with §2's table cut to the desktop rows, §2's "safety" bullets, §6.11 and every
   `pc explain`/`pc-cli.md`/`pc undo`/`pc doctor` mention removed, `pc-cli.md` absent, desktop
   skill without "Below the screen" and the mutations bullet. `diff -u` against the live files
   and keep the diff as `arms/old/RECONSTRUCTION.diff`.
4. Hand-run D01 twice (old arm, new arm): `systemd-run --user --unit pcbench-burn -p
   CPUQuota=150% sh -c 'yes >/dev/null & yes >/dev/null & wait'`; prompt = the owner words from
   PLAN §2.4; `--json-schema` for `{culprit, evidence, fixed}`; stop the unit; run the checker
   logic by hand (`culprit` matches `pcbench-burn|yes`). Record wall, turns, tool calls,
   `pc shot` count, raw-`top`/`ps` count, tokens for each.
5. Write `~/agents/bench/spike/FINDINGS.md` (≤ 40 lines): the four facts, the exact `claude -p`
   command line PB02 must use, the two transcript paths, the D01 numbers.

## Success check
```bash
bwrap --dev-bind / / --bind ~/agents/bench/arms/old/bin ~/agents/bin sh -c 'pc help | grep -c "^  pc"'   # 22, or the fallback is documented
bwrap --dev-bind / / --bind ~/agents/bench/arms/old/bin ~/agents/bin pc explain tv; echo $?        # 127 (unknown command)
ls ~/agents/bench/spike/*.stream.jsonl | wc -l                                                     # 2
systemctl --user list-units 'pcbench-*' --all --no-legend | wc -l                                  # 0
pc doctor --quick --json | jq -e 'map(select(.status=="FAIL"))|length==0'
```

## Rollback
`rm -rf ~/agents/bench/spike ~/agents/bench/arms`; `systemctl --user stop pcbench-burn` if it
survived. Nothing else was touched.
