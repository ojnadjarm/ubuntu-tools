# D05 — which user service failed?

pc path: `pc units list --failed` + `pc units log <u>`. Raw path:
`systemctl --user --failed` + `journalctl --user -u <u>`.
