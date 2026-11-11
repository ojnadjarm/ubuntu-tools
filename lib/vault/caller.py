"""Where an admin-socket peer runs: the agent cgroup (agents.slice) it sits in, read from cgroupfs, never /proc."""
import os

ROOT = "/sys/fs/cgroup"
SLICE = "agents.slice"


class Callers:
    """Finds a peer pid among the cgroups of a user's agents.slice (every headless agent's tool calls run there)."""

    def __init__(self, root=ROOT, slice_=SLICE):
        self.root, self.slice = root, slice_

    def agent_unit(self, pid, uid):
        """The agents.slice unit holding pid (e.g. run-p1-i2.scope), or None."""
        if not pid or uid is None or uid < 0:
            return None
        base = os.path.join(self.root, "user.slice", f"user-{uid}.slice", f"user@{uid}.service", self.slice)
        want = str(pid)
        for d, _subs, files in os.walk(base):
            if "cgroup.procs" not in files:
                continue
            try:
                with open(os.path.join(d, "cgroup.procs")) as f:
                    if want in f.read().split():
                        return os.path.relpath(d, base) if d != base else self.slice
            except OSError:
                continue
        return None
