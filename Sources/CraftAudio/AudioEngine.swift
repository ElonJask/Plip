import AVFoundation
import CraftAudioCore

/// 核心音频引擎。
/// 低延迟策略：加载音效包时把所有音频按 25 音分为粒度预渲染成一系列变速变调 Buffer，
/// 敲击时直接查表 scheduleBuffer —— 运行期不做任何实时 DSP（不用 AVAudioUnitTimePitch），
/// 从事件回调到发声只有 AVAudioEngine 本身的渲染延迟（约 3~6ms）。
/// 8 个 PlayerNode 轮转复用：高速连击时最老的尾音被自然截断，避免浑浊（anti-muddying）。
final class AudioEngine {
    static let shared = AudioEngine()

    private let engine = AVAudioEngine()
    private var players: [AVAudioPlayerNode] = []
    private var nextPlayer = 0
    private let queue = DispatchQueue(label: "audio.craftaudio.engine", qos: .userInteractive)
    private var monoFormat: AVAudioFormat?

    /// fileURL -> 按音分升序排列的预渲染变体
    private var variants: [URL: [(cents: Int, buffer: AVAudioPCMBuffer)]] = [:]

    private static let playerCount = 8
    private static let centStep = 25

    func start() {
        let hwFormat = engine.outputNode.outputFormat(forBus: 0)
        monoFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                   sampleRate: hwFormat.sampleRate,
                                   channels: 1,
                                   interleaved: false)
        for _ in 0..<Self.playerCount {
            let p = AVAudioPlayerNode()
            engine.attach(p)
            engine.connect(p, to: engine.mainMixerNode, format: monoFormat)
            players.append(p)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            NSLog("Plip: audio engine failed to start: \(error)")
        }

        // 插拔耳机等导致采样率变化时，重建预渲染变体
        NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange,
                                               object: engine, queue: nil) { [weak self] _ in
            self?.handleConfigurationChange()
        }
    }

    private func handleConfigurationChange() {
        let hwFormat = engine.outputNode.outputFormat(forBus: 0)
        guard hwFormat.sampleRate != monoFormat?.sampleRate else { return }
        monoFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                   sampleRate: hwFormat.sampleRate,
                                   channels: 1,
                                   interleaved: false)
        for p in players {
            engine.disconnectNodeOutput(p)
            engine.connect(p, to: engine.mainMixerNode, format: monoFormat)
        }
        // 采样率变了，旧变体作废；由 SoundEngine 重新 prepare 当前包
        queue.async { [weak self] in self?.variants.removeAll() }
        DispatchQueue.main.async {
            SoundEngine.shared.reprepareCurrentPack()
        }
    }

    /// 为音效包预渲染全部音高变体（异步，切包时调用）
    func prepare(pack: Soundpack) {
        queue.async { [weak self] in
            self?.buildVariants(for: pack)
        }
    }

    private func buildVariants(for pack: Soundpack) {
        guard let format = monoFormat else { return }
        let rules = pack.manifest.rules
        let topCents = Int((rules.comboEnabled
                            ? Double(rules.comboMaxSteps) * rules.comboPitchStep * 100
                            : 0)
                           + rules.pitchJitter * 100 + 50)
        let bottomCents = -Int(rules.pitchJitter * 100) - 50
        var newVariants: [URL: [(cents: Int, buffer: AVAudioPCMBuffer)]] = [:]

        for url in pack.allFiles {
            guard let samples = Self.decodeToMonoFloat(url: url, targetFormat: format) else { continue }
            var list: [(cents: Int, buffer: AVAudioPCMBuffer)] = []
            var cents = bottomCents
            while cents <= topCents {
                if let buf = Self.resample(samples: samples, cents: cents, format: format) {
                    list.append((cents, buf))
                }
                cents += Self.centStep
            }
            newVariants[url] = list
        }
        variants = newVariants
    }

    /// 播放一个文件，semitones 为总音高偏移（半音，可负），volume 0~1
    func play(_ url: URL, semitones: Float, volume: Float) {
        queue.async { [weak self] in
            guard let self, let list = self.variants[url], !list.isEmpty else { return }
            let target = Int(semitones * 100)
            // 找最近的预渲染变体
            var best = list[0]
            var bestDist = abs(target - best.cents)
            for v in list {
                let dist = abs(target - v.cents)
                if dist < bestDist { best = v; bestDist = dist }
            }
            let player = self.players[self.nextPlayer]
            self.nextPlayer = (self.nextPlayer + 1) % self.players.count
            player.stop()
            player.volume = min(max(volume, 0), 1)
            player.scheduleBuffer(best.buffer, at: nil, options: [], completionHandler: nil)
            player.play()
        }
    }

    // MARK: - 解码与重采样

    /// 任意格式音频 -> 目标格式的单声道 Float32 数组
    private static func decodeToMonoFloat(url: URL, targetFormat: AVAudioFormat) -> [Float]? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        guard let converter = AVAudioConverter(from: file.processingFormat, to: targetFormat) else { return nil }
        let ratio = targetFormat.sampleRate / file.processingFormat.sampleRate
        let capacity = AVAudioFrameCount(Double(file.length) * ratio) + 1024
        guard let outBuf = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return nil }

        var error: NSError?
        var consumed = false
        converter.convert(to: outBuf, error: &error) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            let inBuf = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                         frameCapacity: AVAudioFrameCount(file.length))
            guard let inBuf else {
                outStatus.pointee = .endOfStream
                return nil
            }
            do {
                try file.read(into: inBuf)
            } catch {
                outStatus.pointee = .endOfStream
                return nil
            }
            outStatus.pointee = .haveData
            return inBuf
        }
        if error != nil { return nil }
        guard let channelData = outBuf.floatChannelData else { return nil }
        let count = Int(outBuf.frameLength)
        return Array(UnsafeBufferPointer(start: channelData[0], count: count))
    }

    /// 线性插值重采样。算法在 Pitch，这里只装进播放缓冲。
    private static func resample(samples: [Float], cents: Int, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let rendered = Pitch.resample(samples, cents: cents)
        guard !rendered.isEmpty,
              let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(rendered.count)),
              let out = buf.floatChannelData?[0] else { return nil }
        buf.frameLength = AVAudioFrameCount(rendered.count)
        for i in 0..<rendered.count { out[i] = rendered[i] }
        return buf
    }
}
