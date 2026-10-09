const assert = require("assert");
const { create, toArrayBuffer, MAX_VOICES } = require("../ui/player-engine.js");

class Param {
  constructor(value) { this.value = value; }
  cancelScheduledValues() {}
  setValueAtTime(value) { this.value = value; }
  linearRampToValueAtTime(value) { this.value = value; }
}

class FakeNode {
  constructor() {
    this.gain = new Param(1);
    this.playbackRate = new Param(1);
    this.buffer = null;
    this.onended = null;
    this.started = 0;
    this.stopped = 0;
  }
  connect() { return this; }
  start() { this.started += 1; }
  stop() {
    this.stopped += 1;
    if (this.onended) this.onended();
  }
}

class FakeAudioContext {
  constructor() {
    this.state = "running";
    this.currentTime = 0;
    this.destination = {};
    this.decoded = 0;
    this.sources = [];
  }
  createGain() { return new FakeNode(); }
  createBufferSource() {
    const source = new FakeNode();
    this.sources.push(source);
    return source;
  }
  createConstantSource() { return new FakeNode(); }
  resume() { this.state = "running"; return Promise.resolve(); }
  decodeAudioData(bytes) {
    this.decoded += 1;
    return Promise.resolve({ frames: bytes.byteLength });
  }
}

function engineWith(files) {
  const ctxHolder = { ctx: null };
  const AudioContext = function () {
    ctxHolder.ctx = new FakeAudioContext();
    return ctxHolder.ctx;
  };
  const engine = create({
    AudioContext,
    readSound: async (file) => files[file] || null
  });
  return { engine, ctxHolder };
}

async function main() {
  const wav = Buffer.alloc(16, 1);
  const { engine, ctxHolder } = engineWith({ "/pack/a.wav": wav, "/pack/b.wav": wav });

  await engine.loadPack({ files: ["/pack/a.wav", "/pack/b.wav"] });
  assert.strictEqual(ctxHolder.ctx.decoded, 2);
  assert.strictEqual(engine.buffers.size, 2);

  const immediate = engine.play({ file: "/pack/a.wav", volume: 0.8, rate: 1.02 });
  assert.strictEqual(immediate, true);
  assert.strictEqual(engine.voices.length, 1);
  assert.strictEqual(ctxHolder.ctx.sources[0].started, 1);
  assert.strictEqual(ctxHolder.ctx.sources[0].playbackRate.value, 1.02);

  engine.play({ file: "/pack/a.wav", volume: 0, rate: 1 });
  assert.strictEqual(engine.voices.length, 1);

  for (let i = 0; i < MAX_VOICES + 5; i++) {
    assert.strictEqual(engine.play({ file: "/pack/a.wav", volume: 0.5, rate: 1 }), true);
  }
  assert.strictEqual(engine.voices.length, MAX_VOICES);
  engine.play({ file: "/pack/b.wav", volume: 1, rate: 1 });
  assert.strictEqual(engine.voices.length, MAX_VOICES);

  const view = new Uint8Array([1, 2, 3, 4]);
  const copied = toArrayBuffer(view);
  assert.ok(copied instanceof ArrayBuffer);
  assert.strictEqual(copied.byteLength, 4);
  view[0] = 9;
  assert.strictEqual(new Uint8Array(copied)[0], 1);

  await engine.loadPack({ files: ["/pack/a.wav"] });
  assert.strictEqual(ctxHolder.ctx.decoded, 2);

  const missing = engineWith({});
  const queued = missing.engine.play({ file: "/missing.wav", volume: 1, rate: 1 });
  assert.strictEqual(queued, false);
  await new Promise((r) => setTimeout(r, 10));
  assert.strictEqual(missing.engine.voices.length, 0);

  const held = engineWith({ "/pack/a.wav": wav });
  await held.engine.loadPack({ files: ["/pack/a.wav"] });
  held.ctxHolder.ctx.state = "suspended";
  assert.strictEqual(held.engine.play({ file: "/pack/a.wav", volume: 1, rate: 1 }), false);
  await new Promise((r) => setTimeout(r, 10));
  assert.strictEqual(held.ctxHolder.ctx.state, "running");
  assert.strictEqual(held.engine.voices.length, 1);

  let reads = 0;
  const delayed = create({
    AudioContext: function () { return new FakeAudioContext(); },
    readSound: () => {
      reads += 1;
      return new Promise((resolve) => setTimeout(() => resolve(wav), 20));
    }
  });
  const first = delayed.play({ file: "/pack/slow.wav", volume: 1, rate: 1 });
  const second = delayed.play({ file: "/pack/slow.wav", volume: 1, rate: 1 });
  assert.strictEqual(first, false);
  assert.strictEqual(second, false);
  await new Promise((r) => setTimeout(r, 50));
  assert.strictEqual(reads, 1);
  assert.strictEqual(delayed.voices.length, 2);

  console.log("player-engine ok");
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
