import Foundation
@testable import TokenCalibrationKit
import XCTest

final class SnapshotTests: XCTestCase {
    private let model = "anthropic/claude-sonnet"

    private func trained() async throws -> TokenCalibrator {
        let calibrator = TokenCalibrator()
        var rng = LCG(seed: 42)
        for _ in 0..<30 {
            let features = Fixture.englishPrompt(&rng)
            _ = try await calibrator.record(features, billedTokens: Fixture.bill(features, rng: &rng), model: model)
        }
        return calibrator
    }

    func testRoundTripsThroughJSON() async throws {
        let calibrator = try await trained()
        let snapshot = await calibrator.snapshot()
        XCTAssertEqual(snapshot.version, 1)
        XCTAssertEqual(snapshot.modelIDs, [model])
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(CalibrationSnapshot.self, from: data)
        XCTAssertEqual(decoded, snapshot)
        let restored = try TokenCalibrator(restoring: decoded)
        let features = TextFeatures.prompt(messages: ["Plan the budget for the token window."])
        let original = try await calibrator.estimate(features, model: model)
        let resumed = try await restored.estimate(features, model: model)
        XCTAssertEqual(resumed, original)
        let originalReport = try await calibrator.report(for: model)
        let resumedReport = try await restored.report(for: model)
        XCTAssertEqual(resumedReport, originalReport)
    }

    func testRejectsSnapshotsNoCalibratorWrote() async throws {
        let snapshot = try await trained().snapshot()
        let good = try XCTUnwrap(snapshot.models[model])
        let size = TextFeatures.dimension
        var cases: [(CalibrationSnapshot, String)] = []
        cases.append((CalibrationSnapshot(version: 2, models: [:]), "version 2 is not 1"))
        cases.append((CalibrationSnapshot(version: 1, models: ["": good]), "a model identifier is empty"))
        var state = good
        state.gram.removeLast()
        cases.append((wrap(state), "m: the normal matrix has \(size * size - 1) entries, not \(size * size)"))
        state = good
        state.moment.append(1)
        cases.append((wrap(state), "m: the moment vector has \(size + 1) entries, not \(size)"))
        state = good
        state.residuals[0] = .nan
        cases.append((wrap(state), "m: a stored value is not finite"))
        state = good
        state.residuals += Array(repeating: 0, count: 200)
        state.bills += 200
        state.lifetimeBills += 200
        cases.append((wrap(state), "m: \(good.residuals.count + 200) errors exceed the window"))
        state = good
        state.recentOutside += Array(repeating: false, count: 21)
        cases.append((wrap(state), "m: \(good.recentOutside.count + 21) misses exceed the drift window"))
        state = good
        state.resets = -1
        cases.append((wrap(state), "m: a counter is negative"))
        state = good
        state.inside = state.checked + 1
        cases.append((wrap(state), "m: the counters disagree"))
        for (snapshot, reason) in cases {
            XCTAssertThrowsError(try TokenCalibrator(restoring: snapshot)) {
                XCTAssertEqual($0 as? CalibrationError, .invalidSnapshot(reason))
            }
        }
    }

    private func wrap(_ state: ModelState) -> CalibrationSnapshot {
        CalibrationSnapshot(version: 1, models: ["m": state])
    }
}
