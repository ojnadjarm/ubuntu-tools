# Dashboard office: add a team, a member, a name; the 3D Org page (`staff.json`, `/api/office`)

Ticket: T1601 (01-18), T1658, T1666, T1687, T1755, T1756, T1757, T1759, T1758 · Last verified: 2026-11-17 by T1758 (CEO floor, `tests/test_office_ceo.js` 7, shots `~/drop/T1758/`), T1759 (deck key, `tests/test_office_floor_work.js`, `test_office_floors.py` deck, live `/api/office` 5 floors, shots `~/drop/T1759/`), T1757 (four floors, `tests/test_office_floor_four.js`, `test_office_floors.py` rest, live `/api/office`, shots `~/drop/T1757/` 4 floors × 5 widths), T1756 (floor head, `tests/test_office_floor_model.js`, shots `~/drop/T1756/`), T1755 (`tests/test_office_floor_model.js`, `tests/test_office_floors.py`, live `/api/office` floors, shots 2 floors × 5 widths); 2026-11-11 by T1687 (`tests/test_office_status.js`, `tests/test_section_status.py`, live `/api/office` vass paused), T1666 (`bin/tests/dashboard-office-drag.test.sh`), T1658 (`bin/tests/dashboard-office-chat.test.sh`); 2026-11-10 by T1601-16 (`staff.load()` 3 teams 12 members, live `GET /api/office`
4 teams incl. Unassigned 1 (`memory-keeper`), `test_office_*.js` green, `GPU=1 tools/shots.mjs` margins at 5 widths)

## When to use
- A new team, member, display name or rank in the office (Agents › Office, `#org`), or a seat in it.
- A new floor of the office (T1755: the Discord projects' floor), or a team moved to another floor.
- Changing the office scene (rooms, signs, camera) or its budgets. Not for chat rules or seats' wakes: guide `agent-chat`.
  Not for the dashboard eye (glyph swarm): guide `dashboard-threejs-glyph-eye`.

## The path we took
- Owner's pick: mockup A2 (`~/drop/T1596/A2/`), a cyberpunk loft in real 3D, ported, not redesigned. Plan
  `~/agent-work/research/2026-11-10/T1601/PLAN.md`; history lines in `~/agents/dashboard/CLAUDE.md` (T1601-01 … 18).
- Content is data (no skill: each recipe is one JSON line). Teams, members, names, ranks: `~/agents/staff.json`.
  Seats (CEO, POs, managers, pull seats): `~/agents/org.json`. Neither edit touches a second file or needs a restart:
  `staff.json` is read on every `/api/office` build (`cached("office", 3)`), seats through `/api/org`.
- A new hire appears by itself: a new org.json seat gets a room; a new rostered agent (`~/agents/<name>/`) gets a desk in
  its team if `staff.json` names it, else in the room "Unassigned" (name = id, rank Staff). `hidden` keeps one out.
- Avatar-only office (owner, T1601-17): creatures, rooms, one name board per room (two racks + a holo screen,
  `build/sign.js`); no floating tags, no floor names, no boards beside the scene, no Recent. A click on a creature or a
  board opens its card (`fields.js`): every Org, Court and Roster field lives on a card (`PARITY.md` 24 pass, 0 FAIL).
  Court and Roster tabs are gone; `#agents` and `#roster` open `#org`.
- Server: `lib/staff.py` (`path`, `load` validates, `assign`), `dash/services/office.py` (`compose` pure, route
  tailnet only). Client (`static/next/js/office/`): pure core under node (`model.js` build + keyed `diff`, `layout.js`
  bay grid, one `GAP` 1.4 m, `fields.js` cards, `time.js`, `build/*` chunks), WebGL only in `gl/*` (one context, draw on
  demand, 0 frames hidden), HTML in `overlay/{list,card}.js`, composition root `screens/org.js`.
- Talk panel (T1658, owner 2026-11-11: talk to an agent without leaving the office): a card's "Message <name>" or the list's
  message button opens `overlay/talk.js`, a modal `<dialog class="otalk">` over the live office (floating panel bottom right
  from 900 px, bottom sheet below that sizes to `visualViewport` so the keyboard never covers the composer). It reuses
  Chat's own rows (`screens/chat-thread.js`, extracted from chat.js) and composer (`chat-compose.js`, whose `bind()` now
  takes the callbacks of whichever view shows it); its own 3 s read of `/api/chat?ch=` while open, `/api/org` every 20 s,
  `/seen` like Chat. ×, Esc, a click outside close it (camera untouched); "Open in Chat" goes to `#chat?ch=`; a modified
  click on Message still opens Chat. CSS `static/css/office-talk.css`.
- Moving the talk panel (T1666, owner 2026-11-11: "move the chat window freely"): from 900 px its header drags it
  (mouse, touch, pen; `static/next/js/ui/drag.js` `movable(box, {handle, when, spot})` → `{place}`: pointer capture on
  the dialog, sets `left/top`, clamps to `documentElement.clientWidth/Height`, re-clamps on `resize`, swallows the click
  that ends a move). `talk.js` keeps the spot in a module object, so the next panel opens there until a reload. Below
  900 px the bottom sheet stays (it follows `visualViewport` so the keyboard never covers the composer; a free window on
  a 400 px phone would cover the office or the composer). Links and buttons in the header never start a drag.
- Full screen (T1658): `overlay/full.js` + `#office-full` (stage top right): `html.ofill` lays the stage over the chrome and,
  where element fullscreen exists, the page (`documentElement`) goes full screen too; iPhone Safari has none, so it only
  fills the window. Esc / the button leave; leaving the office leaves it.
- Section status (T1687, owner 2026-11-11: "a status to the sections, like Vacation"): `lib/section_status.py` checks it on
  load and `office.compose` sends `{id, label, since?, note?}`; a resting room's board turns violet (`th.rest`) with the
  label under a rail, its racks keep their state, floor trace and lamp read as asleep; card state line "Paused since 11 Nov
  · N working now", note first; the list tags the seat or team. Rooms without one build byte-identical chunks. No status
  changes behaviour: a paused seat still works when woken. Shots `~/drop/T1687/`.
- Floors (T1755, owner 2026-11-17: "discord projects will need its own floor"): a floor is one line in `staff.json`
  `floors` (`{"id", "name", "teams": [...]}`); a team id names an org.json head seat (a PO under the CEO, with its whole
  tree) or a staff.json team; everything not named stands on the main floor (id `main`, reserved), with the CEO.
  `lib/staff.py` validates (empty id/name, `main`, duplicate, empty teams, a team on 2 floors); `office.compose` sends
  `floors` only when set. Client: `office/floors.js` (pure: `floors(P)`, `placer(P)` → seat/team/starter floor,
  `view(M, f)`, `working(M, list)`); `model.js` stamps `room.floor` and splits the desk pool per floor (a loose worker
  sits on the floor of the staff member that started it: `started_by` = member id or `<id>-…`; `pool-<floor>` only
  when it has people); a manager's po-work worker already sits in its seat's room, so it follows the seat. `org.js`
  hands the renderer `view(M, floor)` (a floor change = `patch.layout`, full rebuild and camera fit), cards and the
  list keep the whole model. The elevator panel `.oflr` (top left of the stage, top floor first, `aria-pressed`,
  count of working people per floor) is hidden with one floor and in still mode; `#org?floor=<id>` keeps the floor
  over a reload (`read`/`hash` exports).
- Four floors (T1757, owner 2026-11-17: CEO floor, personal projects, maintenance/finance): the `floors` lines are the
  whole building, bottom floor first (1F = first line; the panel shows the last line on top). The line whose `teams`
  holds the CEO seat (`orchestrator`) is the CEO's floor (`floors.js` `home(P)`): there is then no `main` floor, the
  page opens on it, an unknown `?floor=` falls back to it (`pick`), the desk pool `pool` and any worker of an unknown
  starter stand on it. Listing the CEO seat holds the CEO only, not its tree. Today: 1F Operations (`operations`,
  `quality`, `improvement`, `finance`, `"rest": ["team"]`), 2F Projects (`mooblox`, `vass`, `"rest": ["po"]`), 3F
  Discord, 4F CEO. Default floor of a newcomer: an org.json seat on no line goes to its nearest listed parent's floor
  below the CEO (a new Discord PO: Discord), else to the `"rest": ["po"]` floor (Projects); a staff team on no line,
  Unassigned included, to the `"rest": ["team"]` floor (Operations); with no `rest` line, the CEO's floor. Without a
  CEO line the old `main` floor comes back (fixtures of T1755/T1756). Panel: a column up to a 600 px stage; a
  narrower stage (container query) puts it two by two across the top, Full screen at the bottom left; six floors =
  3 rows there (about 140 px), a 6-button column (about 280 px) on wider stages. `layout.js` `rowsOf(M)` (shared with `build/hall.js`): seat rows from 1 (was
  2), at least 2 rows in all for the pool by the stairs. The renderer and builders have no floor branch.
- Personal and Work floors (T1759, owner 2026-11-17: "another floor for work related projects", "Personal and Work
  related projects shouldn't have an upper section"): five floors, top to bottom CEO, Discord, Personal projects
  (`personal`: mooblox, `rest: ["po"]`, so a new PO lands here), Work projects (`work`: vass), Operations. Key
  `"deck": false` on a floor line (default true: absent = the raised office) drops the mezzanine column: `floors.js`
  `flat(P)` lists those floors, `view(M, f, P)` sets `deck` and puts nobody up there, `layout.js` `x0Of(M)` starts the
  bays half a GAP from the left wall (`plan.hall.x0`), the desk pool takes a bay (`layout.js` `baysOf(M)` counts it, also in the
  hall stamp), `build/hall.js` draws no deck, stairs or kitchen and windows the whole left wall. `lib/staff.py`:
  `deck` must be a bool, and a line with `head` and `deck: false` is an error ("needs the raised office").
- Unread mark in the 3D office: left out (T1658). The data is cheap (`/api/chat` `channels[].unread` per `dmOf(id)`), but a
  mark over a creature needs a per-creature lamp or halo in `model.js` + `gl/` (Room.key, diff, rebuild), not a few lines.

`GET /api/office` (tailnet only, 403 from the LAN):
```
{ seats:    [{id, name, rank, role, parent, area, about?, wake, runner?}],          no owner seat
  sessions: [{seat, state, since, pid?, parent?, name?, cwd?, started_by?, rank?}], protected row: seat, state, since only
  staff:    [{id, name, members: [{id, name, rank, kind, state, on, health, schedule, next, last, runner, fallback?, report, …}]}],
  agents:   {orchestrator: {name, role, rank, session, state}, subagents: [{id, label, type, started, last, state, doing, report}], claims: [str]},
  error?:   "…" }                                                                    last good body kept on a source error
```

## CEO floor: the Switchboard (T1758, last verified 2026-11-17)

The CEO's floor line, when it holds only the CEO and the desk pool, is its own room (`view()` sets `shell: "ceo"`); any other case keeps the loft. No mezzanine: the office is a stone platform, the pit one step (0.16 m) lower.

| Object | Live from | Files |
|---|---|---|
| Patch wall: a column per floor (top first), a cable + pilot per ticket (green working, dim waiting, red failing), floor plate lit while a ticket runs there | workers and sub-agents in `/api/office`, by `room.floor`; the orchestrator's own sub-agents plug into the CEO column | `office/ceo/desk.js` `tickets`, `columns`; `build/ceo/wall.js` |
| Round table: a sheet per ticket, newest on top; the Conductor stands at it | the same tickets (`sheets`, 12 at most) | `build/ceo/table.js` |
| His chair and reading lamp (amber, the only warm light) | the needs-you verdict (`ceo.live.lamp`, `lampOn`) | `build/ceo/nook.js` |
| Well: a capsule drops for a ticket that starts, rises for one that ends or fails; one run per event | the difference between two reads (`events`, sent as `patch.events`) | `build/ceo/well.js` (rails), `gl/capsule.js` |
| Pit: desks on arcs facing the table (7, 16 once more than 7 sit), step light while it works | desk pool people | `ceo/plan.js` `desk(k)`, `build/ceo/pit.js` |
| Windows: sky over a low skyline, stars at night | `M.night` (quad `k[2] = 1`, `uNight` in `gl/fx.js`) | `build/ceo/shell.js` |
| Chair, tubes, shell | static | |

- A new floor shell = one entry `{hall, rooms, at}` in `build/index.js` `shellOf` plus a plan in `layout.js`; the renderer is untouched.
- `ceo.desk` is in the CEO's `Room.key`, so a ticket anywhere rebuilds the CEO chunk (9,700 vertices, about 16 ms under node); the one-hall office (no floor lines) gets no desk.
- Measured (fixture, 1366, GPU): 76,406 → 17,861 vertices, 11 → 11 draw calls, frame median 0.2 → 0.2 ms; a capsule is 1 extra draw only while it moves.
- Pitfall: with nobody working the page reads `/api/office` on the 30 s tick, so the first brief out of a calm office shows up to 30 s late (5 s once anything runs).
- No closed ceiling (the camera lives above): a bronze head beam on the glass walls only.

## Exact commands
```bash
cd ~/agents
# a team: one object in "teams"; a member: one object in its "members"; a name or rank: edit that object
#   {"id": "<team>", "name": "<Team>", "members": [{"id": "<agent folder or unit id>", "name": "<Name>", "rank": "<Rank>"}]}
#   "unit": "<x>.timer|.service" only for a member with no ~/agents/<id> folder; "hidden": ["<id>"] keeps one out
# a floor: one line in "floors" (teams = org.json head seat ids and/or staff team ids; their trees and members follow)
#   {"id": "<floor>", "name": "<Name>", "teams": ["<head seat id>", "<staff team id>"]}     the panel and #org?floor=<floor> follow
#   "head": "<seat id in teams>" seats it in the raised office (the CEO's on main; T1756 `office/floors.js` view, `build/room.js` headSpot); no head = an empty one
#   lines are bottom floor first; the line whose teams hold "orchestrator" is the CEO's floor (no main then)
#   "rest": ["po"] / ["team"] takes every seat / staff team no line names (one floor each; validated in lib/staff.py)
#   "deck": false = no raised office, no stairs, rooms from the left wall (default true; not with "head"; T1759)
python3 -c 'import sys; sys.path.insert(0, "lib"); import staff; d = staff.load(); print(len(d["teams"]), "teams ok")'   # ValueError names the first problem
# set or clear a section's status (T1687): on its org.json seat or staff.json team line add
#   "status": {"id": "paused|vacation", "since": "YYYY-MM-DD", "note": "<optional>"}; delete the key (or "id": "active") to clear;
#   the ids live only in lib/section_status.py STATUSES (a new one = one line); a finished project still just loses its line
python3 -c 'import sys; sys.path.insert(0, "lib"); import org; print([(s["id"], s["status"]) for s in org.seats() if "status" in s])'   # unknown id: ValueError
curl -s http://127.0.0.1:19998/api/office | python3 -c 'import sys,json; d=json.load(sys.stdin); print([(t["id"], len(t["members"])) for t in d["staff"]], d.get("error"))'
cd dashboard
python3 -m pytest tests/test_staff.py tests/test_office_api.py -q
for t in model build fields gl screen signs gap touch keys avatar_only patch workers_drawn; do node tests/test_office_$t.js || break; done
node --test tests/test_office_floor*.js && python3 -m pytest tests/test_office_floors.py -q   # floors (T1755)
node tests/test_office_parity_org.js && node tests/test_office_parity_court.js && node tests/test_office_parity_roster.js
bash ~/agents/bin/tests/dashboard-office-chat.test.sh      # talk panel + full screen, sandboxed (ONLY=desktop|full|phone|widths)
bash ~/agents/bin/tests/dashboard-office-drag.test.sh      # talk panel drag, sandboxed (ONLY=desktop|touch|phone)
GPU=1 node tools/shots.mjs ~/drop/T<n>/after org        # 3D shots at 400/768/1366/1920/2560 (without GPU=1: the still picture)
node tools/office-measure.mjs --gate                     # CPU rest < 2 %, 3 working ≤ 5.7 %, hidden 0 frames; exit 3 = machine not quiet
```

## Pitfalls (measured)
- Before T1666 a drag on the talk panel's header closed it: without pointer capture the click lands on the common
  ancestor (the dialog) at a point outside its box, which the outside-click rule reads as "close". `ui/drag.js` captures
  the pointer and eats the click that ends a move; a move clamped at the window edge leaves the pointer outside the box.
- Element fullscreen on `.office .stage` hid the card popover: Chrome drew the stage's canvas over the later-opened
  popover (`elementFromPoint` on the card hit the canvas; the click on Message timed out). Fullscreen on `documentElement`
  plus the fill CSS keeps the card and the talk dialog on top (T1658).
- The office reads `/api/office` every 4.5 s only while `/api/agents` shows someone working; with the default empty
  fixture the read is every 30 s, so a "keeps updating" test must serve working agents (T1658).
- A po-work worker (`po-work-<p>-T<n>`, session `agent-po-<p>-T<n>`, cwd = the PO folder) was placed on the seat by
  `lib/sessions.py` (exact folder) and listed by `agents.job_rows` as a pool sub-agent: the manager read "Now working" and
  the worker sat in the Desk pool (T1627). `office.crews()` moves any session started by `<seat folder>-T<n>` under its
  seat (Worker, named by ticket) and drops its sub-agent row; the model makes a seat with only working workers
  `available` ("Free to talk · N workers running", part "Workers running"). Only the Office: /api/agents and chat untouched.
- A worker in the model is not a worker he sees (T1630): Aplicación Coche's T1636 sat at the back-left desk behind a
  1.3 m decor rack in the next desk place (16-18 % of its pixels on screen at 1366/1920). Seat rooms now put a bare desk
  in every place in front of a worker on that wall, and people beyond the 6 desks stand in the aisle; card count = the
  room's crew (`raw.crew.n`, idle workers too). `tests/test_office_workers_drawn.js` checks pixels (`__office.seen(id)`:
  seen vs alone, ≥ 50 %) at 1920/1366/400, not only the model. Front desks first was tried and failed: the next row's
  1.85 m name board hid row-1 front workers (32-42 %).
- Owner rejections (2026-11-10): name tags flying over the scene, room names on the floor, and boards beside the scene
  were all removed (17, 17c); the name sits on a rack-and-screen board inside each room. Do not bring any of them back.
- Rest CPU 4.8 % (gate < 2) came from the list's Familiar CSS loops (`familiars.css`, 6.3 of 7.8 % at rest), not
  WebGL; 6 fps vs 8 fps was inside the noise (12). Pausing them while the list is hidden: rest 0.95-1.15 %, 3 working
  4.15-5.35 %, hidden 0 frames, 447-449 KB first visit (14b, 15, 17b).
- One 294 ms first build froze input; split into 8 sliced tasks, longest 69 ms. A seat state change rebuilds 1 room
  (8.3 ms), a day/night flip re-lights 12 in 21-27 ms. The hall is baked with its own lamps only: all 94 lamps on its
  64,396 vertices cost 44-74 ms, over the 30 ms budget (06).
- The ResizeObserver's first call re-fitted the camera after the first frame (software path, 1 run in 3): the stage
  now measures the canvas at construction (0/6 → 6/6, 12).
- Phones: one finger used to tilt the view on a scroll (0.83 → 0.30 on 300 px) and two fingers slid the office; the
  stage handles touch itself: one finger turns, up/down scrolls the page, two fingers tilt and pinch (11).
- At 400 px the board capitals are 3.4-5.1 px at the home view (1920: 11.4-17.0 px), so boards are tapped through a
  44 px pick area, not read (17c, 18).
- The camera looked at the hall's box centre, which perspective puts 51 px left of centre at 1366 (82 at 1920, 116 at
  2560); `gl/stage.js` `centre()` slides it sideways until the margins match: 10-15 px difference at 5 widths (16).
- Three.js r186 `ColorManagement` is one module shared with the eye: the office never sets `enabled` (04). A signed
  `>>` in rack rows gave zero-width rows and NaN colours; use `>>>` (03).
- Headless shots of Library › Terminal log a `frame-ancestors` error: the terminal only allows the https :8498 front,
  and shots load `http://127.0.0.1:19998`; through `https://<tailnet-fqdn>:8498` it frames with 0 errors (16).
- The Familiars are the dashboard's own `js/familiars/*`, `js/gl/familiars/*` (no copy); only `office/gl/*` imports
  three.js, from `vendor/three.sub.js`; no file over 12 KB.

## Links
- Code: `~/agents/staff.json`, `~/agents/org.json`, `~/agents/lib/staff.py`, `~/agents/dashboard/dash/services/office.py`,
  `~/agents/dashboard/static/next/js/office/`, `static/next/js/screens/org.js`, `static/css/office.css`
- Tests: `~/agents/dashboard/tests/test_staff.py`, `test_office_api.py`, `test_office_*.js`, fixture `tests/fixtures/office.json`
- Reusable scripts: `tools/office-measure.mjs` (budgets), `GPU=1 tools/shots.mjs` (5-width shots)
- Design / results: `~/agent-work/research/2026-11-10/T1601/{PLAN,TICKETS,PARITY,DECISIONS}.md`, `done/*.md`; shots `~/drop/T1601-<nn>/`
