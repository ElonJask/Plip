const { contextBridge, ipcRenderer } = require("electron");

function show(state) {
  window.__plipState = state;
  if (window.plipRender) window.plipRender(state);
}

contextBridge.exposeInMainWorld("plip", {
  ready: () => ipcRenderer.invoke("ready").then(show),
  resize: (size) => ipcRenderer.send("resize", size),
  setVolume: (value) => ipcRenderer.send("setVolume", value),
  setMuted: (value) => ipcRenderer.send("setMuted", value),
  setCombo: (value) => ipcRenderer.send("setCombo", value),
  setSmartMute: (value) => ipcRenderer.send("setSmartMute", value),
  setLogin: (value) => ipcRenderer.send("setLogin", value),
  selectPack: (value) => ipcRenderer.send("selectPack", value),
  removeApp: (value) => ipcRenderer.send("removeApp", value),
  openAccessibility: () => ipcRenderer.send("openAccessibility"),
  openLogin: () => ipcRenderer.send("openLogin"),
  pickApp: () => ipcRenderer.send("pickApp"),
  importPack: () => ipcRenderer.send("importPack"),
  quit: () => ipcRenderer.send("quit")
});

ipcRenderer.on("state", (_event, state) => show(state));

const voices = [];
ipcRenderer.on("play", (_event, strike) => {
  const audio = new Audio("file://" + encodeURI(strike.file));
  audio.volume = Math.max(0, Math.min(1, strike.volume || 0.8));
  audio.playbackRate = strike.rate || 1;
  voices.push(audio);
  if (voices.length > 8) voices.shift().pause();
  audio.play();
});
