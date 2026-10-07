import { test } from 'node:test';
import assert from 'node:assert/strict';
import { VoicePlayer } from '../src/audio/voice';
import type { UnitBundle } from '../src/content/types';

/** A fake Web Audio: decodes resolve when the test says so; sources log start and stop. */
function fakeAudio() {
  const sounding = new Set<string>(), started: string[] = [], decodes: (() => void)[] = [];
  class Param { setTargetAtTime() {} }
  class Node { connect() { return this; } }
  class Ctx { currentTime = 0; destination = {}; decodeAudioData(b: { id: string }) { return new Promise((r) => decodes.push(() => r({ id: b.id, duration: 4 }))); } }
  class Gain extends Node { gain = new Param(); }
  class Src extends Node {
    buffer: { id: string }; onended: (() => void) | null = null;
    constructor(_c: unknown, o: { buffer: { id: string } }) { super(); this.buffer = o.buffer; }
    start() { sounding.add(this.buffer.id); started.push(this.buffer.id); }
    stop() { sounding.delete(this.buffer.id); }
    addEventListener() {}
  }
  Object.assign(globalThis, { AudioContext: Ctx, GainNode: Gain, AudioBufferSourceNode: Src, Audio: class { canPlayType() { return 'probably'; } },
    fetch: async (u: string) => ({ arrayBuffer: async () => ({ id: u.replace(/\.\w+$/, '') }) }) });
  const flush = async () => { await new Promise((r) => setTimeout(r, 0)); while (decodes.length) decodes.shift()!(); await new Promise((r) => setTimeout(r, 0)); };
  return { sounding, started, flush };
}

test('V1 one voice at a time: a line cut while its clip decodes never starts, a new line stops the one playing, stop stops all', async () => {
  const a = fakeAudio();
  const clips = { d1: { src: 'd1', duration: 4, marks: {}, words: [] }, d2: { src: 'd2', duration: 4, marks: {}, words: [] } };
  const v = new VoicePlayer({ spec: { introduces: [], clips: [] }, cues: { bias: 0, clips }, base: '' } as unknown as UnitBundle);
  v.line('d1'); v.line('d1'); v.stop(); v.line('d1');
  await a.flush();
  assert.deepEqual(a.started, ['d1'], 'two entries while decoding and a stop between: one start');
  v.line('d2'); await a.flush();
  assert.deepEqual([...a.sounding], ['d2']);
  v.segment('d1', 1, 2); v.line('d2'); await a.flush();
  assert.deepEqual([...a.sounding], ['d2']);
  v.stop();
  assert.equal(a.sounding.size, 0);
  assert.equal(v.speaking(), false);
});
