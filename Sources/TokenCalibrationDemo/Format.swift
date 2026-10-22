import Foundation
import TokenCalibrationKit

enum Format {
    /// `+12.3%` style.
    static func signed(_ value: Double) -> String {
        String(format: "%+.1f%%", value * 100)
    }

    static func percent(_ value: Double) -> String {
        String(format: "%.1f%%", value * 100)
    }

    static func rate(_ value: Double) -> String {
        String(format: "%.3f", value)
    }

    static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        let middle = sorted.count / 2
        return sorted.count % 2 == 1 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2
    }

    static func padded(_ text: String, _ width: Int) -> String {
        text.count >= width ? text : text + String(repeating: " ", count: width - text.count)
    }

    static func heading(_ title: String) {
        print("")
        print("== \(title)")
    }
}

/// One bill as the demo saw it: what the flat ratio said, what the calibrator said before the bill
/// arrived, and what was billed.
struct BilledRow {
    let kind: ChatRequest.Kind
    let flat: Int
    let estimate: TokenEstimate
    let billed: Int
    let check: IntervalCheck

    var flatError: Double { Double(flat) / Double(billed) - 1 }
    var calibratedError: Double { Double(estimate.point) / Double(billed) - 1 }
}
