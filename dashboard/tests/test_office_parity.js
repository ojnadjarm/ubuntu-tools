// Office parity (T1601-14): nothing Org, Court and Roster showed is lost. One fixture fills every field of PLAN §2.1 (payload §4.1); one row per kept
// item (25), its assertion read from the old screens' source (court.js, roster.js, org.js before T1601-05), run at 1366 and 400. Every card is reached
// by clicks from the list (the keyboard path to the card a click on an avatar opens) and every subject is checked to stand in the 3D scene.
// Rows by area: test_office_parity_{org,court,roster}.js; fixture and helpers tests/lib/parity-fixture.js, runner tests/lib/parity.js.
// Writes PARITY.md (item, where found, pass or FAIL) from the results. Run: node tests/test_office_parity.js   (fixture API only; PARITY=<file> moves the table)
"use strict";
const os = require("os"), path = require("path");
const OUT = process.env.PARITY || path.join(os.homedir(), "agent-work", "research", "2026-11-10", "T1601", "PARITY.md");

require("./lib/parity").main([require("./test_office_parity_org"), require("./test_office_parity_court"), require("./test_office_parity_roster")], { out: OUT });
