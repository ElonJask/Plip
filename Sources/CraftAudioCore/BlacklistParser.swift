import Foundation

public enum BlacklistParser {
    /// 逗号分隔的 Bundle ID。空白项丢掉，重复项只留第一次出现的。
    public static func parse(_ text: String) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for part in text.split(separator: ",", omittingEmptySubsequences: false) {
            let id = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty, seen.insert(id).inserted else { continue }
            out.append(id)
        }
        return out
    }
}

public extension Notification.Name {
    /// 设置面板关闭时提交黑名单。输入过程中不写，避免把没写完的 Bundle ID 存进去。
    static let craftAudioCommitBlacklist = Notification.Name("craftAudioCommitBlacklist")
}
