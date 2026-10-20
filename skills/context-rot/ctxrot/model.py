"""Model port: a headless, tool-less `claude -p` call that returns text, latency and token usage."""
import json
import os
import subprocess
import tempfile
import time
from dataclasses import dataclass


@dataclass
class Reply:
    text: str
    latency_s: float
    input_tokens: int
    output_tokens: int
    cost_usd: float
    raw: dict


class ClaudeCLI:
    """Calls the Claude Code CLI with no tools, no MCP, no settings, no CLAUDE.md and no session file."""

    def __init__(self, model: str, effort: str, system: str, timeout_s: int = 1200):
        self.model, self.effort, self.system, self.timeout_s = model, effort, system, timeout_s

    def ask(self, prompt: str) -> Reply:
        cmd = ["claude", "-p", "--model", self.model, "--effort", self.effort, "--tools", "",
               "--strict-mcp-config", "--setting-sources", "", "--system-prompt", self.system,
               "--no-session-persistence", "--disable-slash-commands", "--output-format", "json"]
        env = dict(os.environ, CLAUDE_CODE_DISABLE_AUTO_MEMORY="1")
        with tempfile.TemporaryDirectory(prefix="ctxrot-") as cwd:
            t0 = time.monotonic()
            p = subprocess.run(cmd, input=prompt, capture_output=True, text=True, cwd=cwd, env=env,
                               timeout=self.timeout_s)
            dt = time.monotonic() - t0
        if p.returncode != 0:
            raise RuntimeError(f"claude exit {p.returncode}: {(p.stderr or p.stdout)[-400:]}")
        d = json.loads(p.stdout)
        u = d.get("usage", {})
        tokens_in = u.get("input_tokens", 0) + u.get("cache_read_input_tokens", 0) + u.get("cache_creation_input_tokens", 0)
        return Reply(d.get("result", ""), dt, tokens_in, u.get("output_tokens", 0), d.get("total_cost_usd", 0.0), d)
