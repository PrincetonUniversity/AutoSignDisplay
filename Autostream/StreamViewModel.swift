//
//  StreamViewModel.swift
//  Autostream
//
//  Created by Michael Bino on 4/20/25.
//

import Foundation
import AVKit

class StreamViewModel: ObservableObject {
    static let maxChannelPresets = 20
    static let defaultPresets = [
        "https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8",
        "https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8",
        "https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8",
        "https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8"
    ]

    @Published var streamURL: String
    @Published var isPlayingOnOpen: Bool
    @Published var retryTimeout: Double
    @Published var autoResume: Bool
    @Published var settingsDisabled: Bool
    @Published var channelPresets: [String]
    @Published var channelPresetsManaged: Bool
    @Published var selectedPresetIndex: Int?
    @Published var defaultChannelURL: String?
    @Published var player: AVPlayer?

    private var retryTimer: Timer?

    // Inject a logger for easier testing. Defaults to printing to stdout.
    private let logger: Logger

    init(logger: Logger = PrintLogger()) {
        let defaults = UserDefaults.standard
        self.logger = logger

        // Ensure the managed flag has an explicit default when no MDM payload exists.
        if defaults.object(forKey: ContentView.channelPresetsManagedKey) == nil {
            defaults.set(false, forKey: ContentView.channelPresetsManagedKey)
        }

        self.streamURL = defaults.string(forKey: ContentView.lastStreamURLKey) ?? ""
        self.isPlayingOnOpen = defaults.bool(forKey: ContentView.playOnOpenKey)
        let timeout = defaults.double(forKey: ContentView.retryTimeoutKey)
        self.retryTimeout = timeout == 0 ? 5.0 : timeout
        self.autoResume = defaults.bool(forKey: ContentView.autoResumeKey)
        self.settingsDisabled = defaults.bool(forKey: ContentView.settingsDisabledKey)

        let storedPresets = defaults.stringArray(forKey: ContentView.channelPresetsKey)
        let sanitizedPresets: [String]
        if let storedPresets, !storedPresets.isEmpty {
            sanitizedPresets = Array(storedPresets.prefix(StreamViewModel.maxChannelPresets))
            if sanitizedPresets.count != storedPresets.count {
                defaults.set(sanitizedPresets, forKey: ContentView.channelPresetsKey)
            }
        } else {
            sanitizedPresets = StreamViewModel.defaultPresets
            defaults.set(sanitizedPresets, forKey: ContentView.channelPresetsKey)
            defaults.set(false, forKey: ContentView.channelPresetsManagedKey)
        }
        self.channelPresets = sanitizedPresets
        self.channelPresetsManaged = defaults.bool(forKey: ContentView.channelPresetsManagedKey)

        if let managedDefault = defaults.string(forKey: ContentView.defaultChannelKey), !managedDefault.isEmpty {
            self.defaultChannelURL = managedDefault
        } else {
            self.defaultChannelURL = nil
        }

        if let defaultChannelURL = self.defaultChannelURL {
            if channelPresetsManaged {
                self.streamURL = defaultChannelURL
                defaults.set(defaultChannelURL, forKey: ContentView.lastStreamURLKey)
            } else if self.streamURL.isEmpty {
                self.streamURL = defaultChannelURL
                defaults.set(defaultChannelURL, forKey: ContentView.lastStreamURLKey)
            }
        }

        let storedIndex = defaults.object(forKey: ContentView.selectedPresetIndexKey) as? Int
        if let storedIndex, channelPresets.indices.contains(storedIndex) {
            self.selectedPresetIndex = storedIndex
            let presetURL = channelPresets[storedIndex]
            if !presetURL.isEmpty, self.streamURL != presetURL {
                self.streamURL = presetURL
                defaults.set(presetURL, forKey: ContentView.lastStreamURLKey)
            }
        } else if let matchIndex = channelPresets.firstIndex(of: self.streamURL), !self.streamURL.isEmpty {
            self.selectedPresetIndex = matchIndex
            defaults.set(matchIndex, forKey: ContentView.selectedPresetIndexKey)
        } else {
            self.selectedPresetIndex = nil
            defaults.removeObject(forKey: ContentView.selectedPresetIndexKey)
        }
    }

    func updateSettings(isPlayingOnOpen: Bool, retryTimeout: Double, autoResume: Bool, settingsDisabled: Bool = false) {
        self.isPlayingOnOpen = isPlayingOnOpen
        self.retryTimeout = retryTimeout
        self.autoResume = autoResume
        self.settingsDisabled = settingsDisabled
        UserDefaults.standard.set(isPlayingOnOpen, forKey: ContentView.playOnOpenKey)
        UserDefaults.standard.set(retryTimeout, forKey: ContentView.retryTimeoutKey)
        UserDefaults.standard.set(autoResume, forKey: ContentView.autoResumeKey)
        UserDefaults.standard.set(settingsDisabled, forKey: ContentView.settingsDisabledKey)
        restartRetryTimer()
    }

    func updateStreamURL(_ url: String, selectedPresetIndex: Int? = nil) {
        self.streamURL = url
        UserDefaults.standard.set(url, forKey: ContentView.lastStreamURLKey)

        if let selectedPresetIndex {
            self.selectedPresetIndex = selectedPresetIndex
        } else if let matchIndex = channelPresets.firstIndex(of: url), !url.isEmpty {
            self.selectedPresetIndex = matchIndex
        } else {
            self.selectedPresetIndex = nil
        }
        persistSelectedPresetIndex()
    }

    func selectPreset(at index: Int) {
        guard channelPresets.indices.contains(index) else { return }
        updateStreamURL(channelPresets[index], selectedPresetIndex: index)
    }

    func addChannelPreset() {
        guard !channelPresetsManaged, channelPresets.count < StreamViewModel.maxChannelPresets else { return }
        channelPresets.append("")
        persistChannelPresets()
    }

    func removeChannelPreset(at index: Int) {
        guard !channelPresetsManaged, channelPresets.indices.contains(index) else { return }
        channelPresets.remove(at: index)
        if let selectedIndex = selectedPresetIndex {
            if selectedIndex == index {
                selectedPresetIndex = nil
            } else if selectedIndex > index {
                selectedPresetIndex = selectedIndex - 1
            }
            persistSelectedPresetIndex()
        }
        persistChannelPresets()
    }

    func updateChannelPreset(at index: Int, with url: String) {
        guard channelPresets.indices.contains(index), !channelPresetsManaged else { return }
        channelPresets[index] = url
        persistChannelPresets()

        if selectedPresetIndex == index {
            updateStreamURL(url, selectedPresetIndex: index)
        } else if selectedPresetIndex == nil, streamURL == url {
            updateStreamURL(url)
        }
    }

    var canAddMorePresets: Bool {
        !channelPresetsManaged && channelPresets.count < StreamViewModel.maxChannelPresets
    }

    func playStream() {
        guard let url = URL(string: streamURL) else { return }
        player = AVPlayer(url: url)
        player?.play()
    }

    func startStreamIfNeeded() {
        guard let url = URL(string: streamURL) else { return }
        player = AVPlayer(url: url)
        if isPlayingOnOpen {
            player?.play()
        }
        startRetryTimer()
    }

    func stopRetryTimer() {
        retryTimer?.invalidate()
        retryTimer = nil
    }

    private func restartRetryTimer() {
        stopRetryTimer()
        startRetryTimer()
    }

    private func startRetryTimer() {
        guard retryTimer == nil else { return }
        retryTimer = Timer.scheduledTimer(withTimeInterval: retryTimeout, repeats: true) { _ in
            DispatchQueue.main.async {
                // Only attempt to auto-resume if enabled
                if self.autoResume, self.player?.currentItem == nil, let url = URL(string: self.streamURL) {
                    self.logger.log("Auto-resuming stream: \(self.streamURL)")
                    self.player = AVPlayer(url: url)
                    if self.isPlayingOnOpen {
                        self.player?.play()
                    }
                }
            }
        }
    }

    // Exposed for testing: emit the same auto-resume log message so tests can
    // inject a TestLogger and assert the logger received the expected text.
    func emitAutoResumeLogForTesting() {
        logger.log("Auto-resuming stream: \(self.streamURL)")
    }

    private func persistChannelPresets() {
        UserDefaults.standard.set(channelPresets, forKey: ContentView.channelPresetsKey)
    }

    private func persistSelectedPresetIndex() {
        let defaults = UserDefaults.standard
        if let selectedPresetIndex {
            defaults.set(selectedPresetIndex, forKey: ContentView.selectedPresetIndexKey)
        } else {
            defaults.removeObject(forKey: ContentView.selectedPresetIndexKey)
        }
    }
}
