import AVFoundation

/// Procedurally generated ambient noise, mixed under the music.
enum Noise {
    enum Kind: String, CaseIterable {
        case off, brown, pink, white
        var label: String {
            switch self {
            case .off: return "Off"
            case .brown: return "Brown Noise (rain-like)"
            case .pink: return "Pink Noise (soft)"
            case .white: return "White Noise"
            }
        }
    }

    static let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!

    /// A seamless loop: the tail is crossfaded into the head so there's no click at the seam.
    static func buffer(_ kind: Kind, seconds: Double = 8) -> AVAudioPCMBuffer? {
        guard kind != .off else { return nil }
        let n = Int(format.sampleRate * seconds)
        let fade = Int(format.sampleRate * 0.5)
        guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(n)),
              let channels = buf.floatChannelData else { return nil }
        buf.frameLength = AVAudioFrameCount(n)

        for ch in 0..<Int(format.channelCount) {
            var raw = generate(kind, count: n + fade)
            for i in 0..<fade {
                let t = Float(i) / Float(fade)
                raw[i] = raw[i] * t + raw[n + i] * (1 - t)
            }
            let out = channels[ch]
            for i in 0..<n { out[i] = raw[i] }
        }
        return buf
    }

    private static func generate(_ kind: Kind, count: Int) -> [Float] {
        var out = [Float](repeating: 0, count: count)
        switch kind {
        case .off:
            break
        case .white:
            for i in 0..<count { out[i] = Float.random(in: -1...1) * 0.25 }
        case .pink:
            // Paul Kellet's refined pink-noise filter.
            var b0: Float = 0, b1: Float = 0, b2: Float = 0, b3: Float = 0, b4: Float = 0, b5: Float = 0, b6: Float = 0
            for i in 0..<count {
                let w = Float.random(in: -1...1)
                b0 = 0.99886 * b0 + w * 0.0555179
                b1 = 0.99332 * b1 + w * 0.0750759
                b2 = 0.96900 * b2 + w * 0.1538520
                b3 = 0.86650 * b3 + w * 0.3104856
                b4 = 0.55000 * b4 + w * 0.5329522
                b5 = -0.7616 * b5 - w * 0.0168980
                out[i] = (b0 + b1 + b2 + b3 + b4 + b5 + b6 + w * 0.5362) * 0.06
                b6 = w * 0.115926
            }
        case .brown:
            // Leaky integrator keeps it from drifting.
            var last: Float = 0
            for i in 0..<count {
                last = (last + 0.02 * Float.random(in: -1...1)) / 1.02
                out[i] = last * 3.0
            }
        }
        return out
    }
}
