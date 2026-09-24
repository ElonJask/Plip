import CraftAudioCore
import Foundation

/// 把菜单栏进程里的设置、音效包和音频引擎接到 StrikeSession。
final class LiveServices: AppServices {
    var selectedPackID: String {
        get { Settings.shared.selectedPackID }
        set { Settings.shared.selectedPackID = newValue }
    }
    var muted: Bool { Settings.shared.muted }
    var suppressed: Bool { SmartMute.shared.isSuppressed }
    var comboEnabled: Bool { Settings.shared.comboEnabled }
    var masterVolume: Double { Settings.shared.masterVolume }

    func pack(id: String) -> Soundpack? {
        let packs = SoundpackStore.shared.packs
        if id.isEmpty { return packs.first }
        return packs.first { $0.id == id }
    }

    func prepare(_ pack: Soundpack) {
        AudioEngine.shared.prepare(pack: pack)
    }

    func play(_ strike: Strike) {
        AudioEngine.shared.play(strike.file, semitones: Float(strike.semitones), volume: strike.volume)
    }
}
