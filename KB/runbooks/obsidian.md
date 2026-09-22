# Obsidian (desktop)

## Install
Official .deb from `obsidianmd/obsidian-releases` GitHub releases (chosen over snap: avoids
snap's known Wayland/IME issues; chosen over flatpak: no flatpak runtime was installed on this
box, and a single .deb avoids adding one for one app). Note: the repo's tagged releases
alternate platforms — the "latest" release can be an Android-only build (e.g. v1.13.8 shipped
only an `.apk`); find the newest tag whose assets include `*_amd64.deb`.

Installed: v1.13.7, via
`sudo apt-get install -y ./obsidian_1.13.7_amd64.deb`
(downloaded from `https://github.com/obsidianmd/obsidian-releases/releases/download/v1.13.7/obsidian_1.13.7_amd64.deb`).

Desktop entry: `/usr/share/applications/md.obsidian.Obsidian.desktop`.
Binary: `/opt/Obsidian/obsidian` (symlinked as `/usr/bin/obsidian` via update-alternatives).

## Update
No apt repo — repeat the install step with the newer `*_amd64.deb` tag found the same way
(check recent tags at `https://api.github.com/repos/obsidianmd/obsidian-releases/releases`
until one has an amd64.deb asset). `apt-get install -y ./obsidian_<ver>_amd64.deb` upgrades
in place.

## Vault
Default vault folder: `~/notes` — created empty, left for the owner to populate (copy from his
other PC, or open Obsidian and point "Open folder as vault" at it).

## Launch
`obsidian` (or the desktop entry) opens a normal GUI window — same as any Electron app on this
box (Wayland, ozone-platform=wayland). Never launch it to "check" anything: it opens a window
immediately, there is no true `--version`/headless exit. Verify the install instead via
`dpkg -l obsidian` and `dpkg -L obsidian | grep desktop$`.
