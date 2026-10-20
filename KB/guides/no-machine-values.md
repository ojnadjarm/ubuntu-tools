# Keep machine values (hosts, IPs, paths, passwords) out of pushable repo files

Ticket: T278 · Last verified: 2026-10-20 (T846) by paths, `cmp` of both guard copies, `sync.sh` exit line, `.gitignore` (no test run); 2026-10-07 by `bin/tests/no-machine-values.test.sh` green in ubuntu-tools and moodle-harness

## When to use
Before adding a host, tailnet name, IP, MAC, home path, user, email or dev password to any file in `~/agents` or `~/moodle-harness`. Not for files git ignores (`KB/machine.md`, `secrets/`) or `~/agent-work` (outside every repo since T320).

## The path we took
Values live in `~/.config/pc-harness/config.env` (keys documented in `config.example.env`) and `~/.config/pc-harness/private-values` (literals, one per line). Code reads the variable (`bin/env.sh` exports every key); docs use `<tailnet-fqdn>`, `<lan-ip>`, `<github-user>`, `-home-<user>`, `~`. The guard reads the real values at run time and greps git's addable + tracked set.

## Exact commands
```bash
bash ~/agents/bin/tests/no-machine-values.test.sh            # this repo
bash ~/agents/bin/tests/no-machine-values.test.sh <repo-dir>  # any other repo, scan only
echo '<new literal>' >> ~/.config/pc-harness/private-values   # deny a new value
```

## Pitfalls (measured)
- A grep over a symlink to `/dev/input/event3` hung 44 min (T273): the guard skips symlinks and uses `-D skip -d skip`.
- First scan found 17 hits in ubuntu-tools, 1 then 5 in moodle-harness (5 after adding the moodle-docker DB password), 3 in ailearning (public credit links).
- `bench/` is exempt: frozen evidence; its safety selftest names the real remote on purpose (2 hits).
- moodle-harness `sync.sh` exits 1 when a copied file carries a value.

## Links
- Code: `bin/tests/no-machine-values.test.sh`, `~/moodle-harness/tests/no-machine-values.test.sh` (identical copy)
- Design: `~/agent-work/research/2026-10-07/T278/ARCHITECTURE.md`
