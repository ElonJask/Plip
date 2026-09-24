import CraftAudioCore
import Foundation

/// 菜单栏进程里的发声入口。规则在 StrikeSession，依赖由 LiveServices 提供。
final class SoundEngine {
    static let shared = SoundEngine(services: LiveServices())

    private let session: StrikeSession

    init(services: AppServices) {
        session = StrikeSession(services: services, now: { CFAbsoluteTimeGetCurrent() })
    }

    func configure() { session.configure() }
    func reprepareCurrentPack() { session.reprepareCurrentPack() }
    func selectPack(id: String) { session.selectPack(id: id) }
    func keyDown(keyCode: UInt16) { session.keyDown(keyCode: keyCode) }
    func preview() { session.preview() }
}
