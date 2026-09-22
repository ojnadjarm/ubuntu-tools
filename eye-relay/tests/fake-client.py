#!/usr/bin/env python3
"""Fixture MCP client: spawns eye-channel, handshakes, appends every channel line to a file."""
import json
import subprocess
import sys

brain, received = sys.argv[1], sys.argv[2]
p = subprocess.Popen([sys.argv[3], brain], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
for m in ({"jsonrpc": "2.0", "id": 1, "method": "initialize",
           "params": {"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "fixture", "version": "0"}}},
          {"jsonrpc": "2.0", "method": "notifications/initialized"}):
    p.stdin.write(json.dumps(m) + "\n")
    p.stdin.flush()
for raw in p.stdout:
    m = json.loads(raw)
    if m.get("method") == "notifications/claude/channel":
        with open(received, "a") as f:
            f.write(m["params"]["content"] + "\n")
