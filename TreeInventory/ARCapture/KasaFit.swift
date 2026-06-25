//
//  KasaFit.swift
//  TreeInventory
//
//  Pure mathematics — no ARKit imports.
//  Implements the Kasa least-squares circle fit algorithm.
//
//  Reference: I. Kasa, "A circle fitting procedure and its error analysis,"
//  IEEE Transactions on Instrumentation and Measurement, 25(1):8–14, 1976.
//

import Foundation

/// Kasa least-squares circle fitting.
enum KasaFit {

    // MARK: - Public API

    /// Fits a circle to a set of 2-D points using Kasa least-squares.
    ///
    /// The algorithm builds a 3×3 linear system whose solution [a, b, c] gives:
    ///   - center x  = a / 2
    ///   - center z  = b / 2
    ///   - radius    = sqrt(c + a²/4 + b²/4)
    ///
    /// - Parameter points: At least three (x, z) sample points (metres).
    /// - Returns: `(cx, cz, radius)` in metres, or `nil` if the system is
    ///   degenerate or fewer than three points were supplied.
    static func fit(points: [(x: Float, z: Float)]) -> (cx: Float, cz: Float, radius: Float)? {
        guard points.count >= 3 else { return nil }

        // Accumulate the six sums needed to build the normal equations.
        // The Kasa formulation linearises  xi² + zi² = a·xi + b·zi + c
        // by substituting  u = xi,  v = zi,  w = xi² + zi²
        // and solving the least-squares system for [a, b, c].

        var Sx:  Double = 0   // Σ xi
        var Sz:  Double = 0   // Σ zi
        var Sxx: Double = 0   // Σ xi²
        var Szz: Double = 0   // Σ zi²
        var Sxz: Double = 0   // Σ xi·zi
        var Sxw: Double = 0   // Σ xi·wi   where wi = xi²+zi²
        var Szw: Double = 0   // Σ zi·wi
        var Sw:  Double = 0   // Σ wi
        let n = Double(points.count)

        for p in points {
            let x = Double(p.x)
            let z = Double(p.z)
            let w = x * x + z * z
            Sx  += x
            Sz  += z
            Sxx += x * x
            Szz += z * z
            Sxz += x * z
            Sxw += x * w
            Szw += z * w
            Sw  += w
        }

        // The 3×3 system  A · [a, b, c]ᵀ = rhs:
        //
        //  [ Sxx  Sxz  Sx ] [a]   [Sxw]
        //  [ Sxz  Szz  Sz ] [b] = [Szw]
        //  [ Sx   Sz   n  ] [c]   [Sw ]
        //
        // Solve with Gaussian elimination with partial pivoting.

        var A: [[Double]] = [
            [Sxx, Sxz, Sx,  Sxw],
            [Sxz, Szz, Sz,  Szw],
            [Sx,  Sz,  n,   Sw ],
        ]

        guard let sol = gaussianElimination(&A) else { return nil }

        let a = sol[0]
        let b = sol[1]
        let c = sol[2]

        let cx = a / 2.0
        let cz = b / 2.0
        let r2 = c + cx * cx + cz * cz
        guard r2 > 0 else { return nil }
        let radius = sqrt(r2)

        return (cx: Float(cx), cz: Float(cz), radius: Float(radius))
    }

    // MARK: - Helpers

    /// Solves a 3×4 augmented matrix [A | b] in-place using Gaussian elimination
    /// with partial (column) pivoting.  Returns the solution vector [x0, x1, x2]
    /// or `nil` if the system is singular/degenerate.
    private static func gaussianElimination(_ A: inout [[Double]]) -> [Double]? {
        let rows = 3
        let cols = 4   // augmented

        for col in 0 ..< rows {
            // Partial pivot: find row with largest absolute value in this column.
            var maxVal = abs(A[col][col])
            var maxRow = col
            for row in (col + 1) ..< rows {
                let v = abs(A[row][col])
                if v > maxVal { maxVal = v; maxRow = row }
            }

            // Check for degeneracy.
            let eps = 1e-10
            guard maxVal > eps else { return nil }

            // Swap rows.
            if maxRow != col {
                A.swapAt(col, maxRow)
            }

            // Eliminate below.
            for row in (col + 1) ..< rows {
                let factor = A[row][col] / A[col][col]
                for k in col ..< cols {
                    A[row][k] -= factor * A[col][k]
                }
            }
        }

        // Back-substitution.
        var x = [Double](repeating: 0, count: rows)
        for row in stride(from: rows - 1, through: 0, by: -1) {
            var sum = A[row][cols - 1]   // rhs
            for k in (row + 1) ..< rows {
                sum -= A[row][k] * x[k]
            }
            guard abs(A[row][row]) > 1e-10 else { return nil }
            x[row] = sum / A[row][row]
        }

        return x
    }
}

// MARK: - Unit conversions (convenience, used by ARViewContainer)

extension KasaFit {
    /// Converts a radius in metres to inches.
    static func radiusToInches(_ radiusMetres: Float) -> Double {
        Double(radiusMetres) * 39.3701
    }

    /// Returns the circumference in inches for a radius given in metres.
    static func circumferenceInches(_ radiusMetres: Float) -> Double {
        2.0 * .pi * radiusToInches(radiusMetres)
    }
}
