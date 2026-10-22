/// Estimates token counts without a tokenizer and learns each model's real rates from its bills.
///
/// Call `estimate` before a request, to hold a budget or check a context window against the upper
/// end of the interval. Call `record` with the provider's billed count when the response arrives.
/// The calibrator scores every bill against the estimate it would have made without that bill, so the
/// interval is built from honest out-of-sample errors, and it starts again when those errors say the
/// tokenizer changed.
public actor TokenCalibrator {
    /// The configuration every model is calibrated under.
    public nonisolated let configuration: CalibrationConfiguration
    private var calibrations: [String: ModelCalibration] = [:]

    /// A calibrator that knows nothing yet: every model starts at the prior.
    public init(configuration: CalibrationConfiguration = .standard) {
        self.configuration = configuration
    }

    /// A calibrator that resumes from a snapshot taken by one with the same configuration.
    public init(configuration: CalibrationConfiguration = .standard, restoring snapshot: CalibrationSnapshot) throws {
        guard snapshot.version == CalibrationSnapshot.currentVersion else {
            throw CalibrationError.invalidSnapshot(
                "version \(snapshot.version) is not \(CalibrationSnapshot.currentVersion)"
            )
        }
        var restored: [String: ModelCalibration] = [:]
        for (model, state) in snapshot.models {
            guard !model.isEmpty else {
                throw CalibrationError.invalidSnapshot("a model identifier is empty")
            }
            if let problem = state.problem(under: configuration) {
                throw CalibrationError.invalidSnapshot("\(model): \(problem)")
            }
            restored[model] = ModelCalibration(state: state, configuration: configuration)
        }
        self.configuration = configuration
        self.calibrations = restored
    }

    /// The estimate for some features on one model.
    public func estimate(_ features: TextFeatures, model: String) throws -> TokenEstimate {
        try calibration(for: model).estimate(features, model: model)
    }

    /// The estimate for a chat request built from these messages and tool schemas.
    public func estimatePrompt(
        messages: [String],
        toolSchemas: [String] = [],
        model: String
    ) throws -> TokenEstimate {
        try estimate(.prompt(messages: messages, toolSchemas: toolSchemas), model: model)
    }

    /// Learns from one bill: the provider's token count for a request with these features.
    public func record(_ features: TextFeatures, billedTokens: Int, model: String) throws -> CalibrationUpdate {
        guard billedTokens >= 0 else {
            throw CalibrationError.negativeBill(billedTokens)
        }
        var calibration = try calibration(for: model)
        let update = calibration.record(features, billed: billedTokens, model: model)
        calibrations[model] = calibration
        return update
    }

    /// What the calibrator has learned about one model.
    public func report(for model: String) throws -> CalibrationReport {
        try calibration(for: model).report(model: model)
    }

    /// Everything learned so far, to persist and restore later.
    public func snapshot() -> CalibrationSnapshot {
        CalibrationSnapshot(version: CalibrationSnapshot.currentVersion, models: calibrations.mapValues(\.state))
    }

    /// The models that have at least one bill, sorted.
    public var calibratedModels: [String] {
        calibrations.keys.sorted()
    }

    private func calibration(for model: String) throws -> ModelCalibration {
        guard !model.isEmpty else {
            throw CalibrationError.emptyModel
        }
        return calibrations[model] ?? ModelCalibration(configuration: configuration)
    }
}

/// Everything a calibrator has learned, as `Codable` data.
public struct CalibrationSnapshot: Codable, Hashable, Sendable {
    /// The format this version of the package writes and reads.
    public static let currentVersion = 1
    /// The format of this snapshot.
    public let version: Int
    let models: [String: ModelState]

    /// The models in the snapshot, sorted.
    public var modelIDs: [String] {
        models.keys.sorted()
    }
}
