const { app, BrowserWindow, Tray, nativeImage, nativeTheme, Menu, screen, ipcMain, shell, dialog, systemPreferences } = require("electron");
const { uIOhook, UiohookKey } = require("uiohook-napi");
const { execFile } = require("child_process");
const fs = require("fs");
const path = require("path");
const { isPackSound } = require("./pack-path");
const { importSelection } = require("./pack-import");
const { decide } = require("./mute-policy");
const { DEFAULTS, normalize, asBool } = require("./state");

app.commandLine.appendSwitch("disable-renderer-backgrounding");
app.commandLine.appendSwitch("disable-backgrounding-occluded-windows");
app.commandLine.appendSwitch("disable-background-timer-throttling");
app.commandLine.appendSwitch("disable-background-media-suspend");
app.commandLine.appendSwitch("disable-features", "CalculateNativeWinOcclusion");
app.commandLine.appendSwitch("autoplay-policy", "no-user-gesture-required");

const APP_ID = "app.plip.mac";
if (process.platform === "win32") app.setAppUserModelId(APP_ID);

// 只允许一个实例，重复启动时直接打开已运行实例的面板。
const gotLock = app.requestSingleInstanceLock();
if (!gotLock) {
  app.quit();
}

const stateFile = () => path.join(app.getPath("userData"), "state.json");
const userPacksDir = () => path.join(app.getPath("userData"), "Soundpacks");
const MAX_PENDING_PLAYS = 48;
const PANEL_WIDTH = 300;

function panelBackground() {
  return nativeTheme.shouldUseDarkColors ? "#1c1c1e" : "#f4f4f6";
}

let tray;
let panel;
let player;
let packs = [];
const manifests = new Map();
let comboCount = 0;
let lastKeyAt = 0;
let playerReady = false;
let quitting = false;
let holdingPanel = false;
let frontBundleID = "";
let suppressReason = "";
const pendingPlays = [];
let state = { ...DEFAULTS };

function loadState() {
  let raw = null;
  try {
    raw = JSON.parse(fs.readFileSync(stateFile(), "utf8"));
  } catch {}
  state = normalize(raw);
}

function saveState() {
  fs.mkdirSync(path.dirname(stateFile()), { recursive: true });
  fs.writeFileSync(stateFile(), JSON.stringify({
    packID: state.packID,
    volume: state.volume,
    muted: state.muted,
    combo: state.combo,
    smartMute: state.smartMute,
    login: state.login,
    loginMessage: state.loginMessage
  }));
}

function bundledPacks() {
  const candidates = [
    path.join(process.resourcesPath, "Soundpacks"),
    path.join(__dirname, "..", "Soundpacks")
  ];
  return candidates.find((dir) => fs.existsSync(dir)) || candidates[0];
}

function trayImage() {
  const name = process.platform === "darwin" ? "trayTemplate.png" : "tray.png";
  const candidates = [
    path.join(process.resourcesPath || "", "tray", name),
    path.join(__dirname, "build", name)
  ];
  const file = candidates.find((candidate) => fs.existsSync(candidate));
  const image = file ? nativeImage.createFromPath(file) : nativeImage.createEmpty();
  if (process.platform === "darwin") image.setTemplateImage(true);
  return image;
}

function trayTooltip() {
  if (state.muted) return "Plip · 已静音";
  if (suppressReason) return "Plip · " + suppressReason;
  return "Plip";
}

function trayMenu() {
  return Menu.buildFromTemplate([
    { label: "打开 Plip", click: () => showPanel() },
    {
      label: state.muted ? "取消静音" : "静音",
      click: () => {
        state.muted = !state.muted;
        saveState();
        publish();
      }
    },
    { type: "separator" },
    { label: "退出 Plip", click: () => app.quit() }
  ]);
}

function uiFile(name) {
  const packed = path.join(__dirname, "ui", name);
  if (fs.existsSync(packed)) return packed;
  return path.join(__dirname, "..", "ui", name);
}

function readPacks() {
  const found = [];
  for (const root of [bundledPacks(), userPacksDir()]) {
    if (!fs.existsSync(root)) continue;
    for (const name of fs.readdirSync(root)) {
      const dir = path.join(root, name);
      const manifestPath = path.join(dir, "manifest.json");
      if (!fs.existsSync(manifestPath)) continue;
      try {
        const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
        found.push({ id: name, name: manifest.name || name, dir });
      } catch {}
    }
  }
  const byID = new Map();
  for (const pack of found) byID.set(pack.id, pack);
  packs = [...byID.values()];
  manifests.clear();
}

function snapshot() {
  const current = packs.find((pack) => pack.id === state.packID) || packs[0];
  const mute = decide({
    smartMuteEnabled: state.smartMute,
    frontBundleID
  });
  suppressReason = mute.reason;
  return {
    version: app.getVersion(),
    packName: current ? current.name : "无音效",
    packID: current ? current.id : "",
    packs: packs.map((pack) => ({ id: pack.id, name: pack.name })),
    volume: state.volume,
    muted: state.muted,
    combo: state.combo,
    smartMute: state.smartMute,
    accessibility: process.platform === "darwin" ? systemPreferences.isTrustedAccessibilityClient(false) : true,
    suppressReason: mute.suppressed ? mute.reason : "",
    login: state.login,
    loginMessage: state.loginMessage || ""
  };
}

let lastPublished = "";

function publish(force) {
  if (!panel || panel.isDestroyed() || panel.webContents.isDestroyed()) return;
  const next = snapshot();
  const encoded = JSON.stringify(next);
  if (!force && encoded === lastPublished) return;
  try {
    panel.webContents.send("state", next);
    lastPublished = encoded;
  } catch {
    // 渲染进程尚未就绪或已被回收；下次发布会重试。
    lastPublished = "";
  }
  if (tray && !tray.isDestroyed()) tray.setToolTip(trayTooltip());
}

function openAccessibility() {
  if (process.platform !== "darwin") return;
  systemPreferences.isTrustedAccessibilityClient(true);
  shell.openExternal("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility");
}

function currentPack() {
  return packs.find((pack) => pack.id === state.packID) || packs[0];
}

function manifestFor(pack) {
  if (!manifests.has(pack.dir)) {
    manifests.set(pack.dir, JSON.parse(fs.readFileSync(path.join(pack.dir, "manifest.json"), "utf8")));
  }
  return manifests.get(pack.dir);
}

function packFiles(pack) {
  if (!pack) return [];
  const manifest = manifestFor(pack);
  const files = new Set();
  for (const mapping of Object.values(manifest.key_mappings || {})) {
    for (const file of mapping.files || []) files.add(path.join(pack.dir, file));
  }
  return [...files];
}

function allowedSound(file) {
  return isPackSound(file, [bundledPacks(), userPacksDir()]);
}

function sendToPlayer(channel, payload) {
  if (!player || player.isDestroyed() || !playerReady) return false;
  player.webContents.send(channel, payload);
  return true;
}

function allPackFiles() {
  const files = new Set();
  for (const pack of packs) {
    for (const file of packFiles(pack)) files.add(file);
  }
  return [...files];
}

function loadPacksIntoPlayer(files) {
  if (!files.length) return;
  sendToPlayer("loadPack", { files });
}

function loadCurrentPackIntoPlayer() {
  loadPacksIntoPlayer(packFiles(currentPack()));
}

function loadAllPacksIntoPlayer() {
  loadPacksIntoPlayer(allPackFiles());
}

function sendPlay(strike) {
  if (sendToPlayer("play", strike)) return;
  pendingPlays.push(strike);
  if (pendingPlays.length > MAX_PENDING_PLAYS) pendingPlays.shift();
}

function flushPendingPlays() {
  const queued = pendingPlays.splice(0, pendingPlays.length);
  for (const strike of queued) sendPlay(strike);
}

function createPanel() {
  panel = new BrowserWindow({
    width: PANEL_WIDTH,
    height: 420,
    show: false,
    frame: false,
    transparent: false,
    backgroundColor: panelBackground(),
    resizable: false,
    skipTaskbar: true,
    alwaysOnTop: true,
    webPreferences: {
      preload: path.join(__dirname, "preload.js"),
      contextIsolation: true
    }
  });
  panel.loadFile(uiFile("panel.html"));
  panel.webContents.on("did-finish-load", () => {
    publish(true);
  });
  nativeTheme.on("updated", () => {
    if (panel && !panel.isDestroyed()) panel.setBackgroundColor(panelBackground());
  });
  panel.webContents.on("render-process-gone", () => {
    if (quitting || !panel || panel.isDestroyed()) return;
    lastPublished = "";
    panel.destroy();
    panel = null;
  });
  panel.on("blur", () => {
    if (holdingPanel) return;
    if (panel && !panel.isDestroyed()) panel.hide();
  });
}

async function withPanelHeld(work) {
  holdingPanel = true;
  if (panel && !panel.isDestroyed()) panel.setAlwaysOnTop(false);
  try {
    return await work();
  } finally {
    holdingPanel = false;
    if (panel && !panel.isDestroyed()) {
      panel.setAlwaysOnTop(true, "floating");
      panel.show();
      panel.focus();
    }
  }
}

function applyLogin(enabled) {
  state.login = Boolean(enabled);
  try {
    app.setLoginItemSettings({ openAtLogin: state.login, openAsHidden: true });
  } catch {}
  const settings = app.getLoginItemSettings();
  if (state.login && !settings.openAtLogin) {
    state.loginMessage = "系统拒绝登记开机自启。当前安装包是临时签名，macOS 不会在登录时启动它。可到「登录项」里手动添加。";
  } else if (!state.login && settings.openAtLogin) {
    state.loginMessage = "系统仍把 Plip 留在登录项里。请到「登录项」里关掉。";
  } else {
    state.loginMessage = "";
  }
}

let refreshingFront = false;

// 前台应用只用于「通话时静音」。功能关闭时不启动 osascript，也避免触发自动化授权弹窗。
function refreshFrontApp(done) {
  if (process.platform !== "darwin" || !state.smartMute) {
    frontBundleID = "";
    if (done) done();
    return;
  }
  if (refreshingFront) {
    if (done) done();
    return;
  }
  refreshingFront = true;
  execFile("osascript", ["-e", 'tell application "System Events" to get bundle identifier of first application process whose frontmost is true'], { timeout: 800 }, (err, stdout) => {
    refreshingFront = false;
    if (!err) frontBundleID = String(stdout || "").trim();
    if (done) done();
  });
}

function createPlayer() {
  if (player && !player.isDestroyed()) player.destroy();
  playerReady = false;
  player = new BrowserWindow({
    show: false,
    width: 1,
    height: 1,
    x: -20000,
    y: -20000,
    skipTaskbar: true,
    focusable: false,
    frame: false,
    transparent: true,
    hasShadow: false,
    hiddenInMissionControl: true,
    webPreferences: {
      preload: path.join(__dirname, "player-preload.js"),
      contextIsolation: true,
      backgroundThrottling: false
    }
  });
  player.setMenuBarVisibility(false);
  player.setIgnoreMouseEvents(true);
  player.webContents.setBackgroundThrottling(false);
  player.once("ready-to-show", () => {
    if (!player || player.isDestroyed()) return;
    player.setOpacity(0);
    player.showInactive();
    if (process.platform === "darwin") app.dock.hide();
  });
  player.loadFile(uiFile("player.html"));
  player.webContents.on("render-process-gone", () => {
    playerReady = false;
    if (quitting) return;
    setTimeout(createPlayer, 250);
  });
}

function placePanel() {
  const bounds = tray.getBounds();
  const [width, height] = panel.getSize();
  const display = screen.getDisplayNearestPoint({ x: bounds.x, y: bounds.y }).workArea;
  let x = Math.round(bounds.x + bounds.width / 2 - width / 2);
  // 任务栏在屏幕下方时（Windows），面板出现在图标上方；菜单栏在上方时出现在下方。
  const trayInLowerHalf = bounds.y > display.y + display.height / 2;
  let y = trayInLowerHalf
    ? Math.round(bounds.y - height - 6)
    : Math.round(bounds.y + bounds.height + 6);
  x = Math.min(Math.max(x, display.x + 8), display.x + display.width - width - 8);
  y = Math.min(Math.max(y, display.y + 8), display.y + display.height - height - 8);
  panel.setPosition(x, y);
}

function showPanel() {
  if (!panel || panel.isDestroyed()) createPanel();
  placePanel();
  publish(true);
  holdingPanel = true;
  panel.show();
  panel.focus();
  setTimeout(() => { holdingPanel = false; }, 250);
}

function togglePanel() {
  if (panel && !panel.isDestroyed() && panel.isVisible()) {
    panel.hide();
    return;
  }
  showPanel();
}

const keyNames = {
  [UiohookKey.Space]: "space",
  [UiohookKey.Enter]: "return",
  [UiohookKey.NumpadEnter]: "return",
  [UiohookKey.Backspace]: "backspace",
  [UiohookKey.Delete]: "forward_delete",
  [UiohookKey.Shift]: "shift",
  [UiohookKey.ShiftRight]: "shift",
  [UiohookKey.CapsLock]: "capslock",
  [UiohookKey.Tab]: "tab",
  [UiohookKey.Escape]: "escape"
};

function listen() {
  uIOhook.on("keydown", (event) => {
    const alt = Boolean(event.altKey);
    const shift = Boolean(event.shiftKey);
    const ctrl = Boolean(event.ctrlKey);
    const meta = Boolean(event.metaKey);
    if (event.keycode === UiohookKey.M && alt && shift && !ctrl && !meta) {
      state.muted = !state.muted;
      saveState();
      publish();
      return;
    }
    play(keyNames[event.keycode] || "default");
  });
  startHook();
}

// 未授权辅助功能时 start 会失败；每 3 秒重试，授权后自动开始监听。
let hookTimer = null;
function startHook() {
  clearTimeout(hookTimer);
  Promise.resolve()
    .then(() => uIOhook.start())
    .then(() => publish(true))
    .catch(() => {
      if (quitting) return;
      hookTimer = setTimeout(startHook, 3000);
    });
}

function play(key) {
  try {
    strike(key);
  } catch {
    // 音效包配置损坏时不影响监听，下次按键重试。
  }
}

function strike(key) {
  if (state.muted) return;
  const mute = decide({
    smartMuteEnabled: state.smartMute,
    frontBundleID
  });
  if (mute.suppressed) return;
  const current = currentPack();
  if (!current) return;
  const manifest = manifestFor(current);
  const rules = manifest.rules || {};
  const now = Date.now();
  if (state.combo && rules.combo_enabled && now - lastKeyAt < (rules.combo_timeout_ms || 600)) {
    comboCount = Math.min(comboCount + 1, rules.combo_max_steps || 24);
  } else {
    comboCount = 0;
  }
  lastKeyAt = now;
  const mappings = manifest.key_mappings || {};
  const mapping = mappings[key] || mappings.default;
  if (!mapping || !mapping.files || mapping.files.length === 0) return;
  const file = mapping.files[Math.floor(Math.random() * mapping.files.length)];
  const jitter = (Math.random() * 2 - 1) * (rules.pitch_jitter || 0);
  const semitones = jitter + comboCount * (rules.combo_pitch_step || 0);
  sendPlay({
    file: path.join(current.dir, file),
    volume: (typeof mapping.volume === "number" ? mapping.volume : 0.8) * state.volume,
    rate: Math.pow(2, semitones / 12)
  });
}

if (gotLock) app.whenReady().then(() => {
  loadState();
  applyLogin(asBool(state.login));
  saveState();
  fs.mkdirSync(userPacksDir(), { recursive: true });
  readPacks();
  tray = new Tray(trayImage());
  tray.setToolTip(trayTooltip());
  if (process.platform === "darwin") app.dock.hide();
  tray.on("click", togglePanel);
  tray.on("right-click", () => tray.popUpContextMenu(trayMenu()));
  createPanel();
  createPlayer();

  listen();
  refreshFrontApp();
  setInterval(() => refreshFrontApp(() => publish()), 2000);

  // 首次运行缺少辅助功能权限时，直接打开面板引导授权。
  if (process.platform === "darwin" && !systemPreferences.isTrustedAccessibilityClient(false)) {
    setTimeout(showPanel, 600);
  }
});

app.on("second-instance", () => {
  if (app.isReady()) showPanel();
});

ipcMain.handle("ready", () => snapshot());
ipcMain.on("playerReady", () => {
  playerReady = true;
  loadCurrentPackIntoPlayer();
  loadAllPacksIntoPlayer();
  flushPendingPlays();
});
ipcMain.handle("readSound", async (_event, file) => {
  if (!allowedSound(file)) return null;
  try {
    return await fs.promises.readFile(file);
  } catch {
    return null;
  }
});
ipcMain.on("resize", (_event, size) => {
  if (panel) panel.setContentSize(PANEL_WIDTH, Math.max(160, Math.min(size.height, 640)));
});
ipcMain.on("setVolume", (_event, value) => {
  state.volume = Math.max(0, Math.min(1, Number(value) || 0));
  saveState();
  publish();
});
ipcMain.on("setMuted", (_event, value) => {
  state.muted = asBool(value);
  saveState();
  publish();
});
ipcMain.on("setCombo", (_event, value) => {
  state.combo = asBool(value);
  saveState();
  publish();
});
ipcMain.on("setSmartMute", (_event, value) => {
  state.smartMute = asBool(value);
  saveState();
  refreshFrontApp(() => publish());
});
ipcMain.on("setLogin", (_event, value) => {
  applyLogin(asBool(value));
  saveState();
  publish();
});
ipcMain.on("selectPack", (_event, id) => {
  if (!packs.some((pack) => pack.id === id)) return;
  state.packID = id;
  saveState();
  publish();
  loadCurrentPackIntoPlayer();
});
ipcMain.on("openAccessibility", openAccessibility);
ipcMain.on("openLogin", () => {
  if (process.platform !== "darwin") return;
  shell.openExternal("x-apple.systempreferences:com.apple.LoginItems-Settings.extension");
});
ipcMain.on("hide", () => {
  if (panel && !panel.isDestroyed()) panel.hide();
});
ipcMain.on("importPack", async () => {
  const result = await withPanelHeld(() => dialog.showOpenDialog({
    title: "添加音效包",
    properties: ["openFile", "openDirectory", "multiSelections"],
    filters: [{ name: "音频或音效包", extensions: ["wav", "aiff", "aif", "caf", "mp3", "m4a", "json"] }]
  }));
  if (!result || result.canceled || !result.filePaths.length) return;
  let id = "";
  try {
    id = importSelection(result.filePaths, userPacksDir());
  } catch (error) {
    dialog.showErrorBox("无法添加音效包", String((error && error.message) || error));
    return;
  }
  if (!id) {
    dialog.showErrorBox("没有找到可用的音频", "请选择 wav、aiff、caf、mp3、m4a 音频文件，或包含 manifest.json 的音效包文件夹。");
    return;
  }
  readPacks();
  state.packID = id;
  saveState();
  loadCurrentPackIntoPlayer();
  loadAllPacksIntoPlayer();
  publish();
});
ipcMain.on("quit", () => app.quit());

app.on("before-quit", () => {
  quitting = true;
  clearTimeout(hookTimer);
  try { uIOhook.stop(); } catch {}
});
app.on("window-all-closed", (event) => event.preventDefault());
