#!/usr/bin/env python3
"""lib/agent_work.py: $AGENT_WORK, the config.env line, the ~/agent-work default, ~ and $VAR expansion; HOME is a mktemp dir."""
import os, sys, tempfile

HERE = os.path.dirname(os.path.realpath(__file__))
REAL_WORK = os.path.expanduser("~/agent-work")
sys.path.insert(0, os.path.join(HERE, "..", "..", "lib"))
from agent_work import agent_work

fail = 0


def check(name, cond, got=""):
    global fail
    print(f'{"agent_work: " + name:64}' + ("OK" if cond else f"FAIL — {got}"))
    fail |= not cond


home = tempfile.mkdtemp()
cfg = home + "/config.env"
os.environ.update(HOME=home, HARNESS_CONFIG=home + "/none.env")
os.environ.pop("AGENT_WORK", None)

check("unset, no config: HOME/agent-work", agent_work() == home + "/agent-work", agent_work())
os.environ["AGENT_WORK"] = "/srv/papers"
check("env set: used as is", agent_work() == "/srv/papers", agent_work())
os.environ["AGENT_WORK"] = "~/papers"
check("env with ~: expanded against HOME", agent_work() == home + "/papers", agent_work())
os.environ["AGENT_WORK"] = "$HOME/vars"
check("env with $HOME: expanded", agent_work() == home + "/vars", agent_work())
os.environ["AGENT_WORK"] = ""
open(cfg, "w").write('# keys\nOTHER=1\nAGENT_WORK="~/from-config"\n')
os.environ["HARNESS_CONFIG"] = cfg
check("empty env: config.env line, quotes stripped, ~ expanded", agent_work() == home + "/from-config", agent_work())
open(cfg, "w").write("OTHER=1\n")
check("config without the key: HOME/agent-work", agent_work() == home + "/agent-work", agent_work())
check("real ~/agent-work never resolved", agent_work() != REAL_WORK, agent_work())
raise SystemExit(fail)
