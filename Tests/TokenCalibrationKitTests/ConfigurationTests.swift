@testable import TokenCalibrationKit
import XCTest

final class ConfigurationTests: XCTestCase {
    func testStandardConfiguration() throws {
        let standard = CalibrationConfiguration.standard
        XCTAssertEqual(standard.coverage, 0.9)
        XCTAssertEqual(standard.windowCapacity, 200)
        XCTAssertEqual(standard.minimumBills, 19)
        XCTAssertEqual(standard.driftWindow, 20)
        XCTAssertEqual(standard, try CalibrationConfiguration())
    }

    func testRanksNeedEnoughErrors() {
        XCTAssertNil(ConformalRanks.ranks(count: 18, coverage: 0.9))
        XCTAssertEqual(ConformalRanks.ranks(count: 19, coverage: 0.9)?.lower, 1)
        XCTAssertEqual(ConformalRanks.ranks(count: 19, coverage: 0.9)?.upper, 19)
        XCTAssertEqual(ConformalRanks.ranks(count: 39, coverage: 0.9)?.lower, 2)
        XCTAssertEqual(ConformalRanks.ranks(count: 39, coverage: 0.9)?.upper, 38)
        XCTAssertEqual(ConformalRanks.minimumCount(coverage: 0.8), 9)
        XCTAssertEqual(ConformalRanks.minimumCount(coverage: 0.95), 39)
    }

    func testRejectsEachBadValue() {
        let cases: [(() throws -> CalibrationConfiguration, CalibrationError)] = [
            ({ try CalibrationConfiguration(coverage: 1) }, .invalidCoverage(1)),
            ({ try CalibrationConfiguration(coverage: 0) }, .invalidCoverage(0)),
            ({ try CalibrationConfiguration(windowCapacity: 0) }, .invalidCount(field: "windowCapacity", value: 0)),
            ({ try CalibrationConfiguration(coverage: 0.99, windowCapacity: 50) },
             .windowTooSmall(capacity: 50, required: 219)),
            ({ try CalibrationConfiguration(windowCapacity: 38) }, .windowTooSmall(capacity: 38, required: 39)),
            ({ try CalibrationConfiguration(shrinkage: -0.1) }, .invalidRate(field: "shrinkage", value: -0.1)),
            ({ try CalibrationConfiguration(priorBandLower: 1.2) }, .invalidPriorBand(lower: 1.2, upper: 1.8)),
            ({ try CalibrationConfiguration(priorBandUpper: 0.9) }, .invalidPriorBand(lower: 0.6, upper: 0.9)),
            ({ try CalibrationConfiguration(priorBandLower: 0) }, .invalidPriorBand(lower: 0, upper: 1.8)),
            ({ try CalibrationConfiguration(driftWindow: 0) }, .invalidCount(field: "driftWindow", value: 0)),
            ({ try CalibrationConfiguration(driftSignificance: 1) }, .invalidSignificance(1))
        ]
        for (make, expected) in cases {
            XCTAssertThrowsError(try make()) { XCTAssertEqual($0 as? CalibrationError, expected) }
        }
        XCTAssertThrowsError(try CalibrationConfiguration(coverage: .nan))
        XCTAssertThrowsError(try CalibrationConfiguration(priorBandUpper: .infinity))
        XCTAssertThrowsError(try CalibrationConfiguration(driftSignificance: .nan))
    }

    func testCustomConfiguration() throws {
        let custom = try CalibrationConfiguration(coverage: 0.8, windowCapacity: 14, shrinkage: 0, driftWindow: 5)
        XCTAssertEqual(custom.minimumBills, 9)
        XCTAssertEqual(custom.shrinkage, 0)
    }
}
