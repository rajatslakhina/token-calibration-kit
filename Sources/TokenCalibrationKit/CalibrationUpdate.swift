/// What one bill taught the calibrator.
public struct CalibrationUpdate: Hashable, Sendable {
    /// The model billed.
    public let model: String
    /// The token count the provider billed.
    public let billed: Int
    /// The estimate the calibrator would have given for this request just before the bill arrived.
    /// Its error is an honest out-of-sample error, because the bill had not been learned from yet.
    public let estimate: TokenEstimate
    /// Whether the bill fell inside that estimate's interval.
    public let check: IntervalCheck
    /// Set when this bill completed evidence that the tokenizer changed. The model's calibration was
    /// cleared and restarted from this bill.
    public let drift: DriftAlarm?

    /// `billed / point - 1`: positive when the estimate was low.
    public var relativeError: Double {
        Double(billed) / Double(max(estimate.point, 1)) - 1
    }
}

/// Whether a bill fell inside the interval estimated for it.
public enum IntervalCheck: Hashable, Sendable {
    case inside
    case outside
    /// The interval was still the prior band, so it was not counted.
    case noInterval
}

/// Evidence that the model's tokenizer or framing changed under the calibrator.
public struct DriftAlarm: Hashable, Sendable {
    /// Bills outside the reference interval among the last `window` bills.
    public let outside: Int
    /// How many checks the test looked at.
    public let window: Int
    /// The chance of at least `outside` misses in `window` if the claimed coverage were true.
    public let pValue: Double
}

/// One model's calibration, for diagnostics.
public struct CalibrationReport: Hashable, Sendable {
    /// The model.
    public let model: String
    /// Bills learned from since the last drift reset.
    public let bills: Int
    /// Bills learned from in total.
    public let lifetimeBills: Int
    /// How many times drift cleared the calibration.
    public let resets: Int
    /// The rates now in use.
    public let rates: TokenRates
    /// Bills that arrived while a calibrated interval existed for them.
    public let checked: Int
    /// How many of those fell inside it.
    public let inside: Int
    /// Bills still needed before intervals are calibrated; zero once they are.
    public let billsNeeded: Int

    /// `inside / checked`, or `nil` before anything was checked.
    public var empiricalCoverage: Double? {
        checked == 0 ? nil : Double(inside) / Double(checked)
    }
}
