#!/usr/bin/env node
// Parakeet decode of a mono wav at its own sample rate, same model and settings as the Eye; prints JSON.
// `--serve`: one model load, a wav path per stdin line, a JSON line each; exits after TRANSCRIBE_IDLE_MS (120 s) idle.
const path = require("path");
const BODY = process.env.EYE_BODY || path.join(process.env.HOME, "the-dark-eye", "body");
const MODEL = path.join(BODY, "models", "sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8");
const sherpa = require(path.join(BODY, "node_modules", "sherpa-onnx-node"));
const { fillGaps } = require(path.join(BODY, "src", "gapfill"));
const t0 = Date.now();
const asr = new sherpa.OfflineRecognizer({
  featConfig: { sampleRate: 16000, featureDim: 80 },
  modelConfig: {
    transducer: { encoder: path.join(MODEL, "encoder.int8.onnx"), decoder: path.join(MODEL, "decoder.int8.onnx"), joiner: path.join(MODEL, "joiner.int8.onnx") },
    tokens: path.join(MODEL, "tokens.txt"), modelType: "nemo_transducer", numThreads: 1, provider: "cpu", debug: false,
  },
});
const load_ms = Date.now() - t0;
const decode = (s, rate) => { const st = asr.createStream(); st.acceptWaveform({ sampleRate: rate, samples: s }); asr.decode(st); return asr.getResult(st); };
const run = (file) => {
  const { samples, sampleRate } = sherpa.readWave(file);
  const t1 = Date.now();
  const r = decode(samples, sampleRate);
  const { text, filled } = fillGaps(samples, sampleRate, r, (s) => decode(s, sampleRate));
  return { text, filled, tokens: r.tokens || [], timestamps: r.timestamps || [],
    seconds: samples.length / sampleRate, load_ms, decode_ms: Date.now() - t1, model: "parakeet-tdt-0.6b-v3-int8" };
};
if (process.argv[2] !== "--serve") {
  process.stdout.write(JSON.stringify(run(process.argv[2])) + "\n");
} else {
  const idle = Number(process.env.TRANSCRIBE_IDLE_MS) || 120000;
  let timer = setTimeout(() => process.exit(0), idle);
  require("readline").createInterface({ input: process.stdin }).on("line", (file) => {
    clearTimeout(timer);
    let out;
    try { out = run(file.trim()); } catch (e) { out = { error: String(e.message || e) }; }
    process.stdout.write(JSON.stringify(out) + "\n");
    timer = setTimeout(() => process.exit(0), idle);
  }).on("close", () => process.exit(0));
}
