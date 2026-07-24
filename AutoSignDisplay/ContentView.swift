//
//  ContentView.swift
//  AutoSignDisplay
//
//  Created by Michael Bino on 4/20/25.
//

import SwiftUI
import AVKit

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
    private enum SheetDestination: Identifiable {
        case settings
        case presets

        var id: Int {
            switch self {
            case .settings: return 0
            case .presets: return 1
            }
        }
    }

    static let playOnOpenKey = "playOnAppOpen"
    static let retryTimeoutKey = "retryTimeout"
    static let lastStreamURLKey = "lastStreamURL"
    static let autoResumeKey = "autoResume"
    static let settingsDisabledKey = "settingsDisabled"
    static let channelPresetsKey = "channelPresets"
    static let defaultChannelKey = "defaultChannel"
    static let channelPresetsManagedKey = "channelPresetsManaged"
    static let selectedPresetIndexKey = "selectedPresetIndex"

    @StateObject private var viewModel = StreamViewModel()
    @State private var activeSheet: SheetDestination?
    @State private var showPlayer = false
    @State private var presentationFailed = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Simple banner shown when presentation fails and a retry was scheduled
                    if presentationFailed {
                        Text("Failed to present player — retrying...")
                            .foregroundColor(.white)
                            .padding(8)
                            .background(Color.red)
                            .cornerRadius(6)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Selected Stream")
                            .font(.headline)

                        TextField(
                            "Enter HLS Stream URL",
                            text: Binding(
                                get: { viewModel.streamURL },
                                set: { newValue in
                                    viewModel.updateStreamURL(newValue)
                                }
                            )
                        )
                        .padding(.vertical, 8)

                        Button {
                            if let url = URL(string: viewModel.streamURL) {
                                viewModel.player = AVPlayer(url: url)
                                showPlayer = true
                            }
                        } label: {
                            Text("Play Stream")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(viewModel.streamURL.isEmpty)

                        Text("Enter a URL to play an HLS stream.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    if !viewModel.channelPresets.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Stream Presets")
                                .font(.headline)

                            LazyVStack(alignment: .leading, spacing: 12) {
                                ForEach(Array(viewModel.channelPresets.enumerated()), id: \.offset) { index, preset in
                                    Button {
                                        viewModel.selectPreset(at: index)
                                    } label: {
                                        HStack {
                                            Text(preset.isEmpty ? "Preset \(index + 1)" : preset)
                                                .lineLimit(1)
                                                .truncationMode(.middle)
                                            if viewModel.selectedPresetIndex == index {
                                                Spacer()
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundColor(.accentColor)
                                            }
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .buttonStyle(.borderedProminent)
                                }
                            }

                            if viewModel.channelPresetsManaged {
                                Text("Stream presets are managed by your administrator.")
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    HStack(spacing: 16) {
                        Button {
                            activeSheet = .presets
                        } label: {
                            Text("Manage Stream Presets")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(viewModel.channelPresetsManaged)

                        Button {
                            activeSheet = .settings
                        } label: {
                            Text("Settings")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(viewModel.settingsDisabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 48)
                .padding(.vertical, 36)
            }
            .navigationTitle("AutoSignDisplay")
            .sheet(item: $activeSheet) { destination in
                switch destination {
                case .settings:
                    SettingsView(
                        isPlayingOnOpen: $viewModel.isPlayingOnOpen,
                        retryTimeout: $viewModel.retryTimeout,
                        autoResume: $viewModel.autoResume,
                        settingsDisabled: $viewModel.settingsDisabled,
                        onRetryTimeoutChanged: {
                            viewModel.updateSettings(
                                isPlayingOnOpen: viewModel.isPlayingOnOpen,
                                retryTimeout: viewModel.retryTimeout,
                                autoResume: viewModel.autoResume,
                                settingsDisabled: viewModel.settingsDisabled
                            )
                        }
                    )
                case .presets:
                    ChannelPresetsView(viewModel: viewModel)
                }
            }
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
