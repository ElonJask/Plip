// 打包清单必须覆盖主进程与预加载脚本 require 的所有本地模块，且图标资源齐全。
// 漏掉文件时本地运行正常，打包后启动才会报错，所以在这里提前拦住。
const assert = require("assert");
const fs = require("fs");
const path = require("path");

const pkg = require("./package.json");
const listed = new Set(pkg.build.files.filter((item) => typeof item === "string"));

const entries = ["main.js", "preload.js", "player-preload.js"];
const seen = new Set();
function walk(file) {
  if (seen.has(file)) return;
  seen.add(file);
  const source = fs.readFileSync(path.join(__dirname, file), "utf8");
  for (const match of source.matchAll(/require\("(\.\/[^"]+)"\)/g)) {
    const dep = match[1].slice(2).endsWith(".js") ? match[1].slice(2) : match[1].slice(2) + ".js";
    walk(dep);
  }
}
entries.forEach(walk);
for (const file of seen) {
  assert.ok(listed.has(file), `build.files 缺少 ${file}`);
  assert.ok(fs.existsSync(path.join(__dirname, file)), `${file} 不存在`);
}

for (const file of [
  "build/icon.icns",
  "build/icon.ico",
  "build/icon.png",
  "build/tray.png",
  "build/trayTemplate.png",
  "build/trayTemplate@2x.png"
]) {
  assert.ok(fs.existsSync(path.join(__dirname, file)), `缺少图标资源 ${file}`);
}

const version = fs.readFileSync(path.join(__dirname, "..", "VERSION"), "utf8").trim();
assert.strictEqual(pkg.version, version, "package.json 与 VERSION 版本不一致");

console.log("package-files ok");
