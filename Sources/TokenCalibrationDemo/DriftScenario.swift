import Foundation
import TokenCalibrationKit

enum DriftScenario {
    /// The provider ships a new tokenizer. The calibrator notices from the bills alone.
    static func run(_ calibrator: TokenCalibrator, model: String, seed: UInt64) async throws {
        var rng = SeededGenerator(seed: seed)
        Format.heading("4. Tokenizer upgrade at bill 161 (simulated version 2: longer words merge, cheaper framing)")
        var afterChange: [BilledRow] = []
        var alarmAt: Int?
        for index in 0..<80 {
            let request = Corpus.request(rng.pick(ChatRequest.Kind.allCases), using: &rng)
            let features = TextFeatures.prompt(messages: request.messages, toolSchemas: request.tools)
            let billed = ReferenceTokenizer.upgraded.bill(request)
            let update = try await calibrator.record(features, billedTokens: billed, model: model)
            afterChange.append(BilledRow(
                kind: request.kind,
                flat: request.flatEstimate,
                estimate: update.estimate,
                billed: billed,
                check: update.check
            ))
            if let drift = update.drift {
                alarmAt = index + 1
                print("bill \(161 + index): drift alarm, \(drift.outside) of the last \(drift.window) bills outside the"
                    + " reference interval, p = \(String(format: "%.2e", drift.pValue)); calibration restarted")
            }
        }
        let report = try await calibrator.report(for: model)
        let before = afterChange.prefix(alarmAt ?? 0)
        print("before the alarm: median error \(Format.signed(Format.median(before.map(\.calibratedError))))"
            + " over \(before.count) bills")
        let settled = afterChange.suffix(40)
        let checked = settled.filter { $0.check != .noInterval }
        let inside = checked.filter { $0.check == .inside }.count
        print("last 40 bills: median |err| \(Format.percent(Format.median(settled.map { abs($0.calibratedError) })))"
            + ", \(inside)/\(checked.count) inside the 90% interval")
        print("report: \(report.bills) bills since the reset, \(report.lifetimeBills) in all, \(report.resets) reset")
    }
}
