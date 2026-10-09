const { contextBridge, ipcRenderer } = require("electron");

ipcRenderer.removeAllListeners("play");
ipcRenderer.removeAllListeners("loadPack");

contextBridge.exposeInMainWorld("plipPlayer", {
  ready: () => ipcRenderer.send("playerReady"),
  readSound: (file) => ipcRenderer.invoke("readSound", file),
  onPlay: (cb) => {
    ipcRenderer.on("play", (_event, strike) => cb(strike));
  },
  onLoadPack: (cb) => {
    ipcRenderer.on("loadPack", (_event, payload) => cb(payload));
  }
});
