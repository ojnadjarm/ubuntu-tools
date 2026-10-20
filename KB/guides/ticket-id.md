# Next ticket number: allocate a free T-id and find ids used twice

Ticket: T741 · Last verified: 2026-10-20 by `ticket-id --help` and code read (T846); earlier by `bin/tests/ticket-id.test.sh` (40 ok) and a live run (`next` T761, 3 double uses: T716, T717, T718; 0.08 s)

## When to use
Before writing a brief or a backlog: take the id from `ticket-id next` (planners: `--reserve`), never by hand.
Not for which wave item shipped: that is `fleet-survey --shipped`.

## The path we took
- Existed: nothing allocated ids; planners read history.md by eye. T716/T717 went to both MIRASMANT-26 (Vass briefs)
  and wave 18 #1/#2; T718 to MIRASMANT-5 (report) and wave 18 #3. Chosen: one read-only Python CLI over the files.
- Model: a **use** is a brief file, a history line whose subject is the id, an evidence or research dir, a backlog
  heading. An **owner** is a backlog item (`## k. T<n>` heading, brief header `#k (from …/T<p>/BACKLOG.md)`, history
  `(wave N #k)`/`(wN #k)` tag) or `brief` (a brief or report mapped to no item). Evidence, research, other history
  lines and reserved stubs own nothing. Two owners = double use.
- `next`: max over all uses plus every `T<n>` in history.md (so `T748..T759` ranges block ids), +1, stopping below the
  first jump > 100 (`GAP`; a typo like T7410 is named on stderr, never allocated above). Live ids have no jump > 20.
  `--reserve` takes a flock on `briefs/.ticket-id.lock` and creates stubs with O_EXCL (contiguous, never shared).
- fleet-survey `--shipped` asks `ticket-id dups` (one seam) and marks `T716*`; the CLI owns the use model.

## Exact commands
```bash
ticket-id next                      # T760
ticket-id next -n 15 --reserve wave20   # planners: writes briefs/T<n>-wave20.md stubs
ticket-id check T716                # every use; exit 1 on a double use
ticket-id dups                      # every double-used id with its owners
ticket-id release T761 T762         # delete unused reserved stubs (first line only, marker intact)
bash ~/agents/bin/tests/ticket-id.test.sh
```

## Pitfalls (measured)
- Plain `next` takes no lock and writes nothing: two planners at once get the same id. It says so on stderr;
  parallel planners use `--reserve`.
- Unused `--reserve` stubs push `next` up until `release`d; a stub with any line under its header is a real brief and
  stays (release exits 1).
- A reserved stub's first line is `# T<n> — reserved by ticket-id: <slug> (<date>)`; keep it or overwrite the file
  with the real brief. A second brief with another slug and no `#k (from …BACKLOG.md)` header is a second owner.
- A report alone (`T718-report.md`, MIRASMANT-5, 2026-10-20 08:55) counts as a brief: the Vass session never wrote
  a brief. Live 2026-10-20: 3 double uses over 817 brief files, none of them a false alarm.
- History lines without a leading `- ` (T720, line 903) were missed by fleet-survey until T778; dated dash-less lines now count as shipped.
- The T747 Moodle backlog uses `## T748 · title` headings: counted for ids (owner `T747:T748`), not as
  fleet-survey items.
- New CLI in ~/agents/bin: `~/agents/install.sh --links`, else "command not found".

## Links
- Code: ~/agents/bin/ticket-id; fleet-survey `_double_used`, `shipped`
- Tests: ~/agents/bin/tests/ticket-id.test.sh (fixture AGENT_WORK, 6 parallel reserves), ~/agents/bin/tests/fleet-survey.test.sh
- Design / results: ~/agent-work/research/2026-10-20/T731/BACKLOG.md §10; decision in ~/agents/KB/DECISIONS.md (2026-10-20)
