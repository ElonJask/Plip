const { app, BrowserWindow, Tray, nativeImage, ipcMain, shell, dialog, systemPreferences } = require("electron");
const { uIOhook, UiohookKey } = require("uiohook-napi");
const fs = require("fs");
const path = require("path");


const stateFile = () => path.join(app.getPath("userData"), "state.json");
const userPacksDir = () => path.join(app.getPath("userData"), "Soundpacks");

let tray;
let panel;
let player;
let packs = [];
const manifests = new Map();
let comboCount = 0;
let lastKeyAt = 0;
let state = {
  packID: "",
  volume: 0.8,
  muted: false,
  combo: true,
  smartMute: true,
  login: false,
  apps: []
};

function loadState() {
  try {
    state = { ...state, ...JSON.parse(fs.readFileSync(stateFile(), "utf8")) };
  } catch {}
}

function saveState() {
  fs.mkdirSync(path.dirname(stateFile()), { recursive: true });
  fs.writeFileSync(stateFile(), JSON.stringify(state));
}

function bundledPacks() {
  const candidates = [
    path.join(process.resourcesPath, "Soundpacks"),
    path.join(__dirname, "..", "Soundpacks")
  ];
  return candidates.find((dir) => fs.existsSync(dir)) || candidates[0];
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
}

function snapshot() {
  const current = packs.find((pack) => pack.id === state.packID) || packs[0];
  return {
    packName: current ? current.name : "无音效",
    packID: current ? current.id : "",
    packs: packs.map((pack) => ({ id: pack.id, name: pack.name })),
    volume: state.volume,
    muted: state.muted,
    combo: state.combo,
    smartMute: state.smartMute,
    accessibility: process.platform === "darwin" ? systemPreferences.isTrustedAccessibilityClient(false) : true,
    suppressReason: "",
    login: app.getLoginItemSettings().openAtLogin,
    loginMessage: "",
    apps: state.apps
  };
}

function publish() {
  if (panel && !panel.isDestroyed()) panel.webContents.send("state", snapshot());
}

function openAccessibility() {
  if (process.platform !== "darwin") return;
  systemPreferences.isTrustedAccessibilityClient(true);
  shell.openExternal("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility");
}

function createPanel() {
  panel = new BrowserWindow({
    width: 320,
    height: 360,
    show: false,
    frame: false,
    transparent: false,
    backgroundColor: "#ffffff",
    resizable: false,
    skipTaskbar: true,
    alwaysOnTop: true,
    webPreferences: {
      preload: path.join(__dirname, "preload.js"),
      contextIsolation: true
    }
  });
  panel.loadFile(path.join(__dirname, "ui", "panel.html"));
  panel.webContents.on("did-finish-load", () => {
    panel.webContents.executeJavaScript("plipRender(" + JSON.stringify(snapshot()) + ")");
  });
  panel.on("blur", () => { if (panel && !panel.isDestroyed()) panel.hide(); });
}

function createPlayer() {
  player = new BrowserWindow({
    show: false,
    webPreferences: { preload: path.join(__dirname, "preload.js"), contextIsolation: true }
  });
  player.loadFile(path.join(__dirname, "ui", "player.html"));
}

function togglePanel() {
  if (!panel) createPanel();
  if (panel.isVisible()) {
    panel.hide();
    return;
  }
  const bounds = tray.getBounds();
  const size = panel.getSize();
  const display = require("electron").screen.getDisplayNearestPoint({ x: bounds.x, y: bounds.y }).workArea;
  let x = Math.round(bounds.x + bounds.width / 2 - size[0] / 2);
  let y = Math.round(bounds.y + bounds.height + 6);
  x = Math.min(Math.max(x, display.x), display.x + display.width - size[0]);
  y = Math.min(Math.max(y, display.y), display.y + display.height - size[1]);
  panel.setPosition(x, y);
  publish();
  panel.show();
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
  uIOhook.start();
}

function manifestFor(pack) {
  if (!manifests.has(pack.dir)) {
    manifests.set(pack.dir, JSON.parse(fs.readFileSync(path.join(pack.dir, "manifest.json"), "utf8")));
  }
  return manifests.get(pack.dir);
}

function play(key) {
  if (state.muted) return;
  const current = packs.find((pack) => pack.id === state.packID) || packs[0];
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
  if (player && !player.isDestroyed()) {
    player.webContents.send("play", {
      file: path.join(current.dir, file),
      volume: (mapping.volume || 0.8) * state.volume,
      rate: Math.pow(2, semitones / 12)
    });
  }
}

app.whenReady().then(() => {
  loadState();
  fs.mkdirSync(userPacksDir(), { recursive: true });
  readPacks();
  const iconPath = path.join(process.resourcesPath, "trayTemplate.png");
  const icon = nativeImage.createFromPath(iconPath).resize({ width: 22, height: 22 });
  icon.setTemplateImage(true);
  tray = new Tray(icon.isEmpty() ? nativeImage.createEmpty() : icon);
  tray.setTitle("Plip");
  tray.setToolTip("Plip");
  if (process.platform === "darwin") app.dock.hide();
  tray.on("click", togglePanel);
  tray.on("right-click", togglePanel);
  createPanel();
  createPlayer();

  listen();
  setInterval(publish, 2000);
});

ipcMain.handle("ready", () => snapshot());
ipcMain.on("resize", (_event, size) => {
  if (panel) panel.setContentSize(Math.max(268, size.width), Math.max(160, size.height));
});
ipcMain.on("setVolume", (_event, value) => { state.volume = value; saveState(); });
ipcMain.on("setMuted", (_event, value) => { state.muted = value; saveState(); publish(); });
ipcMain.on("setCombo", (_event, value) => { state.combo = value; saveState(); });
ipcMain.on("setSmartMute", (_event, value) => { state.smartMute = value; saveState(); });
ipcMain.on("setLogin", (_event, value) => {
  app.setLoginItemSettings({ openAtLogin: value });
  publish();
});
ipcMain.on("selectPack", (_event, id) => { state.packID = id; saveState(); publish(); });
ipcMain.on("removeApp", (_event, id) => {
  state.apps = state.apps.filter((item) => item.id !== id);
  saveState();
  publish();
});
ipcMain.on("openAccessibility", openAccessibility);
ipcMain.on("openLogin", () => shell.openExternal("x-apple.systempreferences:com.apple.LoginItems-Settings.extension"));
ipcMain.on("pickApp", async () => {
  const result = await dialog.showOpenDialog({ properties: ["openFile"], filters: [{ name: "应用", extensions: ["app", "exe"] }] });
  if (result.canceled || !result.filePaths[0]) return;
  const file = result.filePaths[0];
  state.apps.push({ id: file, name: path.basename(file, path.extname(file)) });
  saveState();
  publish();
});
ipcMain.on("importPack", async () => {
  const result = await dialog.showOpenDialog({ properties: ["openFile", "openDirectory", "multiSelections"] });
  if (result.canceled) return;
  readPacks();
  publish();
});
ipcMain.on("quit", () => app.quit());

app.on("window-all-closed", (event) => event.preventDefault());
