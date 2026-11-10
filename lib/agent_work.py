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


def liaison_papers():
    """Discord liaison jobs, art, escalations, work: LIAISON_PAPERS, default $AGENT_WORK/discord-liaison."""
    return _key("LIAISON_PAPERS") or os.path.join(agent_work(), "discord-liaison")


def bench_papers():
    """pcbench runs, built arms (new/, old/), state: BENCH_PAPERS, default $AGENT_WORK/bench."""
    return _key("BENCH_PAPERS") or os.path.join(agent_work(), "bench")


def po_papers():
    """Product-owner finished requests, <project>/done: PO_PAPERS, default $AGENT_WORK/po."""
    return _key("PO_PAPERS") or os.path.join(agent_work(), "po")


def asr_corpus():
    """The owner's recorded voice clips (owner data): ASR_CORPUS, default $AGENT_WORK/owner/asr-corpus."""
    return _key("ASR_CORPUS") or os.path.join(agent_work(), "owner", "asr-corpus")


def improve_papers():
    """Improvement queue, saved/ restores, metrics.tsv: IMPROVE_PAPERS, default $AGENT_WORK/improve."""
    return _key("IMPROVE_PAPERS") or os.path.join(agent_work(), "improve")


def code_review_papers():
    """Code-review swarm runs, reports, seen findings: CODE_REVIEW_PAPERS, default $AGENT_WORK/code-review."""
    return _key("CODE_REVIEW_PAPERS") or os.path.join(agent_work(), "code-review")


def gamedev_perf_dir():
    """gamedev-perf runs, CSVs, skips: GAMEDEV_PERF_DIR, default $AGENT_WORK/gamedev-perf."""
    return _key("GAMEDEV_PERF_DIR") or os.path.join(agent_work(), "gamedev-perf")
