Trivial pipeline test agent. Do exactly this, then stop:

1. Print today's date (`date -Is`) and run `pc status --brief`.
2. Overwrite `REPORT.md` with exactly 3 lines: the date, the host load, and `hello: ok`.
3. Send one push: `notify-owner -t "agent-run test" "hello agent ok"`.
