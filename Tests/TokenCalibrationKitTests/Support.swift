@testable import TokenCalibrationKit

/// A small deterministic generator, so every test sees the same prompts on every run.
struct LCG {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next(_ bound: Int) -> Int {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Int((state >> 33) % UInt64(bound))
    }
}

enum Fixture {
    /// A provider's real rates, unknown to the calibrator.
    static let truth = TokenRates(unchecked: [0.27, 0.5, 0.0, 1.0, 1.5, 0.6, 3.0, 1.0, 3, 10, 7])
    /// The same provider after a tokenizer upgrade: English is cheaper, framing is cheaper.
    static let upgraded = TokenRates(unchecked: [0.17, 0.4, 0.0, 0.8, 1.2, 0.5, 2.5, 1.0, 2, 8, 4])

    private static let words = [
        "swift", "actor", "budget", "token", "window", "provider", "stream", "the", "a",
        "calibrate", "context", "estimate", "bill", "request", "concurrency", "of", "to"
    ]

    static func englishPrompt(_ rng: inout LCG) -> TextFeatures {
        let messageCount = 1 + rng.next(4)
        var messages: [String] = []
        for _ in 0..<messageCount {
            let length = 5 + rng.next(80)
            var sentence: [String] = []
            for _ in 0..<length {
                sentence.append(words[rng.next(words.count)])
            }
            messages.append(sentence.joined(separator: " ") + ".")
        }
        return .prompt(messages: messages)
    }

    static func japanesePrompt(_ rng: inout LCG) -> TextFeatures {
        let phrases = ["予算を確認してください", "トークン数", "文脈の長さ", "東京", "ありがとう"]
        let count = 3 + rng.next(30)
        var text = ""
        for _ in 0..<count {
            text += phrases[rng.next(phrases.count)]
        }
        return .prompt(messages: ["Answer in Japanese.", text])
    }

    /// What `rates` bills for `features`, with up to 5% noise either way.
    static func bill(_ features: TextFeatures, rates: TokenRates = truth, rng: inout LCG) -> Int {
        let exact = rates.tokens(for: features)
        let noise = 1 + Double(rng.next(21) - 10) / 200
        return Int((exact * noise).rounded())
    }
}
