/// Why a calibrator refused an input or a configuration.
public enum CalibrationError: Error, Hashable, Sendable {
    /// A rate was negative, NaN or infinite.
    case invalidRate(field: String, value: Double)
    /// A rate table did not name every scalar class.
    case missingRate(ScalarClass)
    /// Coverage must be strictly between 0 and 1.
    case invalidCoverage(Double)
    /// The window cannot hold enough errors for the requested coverage plus the drift window.
    case windowTooSmall(capacity: Int, required: Int)
    /// The prior band must satisfy `0 < lower <= 1 <= upper`, both finite.
    case invalidPriorBand(lower: Double, upper: Double)
    /// A count that must be positive was not.
    case invalidCount(field: String, value: Int)
    /// The drift significance must be strictly between 0 and 1.
    case invalidSignificance(Double)
    /// A model identifier was empty.
    case emptyModel
    /// A billed token count was negative.
    case negativeBill(Int)
    /// A window or reserved-output size was negative.
    case negativeSize(field: String, value: Int)
    /// A snapshot did not match this configuration or held a value no calibrator could have written.
    case invalidSnapshot(String)
}
