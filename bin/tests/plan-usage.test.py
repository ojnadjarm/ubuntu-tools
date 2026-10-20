#!/usr/bin/env python3
"""plan-usage: parse 3 recorded responses, --check boundary, missing credential and 4xx; inside bwrap --unshare-net."""
import json, os, socket, subprocess, sys, tempfile, threading, http.server

SELF = os.path.realpath(__file__)
CLI = os.path.join(os.path.dirname(os.path.dirname(SELF)), "plan-usage")
if not os.environ.get("PU_SANDBOXED"):
    os.execvp("bwrap", ["bwrap", "--dev-bind", "/", "/", "--unshare-net", "--setenv", "PU_SANDBOXED", "1",
                        "--", sys.executable, SELF])
fail = 0
TOKEN = "sk-ant-oat-FIXTURE-never-printed"  # push-ready: test vector


def check(name, cond, got=""):
    global fail
    print(f'{"plan-usage: " + name:84}' + ("OK" if cond else f"FAIL — {got!r}"))
    fail |= not cond


# Recorded shapes of GET /api/oauth/usage (2026-10): fractional reset seconds, a scoped weekly limit, a null window.
RESP = {
    "typical": {"five_hour": {"utilization": 80.0, "resets_at": "2026-10-19T13:59:59.814469+00:00"},
                "seven_day": {"utilization": 39.0, "resets_at": "2026-10-20T09:59:59.814491+00:00"},
                "limits": [{"kind": "weekly_scoped", "percent": 13, "resets_at": "2026-10-20T09:59:59.814671+00:00",
                            "scope": {"model": {"display_name": "Fable"}}},
                           {"kind": "other", "percent": 99}]},
    "fresh": {"five_hour": {"utilization": 0.0, "resets_at": "2026-10-03T16:09:59.8+00:00"},
              "seven_day": {"utilization": 55.0, "resets_at": "2026-10-06T10:00:00+00:00"}},
    "no5h": {"five_hour": None, "seven_day": {"utilization": 12.5, "resets_at": "2026-10-25T23:30:00+00:00"},
             "limits": []},
}


class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        name = self.path.strip("/")
        H.auth = self.headers.get("Authorization")
        if name in RESP:
            body, code = json.dumps(RESP[name]).encode(), 200
        else:
            body, code = b'{"error":"denied"}', int(name) if name.isdigit() else 404
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *a):
        pass


try:
    socket.create_connection(("1.1.1.1", 443), timeout=2).close()
    print("FAIL selftest: the sandbox reaches the network"); sys.exit(1)
except OSError:
    check("selftest: no route out of the sandbox", True)

srv = http.server.HTTPServer(("127.0.0.1", 0), H)
threading.Thread(target=srv.serve_forever, daemon=True).start()
base = f"http://127.0.0.1:{srv.server_port}/"
tmp = tempfile.mkdtemp()
creds = os.path.join(tmp, "creds.json")
json.dump({"claudeAiOauth": {"accessToken": TOKEN}}, open(creds, "w"))


def run(path, *args, creds_file=creds, state=None):
    env = dict(os.environ, TZ="UTC", LC_ALL="C", PLAN_USAGE_URL=base + path, PLAN_USAGE_CREDS=creds_file,
               PLAN_USAGE_STATE=state or os.path.join(tmp, path + ".state.json"))
    r = subprocess.run([sys.executable, CLI, *args], capture_output=True, text=True, env=env, timeout=30)
    return r.returncode, r.stdout, r.stderr


rc, out, err = run("typical")
check("typical: line with 5h/week % and minute-rounded resets", rc == 0 and out.startswith(
    "5h 80% (resets 14:00) · week 39% (resets Tue 20 Oct 10:00) · source oauth-usage-api · age "), out + err)
check("typical: sends the bearer token, never prints it",
      H.auth == "Bearer " + TOKEN and TOKEN not in out + err, H.auth)
rc, out, _ = run("typical", "--json")
j = json.loads(out)
check("typical --json: pcts, resets and only the weekly_scoped limit",
      (j["5h"]["pct"], j["week"]["pct"], j["week"]["resets_at"], j["scoped"]) ==
      (80.0, 39.0, "2026-10-20T09:59:59.814491+00:00",
       [{"model": "Fable", "pct": 13, "resets_at": "2026-10-20T09:59:59.814671+00:00"}]) and not j["stale"], j)
rc, out, _ = run("fresh")
check("fresh: 0% and 16:09:59.8 rounds to 16:10", rc == 0 and out.startswith(
    "5h 0% (resets 16:10) · week 55% (resets Tue 06 Oct 10:00)"), out)
rc, out, _ = run("no5h")
check("no5h: a null window prints ? and keeps the other", rc == 0 and out.startswith(
    "5h ?% (resets ?) · week 12.5% (resets Sun 25 Oct 23:30)"), out)

for pct, want in (("80", 1), ("79.9", 1), ("80.1", 0)):
    check(f"--check {pct} with 5h at 80% exits {want}", run("typical", "--check", pct)[0] == want)
check("--check 12.5 with 5h null, week 12.5% exits 1", run("no5h", "--check", "12.5")[0] == 1)
check("--check 13 with 5h null, week 12.5% exits 0", run("no5h", "--check", "13")[0] == 0)


def one_line_each(err):
    lines = err.strip().splitlines()
    return len(lines) == 2 and "Traceback" not in err and lines[1].startswith("plan-usage: no reading")


rc, out, err = run("typical", "--check", "80", creds_file=os.path.join(tmp, "missing.json"),
                  state=os.path.join(tmp, "none.json"))
check("missing credential, no cache: rc 2, one line per cause, no traceback",
      rc == 2 and out == "" and one_line_each(err) and "(FileNotFoundError)" in err, err)
for code in ("401", "403"):
    rc, out, err = run(code, "--check", "80")
    check(f"HTTP {code}, no cache: rc 2, one line per cause, no traceback",
          rc == 2 and out == "" and one_line_each(err) and "(HTTPError)" in err and TOKEN not in err, err)
cache = os.path.join(tmp, "cache.json")
run("fresh", state=cache)
rc, out, err = run("401", state=cache)
check("HTTP 401 with a cache: rc 0, the last good reading as source cache",
      rc == 0 and "week 55%" in out and "source cache" in out, out + err)
sys.exit(fail)
