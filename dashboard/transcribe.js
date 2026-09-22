#!/usr/bin/env node
// One-shot Parakeet decode of a 16 kHz mono s16 wav, same model and settings as the Eye; prints JSON.
const path = require("path"), fs = require("fs");
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
const buf = fs.readFileSync(process.argv[2]).subarray(44);
const samples = new Float32Array(buf.length >> 1);
for (let i = 0; i < samples.length; i++) samples[i] = buf.readInt16LE(i * 2) / 32768;
const t1 = Date.now();
const decode = (s) => { const st = asr.createStream(); st.acceptWaveform({ sampleRate: 16000, samples: s }); asr.decode(st); return asr.getResult(st); };
const r = decode(samples);
const { text, filled } = fillGaps(samples, 16000, r, decode);
process.stdout.write(JSON.stringify({ text, filled, tokens: r.tokens || [], timestamps: r.timestamps || [],
  seconds: samples.length / 16000, load_ms: t1 - t0, decode_ms: Date.now() - t1, model: "parakeet-tdt-0.6b-v3-int8" }) + "\n");
