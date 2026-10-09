const assert = require("assert");
const fs = require("fs");
const os = require("os");
const path = require("path");
const { importSelection, keyName } = require("./pack-import");

assert.strictEqual(keyName("space.wav"), "space");
assert.strictEqual(keyName("enter-1.wav"), "return");
assert.strictEqual(keyName("backspace.wav"), "backspace");
assert.strictEqual(keyName("key_1.wav"), "default");

const root = fs.mkdtempSync(path.join(os.tmpdir(), "plip-pack-"));
const src = path.join(root, "src");
fs.mkdirSync(src);
fs.writeFileSync(path.join(src, "key_1.wav"), "wav");
fs.writeFileSync(path.join(src, "space.wav"), "wav");
const id = importSelection([path.join(src, "key_1.wav"), path.join(src, "space.wav")], path.join(root, "out"));
assert.ok(id);
const dest = path.join(root, "out", id);
assert.ok(fs.existsSync(path.join(dest, "manifest.json")));
const manifest = JSON.parse(fs.readFileSync(path.join(dest, "manifest.json"), "utf8"));
assert.ok(manifest.key_mappings.default);
assert.ok(manifest.key_mappings.space);
fs.rmSync(root, { recursive: true, force: true });
console.log("pack-import ok");
