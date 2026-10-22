import Foundation
import TokenCalibrationKit

// Every "billed" count below comes from ReferenceTokenizer, a rule-based stand-in for a provider's
// tokenizer. The calibrator never sees it: it only sees the request text and the billed number.
let model = "support-model"
let calibrator = TokenCalibrator()

print("TokenCalibrationDemo: token counts without a tokenizer, calibrated from the bills")
print("model \(model); 90% intervals; drift test over the last 20 bills at p < 0.001")

let rows = try await LearningScenario.run(calibrator, model: model, seed: 20_261_021)
try await WindowScenario.run(calibrator, model: model)
WindowScenario.holds(Array(rows.suffix(100)))
let learned = try await calibrator.report(for: model)
try await DriftScenario.run(calibrator, model: model, seed: 20_261_022)

Format.heading("5. What it learned before the upgrade (rates in tokens per unit; prior in brackets)")
let prior = TokenRates.standardPrior
for scalarClass in ScalarClass.allCases {
    print("  \(Format.padded(scalarClass.label, 18)) \(Format.rate(learned.rates.rate(for: scalarClass)))"
        + " [\(Format.rate(prior.rate(for: scalarClass)))]")
}
let framing: [(label: String, rates: KeyPath<TokenRates, Double>)] = [
    ("per message", \.perMessage), ("per tool", \.perTool), ("per request", \.perRequest)
]
for item in framing {
    let rate = learned.rates[keyPath: item.rates]
    print("  \(Format.padded(item.label, 18)) \(Format.rate(rate)) [\(Format.rate(prior[keyPath: item.rates]))]")
}
print("  (one rate per class is a least-squares fit, so a class that always travels with another,")
print("   such as whitespace with letters, can trade weight with it; the predictions are what is checked)")

Format.heading("6. Snapshot and restore")
let encoder = JSONEncoder()
encoder.outputFormatting = .sortedKeys
let data = try encoder.encode(await calibrator.snapshot())
let restored = try TokenCalibrator(restoring: try JSONDecoder().decode(CalibrationSnapshot.self, from: data))
let probe = TextFeatures.prompt(messages: [Corpus.system, "How do I resume a background upload after suspension?"])
let live = try await calibrator.estimate(probe, model: model)
let resumed = try await restored.estimate(probe, model: model)
print("snapshot: \(data.count) bytes of JSON; probe estimate live \(live.point) [\(live.lower)-\(live.upper)],"
    + " restored \(resumed.point) [\(resumed.lower)-\(resumed.upper)], identical: \(live == resumed)")
