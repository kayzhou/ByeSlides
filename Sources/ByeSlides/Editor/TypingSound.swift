import AppKit
import AVFoundation
import Carbon.HIToolbox

enum TypingTone: String, CaseIterable, Identifiable, Sendable {
    case crisp, soft, deep

    var id: Self { self }

    var title: String {
        switch self {
        case .crisp: "清脆"
        case .soft: "柔和"
        case .deep: "低沉"
        }
    }

    var description: String {
        switch self {
        case .crisp: "短促的触底声，尾音干净。"
        case .soft: "高频更轻，接近静音机械轴。"
        case .deep: "空格和回车带一点低频回响。"
        }
    }

    var acoustics: (bodyHz: Double, attack: Double, brightness: Double, decay: Double) {
        switch self {
        case .crisp: (510, 0.59, 0.37, 0.0050)
        case .soft: (440, 0.33, 0.24, 0.0045)
        case .deep: (345, 0.40, 0.28, 0.0070)
        }
    }
}

enum TypingKey: CaseIterable, Hashable, Sendable {
    case letter, space, enter, delete, tab

    init?(event: NSEvent) {
        guard event.type == .keyDown, event.modifierFlags.intersection([.command, .control]).isEmpty else { return nil }
        switch Int(event.keyCode) {
        case kVK_Space: self = .space
        case kVK_Return, kVK_ANSI_KeypadEnter: self = .enter
        case kVK_Delete, kVK_ForwardDelete: self = .delete
        case kVK_Tab: self = .tab
        default:
            // AppKit puts navigation and function keys in a private-use Unicode range.
            guard event.characters?.unicodeScalars.contains(where: {
                !$0.properties.isWhitespace && !CharacterSet.controlCharacters.contains($0)
                    && !(0xF700...0xF8FF).contains($0.value)
            }) == true else { return nil }
            self = .letter
        }
    }

    var acoustics: (pitch: Double, impact: Double, decay: Double) {
        switch self {
        case .letter: (1, 1, 1)
        case .space: (0.67, 1.18, 1.35)
        case .enter: (0.82, 1.10, 1.20)
        case .delete: (1.08, 0.90, 0.90)
        case .tab: (0.91, 0.95, 1.05)
        }
    }
}

actor TypingSound {
    static let shared = TypingSound()
    static let sampleRate = 44_100
    private static let format = AVAudioFormat(standardFormatWithSampleRate: Double(sampleRate), channels: 1)!
    private static let voicesCount = 6
    private static let maximumKeyAge = 0.055

    private var engine: AVAudioEngine?
    private var voices: [AVAudioPlayerNode] = []
    private var buffers: [TypingTone: [TypingKey: [AVAudioPCMBuffer]]] = [:]
    private var nextVoice = 0
    private var nextVariant = 0
    private var previewTask: Task<Void, Never>?
    private var idleTask: Task<Void, Never>?
    private var lastUse = -Double.infinity
    private var lastKeystroke = -Double.infinity

    func prepare(_ tone: TypingTone) {
        if buffers[tone] == nil {
            buffers[tone] = Dictionary(uniqueKeysWithValues: TypingKey.allCases.map { key in
                let samples = (0..<4).compactMap { variant -> AVAudioPCMBuffer? in
                    let samples = Self.sample(tone, key: key, variant: variant)
                    guard let buffer = AVAudioPCMBuffer(pcmFormat: Self.format, frameCapacity: AVAudioFrameCount(samples.count)),
                          let channel = buffer.floatChannelData?[0] else { return nil }
                    buffer.frameLength = buffer.frameCapacity
                    samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: $0.count) }
                    return buffer
                }
                return (key, samples)
            })
        }
        startEngineIfNeeded()
        if engine?.isRunning == true { keepEngineWarm() }
    }

    nonisolated func enqueue(_ key: TypingKey, tone: TypingTone, volume: Double, timestamp: TimeInterval, isRepeat: Bool) {
        Task.detached(priority: .userInitiated) {
            await self.type(key, tone: tone, volume: volume, timestamp: timestamp, isRepeat: isRepeat)
        }
    }

    private func type(_ key: TypingKey, tone: TypingTone, volume: Double, timestamp: TimeInterval, isRepeat: Bool) {
        guard timestamp > lastKeystroke,
              Self.isTimely(timestamp, now: ProcessInfo.processInfo.systemUptime),
              !isRepeat || timestamp - lastKeystroke >= 0.065 else { return }
        lastKeystroke = timestamp
        play(key, tone: tone, volume: volume, timestamp: timestamp)
    }

    nonisolated static func isTimely(_ timestamp: TimeInterval, now: TimeInterval) -> Bool {
        now - timestamp <= maximumKeyAge
    }

    func preview(_ tone: TypingTone, volume: Double) {
        previewTask?.cancel()
        previewTask = Task {
            let phrase: [(TypingKey, Int)] = [
                (.letter, 87), (.letter, 112), (.space, 94), (.letter, 76),
                (.letter, 170), (.delete, 94), (.letter, 148), (.enter, 0),
            ]
            for (key, pause) in phrase {
                guard !Task.isCancelled else { return }
                play(key, tone: tone, volume: volume)
                try? await Task.sleep(for: .milliseconds(pause))
            }
        }
    }

    func stopPreview() {
        previewTask?.cancel()
    }

    private func play(_ key: TypingKey, tone: TypingTone, volume: Double, timestamp: TimeInterval? = nil) {
        guard volume.isFinite, volume > 0 else { return }
        if engine?.isRunning != true || buffers[tone] == nil { prepare(tone) }
        guard engine?.isRunning == true, let samples = buffers[tone]?[key], !samples.isEmpty else { return }
        if let timestamp, !Self.isTimely(timestamp, now: ProcessInfo.processInfo.systemUptime) { return }
        let voice = voices[nextVoice]
        let sample = samples[nextVariant % samples.count]
        nextVoice = (nextVoice + 1) % voices.count
        nextVariant = (nextVariant + 1) % 4
        voice.volume = Float(min(volume, 1))
        // Each new keystroke plays on its own voice. A saturated voice drops its old tail.
        voice.scheduleBuffer(sample, at: nil, options: .interrupts)
        if !voice.isPlaying { voice.play() }
        keepEngineWarm()
    }

    private func startEngineIfNeeded() {
        if engine?.isRunning == true { return }
        if engine == nil {
            let engine = AVAudioEngine()
            let mixer = engine.mainMixerNode
            voices = (0..<Self.voicesCount).map { _ in
                let voice = AVAudioPlayerNode()
                engine.attach(voice)
                engine.connect(voice, to: mixer, format: Self.format)
                return voice
            }
            self.engine = engine
        }
        guard let engine else { return }
        for voice in voices { voice.stop() }
        engine.prepare()
        guard (try? engine.start()) != nil else { return }
        for voice in voices { voice.play() }
    }

    private func keepEngineWarm() {
        lastUse = ProcessInfo.processInfo.systemUptime
        guard idleTask == nil else { return }
        idleTask = Task { [weak self] in await self?.stopWhenIdle() }
    }

    private func stopWhenIdle() async {
        let timeout = 30.0
        while !Task.isCancelled {
            let remaining = timeout - (ProcessInfo.processInfo.systemUptime - lastUse)
            if remaining <= 0 { break }
            try? await Task.sleep(for: .seconds(remaining))
        }
        for voice in voices { voice.stop() }
        engine?.stop()
        idleTask = nil
    }

    /// A band-limited switch click, a damped keycap impact and a light mechanical rebound.
    nonisolated static func sample(_ tone: TypingTone, key: TypingKey, variant: Int) -> [Float] {
        let rate = sampleRate
        let count = rate * 64 / 1_000
        let (body, attack, brightness, toneDecay) = tone.acoustics
        let (pitch, impact, keyDecay) = key.acoustics
        let variation = Double(variant) - 1.5
        let angularFrequency = 2 * Double.pi * body * pitch * (1 + variation * 0.012)
        let gain = impact * (1 + variation * 0.035)
        let decay = toneDecay * keyDecay
        let bottomDelay = 0.0011 + variation * 0.00012
        let reboundDelay = 0.010 + variation * 0.0006
        var random = UInt32(truncatingIfNeeded: 31 + variant * 19)
        var high = 0.0
        var low = 0.0
        var output: [Float] = []
        output.reserveCapacity(count)

        for frame in 0..<count {
            let time = Double(frame) / Double(rate)
            random = 1_664_525 &* random &+ 1_013_904_223
            let noise = Double(random >> 8) / 8_388_608 - 1
            high += brightness * (noise - high)
            low += 0.075 * (noise - low)
            let contact = high - low
            let click = contact * attack * exp(-time / 0.0012) * min(time / 0.00018, 1)

            let bottomTime = max(0, time - bottomDelay)
            let angle = angularFrequency * bottomTime
            let bottom = (0.27 * sin(angle) + 0.15 * sin(angle * 2.21)) * exp(-bottomTime / decay)
            let keycap = (0.10 * sin(angle * 4.37) + 0.04 * sin(angle * 7.13)) * exp(-bottomTime / 0.0020)

            let reboundTime = max(0, time - reboundDelay)
            let rebound = (0.055 * sin(angularFrequency * 1.63 * reboundTime) + 0.12 * contact)
                * exp(-reboundTime / 0.0023) * min(reboundTime / 0.00035, 1)
            let fadeOut = min(Double(count - frame - 1) / 140, 1)
            let value = (click + (bottom + keycap) * gain + rebound) * fadeOut
            output.append(Float(min(max(value, -1), 1)))
        }
        return output
    }
}
