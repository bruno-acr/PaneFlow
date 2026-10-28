import CoreGraphics
import XCTest
@testable import PaneFlowCore

final class SplitSolverTests: XCTestCase {
    private func sizes(_ s: SplitSolution) -> [CGFloat]? {
        if case let .feasible(sizes, _) = s { sizes } else { nil }
    }

    func testUnconstrainedFollowsFractions() {
        let s = SplitSolver.solve(length: 1470, fractions: [0.5, 0.5], constraints: [.unconstrained, .unconstrained])
        XCTAssertEqual(s, .feasible(sizes: [735, 735], adjusted: false))
        let r = SplitSolver.solve(length: 1000, fractions: [0.4, 0.6], constraints: [.unconstrained, .unconstrained])
        XCTAssertEqual(r, .feasible(sizes: [400, 600], adjusted: false))
    }

    func testGapIsSubtracted() {
        let s = SplitSolver.solve(length: 1010, gap: 10, fractions: [1, 1], constraints: [.unconstrained, .unconstrained])
        XCTAssertEqual(sizes(s), [500, 500])
    }

    func testMinimumPushesOtherPane() {
        // Word refuses to be narrower than 500 pt: 30/70 of 1000 becomes 500/500.
        let s = SplitSolver.solve(length: 1000, fractions: [0.3, 0.7],
                                  constraints: [PaneConstraint(minimum: 500), .unconstrained])
        XCTAssertEqual(s, .feasible(sizes: [500, 500], adjusted: true))
    }

    func testMinimumAndMaximumTogether() {
        // The case that breaks naive single-pass clamping.
        let s = SplitSolver.solve(length: 100, fractions: [0.5, 0.5],
                                  constraints: [PaneConstraint(minimum: 70), PaneConstraint(maximum: 20)])
        XCTAssertEqual(sizes(s), [80, 20])
    }

    func testThreePanesWithOneMaximum() {
        let s = SplitSolver.solve(length: 900, fractions: [1, 1, 1],
                                  constraints: [.unconstrained, PaneConstraint(maximum: 100), .unconstrained])
        XCTAssertEqual(sizes(s), [400, 100, 400])
    }

    func testInfeasibleMinimums() {
        let s = SplitSolver.solve(length: 800, gap: 10, fractions: [0.5, 0.5],
                                  constraints: [PaneConstraint(minimum: 500), PaneConstraint(minimum: 300)])
        XCTAssertEqual(s, .infeasible(.minimumsExceedSpace(required: 810, available: 800)))
    }

    func testInfeasibleMaximums() {
        let s = SplitSolver.solve(length: 800, fractions: [0.5, 0.5],
                                  constraints: [PaneConstraint(maximum: 300), PaneConstraint(maximum: 300)])
        XCTAssertEqual(s, .infeasible(.maximumsBelowSpace(maximumTotal: 600, available: 800)))
    }

    func testInvalidInput() {
        XCTAssertEqual(SplitSolver.solve(length: 100, fractions: [], constraints: []), .infeasible(.invalidInput))
        XCTAssertEqual(SplitSolver.solve(length: 100, fractions: [0.5, 0], constraints: [.unconstrained, .unconstrained]), .infeasible(.invalidInput))
        XCTAssertEqual(SplitSolver.solve(length: 100, fractions: [1], constraints: []), .infeasible(.invalidInput))
    }

    func testSizesAlwaysSumToAvailableAndRespectBounds() {
        // Deterministic pseudo-random sweep.
        var seed: UInt64 = 42
        func next() -> CGFloat {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat(seed >> 33) / CGFloat(1 << 31)
        }
        for _ in 0..<500 {
            let n = 2 + Int(next() * 3)
            let length = 600 + (next() * 2400).rounded()
            let fractions = (0..<n).map { _ in 0.1 + next() }
            let constraints = (0..<n).map { _ in PaneConstraint(minimum: (next() * 300).rounded()) }
            guard case let .feasible(result, _) = SplitSolver.solve(length: length, gap: 8, fractions: fractions, constraints: constraints) else {
                continue
            }
            XCTAssertEqual(result.reduce(0, +), length - 8 * CGFloat(n - 1), accuracy: 0.001)
            for (size, c) in zip(result, constraints) {
                XCTAssertGreaterThanOrEqual(size, c.minimum - 1)
            }
        }
    }
}
