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

    /// Strict decode for **managed configuration**. A URL-less entry in an MDM
    /// payload is malformed, so it is rejected outright.
    static func fromDictionary(_ dict: [String: Any]) -> ChannelPreset? {
        guard let url = dict[managedURLKey] as? String,
              !url.trimmingCharacters(in: .whitespaces).isEmpty else {
            return nil
        }
        let name = (dict[managedNameKey] as? String) ?? ""
        return ChannelPreset(name: name, url: url)
    }

    /// Permissive decode for the app's **own persisted storage**. A blank URL is
    /// valid here — `addChannelPreset()` creates an empty row that the user then
    /// fills in, and that row must survive a reload before it has a URL.
    static func fromStoredDictionary(_ dict: [String: Any]) -> ChannelPreset? {
        // Require at least one of the expected keys so genuinely foreign dicts
        // are still rejected.
        guard dict[managedURLKey] != nil || dict[managedNameKey] != nil else {
            return nil
        }
        return ChannelPreset(
            name: (dict[managedNameKey] as? String) ?? "",
            url: (dict[managedURLKey] as? String) ?? ""
        )
    }

    /// Short, speakable stand-in for this preset, or nil when it has nothing worth
    /// reading out.
    ///
    /// A full HLS URL spelled character by character is unusable in VoiceOver — and
    /// unreadable in a confirmation alert — so an unnamed preset falls back to the
    /// URL's filename, then its host, rather than the whole string. Shared by the
    /// main screen's row labels and the delete-confirmation message so the two
    /// cannot drift.
    var spokenDescriptor: String? {
        if !name.isEmpty { return name }
        guard let parsed = URL(string: url) else { return nil }
        let filename = parsed.lastPathComponent
        if !filename.isEmpty, filename != "/" { return filename }
        if let host = parsed.host, !host.isEmpty { return host }
        return nil
    }

    /// Legacy format: managed config or persisted UserDefaults stored the presets
    /// as `[String]` (URLs only). Convert to a nameless ChannelPreset.
    static func fromLegacyString(_ url: String) -> ChannelPreset? {
        let trimmed = url.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return ChannelPreset(name: "", url: url)
    }
}

/// What the retry timer should do about the current state of playback.
enum PlaybackRecovery: Equatable {
    case leaveAlone
    case reload(reason: String)
}

/// The observable facts the recovery rules need, sampled from `AVPlayer`.
///
/// Kept separate from the player so the rules are testable. Driving a real AVPlayer
/// into an expired signed URL or a frozen origin is not something a unit test can
/// arrange, but every input that decides the outcome is a plain value.
struct PlaybackSnapshot: Equatable {
    var hasPlayer: Bool
    var hasItem: Bool
    var itemFailed: Bool
    /// True when the player is not trying to play — never started, or paused on
    /// purpose. A paused player is not a stalled one.
    var isPaused: Bool
    /// Wall-clock seconds since `currentTime()` last moved forward.
    var secondsSinceProgress: TimeInterval
}

class StreamViewModel: ObservableObject {
    static let maxChannelPresets = 20

    /// Shown at the top of the main screen when no custom title is set. Stored as
    /// empty-means-default rather than seeding this string, so a future rename of
    /// the app carries through for anyone who never customized it.
    static let defaultDisplayTitle = "AutoSignDisplay"
    static let defaultPresets: [ChannelPreset] = [
        ChannelPreset(name: "News", url: "https://orfe.princeton.edu/live/news"),
        ChannelPreset(name: "News Plus", url: "https://orfe.princeton.edu/live/news-plus"),
        ChannelPreset(name: "Scenic", url: "https://orfe.princeton.edu/live/scenic"),
        ChannelPreset(name: "Announcements", url: "https://orfe.princeton.edu/live/announcements")
    ]

    @Published var streamURL: String
    @Published var isPlayingOnOpen: Bool
    @Published var retryTimeout: Double
    @Published var autoResume: Bool
    @Published var settingsDisabled: Bool
    @Published var channelPresets: [ChannelPreset]
    @Published var channelPresetsManaged: Bool
    @Published var confirmBeforeDelete: Bool
    /// Custom main-screen heading. Empty means "use `defaultDisplayTitle`".
    @Published var displayTitle: String
    /// Reduces the main screen to the preset list: no URL entry, no preset
    /// management. Pressing a preset plays it.
    @Published var viewOnlyMode: Bool
    /// Gates the Settings screen. Empty means no lock.
    @Published var settingsPIN: String
    /// The PIN came from MDM, so it cannot be changed on the device.
    @Published var settingsPINManaged: Bool
    @Published var selectedPresetIndex: Int?
    @Published var defaultChannelURL: String?
    @Published var player: AVPlayer?

    private var retryTimer: Timer?

    /// Progress clock backing stall detection.
    private var lastObservedTime: CMTime = .invalid
    private var lastProgressAt: Date?

    /// How long playback may sit frozen before it counts as a failure.
    ///
    /// A live stream rebuffering for a few seconds is ordinary, so reacting at the
    /// retry interval alone would thrash on an everyday hiccup. Three intervals with a
    /// 15-second floor means the 5s default waits 15s — long enough to ignore a
    /// rebuffer, short enough that a display heals while someone is still looking at it.
    var stallThreshold: TimeInterval { max(15, retryTimeout * 3) }

    /// Decides whether playback needs rebuilding.
    ///
    /// This replaces a condition that could never be true. The old rule was
    /// `player?.currentItem == nil`, but AVPlayer does not nil `currentItem` when a
    /// stream fails: a failed item stays put with `status == .failed`, and a frozen one
    /// simply stops advancing. The only code that nils the player is `stopPlayback()`,
    /// which also stops this timer. So Auto Resume recovered from nothing — not an
    /// expired signed URL, not a dropped network, not an off-air source.
    ///
    /// Time-not-advancing is the primary signal deliberately. It does not depend on
    /// which notification AVFoundation happens to post, and it catches every failure
    /// mode that matters to an unattended display.
    static func recoveryDecision(for snapshot: PlaybackSnapshot,
                                 autoResume: Bool,
                                 stoppedByUser: Bool,
                                 stallThreshold: TimeInterval) -> PlaybackRecovery {
        // An explicit stop outranks everything, Auto Resume included.
        if stoppedByUser { return .leaveAlone }
        guard autoResume else { return .leaveAlone }

        if !snapshot.hasPlayer { return .reload(reason: "no player") }
        if !snapshot.hasItem { return .reload(reason: "no player item") }
        if snapshot.itemFailed { return .reload(reason: "player item failed") }

        // Paused is a legitimate resting state, not a fault.
        if snapshot.isPaused { return .leaveAlone }

        if snapshot.secondsSinceProgress >= stallThreshold {
            return .reload(reason: "stalled for \(Int(snapshot.secondsSinceProgress))s")
        }
        return .leaveAlone
    }

    /// Set when the user explicitly stops playback, so neither the retry timer nor a
    /// scene-phase reactivation brings the player back. Deliberately in-memory only:
    /// a fresh launch honors `PlayOnAppOpen` again, which the kiosk path depends on.
    private var playbackStoppedByUser = false

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
        self.displayTitle = defaults.string(forKey: ContentView.displayTitleKey) ?? ""
        self.viewOnlyMode = defaults.bool(forKey: ContentView.viewOnlyModeKey)
        self.settingsPIN = defaults.string(forKey: ContentView.settingsPINKey) ?? ""
        self.settingsPINManaged = defaults.bool(forKey: ContentView.settingsPINManagedKey)

        // Defaults to ON. bool(forKey:) yields false for a missing key, so the
        // absent case has to be seeded explicitly rather than read.
        if defaults.object(forKey: ContentView.confirmBeforeDeleteKey) == nil {
            defaults.set(true, forKey: ContentView.confirmBeforeDeleteKey)
            self.confirmBeforeDelete = true
        } else {
            self.confirmBeforeDelete = defaults.bool(forKey: ContentView.confirmBeforeDeleteKey)
        }

        let sanitizedPresets: [ChannelPreset]
        if let stored = StreamViewModel.loadPresets(from: defaults), !stored.isEmpty {
            sanitizedPresets = Array(stored.prefix(StreamViewModel.maxChannelPresets))
            // Rewrite storage when it is still the legacy [String] form, or when it
            // was over the cap and got trimmed. Otherwise leave it untouched — an
            // unconditional rewrite would fire on every launch.
            let wasLegacy = StreamViewModel.presetStorageIsLegacy(defaults)
            let storedCount = (defaults.object(forKey: ContentView.channelPresetsKey) as? [Any])?.count ?? 0
            if wasLegacy || storedCount != sanitizedPresets.count {
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
                return ChannelPreset.fromStoredDictionary(dict)
            }
            if let url = item as? String {
                return ChannelPreset.fromLegacyString(url)
            }
            return nil
        }
        return presets.isEmpty ? nil : presets
    }

    /// True when persisted presets are still in the pre-migration `[String]` form.
    /// Detected by element type, which survives CFPreferences bridging — unlike
    /// casting the whole array to `[[String: String]]`, which fails for dict
    /// arrays imported via `defaults import`.
    static func presetStorageIsLegacy(_ defaults: UserDefaults) -> Bool {
        guard let raw = defaults.object(forKey: ContentView.channelPresetsKey) as? [Any] else {
            return false
        }
        return raw.contains { $0 is String }
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

    /// Clears the active stream, whether it came from a preset or was typed by hand.
    ///
    /// Clears `streamURL` as well as the selection. Leaving the URL behind would not
    /// survive a relaunch: `init()` re-derives `selectedPresetIndex` by matching the
    /// stored URL against the preset list, so the selection would silently come back.
    ///
    /// Blocked under MDM — the administrator's `DefaultChannel` is meant to play
    /// unattended, and `init()` would re-apply it on the next launch anyway.
    func clearStream() {
        guard !channelPresetsManaged else { return }
        selectedPresetIndex = nil
        streamURL = ""
        UserDefaults.standard.removeObject(forKey: ContentView.lastStreamURLKey)
        persistSelectedPresetIndex()
    }

    /// Pressing the already-selected preset clears it — the same effect as Clear Stream.
    func deselectPreset() {
        clearStream()
    }

    /// False when there is nothing to clear, or when MDM owns the selection.
    var canClearStream: Bool {
        !channelPresetsManaged && (!streamURL.isEmpty || selectedPresetIndex != nil)
    }

    /// True when tapping preset `index` would clear the selection rather than set it.
    func isPresetSelected(_ index: Int) -> Bool {
        selectedPresetIndex == index
    }

    /// True when preset `index` is the stream currently loaded in the player.
    func isPlayingPreset(at index: Int) -> Bool {
        player != nil && selectedPresetIndex == index
    }

    /// Appends a preset. Defaults produce a blank entry; the Add Preset screen
    /// supplies both values so the list never gains an empty row.
    @discardableResult
    func addChannelPreset(name: String = "", url: String = "") -> Int? {
        guard !channelPresetsManaged, channelPresets.count < StreamViewModel.maxChannelPresets else { return nil }
        channelPresets.append(ChannelPreset(name: name, url: url))
        persistChannelPresets()
        return channelPresets.indices.last
    }

    func removeChannelPreset(at index: Int) {
        guard !channelPresetsManaged, channelPresets.indices.contains(index) else { return }
        // Refuse to remove the entry that is currently playing. The UI disables the
        // button, but enforce it here too: deleting it would shift every later index
        // while the player keeps running against a preset that no longer exists.
        guard !isPlayingPreset(at: index) else { return }
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
        // Editing the entry that is on screen would leave it describing something
        // other than what the player is actually streaming.
        guard !isPlayingPreset(at: index) else { return }
        channelPresets[index].url = url
        persistChannelPresets()

        if selectedPresetIndex == index {
            updateStreamURL(url, selectedPresetIndex: index)
        } else if selectedPresetIndex == nil, streamURL == url {
            updateStreamURL(url)
        }
    }

    /// What the main screen actually shows, resolving empty to the default.
    var effectiveDisplayTitle: String {
        let trimmed = displayTitle.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? StreamViewModel.defaultDisplayTitle : trimmed
    }

    /// Persists a custom title. Blank input clears the override rather than storing
    /// an empty heading, so the field doubles as "reset to default".
    func updateDisplayTitle(_ title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        displayTitle = trimmed
        if trimmed.isEmpty {
            UserDefaults.standard.removeObject(forKey: ContentView.displayTitleKey)
        } else {
            UserDefaults.standard.set(trimmed, forKey: ContentView.displayTitleKey)
        }
    }

    func updateViewOnlyMode(_ enabled: Bool) {
        viewOnlyMode = enabled
        UserDefaults.standard.set(enabled, forKey: ContentView.viewOnlyModeKey)
    }

    /// True when Settings should demand a PIN before opening.
    var settingsLocked: Bool {
        !settingsPIN.isEmpty
    }

    /// Case- and whitespace-insensitive comparison, so a stray space typed on the
    /// on-screen keyboard does not read as a wrong PIN.
    func isCorrectSettingsPIN(_ candidate: String) -> Bool {
        guard settingsLocked else { return true }
        return candidate.trimmingCharacters(in: .whitespaces) == settingsPIN
    }

    /// Shortest PIN the UI will store. A one-character PIN is almost always a
    /// half-typed one, and it locks the very screen needed to correct it.
    static let minimumSettingsPINLength = 6

    /// Digits only, at least `minimumSettingsPINLength`.
    static func isValidSettingsPIN(_ candidate: String) -> Bool {
        let trimmed = candidate.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= minimumSettingsPINLength else { return false }
        return trimmed.allSatisfy(\.isNumber)
    }

    /// Sets a PIN, returning false and changing nothing if it is invalid or MDM-owned.
    ///
    /// Deliberately not a property setter: an earlier version wrote through on every
    /// keystroke, so typing the first digit of a longer PIN stored a one-character
    /// PIN and locked the user out.
    @discardableResult
    func setSettingsPIN(_ pin: String) -> Bool {
        guard !settingsPINManaged else { return false }
        guard StreamViewModel.isValidSettingsPIN(pin) else { return false }
        let trimmed = pin.trimmingCharacters(in: .whitespaces)
        settingsPIN = trimmed
        UserDefaults.standard.set(trimmed, forKey: ContentView.settingsPINKey)
        return true
    }

    /// Removes the lock. Refused when MDM owns the PIN.
    @discardableResult
    func clearSettingsPIN() -> Bool {
        guard !settingsPINManaged else { return false }
        settingsPIN = ""
        UserDefaults.standard.removeObject(forKey: ContentView.settingsPINKey)
        return true
    }

    func updateConfirmBeforeDelete(_ enabled: Bool) {
        confirmBeforeDelete = enabled
        UserDefaults.standard.set(enabled, forKey: ContentView.confirmBeforeDeleteKey)
    }

    func updateChannelPresetName(at index: Int, name: String) {
        guard channelPresets.indices.contains(index), !channelPresetsManaged else { return }
        guard !isPlayingPreset(at: index) else { return }
        channelPresets[index].name = name
        persistChannelPresets()
    }

    var canAddMorePresets: Bool {
        !channelPresetsManaged && channelPresets.count < StreamViewModel.maxChannelPresets
    }

    func playStream() {
        guard let url = URL(string: streamURL) else { return }
        playbackStoppedByUser = false
        resetProgressTracking()
        player = AVPlayer(url: url)
        player?.play()
    }

    func startStreamIfNeeded() {
        // Respect an explicit stop: without this, returning to the foreground would
        // resurrect the player the user just dismissed.
        guard !playbackStoppedByUser else { return }
        guard let url = URL(string: streamURL) else { return }
        resetProgressTracking()
        player = AVPlayer(url: url)
        if isPlayingOnOpen {
            player?.play()
        }
        startRetryTimer()
    }

    /// Tears playback down. Leaving the fullscreen player only hides it — the
    /// AVPlayer keeps running (audible), so the main screen needs a way to end it.
    ///
    /// Also stops the retry timer. The watchdog treats a missing player as a fault to
    /// repair, so leaving it running would rebuild the stream the user just ended —
    /// `playbackStoppedByUser` guards the same case, and both are deliberate.
    func stopPlayback() {
        playbackStoppedByUser = true
        player?.pause()
        player = nil
        resetProgressTracking()
        stopRetryTimer()
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
        // [weak self]: the timer is retained by this object, so a strong capture would
        // keep the pair alive together.
        retryTimer = Timer.scheduledTimer(withTimeInterval: retryTimeout, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.evaluatePlaybackHealth()
            }
        }
    }

    /// One tick of the watchdog. Internal rather than private so a test can drive it
    /// directly instead of waiting on a Timer.
    func evaluatePlaybackHealth() {
        switch StreamViewModel.recoveryDecision(for: samplePlayback(),
                                                autoResume: autoResume,
                                                stoppedByUser: playbackStoppedByUser,
                                                stallThreshold: stallThreshold) {
        case .leaveAlone:
            break
        case .reload(let reason):
            reloadPlayer(reason: reason)
        }
    }

    /// Samples the player, advancing the progress clock as a side effect.
    private func samplePlayback(now: Date = Date()) -> PlaybackSnapshot {
        guard let player else {
            resetProgressTracking()
            return PlaybackSnapshot(hasPlayer: false, hasItem: false, itemFailed: false,
                                    isPaused: true, secondsSinceProgress: 0)
        }

        let current = player.currentTime()
        let advanced = current.isValid && lastObservedTime.isValid && current > lastObservedTime
        if lastProgressAt == nil || advanced {
            lastProgressAt = now
        }
        lastObservedTime = current

        return PlaybackSnapshot(
            hasPlayer: true,
            hasItem: player.currentItem != nil,
            itemFailed: player.currentItem?.status == .failed,
            isPaused: player.timeControlStatus == .paused,
            secondsSinceProgress: now.timeIntervalSince(lastProgressAt ?? now)
        )
    }

    private func resetProgressTracking() {
        lastObservedTime = .invalid
        lastProgressAt = nil
    }

    private func reloadPlayer(reason: String) {
        guard let url = URL(string: streamURL) else { return }
        logger.log(autoResumeLogMessage(reason: reason))
        resetProgressTracking()
        player = AVPlayer(url: url)
        // Always play. Recovery only runs when playback was expected, so deferring to
        // isPlayingOnOpen here would leave a repaired display sitting on a paused
        // player. That flag governs launch, not repair.
        player?.play()
    }

    private func autoResumeLogMessage(reason: String) -> String {
        "Auto-resuming stream (\(reason)): \(streamURL)"
    }

    // Exposed for testing: emits exactly what a real recovery emits, so a test can
    // assert the wording without driving an AVPlayer into a genuine failure.
    func emitAutoResumeLogForTesting(reason: String = "no player item") {
        logger.log(autoResumeLogMessage(reason: reason))
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
