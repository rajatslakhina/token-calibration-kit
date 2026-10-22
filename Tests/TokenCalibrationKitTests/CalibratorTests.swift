@testable import TokenCalibrationKit
import XCTest

final class CalibratorTests: XCTestCase {
    private let model = "openai/gpt-4o"

    func testAFreshModelUsesThePriorBand() async throws {
        let calibrator = TokenCalibrator()
        let features = TextFeatures.prompt(messages: ["Hello there, how are you?"])
        let raw = TokenRates.standardPrior.tokens(for: features)
        let estimate = try await calibrator.estimate(features, model: model)
        XCTAssertEqual(estimate.point, Int(raw.rounded()))
        XCTAssertEqual(estimate.lower, Int((raw * 0.6).rounded(.down)))
        XCTAssertEqual(estimate.upper, Int((raw * 1.8).rounded(.up)))
        XCTAssertEqual(estimate.basis, .priorBand(billsNeeded: 19))
        XCTAssertEqual(estimate.model, model)
        let viaPrompt = try await calibrator.estimatePrompt(messages: ["Hello there, how are you?"], model: model)
        XCTAssertEqual(viaPrompt, estimate)
        let nothing = try await calibrator.estimate(.empty, model: model)
        XCTAssertEqual([nothing.lower, nothing.point, nothing.upper], [0, 0, 0])
    }

    func testRejectsBadInput() async {
        let calibrator = TokenCalibrator()
        await XCTAssertThrowsAsync(try await calibrator.estimate(.empty, model: ""), .emptyModel)
        await XCTAssertThrowsAsync(try await calibrator.record(.empty, billedTokens: 5, model: ""), .emptyModel)
        await XCTAssertThrowsAsync(try await calibrator.report(for: ""), .emptyModel)
        await XCTAssertThrowsAsync(try await calibrator.record(.empty, billedTokens: -1, model: model), .negativeBill(-1))
        let models = await calibrator.calibratedModels
        XCTAssertEqual(models, [])
    }

    func testLearnsAndCalibrates() async throws {
        let calibrator = TokenCalibrator()
        var rng = LCG(seed: 7)
        var checks: [IntervalCheck] = []
        for index in 0..<120 {
            let features = Fixture.englishPrompt(&rng)
            let update = try await calibrator.record(features, billedTokens: Fixture.bill(features, rng: &rng), model: model)
            if index < 19 {
                XCTAssertEqual(update.check, .noInterval)
            }
            checks.append(update.check)
            XCTAssertNil(update.drift)
        }
        let report = try await calibrator.report(for: model)
        XCTAssertEqual(report.bills, 120)
        XCTAssertEqual(report.lifetimeBills, 120)
        XCTAssertEqual(report.checked, 101)
        XCTAssertEqual(report.billsNeeded, 0)
        XCTAssertEqual(report.inside, checks.filter { $0 == .inside }.count)
        XCTAssertGreaterThan(report.empiricalCoverage ?? 0, 0.8)
        // English bills say nothing about CJK, so that rate is still the prior.
        XCTAssertEqual(report.rates.rate(for: .cjk), 1.2, accuracy: 1e-12)

        var held = LCG(seed: 1234)
        var inside = 0
        for _ in 0..<50 {
            let features = Fixture.englishPrompt(&held)
            let truth = Fixture.truth.tokens(for: features)
            let estimate = try await calibrator.estimate(features, model: model)
            XCTAssertEqual(estimate.basis, .calibrated(bills: 120, coverage: 0.9))
            XCTAssertEqual(Double(estimate.point) / truth, 1, accuracy: 0.08)
            XCTAssertLessThanOrEqual(estimate.lower, estimate.point)
            XCTAssertLessThanOrEqual(estimate.point, estimate.upper)
            inside += (Double(estimate.lower)...Double(estimate.upper)).contains(truth) ? 1 : 0
        }
        XCTAssertGreaterThanOrEqual(inside, 45)
        let models = await calibrator.calibratedModels
        XCTAssertEqual(models, [model])
    }

    func testLearnsANewScriptWhenItArrives() async throws {
        let calibrator = TokenCalibrator()
        var rng = LCG(seed: 21)
        for _ in 0..<40 {
            let features = Fixture.japanesePrompt(&rng)
            _ = try await calibrator.record(features, billedTokens: Fixture.bill(features, rng: &rng), model: model)
        }
        let report = try await calibrator.report(for: model)
        XCTAssertEqual(report.rates.rate(for: .cjk), Fixture.truth.rate(for: .cjk), accuracy: 0.15)
    }

    func testWindowKeepsTheMostRecentErrors() async throws {
        let configuration = try CalibrationConfiguration(windowCapacity: 22, driftWindow: 3)
        let calibrator = TokenCalibrator(configuration: configuration)
        var rng = LCG(seed: 5)
        for _ in 0..<30 {
            let features = Fixture.englishPrompt(&rng)
            _ = try await calibrator.record(features, billedTokens: Fixture.bill(features, rng: &rng), model: model)
        }
        let estimate = try await calibrator.estimate(Fixture.englishPrompt(&rng), model: model)
        XCTAssertEqual(estimate.basis, .calibrated(bills: 22, coverage: 0.9))
        let snapshot = await calibrator.snapshot()
        XCTAssertEqual(snapshot.models[model]?.recentOutside.count, 3)
        XCTAssertEqual(snapshot.models[model]?.residuals.count, 22)
    }

    func testDetectsATokenizerChangeAndStartsAgain() async throws {
        let calibrator = TokenCalibrator()
        var rng = LCG(seed: 3)
        for _ in 0..<60 {
            let features = Fixture.englishPrompt(&rng)
            _ = try await calibrator.record(features, billedTokens: Fixture.bill(features, rng: &rng), model: model)
        }
        var alarm: DriftAlarm?
        var billsAfterChange = 0
        while alarm == nil, billsAfterChange < 40 {
            let features = Fixture.englishPrompt(&rng)
            let billed = Fixture.bill(features, rates: Fixture.upgraded, rng: &rng)
            alarm = try await calibrator.record(features, billedTokens: billed, model: model).drift
            billsAfterChange += 1
        }
        let drift = try XCTUnwrap(alarm)
        XCTAssertEqual(drift.window, 20)
        XCTAssertGreaterThanOrEqual(drift.outside, 8)
        XCTAssertLessThan(drift.pValue, 0.001)
        XCTAssertLessThanOrEqual(billsAfterChange, 12)
        let report = try await calibrator.report(for: model)
        XCTAssertEqual(report.resets, 1)
        XCTAssertEqual(report.bills, 1)
        XCTAssertEqual(report.lifetimeBills, 60 + billsAfterChange)
        XCTAssertEqual(report.checked, 0)
        XCTAssertEqual(report.billsNeeded, 19)
    }
}

func XCTAssertThrowsAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ expected: CalibrationError,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("expected \(expected)", file: file, line: line)
    } catch {
        XCTAssertEqual(error as? CalibrationError, expected, file: file, line: line)
    }
}
