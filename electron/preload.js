const { contextBridge, ipcRenderer } = require("electron");

// 预加载脚本运行在隔离环境，不能直接调用页面里的函数。
// 状态通过 onState 订阅交给页面，页面自己负责渲染。
contextBridge.exposeInMainWorld("plip", {
  ready: () => ipcRenderer.invoke("ready"),
  onState: (callback) => {
    ipcRenderer.on("state", (_event, state) => callback(state));
  },
  resize: (size) => ipcRenderer.send("resize", size),
  setVolume: (value) => ipcRenderer.send("setVolume", value),
  setMuted: (value) => ipcRenderer.send("setMuted", value),
  setCombo: (value) => ipcRenderer.send("setCombo", value),
  setSmartMute: (value) => ipcRenderer.send("setSmartMute", value),
  setLogin: (value) => ipcRenderer.send("setLogin", value),
  selectPack: (value) => ipcRenderer.send("selectPack", value),
  openAccessibility: () => ipcRenderer.send("openAccessibility"),
  openLogin: () => ipcRenderer.send("openLogin"),
  importPack: () => ipcRenderer.send("importPack"),
  hide: () => ipcRenderer.send("hide"),
  quit: () => ipcRenderer.send("quit")
});
