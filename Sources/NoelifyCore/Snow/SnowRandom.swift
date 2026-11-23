import Foundation

/// SplitMix64: tiny, fast and seedable, so simulations can be reproduced in tests.
struct SnowRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        return SnowRandom.mix(state)
    }

    /// Uniform in 0..<1.
    mutating func unit() -> Float { Float(next() >> 40) / Float(1 << 24) }

    mutating func value(in range: ClosedRange<Float>) -> Float {
        range.lowerBound + (range.upperBound - range.lowerBound) * unit()
    }

    mutating func chance(_ probability: Float) -> Bool { unit() < probability }

    static func mix(_ value: UInt64) -> UInt64 {
        var z = value
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Smooth one-dimensional value noise in -1...1. Unlike a sum of sines it never loops,
/// which keeps gusts from looking like a repeating animation.
struct SmoothNoise {
    let seed: UInt64

    func value(at position: Double) -> Float {
        let cell = position.rounded(.down)
        let t = Float(position - cell)
        let i = Int64(cell)
        let a = lattice(i), b = lattice(i &+ 1)
        let s = t * t * (3 - 2 * t)
        return a + (b - a) * s
    }

    private func lattice(_ i: Int64) -> Float {
        let hashed = SnowRandom.mix(UInt64(bitPattern: i) &* 0x9E37_79B9_7F4A_7C15 ^ seed)
        return Float(hashed >> 40) / Float(1 << 23) - 1
    }
}
