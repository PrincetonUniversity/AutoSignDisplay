//
//  ContentView.swift
//  AutoSignDisplay
//
//  Created by Michael Bino on 4/20/25.
//

import SwiftUI
import AVKit

/// Group label above a block of controls. tvOS convention is a small,
/// uppercased, letter-spaced caption in a secondary color — it reads as a
/// divider rather than competing with the content beneath it.
struct SectionHeader: View {
    private let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title.uppercased())
            .font(.caption)
            .fontWeight(.semibold)
            .tracking(1.5)
            .foregroundColor(.secondary)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A preset row on the main screen: name (or URL) on the left, and a "Selected"
/// marker on the right when it's the active preset. Colors are explicit rather
/// than inherited so the accent tint doesn't leak into the row's text.
private struct PresetListRow: View {
    let title: String
    let isSelected: Bool
    /// True while a player exists, which turns the marker from "this is the one
    /// chosen" into "this is the one on screen right now".
    var isPlaying: Bool = false
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        HStack {
            Text(title)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundColor(isFocused ? .black : .primary)

            if isSelected {
                Spacer()
                Text(isPlaying ? "Playing" : "Selected")
                    .font(.caption)
                    .foregroundColor(isFocused ? .black.opacity(0.65) : .secondary)
                    .accessibilityHidden(true)
                Image(systemName: isPlaying ? "play.circle.fill" : "checkmark.circle.fill")
                    // Focused rows get a near-white background, so the accent blue
                    // needs to darken to stay legible against it.
                    .foregroundColor(isFocused
                                     ? Color(red: 0.10, green: 0.40, blue: 0.62)
                                     : .accentColor)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct FullscreenPlayerView: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        uiViewController.player = player
    }
}

struct ContentView: View {
    static let playOnOpenKey = "playOnAppOpen"
    static let retryTimeoutKey = "retryTimeout"
    static let lastStreamURLKey = "lastStreamURL"
    static let autoResumeKey = "autoResume"
    static let settingsDisabledKey = "settingsDisabled"
    static let channelPresetsKey = "channelPresets"
    static let defaultChannelKey = "defaultChannel"
    static let channelPresetsManagedKey = "channelPresetsManaged"
    static let selectedPresetIndexKey = "selectedPresetIndex"
    static let displayTitleKey = "displayTitle"
    // Intentionally has no AppConfigKeys counterpart: presets are read-only when
    // MDM-managed, so there is nothing to confirm deleting and nothing for an
    // administrator to configure. Purely a local preference.
    static let confirmBeforeDeleteKey = "confirmBeforeDelete"

    @StateObject private var viewModel = StreamViewModel()
    @State private var showPlayer = false
    @State private var presentationFailed = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: ScreenMetrics.groupSpacing) {
                    // Simple banner shown when presentation fails and a retry was scheduled
                    if presentationFailed {
                        Text("Failed to present player — retrying...")
                            .foregroundColor(.white)
                            .padding(8)
                            .background(Color.red)
                            .cornerRadius(6)
                    }

                    VStack(alignment: .leading, spacing: ScreenMetrics.rowSpacing) {
                        SectionHeader(isPlaying ? "Playing Stream" : "Selected Stream")

                        // Locked while playing: changing the URL under a running
                        // player would leave the field describing something other
                        // than what is on screen. Stop first.
                        TextField(
                            "Enter a Stream URL or select a Stream Preset.",
                            text: Binding(
                                get: { viewModel.streamURL },
                                set: { newValue in
                                    viewModel.updateStreamURL(newValue)
                                }
                            )
                        )
                        .padding(.vertical, 8)
                        .accessibilityLabel("HLS stream URL")
                        .disabled(isPlaying)
                        .accessibilityHint(isPlaying ? "Stop the stream to edit" : "")

                        // Leaving the fullscreen player only hides it — playback
                        // continues, audibly — so while it lives these two replace
                        // Play: one way back to it, one way to end it.
                        if isPlaying {
                            HStack(spacing: ScreenMetrics.buttonSpacing) {
                                Button {
                                    showPlayer = true
                                } label: {
                                    CenteredRowLabel(title: "Return to Stream")
                                }
                                .buttonStyle(.borderedProminent)

                                Button {
                                    viewModel.stopPlayback()
                                    AccessibilityNotification.Announcement("Playback stopped").post()
                                } label: {
                                    CenteredRowLabel(title: "Stop Stream")
                                }
                                .buttonStyle(.bordered)
                            }
                        } else {
                            HStack(spacing: ScreenMetrics.buttonSpacing) {
                                Button {
                                    if let url = URL(string: viewModel.streamURL) {
                                        viewModel.player = AVPlayer(url: url)
                                        showPlayer = true
                                    }
                                } label: {
                                    CenteredRowLabel(title: "Play Stream")
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(viewModel.streamURL.isEmpty)

                                // Clears either a typed URL or a preset selection —
                                // both live in the same two properties.
                                Button {
                                    viewModel.clearStream()
                                    AccessibilityNotification.Announcement("Stream cleared").post()
                                } label: {
                                    CenteredRowLabel(title: "Clear Stream")
                                }
                                .buttonStyle(.bordered)
                                .disabled(!viewModel.canClearStream)
                                .accessibilityHint(
                                    viewModel.channelPresetsManaged
                                        ? "Managed by your administrator"
                                        : ""
                                )
                            }
                        }
                    }

                    if !viewModel.channelPresets.isEmpty {
                        VStack(alignment: .leading, spacing: ScreenMetrics.rowSpacing) {
                            SectionHeader("Stream Presets")

                            LazyVStack(alignment: .leading, spacing: ScreenMetrics.rowSpacing) {
                                ForEach(Array(viewModel.channelPresets.enumerated()), id: \.offset) { index, preset in
                                    Button {
                                        togglePreset(at: index)
                                    } label: {
                                        PresetListRow(
                                            title: presetDisplayText(preset, index: index),
                                            isSelected: viewModel.selectedPresetIndex == index,
                                            isPlaying: isPlaying
                                        )
                                    }
                                    .buttonStyle(.borderedProminent)
                                    // Locked while playing: switching streams from
                                    // under a running player is the same confusion as
                                    // editing the URL.
                                    .disabled(isPlaying)
                                    .accessibilityLabel(presetAccessibilityLabel(index: index, preset: preset))
                                    .accessibilityAddTraits(viewModel.selectedPresetIndex == index ? .isSelected : [])
                                    .accessibilityHint(presetActionHint(index: index))
                                }
                            }

                            if viewModel.channelPresetsManaged {
                                Text("Stream presets are managed by your administrator.")
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    // Pushed, not presented. A text field inside a .sheet or
                    // .fullScreenCover on tvOS does not get its editing presentation
                    // torn down when the user cancels out of the keyboard — the field
                    // is left stuck white with compact text. Fields reached by a
                    // navigation push behave correctly, like the URL field above.
                    HStack(spacing: ScreenMetrics.buttonSpacing) {
                        NavigationLink {
                            ChannelPresetsView(viewModel: viewModel)
                        } label: {
                            CenteredRowLabel(title: "Manage Stream Presets")
                        }
                        .buttonStyle(.bordered)
                        .disabled(viewModel.channelPresetsManaged)
                        .accessibilityHint(viewModel.channelPresetsManaged ? "Managed by your administrator" : "")

                        NavigationLink {
                            SettingsView(
                                isPlayingOnOpen: $viewModel.isPlayingOnOpen,
                                retryTimeout: $viewModel.retryTimeout,
                                autoResume: $viewModel.autoResume,
                                settingsDisabled: $viewModel.settingsDisabled,
                                confirmBeforeDelete: $viewModel.confirmBeforeDelete,
                                displayTitle: $viewModel.displayTitle,
                                channelPresetsManaged: viewModel.channelPresetsManaged,
                                onRetryTimeoutChanged: {
                                    viewModel.updateSettings(
                                        isPlayingOnOpen: viewModel.isPlayingOnOpen,
                                        retryTimeout: viewModel.retryTimeout,
                                        autoResume: viewModel.autoResume,
                                        settingsDisabled: viewModel.settingsDisabled
                                    )
                                },
                                onConfirmBeforeDeleteChanged: { newValue in
                                    viewModel.updateConfirmBeforeDelete(newValue)
                                },
                                onDisplayTitleChanged: { newValue in
                                    viewModel.updateDisplayTitle(newValue)
                                }
                            )
                        } label: {
                            CenteredRowLabel(title: "Settings")
                        }
                        .buttonStyle(.bordered)
                        .disabled(viewModel.settingsDisabled)
                        .accessibilityHint(viewModel.settingsDisabled ? "Managed by your administrator" : "")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, ScreenMetrics.horizontalPadding)
                .padding(.vertical, ScreenMetrics.verticalPadding)
            }
            .navigationTitle(viewModel.effectiveDisplayTitle)
            .onAppear {
                viewModel.startStreamIfNeeded()
                scheduleAutoPlayPresentation()
            }
            .onDisappear {
                viewModel.stopRetryTimer()
            }
            .onChangeOld(of: scenePhase) { _, newPhase in
                switch newPhase {
                case .active:
                    viewModel.startStreamIfNeeded()
                    scheduleAutoPlayPresentation()
                case .background:
                    viewModel.stopRetryTimer()
                default:
                    break
                }
            }
            .fullScreenCover(isPresented: $showPlayer) {
                if let player = viewModel.player {
                    FullscreenPlayerView(player: player)
                        .edgesIgnoringSafeArea(.all)
                        .onAppear {
                            player.play()
                        }
                }
            }
        }
    }
}

private extension ContentView {
    /// Tapping a preset selects it; tapping the one already selected clears the
    /// selection. Deselect is unavailable under MDM, where the administrator's
    /// channel is meant to keep playing.
    func togglePreset(at index: Int) {
        if viewModel.selectedPresetIndex == index, !viewModel.channelPresetsManaged {
            viewModel.deselectPreset()
            AccessibilityNotification.Announcement("Deselected preset \(index + 1)").post()
        } else {
            viewModel.selectPreset(at: index)
            AccessibilityNotification.Announcement("Selected preset \(index + 1)").post()
        }
    }

    /// Tells VoiceOver what pressing the row will do, since the same control both
    /// selects and deselects — and does neither while a stream is playing.
    func presetActionHint(index: Int) -> String {
        if isPlaying { return "Stop the stream to change selection" }
        guard viewModel.selectedPresetIndex == index else { return "Selects this stream" }
        return viewModel.channelPresetsManaged ? "" : "Clears this selection"
    }

    /// A player exists, so a stream is on screen (or paused behind the main view).
    /// Locks the stream-changing controls and swaps Play for Return/Stop.
    var isPlaying: Bool {
        viewModel.player != nil
    }

    /// What renders in the main preset list row. Prefer the admin- or user-supplied
    /// name; fall back to the URL; fall back to "Preset N" for a totally-empty row
    /// (only possible transiently when a user has just tapped Add Preset).
    func presetDisplayText(_ preset: ChannelPreset, index: Int) -> String {
        if !preset.name.isEmpty { return preset.name }
        if !preset.url.isEmpty { return preset.url }
        return "Preset \(index + 1)"
    }

    // A URL spelled out character-by-character is unusable in VoiceOver. Prefer the
    // preset's name; otherwise reduce the URL to its filename or host so the row
    // reads as e.g. "Preset 1, x36xhzz.m3u8".
    func presetAccessibilityLabel(index: Int, preset: ChannelPreset) -> String {
        let position = "Preset \(index + 1)"
        if !preset.name.isEmpty {
            return "\(position), \(preset.name)"
        }
        guard !preset.url.isEmpty, let parsed = URL(string: preset.url) else {
            return "\(position), empty"
        }
        let filename = parsed.lastPathComponent
        if !filename.isEmpty, filename != "/" {
            return "\(position), \(filename)"
        }
        if let host = parsed.host, !host.isEmpty {
            return "\(position), \(host)"
        }
        return position
    }

    @MainActor
    func scheduleAutoPlayPresentation() {
        DispatchQueue.main.async {
            guard viewModel.isPlayingOnOpen, let _ = URL(string: viewModel.streamURL) else {
                return
            }

            if viewModel.player == nil || viewModel.player?.currentItem == nil {
                viewModel.playStream()
            } else {
                viewModel.player?.play()
            }

            guard let player = viewModel.player else {
                presentationFailed = true
                AccessibilityNotification.Announcement("Failed to present player. Retrying.").post()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    if viewModel.player == nil || viewModel.player?.currentItem == nil {
                        viewModel.playStream()
                    }
                    if viewModel.player != nil {
                        showPlayer = true
                        presentationFailed = false
                    }
                }
                return
            }

            if showPlayer {
                player.play()
                presentationFailed = false
            } else {
                showPlayer = true
                presentationFailed = false
            }
        }
    }
}
