"""Agent working-papers folder and the material dirs under it: env var, else its config.env line, else the default (stdlib only)."""
import os, re


def _key(name):
    """A key's value from the environment, else its config.env line, else ''."""
    val = os.environ.get(name, "")
    if not val:
        cfg = os.environ.get("HARNESS_CONFIG", os.path.expanduser("~/.config/pc-harness/config.env"))
        try:
            with open(cfg) as f:
                pat = re.compile(r"\s*(export\s+)?%s=" % re.escape(name))
                val = next((re.split(r"\s+#", l.split("=", 1)[1])[0].strip().strip("\"'") for l in f if pat.match(l)), "")
        except OSError:
            pass
    return os.path.expanduser(os.path.expandvars(val)) if val else ""


def agent_work():
    """Absolute path of the agent working-papers folder."""
    return _key("AGENT_WORK") or os.path.expanduser("~/agent-work")


def backups_dir():
    """Fleet backups (configs, DB dumps, fix backups, retired items): FLEET_BACKUPS_DIR, default $AGENT_WORK/backups."""
    return _key("FLEET_BACKUPS_DIR") or os.path.join(agent_work(), "backups")


def claims_snap_dir():
    """Claims baselines: CLAIMS_SNAP, default $AGENT_WORK/claims-snap."""
    return _key("CLAIMS_SNAP") or os.path.join(agent_work(), "claims-snap")


def toolsmith_papers():
    """Toolsmith BACKLOG.md and proposals/: TOOLSMITH_PAPERS, default $AGENT_WORK/toolsmith."""
    return _key("TOOLSMITH_PAPERS") or os.path.join(agent_work(), "toolsmith")


def dash_plans_dir():
    """Pages plan-publish writes and the dashboard serves at /plans/: DASH_PLANS_DIR, default $AGENT_WORK/research/dashboard/plans."""
    return _key("DASH_PLANS_DIR") or os.path.join(agent_work(), "research", "dashboard", "plans")
