import Foundation

/// 菜单栏进程提供给按键发声的依赖。测试可以换一套，不必碰到全局单例。
public protocol AppServices: AnyObject {
    var selectedPackID: String { get set }
    var muted: Bool { get }
    var suppressed: Bool { get }
    var comboEnabled: Bool { get }
    var masterVolume: Double { get }
    func pack(id: String) -> Soundpack?
    func prepare(_ pack: Soundpack)
    func play(_ strike: Strike)
}

public final class StrikeSession {
    public private(set) var pack: Soundpack?
    private var planner = StrikePlanner()
    private let services: AppServices
    private let now: () -> TimeInterval
    private let jitterUnit: () -> Double
    private let fileChoice: () -> Int

    public init(services: AppServices,
                now: @escaping () -> TimeInterval = { Date().timeIntervalSinceReferenceDate },
                jitterUnit: @escaping () -> Double = { Double.random(in: 0...1) },
                fileChoice: @escaping () -> Int = { Int.random(in: 0...Int.max) }) {
        self.services = services
        self.now = now
        self.jitterUnit = jitterUnit
        self.fileChoice = fileChoice
    }

    public func configure() {
        selectPack(id: services.selectedPackID)
    }

    public func reprepareCurrentPack() {
        if let pack { services.prepare(pack) }
    }

    public func selectPack(id: String) {
        let target = services.pack(id: id) ?? services.pack(id: "")
        guard target?.url != pack?.url || pack == nil else { return }
        pack = target
        planner.reset()
        services.selectedPackID = target?.id ?? ""
        if let target { services.prepare(target) }
    }

    /// 换音效包时试听一声。不看静音和免打扰，也不推进连击。
    @discardableResult
    public func preview() -> Strike? {
        guard let pack else { return nil }
        let context = StrikeContext(muted: false, suppressed: false, comboEnabled: false, masterVolume: services.masterVolume)
        guard let strike = planner.plan(
            keyName: "default",
            now: now(),
            pack: pack,
            context: context,
            jitterUnit: 0.5,
            fileChoice: 0
        ) else { return nil }
        planner.reset()
        services.play(strike)
        return strike
    }

    @discardableResult
    public func keyDown(keyCode: UInt16) -> Strike? {
        guard let pack else { return nil }
        let rules = pack.manifest.rules
        let unit = rules.pitchJitter == 0 ? 0.5 : jitterUnit()
        guard let strike = planner.plan(
            keyName: KeyMap.name(for: keyCode) ?? "default",
            now: now(),
            pack: pack,
            context: StrikeContext(
                muted: services.muted,
                suppressed: services.suppressed,
                comboEnabled: services.comboEnabled,
                masterVolume: services.masterVolume
            ),
            jitterUnit: unit,
            fileChoice: fileChoice()
        ) else { return nil }
        services.play(strike)
        return strike
    }
}
