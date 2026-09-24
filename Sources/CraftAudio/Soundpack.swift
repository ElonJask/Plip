import Combine
import CraftAudioCore
import Foundation

/// 扫描并管理音效包目录
final class SoundpackStore: ObservableObject {
    static let shared = SoundpackStore()
    @Published private(set) var packs: [Soundpack] = []

    /// 用户自定义音效包目录（也可从菜单栏 UI 打开）
    var userPacksDir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Plip/Soundpacks")
    }

    func reload() {
        var found: [Soundpack] = []
        for dir in searchDirs() {
            guard let contents = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.isDirectoryKey]) else { continue }
            for packDir in contents {
                guard (try? packDir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
                let manifestURL = packDir.appendingPathComponent("manifest.json")
                guard let data = try? Data(contentsOf: manifestURL),
                      let manifest = try? JSONDecoder().decode(SoundpackManifest.self, from: data) else { continue }
                found.append(Soundpack(id: packDir.lastPathComponent, url: packDir, manifest: manifest))
            }
        }
        // 内置包在前、用户包在后；同名时用户包覆盖内置包，选择器里只出现一次。
        packs = SoundpackMerger.merge(found).sorted { $0.manifest.name < $1.manifest.name }
    }

    /// 选中的音频或文件夹写入用户目录，并重新扫描。
    @discardableResult
    func importSelection(_ urls: [URL]) throws -> String? {
        let id = try PackImporter.importSelection(urls, into: userPacksDir)
        reload()
        return id
    }

    private func searchDirs() -> [URL] {
        var dirs: [URL] = []
        if let res = Bundle.main.resourceURL {
            dirs.append(res.appendingPathComponent("Soundpacks"))
        }
        try? FileManager.default.createDirectory(at: userPacksDir, withIntermediateDirectories: true)
        dirs.append(userPacksDir)
        return dirs
    }
}
