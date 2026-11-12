# Vault tests' push seam (T1693): every owner push a test can reach lands in "$W/seam", never the real notify-owner.
# Source it right after `W=$(mktemp -d)`; a test may still point SECRET_RAISE_CMD or NTFY_* at its own fixture in $W.
case "${W:-}" in /tmp/*|"${TMPDIR:-/tmp}"/*) ;; *) echo "FAIL vault-seam: W='${W:-}' is not a temp dir"; exit 1 ;; esac
mkdir -p "$W/seam"
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >>"%s/seam/pushes.log"\n' "$W" >"$W/seam/notify-owner"
chmod +x "$W/seam/notify-owner"
export PATH="$W/seam:$PATH" SECRET_RAISE_CMD="$W/seam/notify-owner -p high" NTFY_ENV_FILE="$W/seam/no-ntfy.env" \
  NTFY_LOG_FILE="$W/seam/notify.log" NTFY_KEYS_FILE="$W/seam/notify-keys.tsv" NTFY_RESOLVED_FILE="$W/seam/notify-resolved.jsonl"
