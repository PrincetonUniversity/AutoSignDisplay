//
//  StreamViewModel.swift
//  AutoSignDisplay
//
//  Created by Michael Bino on 4/20/25.
//

import Foundation
import AVKit

/// One entry in the Stream Presets list. `name` is optional (empty means "no
/// name set" — the UI falls back to the URL). Persisted in UserDefaults as
/// `[String: String]` under keys `Name` / `URL`; the same keys appear in the
/// managed-config plist so a single decoder handles both.
struct ChannelPreset: Equatable {
    var name: String
    var url: String

    static let managedNameKey = "Name"
    static let managedURLKey = "URL"

    var dictionaryRepresentation: [String: String] {
        [Self.managedNameKey: name, Self.managedURLKey: url]
    }

    /// New-format dict from managed config or persisted UserDefaults.
    /// URL is required and must be non-empty after whitespace trim.
    static func fromDictionary(_ dict: [String: Any]) -> ChannelPreset? {
        guard let url = dict[managedURLKey] as? String,
              !url.trimmingCharacters(in: .whitespaces).isEmpty else {
            return nil
        }
        let name = (dict[managedNameKey] as? String) ?? ""
        return ChannelPreset(name: name, url: url)
    }

    /// Legacy format: managed config or persisted UserDefaults stored the presets
    /// as `[String]` (URLs only). Convert to a nameless ChannelPreset.
    static func fromLegacyString(_ url: String) -> ChannelPreset? {
        let trimmed = url.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return ChannelPreset(name: "", url: url)
    }
}

class StreamViewModel: ObservableObject {
    static let maxChannelPresets = 20
    static let defaultPresets: [ChannelPreset] = [
        ChannelPreset(name: "", url: "https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8"),
        ChannelPreset(name: "", url: "https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8"),
        ChannelPreset(name: "", url: "https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8"),
        ChannelPreset(name: "", url: "https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8")
    ]

    @Published var streamURL: String
    @Published var isPlayingOnOpen: Bool
    @Published var retryTimeout: Double
    @Published var autoResume: Bool
    @Published var settingsDisabled: Bool
    @Published var channelPresets: [ChannelPreset]
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

        let sanitizedPresets: [ChannelPreset]
        if let stored = StreamViewModel.loadPresets(from: defaults), !stored.isEmpty {
            sanitizedPresets = Array(stored.prefix(StreamViewModel.maxChannelPresets))
            // If storage was over-cap, trim it back. Otherwise leave the on-disk shape
            // alone — loadPresets handles both new and legacy formats, so migration
            // happens naturally on the next mutation.
            let storedCount = (defaults.object(forKey: ContentView.channelPresetsKey) as? [Any])?.count ?? 0
            if storedCount != sanitizedPresets.count {
                defaults.set(sanitizedPresets.map { $0.dictionaryRepresentation },
                             forKey: ContentView.channelPresetsKey)
            }
        } else {
            sanitizedPresets = StreamViewModel.defaultPresets
            defaults.set(sanitizedPresets.map { $0.dictionaryRepresentation },
                         forKey: ContentView.channelPresetsKey)
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
            let presetURL = channelPresets[storedIndex].url
            if !presetURL.isEmpty, self.streamURL != presetURL {
                self.streamURL = presetURL
                defaults.set(presetURL, forKey: ContentView.lastStreamURLKey)
            }
        } else if let matchIndex = channelPresets.firstIndex(where: { $0.url == self.streamURL }),
                  !self.streamURL.isEmpty {
            self.selectedPresetIndex = matchIndex
            defaults.set(matchIndex, forKey: ContentView.selectedPresetIndexKey)
        } else {
            self.selectedPresetIndex = nil
            defaults.removeObject(forKey: ContentView.selectedPresetIndexKey)
        }
    }

    /// Read presets from defaults. Accepts both the new `[[String: String]]` form
    /// and legacy `[String]` form. Returns nil if the key is absent or every entry
    /// is malformed; caller re-seeds defaults in that case.
    ///
    /// Uses `object(forKey:)` and iterates as `[Any]` because `array(forKey:)`
    /// returns nil for arrays of dictionaries imported via `defaults import`
    /// (CFPreferences round-trip subtly changes the collection's Swift-bridged type).
    static func loadPresets(from defaults: UserDefaults) -> [ChannelPreset]? {
        guard let raw = defaults.object(forKey: ContentView.channelPresetsKey) as? [Any],
              !raw.isEmpty else {
            return nil
        }
        let presets = raw.compactMap { item -> ChannelPreset? in
            if let dict = item as? [String: Any] {
                return ChannelPreset.fromDictionary(dict)
            }
            if let url = item as? String {
                return ChannelPreset.fromLegacyString(url)
            }
            return nil
        }
        return presets.isEmpty ? nil : presets
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
        } else if let matchIndex = channelPresets.firstIndex(where: { $0.url == url }), !url.isEmpty {
            self.selectedPresetIndex = matchIndex
        } else {
            self.selectedPresetIndex = nil
        }
        persistSelectedPresetIndex()
    }

    func selectPreset(at index: Int) {
        guard channelPresets.indices.contains(index) else { return }
        updateStreamURL(channelPresets[index].url, selectedPresetIndex: index)
    }

    func addChannelPreset() {
        guard !channelPresetsManaged, channelPresets.count < StreamViewModel.maxChannelPresets else { return }
        channelPresets.append(ChannelPreset(name: "", url: ""))
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

    func updateChannelPreset(at index: Int, url: String) {
        guard channelPresets.indices.contains(index), !channelPresetsManaged else { return }
        channelPresets[index].url = url
        persistChannelPresets()

        if selectedPresetIndex == index {
            updateStreamURL(url, selectedPresetIndex: index)
        } else if selectedPresetIndex == nil, streamURL == url {
            updateStreamURL(url)
        }
    }

    func updateChannelPresetName(at index: Int, name: String) {
        guard channelPresets.indices.contains(index), !channelPresetsManaged else { return }
        channelPresets[index].name = name
        persistChannelPresets()
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
        UserDefaults.standard.set(channelPresets.map { $0.dictionaryRepresentation },
                                  forKey: ContentView.channelPresetsKey)
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
