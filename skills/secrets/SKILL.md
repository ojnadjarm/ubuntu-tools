---
name: secrets
description: The fleet's secrets vault (fleet-vault broker, `secret` CLI). Use for "secret", "API key", "token", "password", "credential", "vault", "lease", "Secrets: line", "add a secret", "rotate", "re-issue", "leaked", "scan for secrets", "laptop died". Agents hold a lease, never a value.
---

Triggers: secrets vault, fleet-vault, secret list, secret grant, secret scan, secret reissue, owner-secret, credstore.

# secrets

1. Need a credential in a task: put `Secrets: <name>[, <name>]` in the brief (openrouter also needs `AI image grant: "<quote>"`); the launcher leases it; call `http://127.0.0.1:$FLEET_VAULT_PORT/$FLEET_LEASE_<NAME>/<name>/<path>`. Never read, print or copy a value; there is no verb that shows one.
2. See what exists: `secret list`, `secret log -n 20 [name]`, `secret pending` (critical leases waiting for approval).
3. Owner adds or replaces one: `owner-secret <name>` (no echo) or the dashboard Vault page; agents never add a card (class critical).
4. A value may have leaked, or the laptop died: `secret scan` (logs) or `secret scan --all`; then `secret reissue <name>|--all` and file the owner step with `owner-todo add`.
5. After a vault code change: `sudo -n ~/agents/vault/install --apply`, then `pc units restart fleet-vault --system --apply`, then `secret list`.

Rules: names only in reports, tests, commits and logs; fixtures are `selftest-*` names on a temp broker. Guide: `~/agents/KB/guides/secrets-vault.md`.
