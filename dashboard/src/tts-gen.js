/**
 * Pre-generate one wav per drill sentence and per distinct target word with the
 * Eye's own Kokoro (sherpa-onnx), so the page never synthesizes on request.
 * Usage: node src/tts-gen.js [--force]
 */
const fs = require("node:fs");
const path = require("node:path");
const sherpa = require(path.join(process.env.HOME, "the-dark-eye/body/node_modules/sherpa-onnx-node"));

const HERE = path.join(__dirname, "..");
const MODEL = path.join(process.env.HOME, "the-dark-eye/body/models/kokoro-int8-multi-lang-v1_0");
const OUT = path.join(HERE, "state", "tts");
const SID = 17;
const SPEED = 1.0;
const force = process.argv.includes("--force");

/** The dashboard's filename for one piece of speech. */
function slug(word) {
  return word.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "");
}

function wav(samples, rate) {
  const pcm = Buffer.alloc(samples.length * 2);
  for (let i = 0; i < samples.length; i++) {
    const v = Math.max(-1, Math.min(1, samples[i]));
    pcm.writeInt16LE(Math.round(v * 32767), i * 2);
  }
  const head = Buffer.alloc(44);
  head.write("RIFF", 0);
  head.writeUInt32LE(36 + pcm.length, 4);
  head.write("WAVE", 8);
  head.write("fmt ", 12);
  head.writeUInt32LE(16, 16);
  head.writeUInt16LE(1, 20);
  head.writeUInt16LE(1, 22);
  head.writeUInt32LE(rate, 24);
  head.writeUInt32LE(rate * 2, 28);
  head.writeUInt16LE(2, 32);
  head.writeUInt16LE(16, 34);
  head.write("data", 36);
  head.writeUInt32LE(pcm.length, 40);
  return Buffer.concat([head, pcm]);
}

const prompts = JSON.parse(fs.readFileSync(path.join(HERE, "voice_prompts.json"), "utf8")).prompts;
const drills = prompts.filter((p) => p.group === "drill");
const jobs = [];
for (const p of drills) jobs.push({ file: "s-" + p.id + ".wav", text: p.text });
const seen = new Set();
for (const p of drills)
  for (const t of p.targets || []) {
    const s = slug(t.word);
    if (!seen.has(s)) {
      seen.add(s);
      jobs.push({ file: "w-" + s + ".wav", text: t.word });
    }
  }

fs.mkdirSync(OUT, { recursive: true });
const tts = new sherpa.OfflineTts({
  model: {
    kokoro: {
      model: path.join(MODEL, "model.int8.onnx"),
      voices: path.join(MODEL, "voices.bin"),
      tokens: path.join(MODEL, "tokens.txt"),
      dataDir: path.join(MODEL, "espeak-ng-data"),
      dictDir: path.join(MODEL, "dict"),
      lexicon: [path.join(MODEL, "lexicon-us-en.txt"), path.join(MODEL, "lexicon-zh.txt")].join(","),
    },
    numThreads: 4,
    debug: false,
    provider: "cpu",
  },
  maxNumSentences: 1,
});

const t0 = Date.now();
let made = 0;
for (const j of jobs) {
  const full = path.join(OUT, j.file);
  if (!force && fs.existsSync(full)) continue;
  const audio = tts.generate({ text: j.text, sid: SID, speed: SPEED, enableExternalBuffer: false });
  fs.writeFileSync(full, wav(new Float32Array(audio.samples), audio.sampleRate));
  made++;
}
console.log(jobs.length + " wavs (" + drills.length + " sentences, " + seen.size + " words), " + made + " generated in " + ((Date.now() - t0) / 1000).toFixed(1) + " s");
