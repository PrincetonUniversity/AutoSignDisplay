//
//  ContentView.swift
//  Autostream
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
    static let playOnOpenKey = "playOnAppOpen"
    static let retryTimeoutKey = "retryTimeout"
    static let lastStreamURLKey = "lastStreamURL"
    static let autoResumeKey = "autoResume"
    static let settingsDisabledKey = "settingsDisabled"

    @StateObject private var viewModel = StreamViewModel()
    @State private var showingSettings = false
    @State private var showPlayer = false
    @State private var presentationFailed = false

    var body: some View {
        NavigationView {
            VStack {
                // Simple banner shown when presentation fails and a retry was scheduled
                if presentationFailed {
                    Text("Failed to present player — retrying...")
                        .foregroundColor(.white)
                        .padding(8)
                        .background(Color.red)
                        .cornerRadius(6)
                        .padding(.bottom, 8)
                }
                TextField("Enter HLS Stream URL", text: $viewModel.streamURL)
                    .padding()
                    .onChangeOld(of: viewModel.streamURL) { oldValue, newValue in
                        viewModel.updateStreamURL(newValue)
                    }

                Text("Enter a URL to play an HLS stream.")
                    .padding()

                Button("Play Stream") {
                    if let url = URL(string: viewModel.streamURL) {
                        viewModel.player = AVPlayer(url: url)
                        showPlayer = true
                    }
                }
                .padding()
                .disabled(viewModel.streamURL.isEmpty)

                Spacer()

                Button("Settings") {
                    showingSettings = true
                }
                .padding()
                .disabled(UserDefaults.standard.bool(forKey: ContentView.settingsDisabledKey))
            }
            .navigationTitle("Autostream")
            .sheet(isPresented: $showingSettings) {
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
            }
            .onAppear {
                viewModel.startStreamIfNeeded()

                // Delay presentation until the view hierarchy is ready. On tvOS
                // presenting a full-screen cover immediately in onAppear can
                // sometimes fail when the app launches from the Home screen.
                DispatchQueue.main.async {
                    if viewModel.isPlayingOnOpen, let _ = URL(string: viewModel.streamURL) {
                        // Ensure player is created and playing, then present full screen
                        if viewModel.player == nil {
                            viewModel.playStream()
                        }
                        if viewModel.player != nil {
                            showPlayer = true
                            presentationFailed = false
                        } else {
                            // mark failure and retry once after a short delay
                            presentationFailed = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                if viewModel.player == nil {
                                    viewModel.playStream()
                                }
                                if viewModel.player != nil {
                                    showPlayer = true
                                    presentationFailed = false
                                }
                            }
                        }
                    }
                }
            }
            .onDisappear {
                viewModel.stopRetryTimer()
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
