const assert = require("assert");
const path = require("path");
const { isInsideRoot, isPackSound } = require("./pack-path");

const bundled = path.join("/tmp", "Plip", "Soundpacks");
const user = path.join("/tmp", "user", "Soundpacks");
const roots = [bundled, user];

assert.strictEqual(isPackSound(path.join(bundled, "real-mx-blue", "key_1.wav"), roots), true);
assert.strictEqual(isPackSound(path.join(user, "custom", "space.wav"), roots), true);
assert.strictEqual(isPackSound(path.join(bundled, "..", "main.js"), roots), false);
assert.strictEqual(isPackSound("/etc/passwd", roots), false);
assert.strictEqual(isPackSound("", roots), false);
assert.strictEqual(isPackSound(null, roots), false);
assert.strictEqual(isInsideRoot(bundled, bundled), false);
assert.strictEqual(isPackSound(path.join(bundled, "real-mx-blue", "key_1.wav"), []), false);

console.log("pack-path ok");
