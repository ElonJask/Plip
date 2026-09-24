import Foundation

public enum SoundpackMerger {
    /// 同 id 只保留后出现的那一份。调用方应先放内置包、再放用户包，使用户目录覆盖内置包。
    public static func merge(_ packs: [Soundpack]) -> [Soundpack] {
        var byID: [String: Soundpack] = [:]
        var order: [String] = []
        for pack in packs {
            if byID[pack.id] == nil { order.append(pack.id) }
            byID[pack.id] = pack
        }
        return order.compactMap { byID[$0] }
    }
}
