const assert = require("assert");
const { normalize, asBool, clampVolume, DEFAULTS } = require("./state");

// 音量 0 是合法值，不能被当成缺失而回退到默认值
assert.strictEqual(normalize({ volume: 0 }).volume, 0);
assert.strictEqual(normalize({ volume: 1 }).volume, 1);
assert.strictEqual(normalize({ volume: 0.35 }).volume, 0.35);

// 非法音量回退默认值或被夹紧
assert.strictEqual(normalize({}).volume, DEFAULTS.volume);
assert.strictEqual(normalize({ volume: "abc" }).volume, DEFAULTS.volume);
assert.strictEqual(normalize({ volume: null }).volume, DEFAULTS.volume);
assert.strictEqual(normalize({ volume: NaN }).volume, DEFAULTS.volume);
assert.strictEqual(clampVolume(7), 1);
assert.strictEqual(clampVolume(-3), 0);

// 布尔字段：开关默认开启的项只有显式 false 才关闭
assert.strictEqual(normalize({ combo: false }).combo, false);
assert.strictEqual(normalize({}).combo, true);
assert.strictEqual(normalize({ smartMute: false }).smartMute, false);
assert.strictEqual(normalize({ muted: "true" }).muted, true);
assert.strictEqual(normalize({ login: 1 }).login, true);
assert.strictEqual(normalize({ login: "no" }).login, false);
assert.ok(asBool("1") && !asBool("0") && !asBool(undefined));

// 损坏的输入
for (const bad of [null, undefined, "x", 5, []]) {
  assert.deepStrictEqual(normalize(bad), normalize({}));
}
assert.strictEqual(normalize({ packID: 12 }).packID, "");
assert.strictEqual(normalize({ packID: "real-cream" }).packID, "real-cream");

console.log("state ok");
