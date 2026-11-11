# Dashboard office: add a team, a member, a name; the 3D Org page (`staff.json`, `/api/office`)

Ticket: T1601 (01-18) · Last verified: 2026-11-10 by T1601-16 (`staff.load()` 3 teams 12 members, live `GET /api/office`
4 teams incl. Unassigned 1 (`memory-keeper`), `test_office_*.js` green, `GPU=1 tools/shots.mjs` margins at 5 widths)

## When to use
- A new team, member, display name or rank in the office (Agents › Office, `#org`), or a seat in it.
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

`GET /api/office` (tailnet only, 403 from the LAN):
```
{ seats:    [{id, name, rank, role, parent, area, about?, wake, runner?}],          no owner seat
  sessions: [{seat, state, since, pid?, parent?, name?, cwd?, started_by?, rank?}], protected row: seat, state, since only
  staff:    [{id, name, members: [{id, name, rank, kind, state, on, health, schedule, next, last, runner, fallback?, report, …}]}],
  agents:   {orchestrator: {name, role, rank, session, state}, subagents: [{id, label, type, started, last, state, doing, report}], claims: [str]},
  error?:   "…" }                                                                    last good body kept on a source error
```

## Exact commands
```bash
cd ~/agents
# a team: one object in "teams"; a member: one object in its "members"; a name or rank: edit that object
#   {"id": "<team>", "name": "<Team>", "members": [{"id": "<agent folder or unit id>", "name": "<Name>", "rank": "<Rank>"}]}
#   "unit": "<x>.timer|.service" only for a member with no ~/agents/<id> folder; "hidden": ["<id>"] keeps one out
python3 -c 'import sys; sys.path.insert(0, "lib"); import staff; d = staff.load(); print(len(d["teams"]), "teams ok")'   # ValueError names the first problem
curl -s http://127.0.0.1:19998/api/office | python3 -c 'import sys,json; d=json.load(sys.stdin); print([(t["id"], len(t["members"])) for t in d["staff"]], d.get("error"))'
cd dashboard
python3 -m pytest tests/test_staff.py tests/test_office_api.py -q
for t in model build fields gl screen signs gap touch keys avatar_only patch; do node tests/test_office_$t.js || break; done
node tests/test_office_parity_org.js && node tests/test_office_parity_court.js && node tests/test_office_parity_roster.js
GPU=1 node tools/shots.mjs ~/drop/T<n>/after org        # 3D shots at 400/768/1366/1920/2560 (without GPU=1: the still picture)
node tools/office-measure.mjs --gate                     # CPU rest < 2 %, 3 working ≤ 5.7 %, hidden 0 frames; exit 3 = machine not quiet
```

## Pitfalls (measured)
- A po-work worker (`po-work-<p>-T<n>`, session `agent-po-<p>-T<n>`, cwd = the PO folder) was placed on the seat by
  `lib/sessions.py` (exact folder) and listed by `agents.job_rows` as a pool sub-agent: the manager read "Now working" and
  the worker sat in the Desk pool (T1627). `office.crews()` moves any session started by `<seat folder>-T<n>` under its
  seat (Worker, named by ticket) and drops its sub-agent row; the model makes a seat with only working workers
  `available` ("Free to talk · N workers running", part "Workers running"). Only the Office: /api/agents and chat untouched.
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
