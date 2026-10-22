/// A token count before the bill: a point and an interval, and where the interval came from.
public struct TokenEstimate: Hashable, Sendable {
    /// The model the estimate is for.
    public let model: String
    /// The single best guess.
    public let point: Int
    /// The low end of the interval.
    public let lower: Int
    /// The high end of the interval. Hold budgets and check context windows against this one.
    public let upper: Int
    /// Whether the interval was measured from this model's bills or is still the prior band.
    public let basis: EstimateBasis
}

/// Where an interval came from.
public enum EstimateBasis: Hashable, Sendable {
    /// Built from this many recent prediction errors on real bills, at this coverage.
    case calibrated(bills: Int, coverage: Double)
    /// The configuration's prior band, because this many more bills are needed first.
    case priorBand(billsNeeded: Int)

    /// A short description for logs and diagnostics.
    public var label: String {
        switch self {
        case let .calibrated(bills, coverage):
            "calibrated on \(bills) bills at \(Int((coverage * 100).rounded()))%"
        case let .priorBand(needed):
            "prior band, \(needed) more \(needed == 1 ? "bill" : "bills") to calibrate"
        }
    }
}

/// Whether a request fits a model's context window once its output is reserved.
public enum ContextFit: Hashable, Sendable {
    /// Even the upper estimate fits, with this many tokens to spare.
    case fits(headroom: Int)
    /// The lower estimate fits and the upper one does not: it overflows by up to this many tokens.
    case uncertain(worstCaseOverflow: Int)
    /// Even the lower estimate does not fit: it overflows by at least `by` tokens and at most
    /// `worstCaseOverflow`.
    case overflows(by: Int, worstCaseOverflow: Int)

    /// Compares the estimate with `contextWindow - reservedOutput`.
    public init(estimate: TokenEstimate, contextWindow: Int, reservedOutput: Int) throws {
        guard contextWindow >= 0 else {
            throw CalibrationError.negativeSize(field: "contextWindow", value: contextWindow)
        }
        guard reservedOutput >= 0 else {
            throw CalibrationError.negativeSize(field: "reservedOutput", value: reservedOutput)
        }
        let available = contextWindow - reservedOutput
        if estimate.upper <= available {
            self = .fits(headroom: available - estimate.upper)
        } else if estimate.lower > available {
            self = .overflows(by: estimate.lower - available, worstCaseOverflow: estimate.upper - available)
        } else {
            self = .uncertain(worstCaseOverflow: estimate.upper - available)
        }
    }

    /// How many tokens, measured at the upper estimate, to remove before sending. Zero when it fits.
    public var tokensToTrim: Int {
        switch self {
        case .fits:
            0
        case let .uncertain(overflow), let .overflows(_, overflow):
            overflow
        }
    }

    /// A short description for logs and diagnostics.
    public var label: String {
        switch self {
        case let .fits(headroom):
            "fits, \(headroom) tokens to spare"
        case let .uncertain(overflow):
            "may overflow by up to \(overflow) tokens"
        case let .overflows(least, most):
            "overflows by \(least) to \(most) tokens"
        }
    }
}
