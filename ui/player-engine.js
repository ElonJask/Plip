(function (root, factory) {
  if (typeof module === "object" && module.exports) module.exports = factory();
  else root.PlipPlayer = factory();
})(typeof globalThis !== "undefined" ? globalThis : this, function () {
  const MAX_VOICES = 32;
  const STEAL_FADE = 0.008;

  function toArrayBuffer(data) {
    if (!data) return null;
    if (data instanceof ArrayBuffer) return data.slice(0);
    if (ArrayBuffer.isView(data)) {
      return data.buffer.slice(data.byteOffset, data.byteOffset + data.byteLength);
    }
    return null;
  }

  function create(options) {
    const AudioContextImpl = options.AudioContext;
    const readSound = options.readSound;
    const buffers = new Map();
    const loading = new Map();
    const voices = [];
    let ctx;
    let master;
    let keepAlive;

    function audio() {
      if (!ctx) {
        ctx = new AudioContextImpl({ latencyHint: "interactive" });
        master = ctx.createGain();
        master.connect(ctx.destination);
        try {
          keepAlive = ctx.createConstantSource();
          const silent = ctx.createGain();
          silent.gain.value = 0;
          keepAlive.connect(silent);
          silent.connect(ctx.destination);
          keepAlive.start();
        } catch {}
      }
      return ctx;
    }

    async function ensureRunning() {
      audio();
      if (ctx.state !== "running" && ctx.resume) await ctx.resume();
    }

    async function decodeFile(file) {
      if (!file) return null;
      if (buffers.has(file)) return buffers.get(file);
      if (loading.has(file)) return loading.get(file);
      const task = (async () => {
        if (!readSound) return null;
        const data = await readSound(file);
        const bytes = toArrayBuffer(data);
        if (!bytes || bytes.byteLength < 12) return null;
        const buf = await audio().decodeAudioData(bytes);
        buffers.set(file, buf);
        return buf;
      })().catch(() => null);
      loading.set(file, task);
      try {
        return await task;
      } finally {
        if (loading.get(file) === task) loading.delete(file);
      }
    }

    function pruneVoices() {
      for (let i = voices.length - 1; i >= 0; i--) {
        if (voices[i].done) voices.splice(i, 1);
      }
    }

    function stealOldest() {
      const voice = voices.shift();
      if (!voice || !ctx) return;
      try {
        const now = ctx.currentTime;
        voice.gain.gain.cancelScheduledValues(now);
        voice.gain.gain.setValueAtTime(voice.gain.gain.value, now);
        voice.gain.gain.linearRampToValueAtTime(0, now + STEAL_FADE);
        voice.source.stop(now + STEAL_FADE + 0.002);
      } catch {}
      voice.done = true;
    }

    function start(buf, volume, rate) {
      pruneVoices();
      if (voices.length >= MAX_VOICES) stealOldest();
      const source = ctx.createBufferSource();
      source.buffer = buf;
      source.playbackRate.value = rate > 0 ? rate : 1;
      const gain = ctx.createGain();
      gain.gain.value = volume;
      source.connect(gain);
      gain.connect(master);
      const voice = { source, gain, done: false };
      source.onended = () => { voice.done = true; };
      voices.push(voice);
      source.start();
      return voice;
    }

    async function playWhenReady(file, volume, rate) {
      await ensureRunning();
      const buf = await decodeFile(file);
      if (!buf) return;
      start(buf, volume, rate);
    }

    function play(strike) {
      if (!strike || !strike.file) return false;
      const volume = Math.max(0, Math.min(1, Number(strike.volume)));
      if (!volume) return false;
      const rate = Number(strike.rate) || 1;
      audio();
      const buf = buffers.get(strike.file);
      if (buf && ctx.state === "running") {
        start(buf, volume, rate);
        return true;
      }
      playWhenReady(strike.file, volume, rate).catch(() => {});
      return false;
    }

    async function loadPack(payload) {
      const files = (payload && payload.files) || [];
      if (!files.length) return;
      await ensureRunning();
      await Promise.all(files.map(decodeFile));
    }

    function resume() {
      if (ctx && ctx.state !== "running" && ctx.resume) return ctx.resume();
    }

    return {
      play,
      loadPack,
      resume,
      buffers,
      voices,
      toArrayBuffer,
      maxVoices: MAX_VOICES
    };
  }

  return { create, toArrayBuffer, MAX_VOICES };
});
