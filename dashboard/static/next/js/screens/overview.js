/* Overview: the eye is the machine; its six rings are the head gauges, the panes around it carry every number and roll when one moves. */
import { esc, when, gb, num } from "/static/js/core/fmt.js";
import { dust } from "../shapes.js";
import { fitEye, FACE } from "../gl/cam.js";
import { odo, trail } from "../ui/num.js";
import { verdict } from "../verdict.js";

export const own = true;
const sec = (D, n) => ((D.status || {}).sections || {})[n] || {};
const val = (o, k) => ((o || {})[k] || {}).value || "";
const R0 = 1.24, DR = 0.1;

/* The six gauges: key, value, unit, percent, bad. */
export function gauges(D) {
  const pw = sec(D, "power"), res = sec(D, "resources"), host = sec(D, "host");
  const ram = /(\d+) MB of (\d+) MB/.exec(val(res, "ram_available")), ramPct = ram ? 100 - 100 * ram[1] / ram[2] : 0;
  const dk = D.docker || [], up = dk.filter((c) => c.state === "running").length, load = num(val(host, "load")), disk = num(val(res, "disk_root")), bh = num(val(pw, "battery_health"));
  return [
    { k: "power", v: num(val(pw, "battery")) || 0, u: "%", p: num(val(pw, "battery")) },
    { k: "disk", v: isNaN(disk) ? "—" : disk, u: "%", p: disk, bad: disk >= 90 },
    { k: "memory", v: ram ? ramPct.toFixed(0) : "—", u: "%", p: ramPct, bad: ramPct >= 90 },
    { k: "load", v: isNaN(load) ? "—" : load.toFixed(2), u: "", p: Math.min(100, load * 12), bad: load * 12 >= 100 },
    { k: "docker", v: up, u: "/" + dk.length, p: dk.length ? 100 * up / dk.length : 0, bad: up < dk.length },
    { k: "battery", v: isNaN(bh) ? "—" : bh, u: "% health", p: bh, bad: bh < 60 },
  ];
}

const sv = (D, k) => ((D.sparks || {})[k] || {}).values || [];
const kv = (rows) => `<dl class="kv">${rows.map(([a, b]) => `<dt>${a}</dt><dd>${esc(b)}</dd>`).join("")}</dl>`;
const pane = (cls, t, s, body) => `<section class="pane ${cls}"><h2><span data-dec>${t}</span><s>${s}</s></h2>${body}</section>`;
const spark = (D, k, unit) => { const v = sv(D, k); return `<figure class="spk">${trail("ov." + k, v, v.length ? `${k}, last 30 minutes, now ${v[v.length - 1].toFixed(0)} ${unit}` : "")}<figcaption>${k} · 30 min <b>${v.length ? odo("ov.s" + k, v[v.length - 1].toFixed(0)) + " " + unit : "—"}</b></figcaption></figure>`; };

export function render(grid, D) {
  const pw = sec(D, "power"), res = sec(D, "resources"), host = sec(D, "host"), net = sec(D, "network"), disk = sec(D, "disk");
  const ram = /(\d+) MB of (\d+) MB/.exec(val(res, "ram_available")), G = gauges(D), vd = verdict(D), dk = D.docker || [];
  const bh = val(pw, "battery_health"), free = (/,\s*(\S+) free/.exec(val(res, "disk_root")) || [])[1] || "", bat = num(val(pw, "battery"));
  const ev = (D.events || []).slice(0, 6).map((e) => `<div class="ev"><span class="t">${esc(when(e.t))}</span><span class="kd ${esc(e.kind)}">${esc(e.kind)}</span><span class="x">${esc(e.text.split("\t")[0])}</span></div>`).join("");
  const probs = vd.items;
  const up = dk.filter((c) => c.state === "running").length;
  return `<div class="nxs hero">` +
    `<div class="side">` +
    pane("p1", "power", esc((val(pw, "profile") || "").toLowerCase()), `<div class="nbig">${isNaN(bat) ? "—" : odo("ov.bat", String(bat))}<u>% · ${esc((val(pw, "source") || "—").toLowerCase())}</u></div><p class="sm">lid ${esc(val(pw, "lid") || "?")}</p>${kv([["health", bh.split(",")[0] || "—"], ["cycles", (bh.split(", ")[1] || "—")], ["uptime", val(host, "uptime").split(", ").slice(0, 2).join(" ") || "—"], ["kernel", val(host, "kernel") || "—"]])}`) +
    pane("p2", "disk", "smart " + esc((val(disk, "smart") || "?").toLowerCase()), `<div class="nbig">${odo("ov.disk", String(G[1].v))}<u>% · ${esc(gb(free))} free</u></div>${kv([["wear", val(disk, "percent_used") || "—"], ["spare", val(disk, "available_spare") || "—"]])}${spark(D, "io", "KB/s")}`) +
    pane("p3", "memory · cpu", "now", `<div class="nbig">${ram ? odo("ov.ram", (ram[1] / 1024).toFixed(1)) : "—"}<u>GB free of ${ram ? (ram[2] / 1024).toFixed(0) : "—"}</u></div>${kv([["load", val(host, "load") || "—"], ["temp", (val(res, "temp_max") || "—").replace(" C", " °C")]])}${spark(D, "cpu", "%")}`) +
    `</div><div class="eyebox" id="eyebox"><div class="eyefield" id="eyefield" aria-hidden="true"></div><div class="verdict${vd.bad ? " bad" : ""}" role="status"><b data-dec>${vd.text}</b>` +
    (probs.length ? `<ul class="probs">${probs.map((p) => `<li>${esc(p)}</li>`).join("")}</ul>` : `<span>nothing failed · every agent finished clean · no push waits on you</span>`) + `</div>` +
    `<dl class="nread">${G.map((g, i) => `<div class="${g.bad ? "bad" : ""}" style="--r:${i}"><dt>${g.k}</dt><dd>${g.v === "—" ? "—" : odo("ov.g" + i, String(g.v))}<u>${esc(g.u)}</u></dd></div>`).join("")}</dl></div>` +
    `<div class="side">` +
    pane("p4", "network", "tailscale " + (val(net, "tailscale") === "Running" ? "on" : esc((val(net, "tailscale") || "?").toLowerCase())), `<div class="nbig">${esc(val(net, "internet") || "—")}</div><p class="sm">${esc(val(net, "wifi_ssid") || "no wifi")}</p>${kv([["lan", val(net, "lan_ip") || "—"], ["tailnet", val(net, "tailscale_ip") || "—"]])}${spark(D, "net", "kbit/s")}`) +
    pane("p5", "docker", up + " of " + dk.length + " up", dk.length ? kv(dk.map((c) => [esc(c.name), c.status.replace(/^Up /, "")])) : `<p class="sm">docker not reachable</p>`) +
    pane("p6", "events", "24 h", ev || `<p class="sm">quiet · no push, no incident</p>`) + `</div></div>`;
}

/* The eye with the six gauges as iris rings, inside the space above the verdict; the mass is dust around it. */
export function scene(D) {
  const G = gauges(D), narrow = innerWidth < 820, outer = R0 + DR * (G.length - 1);
  return {
    key: JSON.stringify(G.map((g) => [Math.round((g.p || 0) / 10), !!g.bad])),
    pts: dust(narrow ? 900 : 2200),
    box: document.getElementById("gl"), span: narrow ? 14 : 24, tilt: 0.2,
    eyeEl: document.getElementById("eyefield"), eyeFit: (b) => fitEye(b, { outer, n: FACE, pad: 0.02 }),
    rings: G.map((g, i) => ({ r: R0 + DR * i, v: (g.p || 0) / 100, kind: g.bad ? 1 : 0 })), ringN: FACE, halo: 0,
  };
}
