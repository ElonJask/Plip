// 持久化状态的默认值与规范化。读取磁盘内容后必须经过 normalize，避免损坏或旧版本数据带入非法值。
const DEFAULTS = {
  packID: "",
  volume: 0.8,
  muted: false,
  combo: true,
  smartMute: true,
  login: false,
  loginMessage: ""
};

function asBool(value) {
  return value === true || value === "true" || value === 1 || value === "1";
}

function clampVolume(value) {
  if (typeof value !== "number" || !Number.isFinite(value)) return DEFAULTS.volume;
  return Math.max(0, Math.min(1, value));
}

function normalize(raw) {
  const input = raw && typeof raw === "object" ? raw : {};
  return {
    packID: typeof input.packID === "string" ? input.packID : DEFAULTS.packID,
    volume: clampVolume(input.volume),
    muted: asBool(input.muted),
    combo: input.combo !== false,
    smartMute: input.smartMute !== false,
    login: asBool(input.login),
    loginMessage: typeof input.loginMessage === "string" ? input.loginMessage : ""
  };
}

module.exports = { DEFAULTS, normalize, asBool, clampVolume };
