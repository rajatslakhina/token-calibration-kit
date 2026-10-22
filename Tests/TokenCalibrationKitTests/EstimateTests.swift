@testable import TokenCalibrationKit
import XCTest

final class EstimateTests: XCTestCase {
    private func estimate(_ lower: Int, _ point: Int, _ upper: Int) -> TokenEstimate {
        TokenEstimate(model: "m", point: point, lower: lower, upper: upper, basis: .priorBand(billsNeeded: 3))
    }

    func testBasisLabels() {
        XCTAssertEqual(EstimateBasis.calibrated(bills: 40, coverage: 0.9).label, "calibrated on 40 bills at 90%")
        XCTAssertEqual(EstimateBasis.priorBand(billsNeeded: 7).label, "prior band, 7 more bills to calibrate")
        XCTAssertEqual(EstimateBasis.priorBand(billsNeeded: 1).label, "prior band, 1 more bill to calibrate")
    }

    func testContextFitHasThreeAnswers() throws {
        let fits = try ContextFit(estimate: estimate(900, 1000, 1100), contextWindow: 2000, reservedOutput: 500)
        XCTAssertEqual(fits, .fits(headroom: 400))
        XCTAssertEqual(fits.tokensToTrim, 0)
        XCTAssertEqual(fits.label, "fits, 400 tokens to spare")

        let unsure = try ContextFit(estimate: estimate(900, 1000, 1700), contextWindow: 2000, reservedOutput: 500)
        XCTAssertEqual(unsure, .uncertain(worstCaseOverflow: 200))
        XCTAssertEqual(unsure.tokensToTrim, 200)
        XCTAssertEqual(unsure.label, "may overflow by up to 200 tokens")

        let over = try ContextFit(estimate: estimate(1600, 1700, 1800), contextWindow: 2000, reservedOutput: 500)
        XCTAssertEqual(over, .overflows(by: 100, worstCaseOverflow: 300))
        XCTAssertEqual(over.tokensToTrim, 300)
        XCTAssertEqual(over.label, "overflows by 100 to 300 tokens")

        let edge = try ContextFit(estimate: estimate(1400, 1450, 1500), contextWindow: 2000, reservedOutput: 500)
        XCTAssertEqual(edge, .fits(headroom: 0))
    }

    func testContextFitRejectsNegativeSizes() {
        XCTAssertThrowsError(try ContextFit(estimate: estimate(1, 1, 1), contextWindow: -1, reservedOutput: 0)) {
            XCTAssertEqual($0 as? CalibrationError, .negativeSize(field: "contextWindow", value: -1))
        }
        XCTAssertThrowsError(try ContextFit(estimate: estimate(1, 1, 1), contextWindow: 10, reservedOutput: -5)) {
            XCTAssertEqual($0 as? CalibrationError, .negativeSize(field: "reservedOutput", value: -5))
        }
    }

    func testUpdateAndReportArithmetic() {
        let update = CalibrationUpdate(model: "m", billed: 120, estimate: estimate(80, 100, 130), check: .inside, drift: nil)
        XCTAssertEqual(update.relativeError, 0.2, accuracy: 1e-12)
        let empty = CalibrationUpdate(model: "m", billed: 3, estimate: estimate(0, 0, 0), check: .outside, drift: nil)
        XCTAssertEqual(empty.relativeError, 2, accuracy: 1e-12)

        let fresh = CalibrationReport(
            model: "m", bills: 0, lifetimeBills: 0, resets: 0, rates: .standardPrior,
            checked: 0, inside: 0, billsNeeded: 19
        )
        XCTAssertNil(fresh.empiricalCoverage)
        let seasoned = CalibrationReport(
            model: "m", bills: 50, lifetimeBills: 50, resets: 0, rates: .standardPrior,
            checked: 31, inside: 28, billsNeeded: 0
        )
        XCTAssertEqual(seasoned.empiricalCoverage ?? 0, 28.0 / 31.0, accuracy: 1e-12)
    }
}
