# Owner play-test rounds: collect his flaws, split into fix lanes, ship live the same hour

Ticket: T1405 (from Mooblox play-test rounds T1379-T1403, 2026-10-26) · Last verified: 2026-10-27 from playtest/FLAWS*.md,
HUB-FEEDBACK.md, the Mooblox `git log` and the session transcript (6 rounds, 39 items, all fixed and live the same day)

## When to use
The owner plays or uses a build (a game, a web app, a Moodle plugin UI) and starts sending flaws, often as stills plus one line each.
Not for automated test findings: those go straight to a fix ticket, and you do not ask (memory fix-found-bugs-unasked).

## The path we took
1. **A live build he can reach.**
   - Point him at the real site (Moodle 5.2) through his https link, with a test account whose progress is fresh each round (kid2 → kid3 → kid4).
   - Every fix lane deploys there with a version bump, so he always tests the newest build.
2. **One file per round.**
   - Use `research/<date>/playtest/FLAWS<n>.md`, one numbered item per message.
   - Quote his words and mark each quote *copy* (what to show or say) or *intent* (what he means).
   - Save each still beside the file (`<n>.png`) and name it in the item.
   - Add your own notes as "(Orchestrator note, not from the owner: …)".
3. **Close the list only on his word** ("Let's start with that for now", "that's all"). Late add-ons are logged as sub-items (9b, 9c) and given to the lane that owns that area.
4. **Lanes by file area, spawned the same hour.**
   - Round 1 (8 items) went to 4 lanes: far view, camera, living props, sound.
   - Round 2 (14 items) went to 4 lanes: sound audit, world geometry, water/smoke/fire, houses/animals.
   - Each lane claims its folders (guide parallel-lanes-one-repo).
5. **Fix the class, not the item.**
   - A wrong stair means the generator gets fixed and a validator counts wrong stairs over every seed = 0. Do not hand-patch (guide procedural-world-validators).
   - His own words in round 2: "There's a lot of those I guess due to the procedural creation".
6. **Split the audit work.**
   - He audits visual glitches himself ("really hard for an LLM see those like the texture glitch").
   - Agents audit what text and code can check: every sound event (T1385: 42 events audited, 19 new sounds), every static element that should move (T1380: 19 kinds), placement, materials.
7. **Report one line per lane on handback** (commit, version, the count that went to 0). Record his verdict only in his words, and only for the object he named.

## Exact commands
```bash
mkdir -p ~/agent-work/research/$(date +%F)/playtest     # FLAWS.md, FLAWS2.md, ... + stills <n>.png
# item format (one per owner message):
# 3. Glitch (5.png close-up, 6.webp context): <what is wrong, located>. Owner *copy*: "<his words>". <class to fix, validator to add>.
claims add T<n> "<lane paths>"                          # one lane per file area
change-class --repo <repo>                              # tier the lane's tests (guide change-tiers)
```

## Pitfalls (measured)
- **Turnaround from list closed to the last fix live:**
  - round 1: 2 h 23 min (8 items)
  - round 2: 2 h 13 min (14)
  - round 3: 2 h 45 min (7)
  - hub r1: 43 min (6)
  - round 4: 20 min (2)
  - round 5: 34 min (2)
  - He kept playing between rounds and was never left waiting on a question.
- **A validator built from one report covers only that pair.** Flicker came back 3 times on 3 different surface pairs (T1382 ground,
  T1386 props, T1389 terrain/path/cliff). Widen the audit to every kind pair the first time.
- **Asking permission to fix what a test found cost a 6-hour gap.** T1376 finished at 00:47 and T1377 started at 06:44, after his "If we now we have bugs why did yoy ask me for permission to fix them?".
- **An over-read verdict:** "Now yes I like" (about touch + PC) was recorded as approval of the world look. His reply: "Where did I said i approved the World look?". Read the verdict back with the object's name.
- **A mockup built without options was rejected outright.** The T1392 sea map got "No, I don't like this approach", and T1393
  rebuilt it as a warp hub. Any new surface goes through 3 options or a quick read-back of the direction first.
- **Never play sound on the box.** Build and test muted; he listens on his device (FLAWS.md item 5 note).
- **Give each round a fresh test account.** A lane's live check can complete his test course (kid3 was used by T1390), so make a new account before he plays again.

## Links
- Rounds: `~/agent-work/research/2026-10-26/playtest/{FLAWS,FLAWS2,FLAWS3,HUB-FEEDBACK}.md`
- Log: `~/agent-work/research/2026-10-24/night/PLAN.md` (10-26 section)
- Postmortem: `~/agent-work/research/2026-10-27/T1405/POSTMORTEM.md`
- Related guides: procedural-world-validators, parallel-lanes-one-repo, change-tiers, resp-check
