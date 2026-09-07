# PB06 — task pack v1, part C: desktop interaction (4 tasks, day set, owner's go required)

**Phase PB · Model: sonnet · Estimated agent time: 2 h · Depends on: PB02; runs only after the owner says go (day set)**

## Goal
Four tasks that need the real screen, scored by state and by the *look economy* (`pc see`/
`pc tree` before `pc shot`, one screenshot per task at most), so the A/B can show whether the
text-first routes are actually taken. Day set only: the owner is present, the TV shows the
desktop, and he has said go for that run.

## Ground rules
PLAN-PCBENCH §2.8 day rules: announce (`pc notify` by the runner, not the agent), one task at
a time, every window the setup opens is closed by teardown (`pc win close`), scratch files
under `~/agents/bench/runs/…`, never the owner's editor tabs (`pc open <file>`, never bare
`gnome-text-editor`), never Spotify, never the owner's Chrome profile. No sound. Never
`git commit`/`push`.

## Context
| ID | prompt | answer fields | setup | check |
|---|---|---|---|---|
| X01 | "what's on the screen right now, and which window has focus?" | `focused`, `windows[]` | `pc open gnome-calculator`; `pc wait-for --focus Calculator` | `focused` matches `pc win focused`; `windows[]` ⊇ `pc win list` titles; **0 screenshots** (text answers it) |
| X02 | "in the calculator, work out 7+8 and tell me the result" | `result` | as X01 | `result==15`; ≤ 1 screenshot; `pc a11y-click`/`pc type` used, no bare coordinates unless the tree failed (`pc tree` exit ≠ 0 in stream) |
| X03 | "a notification just popped, what did it say?" | `text` | `pc notify "pcbench $NONCE" bench` | `text` contains `$NONCE`; 0 screenshots (`pc see` reads the banner) |
| X04 | "type 'pcbench <nonce>' into the scratch note and save it" | `path` | `pc open ~/agents/bench/runs/<run>/scratch.txt`; wait focus | file contains the nonce; the window is the scratch buffer (`pc win focused` title) not another tab; ≤ 1 screenshot |

Look economy is read from the PB02 metrics (`screenshots`, `pc_verbs`), so `check.sh` only
asserts state; the runner flags `screenshots > task.budget.screenshots`.

### Survey (research first)
- Exists: `pc selftest` (the calculator loop, PASS/FAIL, ~20 s), OSWorld GNOME getters
  (a11y tree, clipboard), the desktop skill's see→act→wait-for loop.
- Chosen: reuse `pc selftest`'s calculator recipe as X02's oracle; AT-SPI as the getter.
- Why: the tasks exist to measure the agent, not the tool; the tool is already tested.

## Steps
1. `task.json` ×4 with `set: day`, `needs: [owner_go]`, `budget.screenshots` (0,1,0,1).
2. Scripts; teardown closes every window it opened (`pc win close <sel>`) and asserts
   `pc win list` equals the pre-setup list.
3. Oracle via `solve.sh` using `pc see`/`pc tree --find`/`pc a11y-click`/`pc type`.
4. One day-set dry run with the owner present (he says go in the terminal or by voice);
   report the four oracle wall times.

## Success check
```bash
pcbench list --set day | wc -l                                        # 4
pcbench run --dry-run --set day                                       # setup/solve/check/teardown, owner present
diff <(pc win list) <(cat ~/agents/bench/runs/*/winlist.before | tail -1)   # empty after teardown
```

## Rollback
`rm -rf ~/agents/bench/tasks/X*`; `pc win close Calculator`; delete the scratch file.
