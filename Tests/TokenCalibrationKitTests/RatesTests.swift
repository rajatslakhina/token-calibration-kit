@testable import TokenCalibrationKit
import XCTest

final class RatesTests: XCTestCase {
    private func allClasses(_ value: Double) -> [ScalarClass: Double] {
        Dictionary(uniqueKeysWithValues: ScalarClass.allCases.map { ($0, value) })
    }

    func testBuildsAndReadsRates() throws {
        var perScalar = allClasses(0.5)
        perScalar[.cjk] = 1.5
        let rates = try TokenRates(perScalar: perScalar, perMessage: 4, perTool: 9, perRequest: 2)
        XCTAssertEqual(rates.rate(for: .cjk), 1.5)
        XCTAssertEqual(rates.rate(for: .digit), 0.5)
        XCTAssertEqual(rates.perMessage, 4)
        XCTAssertEqual(rates.perTool, 9)
        XCTAssertEqual(rates.perRequest, 2)
        let tokens = rates.tokens(for: .prompt(messages: ["日本"], toolSchemas: ["x"]))
        XCTAssertEqual(tokens, 1.5 * 2 + 0.5 + 4 + 9 + 2, accuracy: 1e-9)
    }

    func testRejectsBadRates() {
        var missing = allClasses(1)
        missing[.emoji] = nil
        XCTAssertThrowsError(try TokenRates(perScalar: missing, perMessage: 1, perTool: 1, perRequest: 1)) {
            XCTAssertEqual($0 as? CalibrationError, .missingRate(.emoji))
        }
        var negative = allClasses(1)
        negative[.digit] = -1
        XCTAssertThrowsError(try TokenRates(perScalar: negative, perMessage: 1, perTool: 1, perRequest: 1)) {
            XCTAssertEqual($0 as? CalibrationError, .invalidRate(field: "digit", value: -1))
        }
        let rates = allClasses(1)
        XCTAssertThrowsError(try TokenRates(perScalar: rates, perMessage: .nan, perTool: 1, perRequest: 1))
        XCTAssertThrowsError(try TokenRates(perScalar: rates, perMessage: 1, perTool: .infinity, perRequest: 1))
        XCTAssertThrowsError(try TokenRates(perScalar: rates, perMessage: 1, perTool: 1, perRequest: -2)) {
            XCTAssertEqual($0 as? CalibrationError, .invalidRate(field: "per request", value: -2))
        }
    }

    func testStandardPriorReadsAsDocumented() {
        let prior = TokenRates.standardPrior
        XCTAssertEqual(prior.rate(for: .asciiLetter), 0.22)
        XCTAssertEqual(prior.rate(for: .cjk), 1.2)
        XCTAssertEqual(prior.rate(for: .emoji), 2)
        XCTAssertEqual(prior.perMessage, 4)
        XCTAssertEqual(prior.perTool, 8)
        XCTAssertEqual(prior.perRequest, 3)
    }
}
