import Foundation

/// 把用户选择的音频或文件夹写成音效包。文件名决定键位，不要求手写 manifest。
public enum PackImporter {
    public static let audioExtensions: Set<String> = ["wav", "aiff", "aif", "caf", "mp3", "m4a"]

    public static func importSelection(_ urls: [URL], into root: URL) throws -> String? {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let audios = urls.filter { audioExtensions.contains($0.pathExtension.lowercased()) }
        let folders = urls.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        if audios.isEmpty, let folder = folders.first {
            let id = try importFolder(folder, into: root)
            return id.isEmpty ? nil : id
        }
        guard !audios.isEmpty else { return nil }
        let title = audios.count == 1
            ? audios[0].deletingPathExtension().lastPathComponent
            : "自定义音效"
        return try writePack(name: title, files: audios, into: root)
    }

    public static func keyName(for filename: String) -> String {
        let stem = (filename as NSString).deletingPathExtension.lowercased()
        if stem.contains("space") || stem.contains("空格") { return "space" }
        if stem.contains("enter") || stem.contains("return") || stem.contains("回车") { return "return" }
        if stem.contains("backspace") || stem.contains("back") || stem.contains("退格") { return "backspace" }
        return "default"
    }

    private static func importFolder(_ folder: URL, into root: URL) throws -> String {
        let manifest = folder.appendingPathComponent("manifest.json")
        if FileManager.default.fileExists(atPath: manifest.path) {
            let id = uniqueID(folder.lastPathComponent, in: root)
            try FileManager.default.copyItem(at: folder, to: root.appendingPathComponent(id))
            return id
        }
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        let audios = files.filter { audioExtensions.contains($0.pathExtension.lowercased()) }
        guard !audios.isEmpty else { return "" }
        return try writePack(name: folder.lastPathComponent, files: audios, into: root)
    }

    private static func writePack(name: String, files: [URL], into root: URL) throws -> String {
        let id = uniqueID(name, in: root)
        let dest = root.appendingPathComponent(id)
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        var groups: [String: [String]] = [:]
        for file in files {
            let stored = uniqueFileName(file.lastPathComponent, in: dest)
            try FileManager.default.copyItem(at: file, to: dest.appendingPathComponent(stored))
            groups[keyName(for: stored), default: []].append(stored)
        }
        if groups["default"] == nil, let first = groups.values.first {
            groups["default"] = first
        }
        var mappings: [String: Any] = [:]
        for (key, names) in groups {
            mappings[key] = ["files": names, "volume": 0.85]
        }
        let manifest: [String: Any] = [
            "name": name,
            "version": "1.0.0",
            "author": "Plip",
            "key_mappings": mappings
        ]
        let data = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: dest.appendingPathComponent("manifest.json"))
        return id
    }

    private static func uniqueID(_ name: String, in root: URL) -> String {
        let base = name
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
        let stem = base.isEmpty ? "pack" : base
        var id = stem
        var n = 2
        while FileManager.default.fileExists(atPath: root.appendingPathComponent(id).path) {
            id = "\(stem)-\(n)"
            n += 1
        }
        return id
    }

    private static func uniqueFileName(_ name: String, in dir: URL) -> String {
        if !FileManager.default.fileExists(atPath: dir.appendingPathComponent(name).path) { return name }
        let stem = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var n = 2
        while true {
            let candidate = ext.isEmpty ? "\(stem)-\(n)" : "\(stem)-\(n).\(ext)"
            if !FileManager.default.fileExists(atPath: dir.appendingPathComponent(candidate).path) { return candidate }
            n += 1
        }
    }
}
