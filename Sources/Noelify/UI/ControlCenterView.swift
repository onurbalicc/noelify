#if os(macOS)
import AppKit
import SwiftUI
import NoelifyCore

/// The Noelify Control Center, opened from the menu bar snowflake.
///
/// Every control here is wired to real behaviour. Features from later phases are
/// not shown as controls until they exist.
struct ControlCenterView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if let banner = model.banner { bannerView(banner) }
            christmasModeCard
            if model.isAskingWallpaperConsent { consentCard }
            worldSection
            wallpaperSection
            roadmapNote
            footer
        }
        .padding(16)
        .frame(width: 344)
        .background(Palette.background)
        .environment(\.colorScheme, .dark)
        .animation(.easeInOut(duration: 0.25), value: model.banner)
        .animation(.easeInOut(duration: 0.25), value: model.isAskingWallpaperConsent)
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [Palette.winterBlue.opacity(0.45), .clear],
                                         center: .center, startRadius: 2, endRadius: 22))
                    .frame(width: 40, height: 40)
                Image(systemName: "snowflake")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Palette.snowWhite)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("NOELIFY")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .tracking(3)
                    .foregroundStyle(Palette.snowWhite)
                Text("Make your Mac magical.")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.mutedText)
            }
            Spacer()
        }
    }

    private var christmasModeCard: some View {
        Card {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Christmas Mode")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Palette.snowWhite)
                    Text(model.isActive ? "On — \(model.settings.world.displayName)" : "Off — your desktop is untouched")
                        .font(.system(size: 11))
                        .foregroundStyle(model.isActive ? Palette.christmasGold : Palette.mutedText)
                }
                Spacer()
                ChristmasModeSwitch(isOn: model.isActive) {
                    model.setChristmasMode(!model.isActive)
                }
            }
        }
    }

    private var consentCard: some View {
        Card {
            Label("Change your wallpaper?", systemImage: "photo.on.rectangle.angled")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.snowWhite)
            Text("Noelify will save a note of your current wallpaper for each display, then show the \(model.settings.world.displayName) wallpaper. Turning Christmas Mode off or quitting Noelify puts your original back. Your picture files are never modified or deleted.")
                .font(.system(size: 11))
                .foregroundStyle(Palette.mutedText)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button("Change Wallpaper") { model.grantWallpaperConsent() }
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.christmasGold)
                    .foregroundStyle(Palette.midnightNavy)
                Button("Effects Only") { model.activateWithoutWallpaper() }
                    .buttonStyle(.bordered)
                Spacer()
                Button("Cancel") { model.cancelConsent() }
                    .buttonStyle(.plain)
                    .foregroundStyle(Palette.mutedText)
            }
            .controlSize(.small)
        }
    }

    private var worldSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(title: "Christmas World")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(ChristmasWorld.allCases) { world in
                    WorldTile(world: world, isSelected: model.settings.world == world) {
                        model.selectWorld(world)
                    }
                }
            }
            Text(model.settings.world.tagline)
                .font(.system(size: 11))
                .foregroundStyle(Palette.mutedText)
        }
    }

    private var wallpaperSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(title: "Desktop")
            Card {
                Toggle(isOn: Binding(
                    get: { model.settings.changesWallpaper },
                    set: { model.setChangesWallpaper($0) }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Christmas wallpaper")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Palette.snowWhite)
                        Text(model.usesPreviewArt
                             ? "Uses development preview art until this world's final wallpaper ships."
                             : "Your original is restored when Christmas Mode turns off.")
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.mutedText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .toggleStyle(.switch)
                .tint(Palette.christmasGold)

                if model.hasWallpaperBackup && !model.isActive {
                    Divider().overlay(Palette.cardStroke)
                    Button {
                        model.restoreOriginalWallpaper()
                    } label: {
                        Label("Restore Original Wallpaper", systemImage: "arrow.uturn.backward")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Palette.winterBlue)
                }
            }
        }
    }

    private var roadmapNote: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "sparkles")
                .foregroundStyle(Palette.christmasGold.opacity(0.8))
                .font(.system(size: 11))
            Text("Snowfall, window snow, lights and decorations arrive in the next builds.")
                .font(.system(size: 10))
                .foregroundStyle(Palette.mutedText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footer: some View {
        HStack {
            Button("About Noelify") { showAbout() }
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
        .buttonStyle(.plain)
        .font(.system(size: 11))
        .foregroundStyle(Palette.mutedText)
        .padding(.top, 2)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func bannerView(_ banner: Banner) -> some View {
        if banner.kind == .recovery {
            BannerView(
                banner: banner,
                primary: (title: "Restore Now", action: { model.restoreOriginalWallpaper() }),
                secondary: (title: "Later", action: { model.dismissBanner() }),
                onDismiss: { model.dismissBanner() }
            )
        } else {
            BannerView(banner: banner, onDismiss: { model.dismissBanner() })
        }
    }

    private func showAbout() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        let credits = NSAttributedString(
            string: "One Click. Christmas Everywhere.\n\nNo telemetry. No analytics. No network access.\nOpen source under the MIT License.",
            attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]
        )
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Noelify",
            .applicationVersion: version,
            .credits: credits,
        ])
    }
}
#endif
