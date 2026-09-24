import Foundation

public struct StrikeContext: Equatable {
    public var muted: Bool
    public var suppressed: Bool
    public var comboEnabled: Bool
    public var masterVolume: Double

    public init(muted: Bool, suppressed: Bool, comboEnabled: Bool, masterVolume: Double) {
        self.muted = muted
        self.suppressed = suppressed
        self.comboEnabled = comboEnabled
        self.masterVolume = masterVolume
    }
}

public struct Strike: Equatable {
    public var file: URL
    public var semitones: Double
    public var volume: Float
    public var comboCount: Int

    public init(file: URL, semitones: Double, volume: Float, comboCount: Int) {
        self.file = file
        self.semitones = semitones
        self.volume = volume
        self.comboCount = comboCount
    }
}

/// 连击、音调抖动和键位选文件。随机数由调用方传入，方便测试固定结果。
public struct StrikePlanner {
    public private(set) var comboCount = 0
    private var lastKeyTime: TimeInterval = 0
    private var hasTime = false

    public init() {}

    public mutating func reset() {
        comboCount = 0
        hasTime = false
    }

    public mutating func plan(keyName: String,
                               now: TimeInterval,
                               pack: Soundpack,
                               context: StrikeContext,
                               jitterUnit: Double,
                               fileChoice: Int) -> Strike? {
        guard !context.muted, !context.suppressed else { return nil }

        let rules = pack.manifest.rules
        let dtMs = hasTime ? (now - lastKeyTime) * 1000 : TimeInterval.greatestFiniteMagnitude
        lastKeyTime = now
        hasTime = true

        if context.comboEnabled && rules.comboEnabled {
            if dtMs < Double(rules.comboTimeoutMs) {
                comboCount = min(comboCount + 1, rules.comboMaxSteps)
            } else {
                comboCount = 0
            }
        } else {
            comboCount = 0
        }

        guard let mapping = pack.mapping(for: keyName) ?? pack.mapping(for: "default"),
              !mapping.files.isEmpty else { return nil }
        let index = mapping.files.indices.contains(fileChoice) ? fileChoice : 0
        let unit = min(max(jitterUnit, 0), 1)
        let jitter = (unit * 2 - 1) * rules.pitchJitter
        let semitones = jitter + Double(comboCount) * rules.comboPitchStep
        let volume = Float(mapping.volume) * Float(min(max(context.masterVolume, 0), 1))
        return Strike(file: mapping.files[index], semitones: semitones, volume: volume, comboCount: comboCount)
    }
}
