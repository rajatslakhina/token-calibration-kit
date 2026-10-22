/// How a `TokenCalibrator` learns and how much it claims.
public struct CalibrationConfiguration: Hashable, Sendable {
    /// Where every model starts, and what a rate with no evidence stays at.
    public let prior: TokenRates
    /// The share of bills an interval should hold, for example `0.9`.
    public let coverage: Double
    /// How many recent prediction errors the interval is built from.
    public let windowCapacity: Int
    /// How strongly a rate with evidence is still pulled toward the prior, as a share of that
    /// evidence. `0` trusts the bills alone; the prior then only decides rates the bills say nothing about.
    public let shrinkage: Double
    /// The interval used before there are enough bills for a calibrated one, as factors of the point.
    public let priorBandLower: Double
    /// See `priorBandLower`.
    public let priorBandUpper: Double
    /// How many recent bills the drift test looks at. Each is checked against an interval built from
    /// the errors that came before the last `driftWindow` bills, not against the live interval, which a
    /// few drifted bills are enough to stretch over themselves.
    public let driftWindow: Int
    /// How unlikely the recent misses must be, under the claimed coverage, before the calibrator
    /// decides the tokenizer changed and starts again.
    public let driftSignificance: Double
    /// The fewest bills that give a calibrated interval at this coverage.
    public let minimumBills: Int

    /// Validates every value; see each property for its meaning.
    public init(
        prior: TokenRates = .standardPrior,
        coverage: Double = 0.9,
        windowCapacity: Int = 200,
        shrinkage: Double = 0.05,
        priorBandLower: Double = 0.6,
        priorBandUpper: Double = 1.8,
        driftWindow: Int = 20,
        driftSignificance: Double = 0.001
    ) throws {
        guard coverage.isFinite, coverage > 0, coverage < 1 else {
            throw CalibrationError.invalidCoverage(coverage)
        }
        guard windowCapacity > 0 else {
            throw CalibrationError.invalidCount(field: "windowCapacity", value: windowCapacity)
        }
        guard driftWindow > 0 else {
            throw CalibrationError.invalidCount(field: "driftWindow", value: driftWindow)
        }
        let required = ConformalRanks.minimumCount(coverage: coverage)
        // The drift test compares the last `driftWindow` bills with an interval built from the bills
        // before them, so the window has to hold both.
        guard required + driftWindow <= windowCapacity else {
            throw CalibrationError.windowTooSmall(capacity: windowCapacity, required: required + driftWindow)
        }
        guard shrinkage.isFinite, shrinkage >= 0 else {
            throw CalibrationError.invalidRate(field: "shrinkage", value: shrinkage)
        }
        guard priorBandLower.isFinite, priorBandUpper.isFinite, priorBandLower > 0,
              priorBandLower <= 1, priorBandUpper >= 1 else {
            throw CalibrationError.invalidPriorBand(lower: priorBandLower, upper: priorBandUpper)
        }
        guard driftSignificance.isFinite, driftSignificance > 0, driftSignificance < 1 else {
            throw CalibrationError.invalidSignificance(driftSignificance)
        }
        self.prior = prior
        self.coverage = coverage
        self.windowCapacity = windowCapacity
        self.shrinkage = shrinkage
        self.priorBandLower = priorBandLower
        self.priorBandUpper = priorBandUpper
        self.driftWindow = driftWindow
        self.driftSignificance = driftSignificance
        self.minimumBills = required
    }

    private init() {
        prior = .standardPrior
        coverage = 0.9
        windowCapacity = 200
        shrinkage = 0.05
        priorBandLower = 0.6
        priorBandUpper = 1.8
        driftWindow = 20
        driftSignificance = 0.001
        minimumBills = ConformalRanks.minimumCount(coverage: 0.9)
    }

    /// 90% intervals from the last 200 bills, 5% shrinkage, a 0.6x-1.8x band until 19 bills
    /// have arrived, and a drift test over the last 20 checks at p < 0.001.
    public static let standard = CalibrationConfiguration()
}

/// Order statistics for a split-conformal interval over `n` prediction errors.
enum ConformalRanks {
    /// The 1-based ranks of the lower and upper error, or `nil` when `n` errors cannot support the
    /// coverage. The ranks are symmetric: `upper = n + 1 - lower`.
    static func ranks(count: Int, coverage: Double) -> (lower: Int, upper: Int)? {
        let tail = (1 - coverage) / 2
        // The small epsilon keeps 20 * 0.05 from flooring to 0 on binary rounding.
        let lower = Int((Double(count + 1) * tail + 1e-9).rounded(.down))
        guard lower >= 1 else {
            return nil
        }
        return (lower, count + 1 - lower)
    }

    /// The fewest errors that give ranks at this coverage.
    static func minimumCount(coverage: Double) -> Int {
        let tail = (1 - coverage) / 2
        return Int((1 / tail - 1e-9).rounded(.up)) - 1
    }
}
