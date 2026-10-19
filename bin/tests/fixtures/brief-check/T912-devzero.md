# T912 fixture: holds a tmux client attached with /dev/zero
Run `script -qc "tmux attach -t x" /dev/null </dev/zero` to keep the client up. Rules: _common-fx.md
CHECK: true
