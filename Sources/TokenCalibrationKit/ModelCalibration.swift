import Foundation

/// One model's learned state, as a snapshot stores it.
///
/// The normal equations stand in for the bills themselves, so the state stays the same size however
/// many bills arrive. The prediction errors are kept as `log(billed / estimate)`, each measured before
/// its bill was learned from.
public struct ModelState: Codable, Hashable, Sendable {
    var gram: [Double]
    var moment: [Double]
    var residuals: [Double]
    var recentOutside: [Bool]
    var bills: Int
    var lifetimeBills: Int
    var resets: Int
    var checked: Int
    var inside: Int

    static func fresh(resets: Int = 0, lifetimeBills: Int = 0) -> ModelState {
        let size = TextFeatures.dimension
        return ModelState(
            gram: Array(repeating: 0, count: size * size),
            moment: Array(repeating: 0, count: size),
            residuals: [],
            recentOutside: [],
            bills: 0,
            lifetimeBills: lifetimeBills,
            resets: resets,
            checked: 0,
            inside: 0
        )
    }

    /// Why this state could not have been written by a calibrator with this configuration, or `nil`.
    func problem(under configuration: CalibrationConfiguration) -> String? {
        let size = TextFeatures.dimension
        let checks: [(holds: Bool, reason: String)] = [
            (gram.count == size * size, "the normal matrix has \(gram.count) entries, not \(size * size)"),
            (moment.count == size, "the moment vector has \(moment.count) entries, not \(size)"),
            ((gram + moment + residuals).allSatisfy(\.isFinite), "a stored value is not finite"),
            (residuals.count <= configuration.windowCapacity, "\(residuals.count) errors exceed the window"),
            (recentOutside.count <= configuration.driftWindow, "\(recentOutside.count) misses exceed the drift window"),
            (min(bills, resets, checked, inside) >= 0, "a counter is negative"),
            (inside <= checked && residuals.count <= bills && bills <= lifetimeBills, "the counters disagree")
        ]
        return checks.first { !$0.holds }?.reason
    }
}

/// The estimator and learner for one model.
struct ModelCalibration: Sendable {
    private(set) var state: ModelState
    private(set) var rates: TokenRates
    let configuration: CalibrationConfiguration

    init(configuration: CalibrationConfiguration) {
        self.state = .fresh()
        self.rates = configuration.prior
        self.configuration = configuration
    }

    init(state: ModelState, configuration: CalibrationConfiguration) {
        self.state = state
        self.configuration = configuration
        self.rates = RidgeFit.fit(
            gram: state.gram,
            moment: state.moment,
            prior: configuration.prior,
            shrinkage: configuration.shrinkage
        )
    }

    /// The point is the fitted rates corrected by the median recent error; the interval comes from
    /// the order statistics of the recent errors, or from the prior band until there are enough.
    ///
    /// Recent errors only describe text like the text that was billed. The part of the estimate that
    /// comes from feature classes no bill has contained is bounded by the prior band instead, because
    /// its rate is still the prior's guess: in 1.0.0 a request full of digits, sent to a model that had
    /// only been billed for prose, got a tight interval that missed its bill by a third.
    func estimate(_ features: TextFeatures, model: String) -> TokenEstimate {
        let raw = max(0, rates.tokens(for: features))
        let unfamiliar = unfamiliarTokens(in: features)
        guard let ranks = ConformalRanks.ranks(count: state.residuals.count, coverage: configuration.coverage) else {
            return TokenEstimate(
                model: model,
                point: Int(raw.rounded()),
                lower: Int((raw * configuration.priorBandLower).rounded(.down)),
                upper: Int((raw * configuration.priorBandUpper).rounded(.up)),
                basis: .priorBand(billsNeeded: configuration.minimumBills - state.residuals.count),
                unfamiliarTokens: Int(unfamiliar.rounded())
            )
        }
        let sorted = state.residuals.sorted()
        let familiar = max(0, raw - unfamiliar)
        func bound(_ error: Double, _ band: Double) -> Double {
            familiar * exp(error) + unfamiliar * band
        }
        return TokenEstimate(
            model: model,
            point: Int(bound(sorted[(sorted.count - 1) / 2], 1).rounded()),
            lower: Int(bound(sorted[ranks.lower - 1], configuration.priorBandLower).rounded(.down)),
            upper: Int(bound(sorted[ranks.upper - 1], configuration.priorBandUpper).rounded(.up)),
            basis: .calibrated(bills: sorted.count, coverage: configuration.coverage),
            unfamiliarTokens: Int(unfamiliar.rounded())
        )
    }

    /// Tokens at the current rates from features no bill has contained. A feature has been billed
    /// when its diagonal entry in the normal equations is non-zero.
    private func unfamiliarTokens(in features: TextFeatures) -> Double {
        let size = TextFeatures.dimension
        let vector = features.vector
        var total = 0.0
        for index in 0..<size where vector[index] > 0 && state.gram[index * size + index] == 0 {
            total += rates.weights[index] * vector[index]
        }
        return total
    }

    /// Scores the bill against the estimate made without it, then learns from it.
    mutating func record(_ features: TextFeatures, billed: Int, model: String) -> CalibrationUpdate {
        let before = estimate(features, model: model)
        var check = IntervalCheck.noInterval
        if case .calibrated = before.basis {
            let inside = (before.lower...before.upper).contains(billed)
            check = inside ? .inside : .outside
            state.checked += 1
            state.inside += inside ? 1 : 0
        }
        let residual = log(Double(max(billed, 1)) / max(rates.tokens(for: features), 1))
        if let missed = missesReference(residual) {
            state.recentOutside.append(missed)
            if state.recentOutside.count > configuration.driftWindow {
                state.recentOutside.removeFirst()
            }
        }
        state.residuals.append(residual)
        if state.residuals.count > configuration.windowCapacity {
            state.residuals.removeFirst()
        }
        state.lifetimeBills += 1
        learn(features, billed: billed)
        let alarm = driftAlarm()
        if alarm != nil {
            // The old bills describe a tokenizer that is gone. Start again from the prior and keep
            // only this bill, which was billed by the new one.
            state = .fresh(resets: state.resets + 1, lifetimeBills: state.lifetimeBills)
            learn(features, billed: billed)
        }
        return CalibrationUpdate(model: model, billed: billed, estimate: before, check: check, drift: alarm)
    }

    func report(model: String) -> CalibrationReport {
        CalibrationReport(
            model: model,
            bills: state.bills,
            lifetimeBills: state.lifetimeBills,
            resets: state.resets,
            rates: rates,
            checked: state.checked,
            inside: state.inside,
            billsNeeded: max(0, configuration.minimumBills - state.residuals.count)
        )
    }

    private mutating func learn(_ features: TextFeatures, billed: Int) {
        RidgeFit.accumulate(features, billed: billed, gram: &state.gram, moment: &state.moment)
        state.bills += 1
        rates = RidgeFit.fit(
            gram: state.gram,
            moment: state.moment,
            prior: configuration.prior,
            shrinkage: configuration.shrinkage
        )
    }

    /// Whether an error falls outside the interval built from the errors older than the last
    /// `driftWindow`, or `nil` while there are not enough of them.
    private func missesReference(_ residual: Double) -> Bool? {
        let referenceCount = state.residuals.count - configuration.driftWindow
        guard let ranks = ConformalRanks.ranks(count: referenceCount, coverage: configuration.coverage) else {
            return nil
        }
        let reference = state.residuals.prefix(referenceCount).sorted()
        return residual < reference[ranks.lower - 1] || residual > reference[ranks.upper - 1]
    }

    private func driftAlarm() -> DriftAlarm? {
        guard state.recentOutside.count == configuration.driftWindow else {
            return nil
        }
        let outside = state.recentOutside.filter { $0 }.count
        let pValue = DriftTest.upperTail(
            atLeast: outside,
            trials: configuration.driftWindow,
            probability: 1 - configuration.coverage
        )
        guard pValue < configuration.driftSignificance else {
            return nil
        }
        return DriftAlarm(outside: outside, window: configuration.driftWindow, pValue: pValue)
    }
}
