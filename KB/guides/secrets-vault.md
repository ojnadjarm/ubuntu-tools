# Secrets vault: use a credential without holding it, add one, re-issue one, prove none leaked

Ticket: T1634 (V1-V10) · Last verified: 2026-11-11 by `bin/tests/vault-retire.test.sh` and a live `secret scan` on the installed broker (3020 log files, 38 MB, 7 live values, 0 hits, 0.5 s; a fixture value planted in a .gz file found)

## When to use
Any task that needs an API key, token or password; the owner adds or replaces one; a value may have leaked; the laptop
died. Not for local dev literals (`config.env` keeps those) or credentials a tool owns (gh keyring, `~/.ssh`,
Claude login): the vault lists those in `secret reissue` but does not hold them.

## The path we took
Design B of `~/agent-work/research/2026-11-11/T1634/PLAN.md`: a broker `fleet-vault.service` under its own user holds
every value, sealed to the TPM in `/etc/credstore.encrypted` (root 600). An agent never holds a value: it calls
`http://127.0.0.1:$FLEET_VAULT_PORT/<lease>/<name>/<path>` with a lease, and the broker adds the credential. Four
delivery modes: `proxy` (openrouter, Spotify, Discord REST), `op` (ntfy pushes), `exchange` (Salesforce: a session
token out), `unit` (Discord gateway, backup password: systemd hands the value to that unit only). Classes: `free`
(any agent, logged), `ruled` (inside its rules, e.g. the image opt-in), `critical` (each use waits for the owner's or
the orchestrator's approval). Every use, refusal, lease and scan is one line in the broker's log.
`~/agents/secrets` is retired (empty); `secret-mask` has no caller left (the mask broke `sudo` and nested bwrap).

## Exact commands
```bash
secret list                                   # names, class, state, age, last use; never a value
secret log -n 20 [name]                       # who used what, when, result
# a task gets a lease from one brief line (launchers: agent-exec --secrets-from, po-work, liaison jobs):
#   Secrets: openrouter, spotify-token
secret grant <name> --ticket T<n> --ttl 600   # outside an agent only (refused and raised inside agents.slice)
owner-secret <name>                           # the owner types a value, no echo; a registry name goes to the vault
secret add <name> --class free|ruled|critical --used-in "<where>" < file   # all of stdin, multi-line kept
secret replace <name>                         # or the Vault page on the dashboard (masked field, served by the broker)
secret approve|deny <ref>; secret pending     # critical leases
secret reissue <name>|--all                   # where to make each credential anew and what follows
secret scan [--all] [path…]                   # 0 live values in the logs (--all: transcripts, drop, papers, memory, history)
sudo -n ~/agents/vault/install --apply && pc units restart fleet-vault --system --apply   # after a vault code change
bash ~/agents/bin/tests/vault-retire.test.sh  # and vault-core, vault-proxy, vault-op, vault-exchange, vault-grant
```

## Pitfalls (measured)
- Never `cat`/`sed` a secret file to see its shape: key names only (`grep -oE '^[A-Za-z_][A-Za-z0-9_]*'`). V9 leaked one
  config line into a transcript through a heredoc that ran an env file as code.
- The broker runs with `ProtectHome=yes`: `secret scan` works because the client opens each file and passes the
  descriptor (SCM_RIGHTS, 200 per batch); the broker cannot open a home path itself.
- `scan` is refused inside an agent: a file of guesses would make it an oracle for short values.
- A scan needle is the whole value, the secret keys of an env value (`*PASS*`, `*SECRET*`, `*TOKEN*`, `*KEY*`) and the
  secret half of `<id>:<secret>`; needles under 8 bytes are skipped. A URL or user name in an env value is not a leak.
- `secret add` once sealed only the first line of piped stdin (V9: Salesforce's env value had to go in by hand); since
  V10 it keeps every line and drops one trailing newline. The Vault page field is still one line.
- Leases live in the broker's state; approvals in memory: a broker restart drops pending approvals (the launcher asks
  again). Restart only through `pc units restart fleet-vault --system --apply`.
- A new vault CLI in a live session: `~/agents/install.sh --links`.

## Links
- Code: `~/agents/bin/secret`, `~/agents/lib/vault/` (scan.py, scanwalk.py, reissue.py, registry.py, gate.py, …), `~/agents/vault/`
- Tests: `bash ~/agents/bin/tests/vault-retire.test.sh` (and the other `vault-*.test.sh`)
- Design / results: `~/agent-work/research/2026-11-11/T1634/` (PLAN.md, PICK.md, done/V1-V10.md)
- Skill: `/secrets`
