/// A stand-in for the provider's real tokenizer, which this demo does not have.
///
/// It is rule-based and deterministic, and it is deliberately *not* the calibrator's prior: English
/// words cost one token up to six letters and one more per four letters after that, digits go in
/// threes, every ASCII symbol is a token, Han characters cost one or two, kana and Hangul one, other
/// letters about one per 2.5, an emoji one plus one per scalar, and each message, tool definition and
/// request adds framing. `upgraded` is the same provider after a tokenizer release: longer words
/// merge, Han characters cost one, framing is cheaper. Every "billed" number in the demo comes from
/// here, so read the figures as a simulation of the method, not a measurement of any real model.
struct ReferenceTokenizer {
    let wordLettersFree: Int
    let lettersPerExtraToken: Int
    let hanCostsTwoEvery: UInt32?
    let perMessage: Int
    let perTool: Int
    let perRequest: Int

    static let current = ReferenceTokenizer(
        wordLettersFree: 6, lettersPerExtraToken: 4, hanCostsTwoEvery: 3, perMessage: 4, perTool: 9, perRequest: 3
    )
    static let upgraded = ReferenceTokenizer(
        wordLettersFree: 8, lettersPerExtraToken: 5, hanCostsTwoEvery: nil, perMessage: 3, perTool: 7, perRequest: 2
    )

    func bill(_ request: ChatRequest) -> Int {
        let text = (request.messages + request.tools).reduce(0) { $0 + tokens(in: $1) }
        return text + perMessage * request.messages.count + perTool * request.tools.count + perRequest
    }

    func tokens(in text: String) -> Int {
        var total = 0
        var run = ""
        var runIsLetters = true
        func flush() {
            guard !run.isEmpty else { return }
            total += runIsLetters ? wordCost(run.count) : (run.count + 2) / 3
            run = ""
        }
        for character in text {
            let scalars = character.unicodeScalars
            if scalars.contains(where: { $0.properties.isEmojiPresentation || $0.value == 0xFE0F }) {
                flush()
                total += 1 + scalars.count
                continue
            }
            for scalar in scalars {
                let isLetter = scalar.isASCII && scalar.properties.isAlphabetic
                let isDigit = scalar.isASCII && scalar.properties.numericType != nil
                if isLetter || isDigit {
                    if !run.isEmpty && runIsLetters != isLetter { flush() }
                    runIsLetters = isLetter
                    run.unicodeScalars.append(scalar)
                } else {
                    flush()
                    total += cost(of: scalar)
                }
            }
        }
        flush()
        return total
    }

    private func wordCost(_ letters: Int) -> Int {
        guard letters > wordLettersFree else { return 1 }
        return 1 + (letters - wordLettersFree + lettersPerExtraToken - 1) / lettersPerExtraToken
    }

    private func cost(of scalar: Unicode.Scalar) -> Int {
        let value = scalar.value
        switch value {
        case 0x20:
            return 0
        case 0x4E00...0x9FFF:
            if let every = hanCostsTwoEvery, value % every == 0 { return 2 }
            return 1
        case 0x3040...0x30FF, 0xAC00...0xD7AF, 0x3000...0x303F, 0xFF00...0xFFEF:
            return 1
        default:
            if scalar.properties.isWhitespace { return 1 }
            // Other letters merge two or three to a token: charge two scalars in every five.
            if scalar.properties.isAlphabetic { return value % 5 < 2 ? 1 : 0 }
            return 1
        }
    }
}

/// One chat request as the demo builds it.
struct ChatRequest {
    enum Kind: String, CaseIterable {
        case english, code, japanese, emoji
    }

    let kind: Kind
    let messages: [String]
    let tools: [String]

    /// What an app that divides characters by four would hold for it.
    var flatEstimate: Int {
        (messages + tools).reduce(0) { $0 + $1.count } / 4
    }
}
