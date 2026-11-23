#if os(macOS)
import SwiftUI
import NoelifyCore

/// A frosted card container.
struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Palette.cardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Palette.cardStroke, lineWidth: 1)
            )
    }
}

struct SectionLabel: View {
    let title: String
    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(1.2)
            .foregroundStyle(Palette.mutedText)
    }
}

/// The large Christmas Mode switch: a warm, glowing capsule.
struct ChristmasModeSwitch: View {
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn
                          ? AnyShapeStyle(LinearGradient(colors: [Palette.christmasGold, Color(hex: 0xD99A45)],
                                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                          : AnyShapeStyle(Color.white.opacity(0.14)))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(isOn ? 0.35 : 0.15), lineWidth: 1))
                    .shadow(color: isOn ? Palette.christmasGold.opacity(0.55) : .clear, radius: 10)

                Circle()
                    .fill(Palette.snowWhite)
                    .overlay(
                        Image(systemName: "snowflake")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(isOn ? Color(hex: 0xB87A2E) : Palette.midnightNavy.opacity(0.55))
                            .rotationEffect(.degrees(isOn ? 60 : 0))
                    )
                    .frame(width: 28, height: 28)
                    .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                    .padding(3)
            }
            .frame(width: 62, height: 34)
            .animation(.spring(response: 0.35, dampingFraction: 0.75), value: isOn)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Christmas Mode")
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(.isButton)
    }
}

/// A miniature, hand-drawn preview of a Christmas World.
struct WorldTile: View {
    let world: ChristmasWorld
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .bottomLeading) {
                    LinearGradient(colors: Palette.sky(for: world), startPoint: .top, endPoint: .bottom)
                    SnowDots(seed: world.rawValue.hashValueStable, pixelated: world == .pixel)
                    HillShape(phase: Double(world.rawValue.count))
                        .fill(Palette.snowWhite.opacity(0.92))
                        .frame(height: 18)
                    Image(systemName: Palette.symbol(for: world))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Palette.accent(for: world))
                        .shadow(color: Palette.accent(for: world).opacity(0.8), radius: 6)
                        .padding(.leading, 10)
                        .padding(.bottom, 12)
                }
                .frame(height: 58)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                Text(world.shortName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.snowWhite)
                    .padding(.leading, 2)
            }
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(isSelected ? Palette.christmasGold.opacity(0.14) : Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(isSelected ? Palette.christmasGold : Color.white.opacity(0.08),
                                  lineWidth: isSelected ? 1.5 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(world.tagline)
        .accessibilityLabel(world.displayName)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .animation(.easeOut(duration: 0.2), value: isSelected)
    }
}

/// Soft rolling snow hills for preview tiles.
struct HillShape: Shape {
    var phase: Double
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: rect.maxY))
        p.addLine(to: CGPoint(x: 0, y: rect.height * 0.45))
        let steps = 24
        for i in 0...steps {
            let x = rect.width * CGFloat(i) / CGFloat(steps)
            let t = Double(i) / Double(steps)
            let y = rect.height * (0.40 + 0.22 * sin(t * .pi * 2.2 + phase) * 0.6 + 0.12 * sin(t * .pi * 5 + phase * 2))
            p.addLine(to: CGPoint(x: x, y: y))
        }
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// Deterministic little snowflakes drawn with Canvas (no timers, no CPU cost when idle).
struct SnowDots: View {
    let seed: UInt64
    var pixelated = false

    var body: some View {
        Canvas { context, size in
            var rng = SplitMix64(seed: seed)
            for _ in 0..<22 {
                let x = Double(rng.next() % 1000) / 1000 * size.width
                let y = Double(rng.next() % 1000) / 1000 * size.height * 0.8
                let r = 0.6 + Double(rng.next() % 100) / 100 * 1.4
                let rect = CGRect(x: x, y: y, width: r * 2, height: r * 2)
                let opacity = 0.35 + Double(rng.next() % 60) / 100
                let shape = pixelated ? Path(rect.integral) : Path(ellipseIn: rect)
                context.fill(shape, with: .color(.white.opacity(opacity)))
            }
        }
        .allowsHitTesting(false)
    }
}

/// Small deterministic PRNG so previews look identical on every launch.
struct SplitMix64 {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

extension String {
    /// FNV-1a — unlike `hashValue`, stable across launches.
    var hashValueStable: UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in utf8 { hash = (hash ^ UInt64(byte)) &* 0x100000001b3 }
        return hash
    }
}

/// A status / recovery message with optional actions.
struct BannerView: View {
    let banner: Banner
    var primary: (title: String, action: () -> Void)?
    var secondary: (title: String, action: () -> Void)?
    let onDismiss: () -> Void

    private var tint: Color {
        switch banner.kind {
        case .info: return Palette.winterBlue
        case .success: return Color(hex: 0x7EE0A8)
        case .warning, .recovery: return Palette.christmasGold
        case .error: return Color(hex: 0xF08A96)
        }
    }

    private var icon: String {
        switch banner.kind {
        case .info: return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .recovery: return "arrow.uturn.backward.circle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundStyle(tint).font(.system(size: 15))
            VStack(alignment: .leading, spacing: 4) {
                Text(banner.title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.snowWhite)
                Text(banner.message)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
                if primary != nil || secondary != nil {
                    HStack(spacing: 8) {
                        if let primary {
                            Button(primary.title, action: primary.action)
                                .buttonStyle(.borderedProminent)
                                .tint(Palette.christmasGold)
                                .foregroundStyle(Palette.midnightNavy)
                        }
                        if let secondary {
                            Button(secondary.title, action: secondary.action).buttonStyle(.bordered)
                        }
                    }
                    .controlSize(.small)
                    .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
            Button(action: onDismiss) {
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Palette.mutedText)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(tint.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(tint.opacity(0.35)))
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
#endif
