const fs = require("fs");
const path = require("path");

const AUDIO_EXTS = new Set([".wav", ".aiff", ".aif", ".caf", ".mp3", ".m4a"]);

function keyName(filename) {
  const stem = path.parse(filename).name.toLowerCase();
  if (stem.includes("backspace") || stem.includes("退格")) return "backspace";
  if (stem.includes("enter") || stem.includes("return") || stem.includes("回车")) return "return";
  if (stem.includes("space") || stem.includes("空格")) return "space";
  return "default";
}

function slug(name) {
  const base = String(name || "")
    .toLowerCase()
    .replace(/\s+/g, "-")
    .replace(/[^a-z0-9-]/g, "");
  return base || "pack";
}

function uniqueID(name, root) {
  const stem = slug(name);
  let id = stem;
  let n = 2;
  while (fs.existsSync(path.join(root, id))) {
    id = stem + "-" + n;
    n += 1;
  }
  return id;
}

function uniqueFileName(name, dir) {
  if (!fs.existsSync(path.join(dir, name))) return name;
  const parsed = path.parse(name);
  let n = 2;
  while (true) {
    const candidate = parsed.ext ? `${parsed.name}-${n}${parsed.ext}` : `${parsed.name}-${n}`;
    if (!fs.existsSync(path.join(dir, candidate))) return candidate;
    n += 1;
  }
}

function isDir(file) {
  try {
    return fs.statSync(file).isDirectory();
  } catch {
    return false;
  }
}

function writePack(name, files, root) {
  const id = uniqueID(name, root);
  const dest = path.join(root, id);
  fs.mkdirSync(dest, { recursive: true });
  const groups = {};
  for (const file of files) {
    const stored = uniqueFileName(path.basename(file), dest);
    fs.copyFileSync(file, path.join(dest, stored));
    const key = keyName(stored);
    (groups[key] ||= []).push(stored);
  }
  if (!groups.default) {
    const first = Object.values(groups)[0];
    if (first) groups.default = first;
  }
  const mappings = {};
  for (const [key, names] of Object.entries(groups)) {
    mappings[key] = { files: names, volume: 0.85 };
  }
  const manifest = {
    name,
    version: "1.0.0",
    author: "Plip",
    key_mappings: mappings
  };
  fs.writeFileSync(path.join(dest, "manifest.json"), JSON.stringify(manifest, null, 2));
  return id;
}

function importFolder(folder, root) {
  const manifest = path.join(folder, "manifest.json");
  if (fs.existsSync(manifest)) {
    const id = uniqueID(path.basename(folder), root);
    fs.cpSync(folder, path.join(root, id), { recursive: true });
    return id;
  }
  const audios = fs.readdirSync(folder)
    .map((name) => path.join(folder, name))
    .filter((file) => AUDIO_EXTS.has(path.extname(file).toLowerCase()) && fs.statSync(file).isFile());
  if (!audios.length) return "";
  return writePack(path.basename(folder), audios, root);
}

function importSelection(urls, root) {
  fs.mkdirSync(root, { recursive: true });
  const audios = urls.filter((file) => AUDIO_EXTS.has(path.extname(file).toLowerCase()) && fs.existsSync(file) && !isDir(file));
  const folders = urls.filter((file) => isDir(file));
  if (!audios.length && folders[0]) return importFolder(folders[0], root) || "";
  if (!audios.length) return "";
  const title = audios.length === 1 ? path.parse(audios[0]).name : "自定义音效";
  return writePack(title, audios, root);
}

module.exports = { importSelection, keyName, uniqueID, AUDIO_EXTS };
