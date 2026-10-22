import TokenCalibrationKit

enum WindowScenario {
    static let contextWindow = 8_192
    static let reservedOutput = 1_024

    /// Long requests near an 8,192-token window with 1,024 tokens kept for the answer.
    static func run(_ calibrator: TokenCalibrator, model: String) async throws {
        Format.heading("2. Will it fit? 8,192-token window, 1,024 reserved for the answer (7,168 for the prompt)")
        let cases: [(ChatRequest.Kind, Int)] = [
            (.english, 6_400), (.english, 7_500), (.code, 7_000), (.japanese, 7_400)
        ]
        for (index, (kind, target)) in cases.enumerated() {
            var rng = SeededGenerator(seed: 900 + UInt64(index))
            let request = grow(kind, toAbout: target, using: &rng)
            let billed = ReferenceTokenizer.current.bill(request)
            let estimate = try await calibrator.estimatePrompt(
                messages: request.messages, toolSchemas: request.tools, model: model
            )
            let fit = try ContextFit(estimate: estimate, contextWindow: contextWindow, reservedOutput: reservedOutput)
            let flatSays = request.flatEstimate <= contextWindow - reservedOutput ? "fits" : "too long"
            let truth = billed <= contextWindow - reservedOutput ? "fits" : "rejected (context length exceeded)"
            let flatText = "chars/4 \(request.flatEstimate) says \(flatSays)"
            print("\(kind.rawValue) request: \(flatText);"
                + " calibrator \(estimate.lower)-\(estimate.upper) says \(fit.label)"
                + " (trim \(fit.tokensToTrim)); provider bills \(billed): \(truth)")
        }
    }

    /// Adds pasted content until the simulated provider would bill at least `target` tokens.
    private static func grow(
        _ kind: ChatRequest.Kind,
        toAbout target: Int,
        using rng: inout SeededGenerator
    ) -> ChatRequest {
        var body: [String] = []
        while true {
            body.append(Corpus.message(kind, using: &rng))
            let request = ChatRequest(
                kind: kind,
                messages: [Corpus.system, body.joined(separator: "\n"), "Summarise the above."],
                tools: []
            )
            if ReferenceTokenizer.current.bill(request) >= target {
                return request
            }
        }
    }

    /// What a budget would have held, per request, for the bills of the mixed phase.
    static func holds(_ rows: [BilledRow]) {
        Format.heading("3. Budget holds over bills 61-160 (hold first, settle on the bill)")
        let billed = rows.reduce(0) { $0 + $1.billed }
        let flatHeld = rows.reduce(0) { $0 + $1.flat }
        let upperHeld = rows.reduce(0) { $0 + $1.estimate.upper }
        let flatShort = rows.filter { $0.billed > $0.flat }
        let upperShort = rows.filter { $0.billed > $0.estimate.upper }
        let flatShortfall = flatShort.reduce(0) { $0 + $1.billed - $1.flat }
        let upperShortfall = upperShort.reduce(0) { $0 + $1.billed - $1.estimate.upper }
        print("billed \(billed) prompt tokens across \(rows.count) requests")
        let flatText = "short on \(flatShort.count) requests by \(flatShortfall) tokens in all"
        print("holding chars/4: \(flatHeld) held, " + flatText)
        let over = Format.signed(Double(upperHeld) / Double(billed) - 1)
        let shortText = "short on \(upperShort.count) requests by \(upperShortfall) tokens in all"
        print("holding the calibrated upper bound: \(upperHeld) held (\(over) over the bill), " + shortText)
    }
}
