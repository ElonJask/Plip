import XCTest
import ServiceManagement
@testable import CraftAudioCore

private final class FakeServices: AppServices {
    var packs: [Soundpack]
    var selectedPackID = ""
    var muted = false
    var suppressed = false
    var comboEnabled = true
    var masterVolume = 1.0
    var prepared: [String] = []
    var played: [Strike] = []

    init(packs: [Soundpack]) { self.packs = packs }

    func pack(id: String) -> Soundpack? {
        if id.isEmpty { return packs.first }
        return packs.first { $0.id == id }
    }
    func prepare(_ pack: Soundpack) { prepared.append(pack.id) }
    func play(_ strike: Strike) { played.append(strike) }
}

final class LogicTests: XCTestCase {
    func testLoginItemStatusMapping() {
        XCTAssertEqual(LoginItemInterpreter.state(for: .enabled), .on)
        XCTAssertEqual(LoginItemInterpreter.state(for: .requiresApproval), .needsApproval)
        XCTAssertEqual(LoginItemInterpreter.state(for: .notRegistered), .off)
        XCTAssertEqual(LoginItemInterpreter.state(for: .notFound), .off)
        XCTAssertTrue(LoginItemState.needsApproval.isOn)
        XCTAssertFalse(LoginItemState.off.isOn)
        XCTAssertFalse(LoginItemState.failed("x").isOn)
    }

    func testInvalidSignatureIsExplained() {
        let error = NSError(domain: "SMAppServiceErrorDomain", code: 3, userInfo: [
            NSLocalizedDescriptionKey: "invalid"
        ])
        let text = LoginItemInterpreter.failureMessage(for: error, enabling: true)
        XCTAssertTrue(text.contains("Developer ID"))
        XCTAssertFalse(text.contains("invalid"))
    }

    func testUserDenialIsExplained() {
        let error = NSError(domain: "com.apple.ServiceManagement", code: 10)
        let text = LoginItemInterpreter.failureMessage(for: error, enabling: true)
        XCTAssertTrue(text.contains("登录项"))
    }

    func testEnableRequiresApprovalOpensSettings() {
        var opened = false
        let controller = LoginItemController(
            status: { .requiresApproval },
            register: {},
            unregister: {},
            openSettings: { opened = true }
        )
        controller.setEnabled(true)
        XCTAssertEqual(controller.state, .needsApproval)
        XCTAssertTrue(opened)
        XCTAssertTrue(controller.state.isOn)
    }

    func testEnableFailureIsVisible() {
        struct Boom: Error {}
        let controller = LoginItemController(
            status: { .notRegistered },
            register: { throw Boom() },
            unregister: {},
            openSettings: {}
        )
        controller.setEnabled(true)
        guard case .failed = controller.state else {
            return XCTFail("expected failure, got \(controller.state)")
        }
        XCTAssertFalse(controller.state.isOn)
    }

    func testAlreadyRegisteredUsesLiveStatus() {
        let controller = LoginItemController(
            status: { .enabled },
            register: { throw NSError(domain: "SMAppServiceErrorDomain", code: 11) },
            unregister: {},
            openSettings: {}
        )
        controller.setEnabled(true)
        XCTAssertEqual(controller.state, .on)
    }

    func testRefreshKeepsFailureUntilStatusChanges() {
        struct Boom: Error {}
        var status = SMAppService.Status.notRegistered
        let controller = LoginItemController(
            status: { status },
            register: { throw Boom() },
            unregister: {},
            openSettings: {}
        )
        controller.setEnabled(true)
        controller.refresh()
        guard case .failed = controller.state else {
            return XCTFail("failure was cleared while still unregistered")
        }
        status = .enabled
        controller.refresh()
        XCTAssertEqual(controller.state, .on)
    }

    func testBlacklistParse() {
        XCTAssertEqual(
            BlacklistParser.parse(" com.apple.logic10, , com.ableton.live, com.apple.logic10 "),
            ["com.apple.logic10", "com.ableton.live"]
        )
        XCTAssertEqual(BlacklistParser.parse("   "), [])
        XCTAssertEqual(BlacklistParser.parse("com.app"), ["com.app"])
    }

    func testSoundpackMergeUserOverridesBundled() throws {
        let bundled = try pack(id: "real-mx-blue", name: "内置", path: "/bundled/real-mx-blue")
        let user = try pack(id: "real-mx-blue", name: "我的", path: "/user/real-mx-blue")
        let other = try pack(id: "real-cream", name: "奶油", path: "/bundled/real-cream")
        let merged = SoundpackMerger.merge([bundled, other, user])
        XCTAssertEqual(merged.map(\.id), ["real-mx-blue", "real-cream"])
        XCTAssertEqual(merged[0].manifest.name, "我的")
        XCTAssertEqual(merged[0].url.path, "/user/real-mx-blue")
    }

    func testKeyMapAndModifierStrike() {
        XCTAssertEqual(KeyMap.name(for: 49), "space")
        XCTAssertEqual(KeyMap.name(for: 76), "return")
        XCTAssertNil(KeyMap.name(for: 0))
        XCTAssertTrue(ModifierStrike.shouldPlay(keyCode: 57, shiftDown: false))
        XCTAssertTrue(ModifierStrike.shouldPlay(keyCode: 56, shiftDown: true))
        XCTAssertFalse(ModifierStrike.shouldPlay(keyCode: 56, shiftDown: false))
        XCTAssertTrue(Hotkey.isMuteToggle(keyCode: 46, option: true, shift: true, command: false, control: false))
        XCTAssertFalse(Hotkey.isMuteToggle(keyCode: 46, option: true, shift: true, command: true, control: false))
        XCTAssertFalse(Hotkey.isMuteToggle(keyCode: 45, option: true, shift: true, command: false, control: false))
    }

    func testComboRisesThenResets() throws {
        let pack = try pack(id: "combo", name: "连击", path: "/p", combo: true)
        var planner = StrikePlanner()
        let context = StrikeContext(muted: false, suppressed: false, comboEnabled: true, masterVolume: 1)
        let first = planner.plan(keyName: "default", now: 1, pack: pack, context: context, jitterUnit: 0.5, fileChoice: 0)
        let second = planner.plan(keyName: "default", now: 1.2, pack: pack, context: context, jitterUnit: 0.5, fileChoice: 1)
        let later = planner.plan(keyName: "default", now: 3, pack: pack, context: context, jitterUnit: 0.5, fileChoice: 0)
        XCTAssertEqual(first?.comboCount, 0)
        XCTAssertEqual(second?.comboCount, 1)
        XCTAssertEqual(second?.semitones ?? -1, 0.35, accuracy: 0.001)
        XCTAssertEqual(second?.file.lastPathComponent, "b.wav")
        XCTAssertEqual(later?.comboCount, 0)
    }

    func testMutedAndMissingKeyFallbacks() throws {
        let pack = try pack(id: "plain", name: "普通", path: "/p", combo: false)
        var planner = StrikePlanner()
        let muted = StrikeContext(muted: true, suppressed: false, comboEnabled: true, masterVolume: 1)
        XCTAssertNil(planner.plan(keyName: "default", now: 1, pack: pack, context: muted, jitterUnit: 0.5, fileChoice: 0))
        let live = StrikeContext(muted: false, suppressed: false, comboEnabled: true, masterVolume: 0.5)
        let strike = planner.plan(keyName: "escape", now: 2, pack: pack, context: live, jitterUnit: 1, fileChoice: 99)
        XCTAssertEqual(strike?.file.lastPathComponent, "a.wav")
        XCTAssertEqual(strike?.volume ?? -1, 0.4, accuracy: 0.001)
        XCTAssertEqual(strike?.comboCount, 0)
    }

    func testMutePolicyDistinguishesCallAndBackground() {
        let dictation = [AudioClient(bundleID: "com.apple.SpeechRecognitionCore", runningInput: true)]
        XCTAssertEqual(
            MutePolicy.decide(smartMuteEnabled: true, frontBundleID: "com.apple.Terminal",
                               blacklist: [], inputClients: dictation),
            .clear
        )
        let zoom = [AudioClient(bundleID: "us.zoom.xos", runningInput: true)]
        XCTAssertTrue(MutePolicy.decide(smartMuteEnabled: true, frontBundleID: "com.apple.Terminal",
                                         blacklist: [], inputClients: zoom).suppressed)
        let frontMic = [AudioClient(bundleID: "com.apple.Terminal", runningInput: true)]
        XCTAssertEqual(
            MutePolicy.decide(smartMuteEnabled: true, frontBundleID: "com.apple.Terminal",
                               blacklist: [], inputClients: frontMic).reason,
            "前台应用正在使用麦克风"
        )
        XCTAssertEqual(
            MutePolicy.decide(smartMuteEnabled: true, frontBundleID: "com.apple.logic10",
                               blacklist: ["com.apple.logic10"], inputClients: []).reason,
            "前台应用在黑名单中"
        )
        XCTAssertEqual(
            MutePolicy.decide(smartMuteEnabled: false, frontBundleID: "us.zoom.xos",
                               blacklist: ["us.zoom.xos"], inputClients: zoom),
            .clear
        )
    }

    func testManifestDefaultsAndRealPacks() throws {
        let data = #"{"name":"最小","key_mappings":{"default":{"files":["a.wav"]}}}"#.data(using: .utf8)!
        let manifest = try JSONDecoder().decode(SoundpackManifest.self, from: data)
        XCTAssertEqual(manifest.version, "1.0.0")
        XCTAssertEqual(manifest.rules.comboTimeoutMs, 600)
        XCTAssertFalse(manifest.rules.comboEnabled)
        XCTAssertEqual(manifest.keyMappings["default"]?.volume, 0.8)

        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Soundpacks")
        let packs = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.hasDirectoryPath }
        XCTAssertEqual(packs.count, 13)
        for dir in packs {
            let manifestData = try Data(contentsOf: dir.appendingPathComponent("manifest.json"))
            let decoded = try JSONDecoder().decode(SoundpackManifest.self, from: manifestData)
            let pack = Soundpack(id: dir.lastPathComponent, url: dir, manifest: decoded)
            XCTAssertFalse(pack.allFiles.isEmpty, dir.lastPathComponent)
            for file in pack.allFiles {
                XCTAssertTrue(FileManager.default.fileExists(atPath: file.path), file.path)
            }
        }
    }

    func testPitchKeepsShapeAndShortensWhenHigher() {
        let samples: [Float] = [0, 0.5, 1, 0.5, 0, -0.5, -1, -0.5]
        XCTAssertEqual(Pitch.resample([], cents: 100), [])
        XCTAssertEqual(Pitch.resample(samples, cents: 0), samples)
        let up = Pitch.resample(samples, cents: 1200)
        XCTAssertLessThan(up.count, samples.count)
        XCTAssertGreaterThan(up.count, 0)
        XCTAssertEqual(up.first ?? -1, 0, accuracy: 0.001)
    }

    func testSessionPlaysSelectedPackAndSkipsWhenMuted() throws {
        let blue = try pack(id: "blue", name: "青", path: "/packs/blue", combo: true)
        let cream = try pack(id: "cream", name: "奶油", path: "/packs/cream")
        let fake = FakeServices(packs: [blue, cream])
        var clock = 10.0
        let session = StrikeSession(services: fake, now: { clock }, jitterUnit: { 0.5 }, fileChoice: { 0 })
        session.configure()
        XCTAssertEqual(fake.prepared, ["blue"])
        let played = session.keyDown(keyCode: 49)
        XCTAssertEqual(played?.file.lastPathComponent, "a.wav")
        XCTAssertEqual(fake.played.count, 1)

        fake.muted = true
        clock += 0.1
        XCTAssertNil(session.keyDown(keyCode: 0))
        XCTAssertEqual(fake.played.count, 1)

        session.selectPack(id: "cream")
        XCTAssertEqual(fake.selectedPackID, "cream")
        XCTAssertEqual(fake.prepared, ["blue", "cream"])
    }

    private func pack(id: String, name: String, path: String, combo: Bool = false) throws -> Soundpack {
        let rules = combo
            ? #","rules":{"combo_enabled":true,"combo_pitch_step":0.35,"combo_timeout_ms":500,"combo_max_steps":16,"pitch_jitter":0}"#
            : #","rules":{"pitch_jitter":0.04}"#
        let json = """
        {"name":"\(name)"\(rules),"key_mappings":{"default":{"files":["a.wav","b.wav"],"volume":0.8}}}
        """.data(using: .utf8)!
        let manifest = try JSONDecoder().decode(SoundpackManifest.self, from: json)
        return Soundpack(id: id, url: URL(fileURLWithPath: path), manifest: manifest)
    }
}
