const assert = require("assert");
const { decide } = require("./mute-policy");

assert.deepStrictEqual(decide({ smartMuteEnabled: false, frontBundleID: "us.zoom.xos" }), { suppressed: false, reason: "" });
assert.ok(decide({ smartMuteEnabled: true, frontBundleID: "us.zoom.xos" }).suppressed);
assert.ok(!decide({ smartMuteEnabled: true, frontBundleID: "com.apple.Safari" }).suppressed);
console.log("mute-policy ok");
