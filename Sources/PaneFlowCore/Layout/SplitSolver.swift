import CoreGraphics

/// Per-pane constraints along one axis.
public struct PaneConstraint: Sendable, Equatable {
    public var minimum: CGFloat
    public var maximum: CGFloat?

    public init(minimum: CGFloat = 0, maximum: CGFloat? = nil) {
        self.minimum = max(0, minimum)
        self.maximum = maximum
    }

    public static let unconstrained = PaneConstraint()
}

public enum SplitSolution: Sendable, Equatable {
    /// Sizes summing exactly to the available length. `adjusted` is true when constraints
    /// forced a deviation from the requested fractions.
    case feasible(sizes: [CGFloat], adjusted: Bool)
    case infeasible(Infeasibility)
}

public enum Infeasibility: Sendable, Equatable {
    case invalidInput
    /// Minimums plus gaps exceed the available length.
    case minimumsExceedSpace(required: CGFloat, available: CGFloat)
    /// Maximums cannot fill the available length.
    case maximumsBelowSpace(maximumTotal: CGFloat, available: CGFloat)
}

/// One-dimensional constraint solver: distributes a length between panes according to desired
/// fractions while honouring minimum/maximum sizes. Foundation of `SnapConstraintSolver` (Phase 5).
///
/// Water-filling formulation: every pane gets `level × fraction` clamped to its bounds, and the
/// common `level` is chosen so that the panes exactly fill the available length.
public enum SplitSolver {
    public static func solve(
        length: CGFloat,
        gap: CGFloat = 0,
        fractions: [CGFloat],
        constraints: [PaneConstraint]
    ) -> SplitSolution {
        let n = fractions.count
        guard n > 0, constraints.count == n, length > 0, gap >= 0,
              fractions.allSatisfy({ $0 > 0 }) else { return .infeasible(.invalidInput) }

        let available = length - gap * CGFloat(n - 1)
        let minTotal = constraints.reduce(0) { $0 + $1.minimum }
        guard minTotal <= available + 1e-9 else {
            return .infeasible(.minimumsExceedSpace(required: minTotal + gap * CGFloat(n - 1), available: length))
        }
        if constraints.allSatisfy({ $0.maximum != nil }) {
            let maxTotal = constraints.reduce(0) { $0 + ($1.maximum ?? 0) }
            if maxTotal < available - 1e-9 {
                return .infeasible(.maximumsBelowSpace(maximumTotal: maxTotal, available: available))
            }
        }

        let fractionTotal = fractions.reduce(0, +)
        let weights = fractions.map { $0 / fractionTotal }

        // size_i(level) = clamp(level * weight_i, min_i, max_i) is monotone in `level`, so the level
        // whose sizes sum to `available` is found by bisection. Fixed iteration count: no oscillation.
        func sizes(at level: CGFloat) -> [CGFloat] {
            (0..<n).map { i in
                let raw = level * weights[i]
                let lower = max(raw, constraints[i].minimum)
                return constraints[i].maximum.map { min(lower, max($0, constraints[i].minimum)) } ?? lower
            }
        }
        var low: CGFloat = 0
        var high: CGFloat = available / (weights.min() ?? 1) + 1
        for _ in 0..<100 {
            let mid = (low + high) / 2
            if sizes(at: mid).reduce(0, +) < available { low = mid } else { high = mid }
        }
        let solved = sizes(at: high)

        // Whole points, with any rounding remainder given to the last pane.
        var rounded = solved.map { $0.rounded() }
        rounded[n - 1] += available.rounded() - rounded.reduce(0, +)

        let adjusted = zip(rounded, weights).contains { abs($0 - available * $1) > 1 }
        return .feasible(sizes: rounded, adjusted: adjusted)
    }
}
