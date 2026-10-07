#!/usr/bin/env node
// One-shot Parakeet decode of a mono wav at its own sample rate, same model and settings as the Eye; prints JSON.
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
const { samples, sampleRate } = sherpa.readWave(process.argv[2]);
const t1 = Date.now();
const decode = (s) => { const st = asr.createStream(); st.acceptWaveform({ sampleRate, samples: s }); asr.decode(st); return asr.getResult(st); };
const r = decode(samples);
const { text, filled } = fillGaps(samples, sampleRate, r, decode);
process.stdout.write(JSON.stringify({ text, filled, tokens: r.tokens || [], timestamps: r.timestamps || [],
  seconds: samples.length / sampleRate, load_ms: t1 - t0, decode_ms: Date.now() - t1, model: "parakeet-tdt-0.6b-v3-int8" }) + "\n");
