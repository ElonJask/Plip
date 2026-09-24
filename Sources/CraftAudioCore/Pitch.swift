import Foundation

/// 音高换算和线性插值重采样。cents 为正时音高升高、时长变短。
public enum Pitch {
    public static func ratio(cents: Int) -> Double {
        pow(2.0, Double(cents) / 1200.0)
    }

    public static func resample(_ samples: [Float], cents: Int) -> [Float] {
        guard !samples.isEmpty else { return [] }
        let ratio = ratio(cents: cents)
        let outLength = max(1, Int((Double(samples.count) / ratio).rounded(.down)))
        var out = [Float](repeating: 0, count: outLength)
        let last = samples.count - 1
        for i in 0..<outLength {
            let pos = Double(i) * ratio
            let idx = Int(pos)
            if idx >= last {
                out[i] = samples[last]
            } else {
                let frac = Float(pos - Double(idx))
                out[i] = samples[idx] * (1 - frac) + samples[idx + 1] * frac
            }
        }
        return out
    }
}
