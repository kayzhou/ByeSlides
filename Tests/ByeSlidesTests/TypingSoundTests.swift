import AppKit
import Carbon.HIToolbox
import Testing
@testable import ByeSlides

@MainActor
struct TypingSoundTests {
    @Test func onlyWritingKeysProduceSound() throws {
        func key(_ code: Int, _ text: String, modifiers: NSEvent.ModifierFlags = []) throws -> TypingKey? {
            let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
                timestamp: 1, windowNumber: 0, context: nil, characters: text, charactersIgnoringModifiers: text,
                isARepeat: false, keyCode: UInt16(code)))
            return TypingKey(event: event)
        }
        #expect(try key(kVK_ANSI_A, "a") == .letter)
        #expect(try key(kVK_ANSI_A, "中") == .letter)
        #expect(try key(kVK_Space, " ") == .space)
        #expect(try key(kVK_Return, "\r") == .enter)
        #expect(try key(kVK_Delete, "\u{7F}") == .delete)
        #expect(try key(kVK_Tab, "\t") == .tab)
        #expect(try key(kVK_LeftArrow, "\u{F702}") == nil)
        #expect(try key(kVK_Escape, "\u{1B}") == nil)
        #expect(try key(kVK_ANSI_V, "v", modifiers: .command) == nil)
        #expect(try key(kVK_ANSI_A, "a", modifiers: .control) == nil)
    }

    @Test func allTonesProduceShortDistinctAudio() {
        let samples = TypingTone.allCases.flatMap { tone in
            TypingKey.allCases.flatMap { key in
                (0..<4).map { TypingSound.sample(tone, key: key, variant: $0) }
            }
        }
        #expect(Set(samples).count == samples.count)
        for sample in samples {
            #expect((0.06...0.07).contains(Double(sample.count) / Double(TypingSound.sampleRate)))
        }
    }

    @Test func keyTapsLeaveHeadroomAndDecayBeforeTheNextKeystroke() {
        for tone in TypingTone.allCases {
            for key in TypingKey.allCases {
                for variant in 0..<4 {
                    let frames = TypingSound.sample(tone, key: key, variant: variant)
                    let peak = frames.map(abs).max() ?? 0
                    let releasePeak = frames.dropFirst(2_000).map(abs).max() ?? 0
                    #expect((0.12...0.75).contains(peak))
                    #expect(releasePeak < peak * 0.02)
                    #expect(frames.first == 0 && frames.last == 0)
                }
            }
        }
    }

    @Test func delayedKeyEventsAreNotPlayedBack() {
        #expect(TypingSound.isTimely(1.0, now: 1.02))
        #expect(!TypingSound.isTimely(1.0, now: 1.08))
    }
}
