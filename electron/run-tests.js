// 依次运行本目录下所有 *.test.js，任一失败即以非零状态退出。
const { spawnSync } = require("child_process");
const fs = require("fs");
const path = require("path");

const files = fs.readdirSync(__dirname).filter((name) => name.endsWith(".test.js")).sort();
let failed = 0;
for (const name of files) {
  const result = spawnSync(process.execPath, [path.join(__dirname, name)], { stdio: "inherit" });
  if (result.status !== 0) {
    failed += 1;
    console.error(`FAIL ${name}`);
  }
}
if (failed) process.exit(1);
console.log(`${files.length} test files passed`);
