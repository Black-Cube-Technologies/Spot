import Foundation
import CoreGraphics

public enum ModeStrategy {
    case exact
    case binned(width: Double)
}

public struct ModeValue {
    public let value: Double
    public let count: Int
    public let range: ClosedRange<Double>?
}

// MARK: - Helper (renamed to avoid collision)
@inline(__always)
private func modesFromValues(_ values: [Double], strategy: ModeStrategy) -> [ModeValue] {
    guard !values.isEmpty else { return [] }

    switch strategy {
    case .exact:
        var freq: [Double: Int] = [:]
        for v in values { freq[v, default: 0] += 1 }
        let maxCount = freq.values.max() ?? 0
        return freq
            .filter { $0.value == maxCount }
            .map { ModeValue(value: $0.key, count: $0.value, range: nil) }
            .sorted { $0.value < $1.value }

    case .binned(let w):
        precondition(w > 0, "Bin width must be > 0")
        func key(_ v: Double) -> Double {
            let k = floor(v / w) * w
            return k == -0.0 ? 0.0 : k
        }
        var buckets: [Double: [Double]] = [:]
        for v in values { buckets[key(v), default: []].append(v) }
        let maxCount = buckets.values.map(\.count).max() ?? 0

        return buckets
            .filter { $0.value.count == maxCount }
            .map { (lower, vals) -> ModeValue in
                let mean = vals.reduce(0, +) / Double(vals.count)
                return ModeValue(value: mean, count: vals.count, range: lower...(lower + w))
            }
            .sorted { $0.value < $1.value }
    }
}

// MARK: - API
public extension Array where Element == LesionMeasurement {

    /// Modes for a single numeric field (via keyPath) with diameter filter.
    func modes(
        for keyPath: KeyPath<LesionMeasurement, CGFloat>,
        diameterThreshold: CGFloat = 100,
        strategy: ModeStrategy = .binned(width: 1.0)
    ) -> [ModeValue] {
        let values = self
            .filter { $0.equivDiameterMM < diameterThreshold }
            .map { Double($0[keyPath: keyPath]) }
        return modesFromValues(values, strategy: strategy)
    }

    /// Modes for widthMM and heightMM together.
    func widthAndHeightModes(
        diameterThreshold: CGFloat = 100,
        strategy: ModeStrategy = .binned(width: 1.0)
    ) -> (width: [ModeValue], height: [ModeValue]) {
        let filtered = self.filter { $0.equivDiameterMM < diameterThreshold }
        let widths  = filtered.map { Double($0.widthMM) }
        let heights = filtered.map { Double($0.heightMM) }
        return (
            modesFromValues(widths,  strategy: strategy),
            modesFromValues(heights, strategy: strategy)
        )
    }

    func widthMode(
        diameterThreshold: CGFloat = 100,
        strategy: ModeStrategy = .binned(width: 1.0)
    ) -> ModeValue? {
        modes(for: \.widthMM, diameterThreshold: diameterThreshold, strategy: strategy).first
    }

    func heightMode(
        diameterThreshold: CGFloat = 100,
        strategy: ModeStrategy = .binned(width: 1.0)
    ) -> ModeValue? {
        modes(for: \.heightMM, diameterThreshold: diameterThreshold, strategy: strategy).first
    }
}
