# Give the owner an https link to a file or web build in ~/drop (tailscale serve :8470)

Ticket: T70 (set up by T70-godot-web; T65/T69 found the need) · Last verified: 2026-10-20 (T846) by `tailscale serve status` (11 fronts), Caddyfile bind/matcher, `drop-link --help`; 2026-10-19 (T487) by `bin/tests/drop-link.test.sh` 7/7 (1.7 s), `tailscale serve status`, and `curl` on 127.0.0.1/::1 :8070 + :8470 (200; `.html` opens, other files `attachment`)

## When to use
- Any file, video, zip or web page he should open or test: **invoke the `drop-link` skill** (`drop-link <path> <tNN>`),
  send the https link it prints. Never an `http://…:8070` link (owner, 2026-09-24).
- Adding https to another local port: same `tailscale serve` pattern below.
- Not for private files: the drop has no login (tailnet over https, tailnet + LAN over http).

## The path we took
- `drop.service` (user unit): caddy inside bwrap, `~/drop` bind-mounted read-only as `/srv/drop`, `:8070` bound to the
  LAN IP, the tailnet IP, `127.0.0.1` and `::1` (`~/.config/drop/Caddyfile`). Every file URL not ending in `/`, `.html` or `.htm`
  gets `Content-Disposition: attachment` (forced download); `.html` pages open; folders get an index or a browse listing (T388).
- https without certificates to manage: tailscaled terminates TLS with the tailnet cert and proxies to the http port.
  `sudo tailscale serve --bg --https=8470 http://<tailnet-ip>:8070` → `https://<tailnet-fqdn>:8470/`, tailnet only.
- Why https: plain http on a non-localhost origin is not a secure context, so `navigator.gpu` is absent and three.js
  falls back to WebGL2 without a word. `http://localhost` is a secure context, which is why agents did not see it.
- `bin/drop-link` (architecture: publish → url → check, one small bash file): hard-links a file (`ln`), or a folder
  (`cp -al`), into `~/drop/<sub>/`, copies when the link crosses filesystems, prints the URL-encoded https link
  (folders and `index.html` → trailing `/`), and exits 1 unless the link answers 200. Env `DROP_DIR`, `DROP_URL` for fixtures.

## Exact commands
```bash
drop-link ./dist t70                                         # folder with index.html → https://…:8470/t70/dist/ (page opens)
drop-link /path/to/video.mp4 t72                             # → https://…:8470/t72/video.mp4 (downloads)
bash ~/agents/bin/tests/drop-link.test.sh                    # 7 checks, temp drop + loopback server, 0.4 s
tailscale serve status                                       # want: :8470 → http://<tailnet-ip>:8070
systemctl --user status drop.service                         # caddy up?
sudo tailscale serve --https=8470 off                        # undo (orchestrator's go only)
```
Other https fronts on the same pattern: 8452 Moodle 5.2, 8453 Moodle 5.3, 8472 ailearning test site, 8498 dashboard (for the mic), 8499 netdata, 8644 Dark Eye page;
`tailscale serve status` lists 11 fronts (also 8445, 8446, 8447, 8474).

## Pitfalls (measured)
- He tested the T65 Atelier mockup over http: 5 of 5 runs fell back to WebGL2 ("WebGPU is not available"); over :8470
  `isSecureContext` true, backend WebGPU (`research/2026-09-23/T65/perf/context.md` §1).
- https is not automatically faster: on this Iris Xe under load, WebGPU time-to-ready was 20–21 s vs 10–13 s on WebGL2,
  though its worst main-thread block was shorter (4.2–4.5 s vs 5.7 s). Judge on his RX 7800 XT, not here.
- Before T388 (2026-10-18) any `.html` linked directly downloaded (`content-disposition: attachment` from the `@file not path */`
  matcher); the matcher now also skips `*.html *.htm`, verified on 127.0.0.1, ::1 and :8470 (a `.zip` still downloads).
  127.0.0.1 was not bound before T388 (only `::1`): `curl 127.0.0.1:8070` got connection refused.
- Symlinks do not work: caddy sees only the bind-mounted `~/drop`. Hard links do, but not from the scratchpad
  (`/tmp` is tmpfs, another filesystem: `ln` fails, so `drop-link` copies).
- The first https setup (T69) was refused by the auto-mode permission check (`sudo tailscale serve`); it needs an
  explicit go from the orchestrator. T70-godot-web then set it up.
- `~/drop` was emptied at 13:15 on 2026-09-23 by an unknown process (T56b saw t41–t55 vanish), and again at 16:21 on 2026-09-25
  (t70, t71, t76, `AILEARNING-PUSH-STEPS.txt`, t91 at 20:48; all in `~/.local/share/Trash/`). Keep originals under
  `research/`; the drop is a hand-off, not storage.
- Stale doc as of 2026-10-20: the `drop-folder-for-files` memory's `description:` line still gives the http `:8070` URL (its body names :8470).

## Links
- Code: `~/agents/bin/drop-link`, skill `~/.claude/skills/drop-link/SKILL.md`, unit `~/.config/systemd/user/drop.service`,
  `~/.config/drop/Caddyfile`
- Tests: `~/agents/bin/tests/drop-link.test.sh`
- Results: `~/agent-work/research/2026-09-24/T70/installs.md` (setup line), `research/2026-09-23/T65/perf/context.md` §1–2,
  `research/2026-09-24/T70/web-ceiling.md` · brief `~/agent-work/briefs/T70-engine-options.md` ("Output")
