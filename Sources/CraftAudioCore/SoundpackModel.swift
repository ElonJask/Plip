import Foundation

/// manifest.json 数据结构（见 README 的 Schema 说明）
public struct SoundpackManifest: Codable {
    public struct Rules: Codable {
        /// 每次敲击的随机音调抖动范围（半音）
        public var pitchJitter: Double
        /// 是否启用连击升调
        public var comboEnabled: Bool
        /// 每次连击提升的音调（半音）
        public var comboPitchStep: Double
        /// 超过该毫秒间隔未敲击则连击清零
        public var comboTimeoutMs: Int
        /// 连击升调的最大步数
        public var comboMaxSteps: Int

        enum CodingKeys: String, CodingKey {
            case pitchJitter = "pitch_jitter"
            case comboEnabled = "combo_enabled"
            case comboPitchStep = "combo_pitch_step"
            case comboTimeoutMs = "combo_timeout_ms"
            case comboMaxSteps = "combo_max_steps"
        }

        public init() {
            pitchJitter = 0.04
            comboEnabled = false
            comboPitchStep = 0.05
            comboTimeoutMs = 600
            comboMaxSteps = 24
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let def = Rules()
            pitchJitter = try c.decodeIfPresent(Double.self, forKey: .pitchJitter) ?? def.pitchJitter
            comboEnabled = try c.decodeIfPresent(Bool.self, forKey: .comboEnabled) ?? def.comboEnabled
            comboPitchStep = try c.decodeIfPresent(Double.self, forKey: .comboPitchStep) ?? def.comboPitchStep
            comboTimeoutMs = try c.decodeIfPresent(Int.self, forKey: .comboTimeoutMs) ?? def.comboTimeoutMs
            comboMaxSteps = try c.decodeIfPresent(Int.self, forKey: .comboMaxSteps) ?? def.comboMaxSteps
        }
    }

    public struct KeyMapping: Codable {
        public var files: [String]
        public var volume: Double

        init(files: [String], volume: Double) {
            self.files = files
            self.volume = volume
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            files = try c.decode([String].self, forKey: .files)
            volume = try c.decodeIfPresent(Double.self, forKey: .volume) ?? 0.8
        }
    }

    public var name: String
    public var version: String
    public var author: String
    public var rules: Rules
    public var keyMappings: [String: KeyMapping]

    enum CodingKeys: String, CodingKey {
        case name, version, author, rules
        case keyMappings = "key_mappings"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        version = try c.decodeIfPresent(String.self, forKey: .version) ?? "1.0.0"
        author = try c.decodeIfPresent(String.self, forKey: .author) ?? ""
        rules = try c.decodeIfPresent(Rules.self, forKey: .rules) ?? Rules()
        keyMappings = try c.decode([String: KeyMapping].self, forKey: .keyMappings)
    }
}

/// 一个已加载的音效包
public struct Soundpack {
    public let id: String // 文件夹名
    public let url: URL
    public let manifest: SoundpackManifest

    public init(id: String, url: URL, manifest: SoundpackManifest) {
        self.id = id
        self.url = url
        self.manifest = manifest
    }

    /// 键位名 -> 音频文件 URL 列表（键位名见 KeyMap，如 "space"/"return"/"backspace"/"default"）
    public func mapping(for keyName: String) -> (files: [URL], volume: Double)? {
        guard let m = manifest.keyMappings[keyName], !m.files.isEmpty else { return nil }
        let urls = m.files.map { url.appendingPathComponent($0) }
        return (urls, m.volume)
    }

    /// 包内所有去重后的音频文件
    public var allFiles: [URL] {
        var seen = Set<String>()
        var out: [URL] = []
        for m in manifest.keyMappings.values {
            for f in m.files where seen.insert(f).inserted {
                out.append(url.appendingPathComponent(f))
            }
        }
        return out
    }
}

