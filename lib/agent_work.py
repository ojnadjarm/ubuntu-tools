"""Agent working-papers folder: $AGENT_WORK, else its config.env line, else ~/agent-work (stdlib only)."""
import os


def agent_work():
    """Absolute path of the agent working-papers folder."""
    val = os.environ.get("AGENT_WORK", "")
    if not val:
        cfg = os.environ.get("HARNESS_CONFIG", os.path.expanduser("~/.config/pc-harness/config.env"))
        try:
            with open(cfg) as f:
                val = next((l.split("=", 1)[1].strip().strip("\"'") for l in f if l.startswith("AGENT_WORK=")), "")
        except OSError:
            pass
    return os.path.expanduser(os.path.expandvars(val or "~/agent-work"))
