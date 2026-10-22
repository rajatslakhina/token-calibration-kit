@testable import TokenCalibrationKit
import XCTest

final class FitTests: XCTestCase {
    private let size = TextFeatures.dimension

    func testSolvesASymmetricSystem() {
        // [4 2; 2 3] x = [2; 5] has x = [-0.5, 2].
        let solution = RidgeFit.solve([4, 2, 2, 3], [2, 5], size: 2)
        XCTAssertEqual(solution[0], -0.5, accuracy: 1e-12)
        XCTAssertEqual(solution[1], 2, accuracy: 1e-12)
    }

    func testNoBillsGivesThePrior() {
        let fitted = RidgeFit.fit(
            gram: Array(repeating: 0, count: size * size),
            moment: Array(repeating: 0, count: size),
            prior: .standardPrior,
            shrinkage: 0.05
        )
        for (fit, prior) in zip(fitted.weights, TokenRates.standardPrior.weights) {
            XCTAssertEqual(fit, prior, accuracy: 1e-12)
        }
    }

    func testRecoversTheTruthOnNewPrompts() {
        var gram = Array(repeating: 0.0, count: size * size)
        var moment = Array(repeating: 0.0, count: size)
        var rng = LCG(seed: 11)
        for _ in 0..<200 {
            let features = Fixture.englishPrompt(&rng)
            let billed = Int(Fixture.truth.tokens(for: features).rounded())
            RidgeFit.accumulate(features, billed: billed, gram: &gram, moment: &moment)
        }
        let fitted = RidgeFit.fit(gram: gram, moment: moment, prior: .standardPrior, shrinkage: 0)
        var check = LCG(seed: 99)
        for _ in 0..<20 {
            let features = Fixture.englishPrompt(&check)
            XCTAssertEqual(fitted.tokens(for: features) / Fixture.truth.tokens(for: features), 1, accuracy: 0.03)
        }
        // No bill held CJK text, so its rate never moved.
        XCTAssertEqual(fitted.rate(for: .cjk), TokenRates.standardPrior.rate(for: .cjk), accuracy: 1e-12)
    }

    func testClampsANegativeRateToZero() {
        var gram = Array(repeating: 0.0, count: size * size)
        var moment = Array(repeating: 0.0, count: size)
        // More letters, fewer tokens: the unconstrained slope is negative.
        let short = TextFeatures.prompt(messages: [String(repeating: "a", count: 10)])
        let long = TextFeatures.prompt(messages: [String(repeating: "a", count: 400)])
        for _ in 0..<50 {
            RidgeFit.accumulate(short, billed: 60, gram: &gram, moment: &moment)
            RidgeFit.accumulate(long, billed: 20, gram: &gram, moment: &moment)
        }
        let fitted = RidgeFit.fit(gram: gram, moment: moment, prior: .standardPrior, shrinkage: 0)
        XCTAssertEqual(fitted.rate(for: .asciiLetter), 0)
    }

    func testZeroBillStillCounts() {
        var gram = Array(repeating: 0.0, count: size * size)
        var moment = Array(repeating: 0.0, count: size)
        RidgeFit.accumulate(TextFeatures(text: "ab"), billed: 0, gram: &gram, moment: &moment)
        XCTAssertEqual(gram[0], 4)
        XCTAssertEqual(moment[0], 0)
        XCTAssertEqual(gram[size + 1], 0)
    }

    func testBinomialTail() {
        XCTAssertEqual(DriftTest.upperTail(atLeast: 0, trials: 20, probability: 0.1), 1, accuracy: 1e-12)
        XCTAssertEqual(DriftTest.upperTail(atLeast: 21, trials: 20, probability: 0.1), 0)
        XCTAssertEqual(
            DriftTest.upperTail(atLeast: 1, trials: 20, probability: 0.1),
            1 - pow(0.9, 20),
            accuracy: 1e-12
        )
        XCTAssertLessThan(DriftTest.upperTail(atLeast: 8, trials: 20, probability: 0.1), 0.001)
        XCTAssertGreaterThan(DriftTest.upperTail(atLeast: 7, trials: 20, probability: 0.1), 0.001)
    }
}
