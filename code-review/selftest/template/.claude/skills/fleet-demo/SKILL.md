---
name: fleet-demo
description: Report disk use of the fleet folders for the digest - runs disk-report and log-size and formats one line each.
---

# fleet-demo

1. `disk-report ~/agents/log` and `disk-report ~/agents/backups`.
2. `log-size ~/agents/log | head -3`.
3. One line per folder in the digest.
