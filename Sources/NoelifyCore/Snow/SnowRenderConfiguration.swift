import Foundation

/// How much power the Mac can spare for effects right now.
public enum PowerCondition: String, Equatable, Sendable {
    /// Plugged in.
    case pluggedIn
    /// Running on battery.
    case battery
    /// Low Power Mode, or the machine is thermally throttled.
    case constrained
}

/// Everything the renderer needs to draw snow: the user's choices plus the power budget.
public struct SnowRenderConfiguration: Equatable, Sendable {
    public var settings: SnowSettings
    public var power: PowerCondition

    public init(settings: SnowSettings, power: PowerCondition) {
        self.settings = settings
        self.power = power
    }

    /// Snow drifts slowly, so 30 fps reads as smooth; plugged-in Macs get 60.
    public var framesPerSecond: Int {
        // Pixel snow steps across a coarse grid by design; more frames would be wasted.
        if settings.style == .pixel { return power == .constrained ? 20 : 30 }
        switch power {
        case .pluggedIn: return 60
        case .battery: return 30
        case .constrained: return 24
        }
    }

    /// Fraction of the full flake count to simulate.
    public var particleScale: Double {
        switch power {
        case .pluggedIn: return 1
        case .battery: return 0.65
        case .constrained: return 0.4
        }
    }

    /// Resolution to draw at, relative to the display's own. Snow is soft, so it doesn't need
    /// every Retina pixel, and frame buffers are by far the engine's largest memory cost.
    public var renderScale: Double {
        // Pixel art is drawn at exactly half resolution and enlarged without smoothing.
        if settings.style == .pixel { return 0.5 }
        return power == .pluggedIn ? 0.6 : 0.5
    }

    /// Flakes for a display of the given size, so snow looks equally dense everywhere.
    public func flakeCount(width: Double, height: Double) -> Int {
        guard width > 0, height > 0 else { return 0 }
        let areaScale = min(max((width * height) / (1440 * 900), 0.4), 2.5)
        return Int((Double(settings.intensity.baseFlakeCount) * areaScale * particleScale).rounded())
    }
}
