const CALL_BUNDLE_IDS = new Set([
  "us.zoom.xos",
  "com.apple.FaceTime",
  "com.tencent.meeting",
  "com.tencent.wemeet",
  "com.microsoft.teams",
  "com.microsoft.teams2",
  "com.cisco.webexmeetingsapp",
  "com.alibaba.DingTalkMac",
  "com.bytedance.macos.feishu",
  "com.electron.lark"
]);

function decide({ smartMuteEnabled, frontBundleID }) {
  if (!smartMuteEnabled) return { suppressed: false, reason: "" };
  const front = frontBundleID || "";
  if (front && CALL_BUNDLE_IDS.has(front)) {
    return { suppressed: true, reason: "通话应用正在前台" };
  }
  return { suppressed: false, reason: "" };
}

module.exports = { decide, CALL_BUNDLE_IDS };
