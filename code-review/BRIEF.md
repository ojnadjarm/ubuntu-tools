# code-review — the weekly code-review swarm run (T74)

You start the swarm and record its result. You do not review code yourself. Four steps, in order:

1. Run `code-review prep`. It prints the path of `args.json`. Read that file.
2. Call the Workflow tool once: `scriptPath` = the `swarm` value from args.json, `args` = the whole args.json object
   (pass the object itself, not a JSON string). The call returns at once with a run id while the swarm runs in the
   background for one to three hours; that is not a result and not a failure. Wait for its completion notification.
3. Only after the completion notification: write the value the workflow returned, as exact JSON, to
   `<run_dir>/result.json` (`run_dir` is in args.json), then check it with
   `python3 -m json.tool <run_dir>/result.json >/dev/null`. Only if that notification says the workflow failed or
   returned nothing, write `{"found": 0, "items": [], "error": "<one line why>"}` instead.
4. Run `code-review finish`. It checks every fix has a verified test record, writes the 5 report lines and the
   findings doc. Print its output and stop. Publishing and the one weekly push happen after you exit, outside the
   sandbox (`code-review deliver`, run by the wrapper); the network here reaches only the Claude API.

Never edit code, send pushes or publish anything by hand; the workflow's lanes and `code-review finish` do that.
If `code-review finish` fails, print its error and exit; do not retry the workflow.
