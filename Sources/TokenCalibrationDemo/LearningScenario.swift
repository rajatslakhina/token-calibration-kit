import TokenCalibrationKit

enum LearningScenario {
    /// 160 bills: 60 of English and code, then 100 that add Japanese and emoji-heavy chat.
    static func run(_ calibrator: TokenCalibrator, model: String, seed: UInt64) async throws -> [BilledRow] {
        var rng = SeededGenerator(seed: seed)
        Format.heading("1. Learning from bills (simulated upstream tokenizer, version 1)")
        var rows: [BilledRow] = []
        for index in 0..<160 {
            let kinds: [ChatRequest.Kind] = index < 60 ? [.english, .english, .code] : ChatRequest.Kind.allCases
            let request = Corpus.request(rng.pick(kinds), using: &rng)
            let features = TextFeatures.prompt(messages: request.messages, toolSchemas: request.tools)
            let billed = ReferenceTokenizer.current.bill(request)
            let update = try await calibrator.record(features, billedTokens: billed, model: model)
            let row = BilledRow(
                kind: request.kind,
                flat: request.flatEstimate,
                estimate: update.estimate,
                billed: billed,
                check: update.check
            )
            rows.append(row)
            if [0, 18, 19, 59].contains(index) {
                print("bill \(index + 1) (\(row.kind.rawValue)): billed \(billed), chars/4 \(row.flat),"
                    + " calibrator \(row.estimate.point) [\(row.estimate.lower)-\(row.estimate.upper)]"
                    + " \(row.estimate.basis.label)")
            }
        }
        printFirstJapanese(rows)
        printTable(Array(rows.suffix(100)))
        return rows
    }

    private static func printFirstJapanese(_ rows: [BilledRow]) {
        let japanese = rows.enumerated().filter { $0.element.kind == .japanese }.prefix(6)
        print("first Japanese bills, each estimated before it was learned from:")
        for (offset, row) in japanese {
            print("  bill \(offset + 1): billed \(row.billed), chars/4 \(row.flat) (\(Format.signed(row.flatError))),"
                + " calibrator \(row.estimate.point) (\(Format.signed(row.calibratedError))),"
                + " interval \(row.estimate.lower)-\(row.estimate.upper) \(row.check)")
        }
    }

    private static func printTable(_ rows: [BilledRow]) {
        print("bills 61-160, every estimate made before its bill arrived:")
        print("  kind      bills  median |err| chars/4  median |err| calibrated  worst chars/4  inside 90% interval")
        for kind in ChatRequest.Kind.allCases {
            let group = rows.filter { $0.kind == kind }
            summarize(Format.padded(kind.rawValue, 8), group)
        }
        summarize("all     ", rows)
    }

    private static func summarize(_ label: String, _ group: [BilledRow]) {
        let flat = Format.median(group.map { abs($0.flatError) })
        let calibrated = Format.median(group.map { abs($0.calibratedError) })
        let worst = group.map(\.flatError).min() ?? 0
        let checked = group.filter { $0.check != .noInterval }
        let inside = checked.filter { $0.check == .inside }.count
        print("  \(label)  \(Format.padded(String(group.count), 5))  \(Format.padded(Format.percent(flat), 22))"
            + "  \(Format.padded(Format.percent(calibrated), 25))  \(Format.padded(Format.signed(worst), 13))"
            + "  \(inside)/\(checked.count)")
    }
}
