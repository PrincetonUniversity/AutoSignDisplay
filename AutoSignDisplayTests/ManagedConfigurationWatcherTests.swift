//
//  ManagedConfigurationWatcherTests.swift
//  AutoSignDisplayTests
//
//  Rules for deciding that a managed payload has changed.
//
//  The gating these cover is the whole reason the watcher exists rather than a plain
//  `UserDefaults.didChangeNotification` observer. That notification fires for every
//  defaults write, and StreamViewModel writes on nearly every mutation — so an
//  ungated observer would let the app's own writes trigger a reconcile, which writes
//  again, without bound. Comparing the managed dictionary against the last applied one
//  is what breaks the cycle, and `anAppOwnedKeyChangingIsNotAPayloadChange` is the test
//  that holds that line.
//

import Foundation
import Testing
@testable import AutoSignDisplay

struct ManagedConfigurationWatcherTests {

    private func decide(_ previous: [String: Any]?, _ current: [String: Any]?) -> Bool {
        ManagedConfigurationWatcher.needsReconcile(previous: previous, current: current)
    }

    private let payload: [String: Any] = [
        AppConfigKeys.displayTitle: "Lobby",
        AppConfigKeys.playOnOpen: true,
        AppConfigKeys.channelPresets: [["Name": "A", "URL": "https://a.example/1.m3u8"]],
    ]

    // MARK: - The loop guard

    @Test func anAppOwnedKeyChangingIsNotAPayloadChange() {
        // The app rewrites lastStreamURL, selectedPresetIndex and friends constantly.
        // None of that touches the managed dictionary, so the comparison must see no
        // change at all — this is what stops reconcile from feeding itself.
        #expect(decide(payload, payload) == false)
    }

    @Test func anIdenticalPayloadRepushedIsNotAChange() {
        // MDM re-sends unchanged configuration routinely; acting on it would restart
        // playback for no reason.
        let same: [String: Any] = [
            AppConfigKeys.displayTitle: "Lobby",
            AppConfigKeys.playOnOpen: true,
            AppConfigKeys.channelPresets: [["Name": "A", "URL": "https://a.example/1.m3u8"]],
        ]
        #expect(decide(payload, same) == false)
    }

    // MARK: - Real transitions

    @Test func aPayloadArrivingIsAChange() {
        #expect(decide(nil, payload) == true)
    }

    @Test func aPayloadBeingRemovedIsAChange() {
        // Removal has to reconcile too: AppConfig resets presets and clears the managed
        // flags, and a display left on an administrator's locked channel list after the
        // payload was pulled would be stuck.
        #expect(decide(payload, nil) == true)
    }

    @Test func aChangedScalarIsAChange() {
        var changed = payload
        changed[AppConfigKeys.displayTitle] = "Auditorium"
        #expect(decide(payload, changed) == true)
    }

    @Test func aChangedNestedPresetListIsAChange() {
        // The comparison has to be deep. A new channel list is the most likely edit an
        // administrator makes, and it lives inside a nested array of dictionaries.
        var changed = payload
        changed[AppConfigKeys.channelPresets] = [["Name": "B", "URL": "https://b.example/2.m3u8"]]
        #expect(decide(payload, changed) == true)
    }

    @Test func addingAKeyIsAChange() {
        var changed = payload
        changed[AppConfigKeys.viewOnlyMode] = true
        #expect(decide(payload, changed) == true)
    }

    @Test func removingAKeyIsAChange() {
        // Dropping SettingsPIN is the documented way to clear a forgotten managed PIN,
        // so it must reconcile rather than be ignored.
        var changed = payload
        changed.removeValue(forKey: AppConfigKeys.playOnOpen)
        #expect(decide(payload, changed) == true)
    }

    @Test func noPayloadBeforeOrAfterIsNotAChange() {
        // The unmanaged case, which is most installs. Must be completely inert.
        #expect(decide(nil, nil) == false)
    }

    // MARK: - Wiring

    @Test func theWatcherSeedsItselfSoLaunchDoesNotReconcileImmediately() {
        // The payload has already been applied by App.init() before the watcher is
        // created; treating it as new would reconcile on every launch and restart
        // playback each time.
        let suite = UserDefaults(suiteName: "watcher-seed-\(UUID().uuidString)")!
        suite.set(["DisplayTitle": "Lobby"], forKey: AppConfigKeys.managedConfiguration)

        var reconciles = 0
        let watcher = ManagedConfigurationWatcher(defaults: suite, debounce: 0, logger: SilentLogger()) {
            reconciles += 1
        }
        watcher.checkNow()
        #expect(reconciles == 0, "A payload already applied at launch is not a change")

        // A genuine edit still reconciles.
        suite.set(["DisplayTitle": "Auditorium"], forKey: AppConfigKeys.managedConfiguration)
        watcher.checkNow()
        #expect(reconciles == 1)

        // And the same edit seen twice does not.
        watcher.checkNow()
        #expect(reconciles == 1, "Reconciling twice for one change would switch channel twice")

        watcher.stop()
        suite.removePersistentDomain(forName: suite.description)
    }

    private struct SilentLogger: Logger {
        func log(_ message: String) {}
    }
}
