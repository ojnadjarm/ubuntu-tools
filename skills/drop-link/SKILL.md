---
name: drop-link
description: Give the owner a file, build, video or web page as a checked https link (~/drop, port 8470). Use for "drop", "~/drop/tNN", "send him a link", "https test link", or testing a web build on his phone or PC (plain http blocks WebGPU).
allowed-tools: Bash(drop-link:*), Bash(~/agents/bin/drop-link:*)
---

Triggers: tailnet, preview, test on his phone.

# drop-link — the https link for anything in ~/drop

```bash
drop-link <file|dir> t72          # hard-links into ~/drop/t72/, prints https://<tailnet>:8470/t72/<name>, checks 200
drop-link ~/drop/t65/atelier/index.html   # already in ~/drop: prints and checks the folder link
```

- Send the printed link, never `http://…:8070`: http is not a secure context off localhost, so WebGPU and other
  secure-context APIs silently fall back (T65: 5 of 5 runs on http got WebGL2).
- The dropped folder keeps the source's basename: `drop-link dist t77` → `/t77/dist/`. Copy the build to a folder with the name you
  want first (`cp -r dist out/drop/<name> && drop-link out/drop/<name> t77`; the explainer starter's `tools/drop.sh` does this).
- A web page: publish its **folder** (with `index.html`, link ends in `/`) or a single `.html`/`.htm` (opens as a page).
  Any other file is served with `Content-Disposition: attachment` and downloads.
- Exit 1 = the link did not answer 200: read `tailscale serve status` (want `:8470 → http://<tailnet-ip>:8070`) and
  `systemctl --user status drop.service`. Setting up or undoing the https origin needs the orchestrator's go (sudo).
- Nothing private goes in: the share has no login; anyone on the tailnet can read it.
- Never for ailearning: its builds go to the one site, `.local/drop.sh` → https://<tailnet>:8472/ailearning/ (review mode `?review`; guide `local-sites`, T271).
- Full guide: `~/agents/KB/guides/https-drop-tailscale-serve.md`.
