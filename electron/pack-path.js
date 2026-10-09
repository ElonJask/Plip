const path = require("path");

function isInsideRoot(root, file) {
  if (!root || typeof file !== "string" || !file) return false;
  const resolvedRoot = path.resolve(root);
  const resolved = path.resolve(file);
  const rel = path.relative(resolvedRoot, resolved);
  return rel !== "" && !rel.startsWith("..") && !path.isAbsolute(rel);
}

function isPackSound(file, roots) {
  if (!Array.isArray(roots)) return false;
  return roots.some((root) => isInsideRoot(root, file));
}

module.exports = { isInsideRoot, isPackSound };
