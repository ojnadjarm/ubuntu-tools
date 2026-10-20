# Store a credential without pasting it into chat (owner-secret)

Ticket: T422 · Last verified: 2026-10-20 by T846 audit (`--help`, umask/`mv -f`/`ln` in source); 2026-10-19 by bin/tests/owner-secret.test.sh (26 cases, fixture HOME, real pty)

## When to use
The owner (or an agent relaying him) must hand over a password or token: send him `owner-secret <name>` to type in a terminal, never ask for it in chat. Not for keyring secrets (`secret-tool`) or `.env` files with several keys.

## The path we took
Survey: `systemd-ask-password` (no-echo prompt, prints to stdout), `pass`/`secret-tool` (keyring, not files), bash `read -rs`. Chosen: one bash CLI on `read -rs`, because consumers read plain files in `~/agents/secrets`. Flow: validate name → refuse an existing file unless `--replace` → read (no-echo on a tty, first line of stdin otherwise) → `mktemp` in the same dir, umask 077, mode 600 → publish with `mv -f` (`--replace`) or `ln` (atomic no-clobber).

## Exact commands
```bash
owner-secret discord-bot-token            # prompts, no echo; exit 1 if it exists
owner-secret --replace discord-bot-token  # rotate
some-cmd | owner-secret name              # piped: first line only
bash ~/agents/bin/tests/owner-secret.test.sh
```

## Pitfalls (measured)
- A pty echo check needs a control: `script -qec "bash -c 'read -r v'"` does echo the value, so the "no echo" case is meaningful (2026-10-19).
- Names: letters, digits, `. _ -`, no leading dot; `../x`, `.x`, `a/b`, `` exit 2. An empty value exits 1 and writes nothing.
- The file ends with one newline; read it with `$(<file)` to strip it.

## Links
- Code: ~/agents/bin/owner-secret
- Tests: bash ~/agents/bin/tests/owner-secret.test.sh
