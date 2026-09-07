# O02 — which output is the sound going to?

pc path: `pc audio --json` (`.sinks[] | select(.default)`). Raw path: `pactl get-default-sink`
— both legitimate; `check.sh` samples the raw one as ground truth either way.
