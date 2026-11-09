"""The load gauge scales by the CPU count from /api/status: full and red at load >= nproc, in the next and classic headers."""
import json, os, subprocess, sys, unittest
from unittest import mock
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from dash.services import system

STATIC = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "static")
HOOKS = """
import { registerHooks } from "node:module";
import { pathToFileURL } from "node:url";
const ROOT = process.argv[1];
registerHooks({ resolve(s, c, next) {
  if (s.endsWith("/core/router.js")) return { url: "data:text/javascript,export function badges(){}", shortCircuit: true };
  return next(s.startsWith("/static/") ? pathToFileURL(ROOT + s.slice(7)).href : s, c);
} });
globalThis.addEventListener = () => {};
const D = JSON.parse(process.argv[2]);
"""
NEXT = HOOKS + """
const { gauges } = await import(pathToFileURL(ROOT + "/next/js/screens/overview.js").href);
const g = gauges(D).find((x) => x.k === "load");
console.log(JSON.stringify({ p: g.p, bad: !!g.bad }));
"""
CLASSIC = HOOKS + """
const el = {};
globalThis.document = { querySelectorAll: () => [], title: "",
  getElementById: (id) => el[id] || (el[id] = { classList: { toggle() {} }, parentNode: { classList: { toggle() {} } } }) };
const { head } = await import(pathToFileURL(ROOT + "/js/ui/head.js").href);
head(D, false, null);
const load = el.gauges.innerHTML.split("<div").find((x) => x.includes("load "));
console.log(JSON.stringify({ p: +/aria-valuenow="(\\d+)"/.exec(load)[1], bad: /class="[^"]*\\bbad\\b/.test(load) }));
"""


def run(js, load, nproc):
    d = {"nproc": nproc, "host": "box", "status": {"sections": {"host": {"load": {"value": load}}}}}
    out = subprocess.run(["node", "--input-type=module", "-e", js, os.path.abspath(STATIC), json.dumps(d)],
                         capture_output=True, text=True, check=True, timeout=30)
    return json.loads(out.stdout)


class LoadGauge(unittest.TestCase):
    def test_payload_sends_cpu_count(self):
        with mock.patch.object(system, "swr", return_value={"status": {}, "agents": [], "events": []}), \
             mock.patch.object(system, "cache_meta", return_value=(False, {}, None)):
            self.assertEqual(system.payload()["nproc"], os.cpu_count())

    def test_half_load_on_16_threads_is_not_bad(self):
        for js in (NEXT, CLASSIC):
            g = run(js, "8.34 7.00 6.00", 16)
            self.assertFalse(g["bad"])
            self.assertAlmostEqual(g["p"], 52, delta=1)

    def test_load_at_nproc_is_full_and_bad(self):
        for js in (NEXT, CLASSIC):
            self.assertEqual(run(js, "16.50 9.00 8.00", 16), {"p": 100, "bad": True})


if __name__ == "__main__":
    unittest.main()
