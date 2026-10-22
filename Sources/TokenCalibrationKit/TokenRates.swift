/// Tokens per feature unit: per scalar of each class, per message, per tool and per request.
///
/// A rate table is a linear estimate, `tokens = sum(rate * count)`. The `standardPrior` is a
/// starting point that a `TokenCalibrator` moves away from as bills arrive; it is not a measured
/// tokenizer and should not be quoted as one.
public struct TokenRates: Hashable, Sendable {
    /// Rates in `TextFeatures.vector` order.
    let weights: [Double]

    /// Builds a table. Every scalar class needs a rate; every rate must be finite and non-negative.
    public init(
        perScalar: [ScalarClass: Double],
        perMessage: Double,
        perTool: Double,
        perRequest: Double
    ) throws {
        var weights: [Double] = []
        for scalarClass in ScalarClass.allCases {
            guard let rate = perScalar[scalarClass] else {
                throw CalibrationError.missingRate(scalarClass)
            }
            weights.append(try Self.checked(rate, field: scalarClass.label))
        }
        weights.append(try Self.checked(perMessage, field: "per message"))
        weights.append(try Self.checked(perTool, field: "per tool"))
        weights.append(try Self.checked(perRequest, field: "per request"))
        self.weights = weights
    }

    init(unchecked weights: [Double]) {
        self.weights = weights
    }

    private static func checked(_ value: Double, field: String) throws -> Double {
        guard value.isFinite, value >= 0 else {
            throw CalibrationError.invalidRate(field: field, value: value)
        }
        return value
    }

    /// About 4.5 English letters per token, half a token per digit, most whitespace merged into the
    /// next word, 0.7 per ASCII symbol, 1.2 per CJK character, 0.5 per other letter, 2 per emoji,
    /// 4 per message frame, 8 per tool frame and 3 per request.
    public static let standardPrior = TokenRates(unchecked: [0.22, 0.5, 0.05, 0.7, 1.2, 0.5, 2.0, 1.0, 4, 8, 3])

    /// The rate for one scalar class.
    public func rate(for scalarClass: ScalarClass) -> Double {
        weights[scalarClass.rawValue]
    }

    /// Tokens per chat message frame.
    public var perMessage: Double { weights[ScalarClass.allCases.count] }
    /// Tokens per tool definition frame.
    public var perTool: Double { weights[ScalarClass.allCases.count + 1] }
    /// Tokens per request.
    public var perRequest: Double { weights[ScalarClass.allCases.count + 2] }

    /// The linear estimate for some features, before rounding.
    public func tokens(for features: TextFeatures) -> Double {
        zip(weights, features.vector).reduce(0) { $0 + $1.0 * $1.1 }
    }
}
