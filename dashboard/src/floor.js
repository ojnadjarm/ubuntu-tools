/**
 * The machine's error floor: Kokoro says each drill prompt in a native voice, the same
 * Parakeet pipeline decodes it, and the result is scored with the dashboard's own rules.
 * A miss here is the recogniser's, never the speaker's.
 * Usage: node src/floor.js [--force]
 */
const fs = require("node:fs");
const path = require("node:path");
const { execFileSync } = require("node:child_process");

const HERE = path.join(__dirname, "..");
const OUT = path.join(HERE, "state", "floor.json");
const force = process.argv.includes("--force");

const prompts = JSON.parse(fs.readFileSync(path.join(HERE, "voice_prompts.json"), "utf8")).prompts;
const drills = prompts.filter((p) => p.group === "drill");

execFileSync(process.execPath, [path.join(__dirname, "tts-gen.js"), ...(force ? ["--force"] : [])], { stdio: "inherit" });

let old = {};
if (!force && fs.existsSync(OUT)) {
  try {
    old = JSON.parse(fs.readFileSync(OUT, "utf8")).prompts || {};
  } catch (e) {
    old = {};
  }
}

const t0 = Date.now();
let decoded = 0;
const rows = {};
for (const p of drills) {
  const wav = path.join(HERE, "state", "tts", "s-" + p.id + ".wav");
  const prev = old[p.id];
  if (prev && prev.text === p.text && prev.wav_mtime === fs.statSync(wav).mtimeMs) {
    rows[p.id] = prev;
    continue;
  }
  const tr = JSON.parse(execFileSync(process.execPath, [path.join(HERE, "transcribe.js"), wav], { encoding: "utf8" }));
  decoded++;
  rows[p.id] = { text: p.text, pattern: p.pattern, transcript: tr.text, tokens: tr.tokens,
    timestamps: tr.timestamps, wav_mtime: fs.statSync(wav).mtimeMs };
}

const scored = execFileSync("python3", ["-c", `
import json, sys, os
sys.path.insert(0, ${JSON.stringify(HERE)})
import server
rows = json.load(sys.stdin)
prompts = {p["id"]: p for p in server.prompts()}
for pid, r in rows.items():
    r["diff"], r["wer"] = server.word_diff(r["text"], r["transcript"])
    r["verdict"] = server.pattern_verdict(prompts[pid], r["transcript"], r.get("tokens"), r.get("timestamps"))
json.dump(rows, sys.stdout)
`], { input: JSON.stringify(rows), encoding: "utf8", maxBuffer: 1 << 24 });

const out = JSON.parse(scored);
const wers = Object.values(out).map((r) => r.wer);
const misses = [];
for (const r of Object.values(out))
  for (const v of r.verdict || []) if (v.status === "miss") misses.push(v.word);

fs.writeFileSync(OUT, JSON.stringify({
  generated_at: new Date().toISOString(),
  model: "parakeet-tdt-0.6b-v3-int8", voice: "kokoro sid 17",
  mean_wer: +(wers.reduce((a, b) => a + b, 0) / wers.length).toFixed(4),
  floor_misses: [...new Set(misses)].sort(),
  prompts: out,
}, null, 1) + "\n");

console.log(drills.length + " prompts, " + decoded + " decoded, mean WER " +
  (100 * wers.reduce((a, b) => a + b, 0) / wers.length).toFixed(1) + " %, " +
  misses.length + " target misses, " + ((Date.now() - t0) / 1000).toFixed(1) + " s");
