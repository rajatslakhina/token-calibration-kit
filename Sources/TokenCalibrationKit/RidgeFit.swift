import Foundation

/// The rate fit: weighted least squares on the bills, anchored to the prior.
///
/// Each bill `y` with features `x` adds `x * x' / y` and `x * y / y` to the normal equations, so the
/// fit minimises relative rather than absolute error and a long prompt does not drown out short ones.
/// Every rate is pulled toward its prior by `shrinkage` times its own evidence plus a small fixed
/// anchor, so a class no bill has contained (CJK, before the first Japanese message) stays exactly at
/// the prior. The matrix is then positive definite and a Cholesky solve always succeeds.
enum RidgeFit {
    static func fit(gram: [Double], moment: [Double], prior: TokenRates, shrinkage: Double) -> TokenRates {
        let size = TextFeatures.dimension
        var matrix = gram
        var right = moment
        for index in 0..<size {
            let center = prior.weights[index]
            let scale = max(center, 0.05)
            let anchor = shrinkage * gram[index * size + index] + 1 / (scale * scale)
            matrix[index * size + index] += anchor
            right[index] += anchor * center
        }
        // A negative rate would let more text cost fewer tokens; clamp it to zero.
        return TokenRates(unchecked: solve(matrix, right, size: size).map { max(0, $0) })
    }

    /// Adds one bill to the normal equations.
    static func accumulate(
        _ features: TextFeatures,
        billed: Int,
        gram: inout [Double],
        moment: inout [Double]
    ) {
        let size = TextFeatures.dimension
        let vector = features.vector
        let weight = 1 / Double(max(billed, 1))
        for row in 0..<size where vector[row] != 0 {
            moment[row] += weight * vector[row] * Double(billed)
            for column in 0..<size {
                gram[row * size + column] += weight * vector[row] * vector[column]
            }
        }
    }

    /// Solves `matrix * x = right` for a symmetric positive-definite `matrix` by Cholesky.
    static func solve(_ matrix: [Double], _ right: [Double], size: Int) -> [Double] {
        var lower = [Double](repeating: 0, count: size * size)
        for column in 0..<size {
            var diagonal = matrix[column * size + column]
            for inner in 0..<column {
                diagonal -= lower[column * size + inner] * lower[column * size + inner]
            }
            let pivot = max(diagonal, .leastNormalMagnitude).squareRoot()
            lower[column * size + column] = pivot
            for row in (column + 1)..<size {
                var sum = matrix[row * size + column]
                for inner in 0..<column {
                    sum -= lower[row * size + inner] * lower[column * size + inner]
                }
                lower[row * size + column] = sum / pivot
            }
        }
        var forward = [Double](repeating: 0, count: size)
        for row in 0..<size {
            var sum = right[row]
            for inner in 0..<row {
                sum -= lower[row * size + inner] * forward[inner]
            }
            forward[row] = sum / lower[row * size + row]
        }
        var solution = forward
        for row in stride(from: size - 1, through: 0, by: -1) {
            var sum = forward[row]
            for inner in (row + 1)..<size {
                sum -= lower[inner * size + row] * solution[inner]
            }
            solution[row] = sum / lower[row * size + row]
        }
        return solution
    }
}

/// The drift test: how surprising the recent misses are if the claimed coverage holds.
enum DriftTest {
    /// `P(X >= atLeast)` for `X ~ Binomial(trials, probability)`, with `0 < probability < 1`.
    static func upperTail(atLeast: Int, trials: Int, probability: Double) -> Double {
        var mass = pow(1 - probability, Double(trials))
        var tail = 0.0
        for successes in 0...trials {
            if successes >= atLeast {
                tail += mass
            }
            mass *= Double(trials - successes) / Double(successes + 1) * probability / (1 - probability)
        }
        return min(tail, 1)
    }
}
