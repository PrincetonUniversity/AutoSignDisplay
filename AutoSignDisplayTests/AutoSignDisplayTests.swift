//
//  AutoSignDisplayTests.swift
//  AutoSignDisplayTests
//
//  Created by migration agent.
//

import Foundation
import Testing
@testable import AutoSignDisplay

@MainActor
struct AutoSignDisplayTests {

    private func resetDefaults() async {
        await MainActor.run {
            let defaults = UserDefaults.standard
            let identifiers = [
                Bundle.main.bundleIdentifier,
                "edu.princeton.autosigndisplay"
            ].compactMap { $0 }

            // Remove all persistent domains
            for identifier in identifiers {
                defaults.removePersistentDomain(forName: identifier)
                if let suiteDefaults = UserDefaults(suiteName: identifier) {
                    suiteDefaults.removePersistentDomain(forName: identifier)
                    suiteDefaults.synchronize()
                }
            }

            // Remove all possible case variants for the keys
            let allKeys = [
                ContentView.lastStreamURLKey, "lastStreamURL", "LastStreamURL",
                ContentView.playOnOpenKey, "playOnAppOpen", "PlayOnAppOpen",
                ContentView.retryTimeoutKey, "retryTimeout", "RetryTimeout",
                ContentView.autoResumeKey, "autoResume", "AutoResume",
                ContentView.settingsDisabledKey, "settingsDisabled", "SettingsDisabled",
                ContentView.channelPresetsKey, "channelPresets", "ChannelPresets",
                ContentView.channelPresetsManagedKey, "channelPresetsManaged", "ChannelPresetsManaged",
                ContentView.defaultChannelKey, "defaultChannel", "DefaultChannel",
                ContentView.selectedPresetIndexKey, "selectedPresetIndex", "SelectedPresetIndex",
                ContentView.confirmBeforeDeleteKey, "confirmBeforeDelete", "ConfirmBeforeDelete",
                ContentView.displayTitleKey, "displayTitle", "DisplayTitle",
                ContentView.viewOnlyModeKey, "viewOnlyMode", "ViewOnlyMode",
                ContentView.settingsPINKey, "settingsPIN", "SettingsPIN",
                ContentView.settingsPINManagedKey, "settingsPINManaged", "SettingsPINManaged",
                "com.apple.configuration.managed"
            ]

            for key in allKeys {
                defaults.removeObject(forKey: key)
            }

            defaults.synchronize()
        }
    }

    private struct TestLogger: Logger {
        func log(_ message: String) {}
    }

    /// Reads channelPresets in either the new dict form or the legacy string form.
    /// Returns just the URLs — most tests only care about URL identity.
    private func persistedPresetURLs(_ defaults: UserDefaults) -> [String] {
        (StreamViewModel.loadPresets(from: defaults) ?? []).map { $0.url }
    }

    @Test func startStreamOnOpenUsesSelectedPreset() async throws {
        await resetDefaults()

        let presetURL = "https://example.com/channel.m3u8"

        let defaults = UserDefaults.standard
        defaults.set([presetURL], forKey: ContentView.channelPresetsKey)
        defaults.set(0, forKey: ContentView.selectedPresetIndexKey)
        defaults.set(true, forKey: ContentView.playOnOpenKey)
        defaults.removeObject(forKey: ContentView.lastStreamURLKey)

        let viewModel = StreamViewModel(logger: TestLogger())

        #expect(viewModel.streamURL == presetURL)
        #expect(viewModel.selectedPresetIndex == 0)

        viewModel.startStreamIfNeeded()

        #expect(viewModel.player != nil)

        viewModel.stopRetryTimer()
    }

    @Test func startStreamOnOpenReplacesStaleStoredURL() async throws {
        await resetDefaults()

        let presetURL = "https://example.com/managed-or-user.m3u8"

        let defaults = UserDefaults.standard
        defaults.set([presetURL], forKey: ContentView.channelPresetsKey)
        defaults.set(0, forKey: ContentView.selectedPresetIndexKey)
        defaults.set(true, forKey: ContentView.playOnOpenKey)
        defaults.set("https://example.com/stale.m3u8", forKey: ContentView.lastStreamURLKey)

        let viewModel = StreamViewModel(logger: TestLogger())

        #expect(viewModel.streamURL == presetURL)
        #expect(viewModel.selectedPresetIndex == 0)

        viewModel.startStreamIfNeeded()

        #expect(viewModel.player != nil)

        viewModel.stopRetryTimer()
    }

    @Test func startStreamOnOpenFromStoredURL() async throws {
        await resetDefaults()

        let storedURL = "https://example.com/typed-stream.m3u8"

        let defaults = UserDefaults.standard
        defaults.set(storedURL, forKey: ContentView.lastStreamURLKey)
        defaults.set(true, forKey: ContentView.playOnOpenKey)

        let viewModel = StreamViewModel(logger: TestLogger())

        #expect(viewModel.streamURL == storedURL)
        #expect(viewModel.selectedPresetIndex == nil)

        viewModel.startStreamIfNeeded()

        #expect(viewModel.player != nil)

        viewModel.stopRetryTimer()
    }

    @Test func startStreamOnReopenCreatesPlayer() async throws {
        await resetDefaults()

        let storedURL = "https://example.com/reopen-stream.m3u8"

        let defaults = UserDefaults.standard
        defaults.set(storedURL, forKey: ContentView.lastStreamURLKey)
        defaults.set(true, forKey: ContentView.playOnOpenKey)

        let viewModel = StreamViewModel(logger: TestLogger())

        viewModel.startStreamIfNeeded()
        #expect(viewModel.player != nil)

        viewModel.stopRetryTimer()
        viewModel.player = nil

        viewModel.startStreamIfNeeded()

        #expect(viewModel.player != nil)

        viewModel.stopRetryTimer()
    }

    @Test func presetSelectionPersistsAcrossReopen() async throws {
        await resetDefaults()

        let presetURL = "https://example.com/preset-stream.m3u8"

        let defaults = UserDefaults.standard
        defaults.set([presetURL], forKey: ContentView.channelPresetsKey)
        defaults.set(0, forKey: ContentView.selectedPresetIndexKey)
        defaults.set(true, forKey: ContentView.playOnOpenKey)
        defaults.removeObject(forKey: ContentView.lastStreamURLKey)

        @MainActor func makeViewModel() -> StreamViewModel {
            StreamViewModel(logger: TestLogger())
        }

        let firstViewModel = await MainActor.run { makeViewModel() }

        #expect(firstViewModel.streamURL == presetURL)
        #expect(firstViewModel.selectedPresetIndex == 0)

        firstViewModel.startStreamIfNeeded()
        #expect(firstViewModel.player != nil)

        firstViewModel.stopRetryTimer()
        firstViewModel.player = nil

        let secondViewModel = await MainActor.run { makeViewModel() }

        #expect(secondViewModel.streamURL == presetURL)
        #expect(secondViewModel.selectedPresetIndex == 0)

        secondViewModel.startStreamIfNeeded()
        #expect(secondViewModel.player != nil)

        secondViewModel.stopRetryTimer()
    }

    // MARK: - Managed Configuration Tests

    @Test func validManagedConfigIsApplied() async throws {
        await resetDefaults()

        let defaults = UserDefaults.standard

        // Load valid config from plist
        await MainActor.run {
            AppConfig.loadConfigurationFromFile("ValidManagedConfig", logger: TestLogger())
        }

        // Verify all settings were applied
        #expect(defaults.bool(forKey: ContentView.playOnOpenKey) == true)
        #expect(defaults.bool(forKey: ContentView.autoResumeKey) == true)
        #expect(defaults.double(forKey: ContentView.retryTimeoutKey) == 5.0)
        #expect(defaults.string(forKey: ContentView.lastStreamURLKey) == "https://test.example.com/stream.m3u8")

        let presets = persistedPresetURLs(defaults)
        #expect(presets.count == 3)
        #expect(presets.first == "https://test.example.com/channel1.m3u8")

        #expect(defaults.bool(forKey: ContentView.channelPresetsManagedKey) == true)
        #expect(defaults.integer(forKey: ContentView.selectedPresetIndexKey) == 0)
    }

    @Test func invalidManagedConfigIsRejected() async throws {
        await resetDefaults()

        let defaults = UserDefaults.standard

        // Load invalid config from plist
        await MainActor.run {
            AppConfig.loadConfigurationFromFile("InvalidManagedConfig", logger: TestLogger())
        }

        // PlayOnAppOpen as String should be ignored
        #expect(defaults.object(forKey: ContentView.playOnOpenKey) == nil)

        // RetryTimeout as String should be ignored
        #expect(defaults.object(forKey: ContentView.retryTimeoutKey) == nil)

        // AutoResume as Integer should be ignored
        #expect(defaults.object(forKey: ContentView.autoResumeKey) == nil)

        // DefaultChannel as Array should be ignored
        #expect(defaults.object(forKey: ContentView.defaultChannelKey) == nil)

        // ChannelPresets with mixed types should extract only valid Strings
        let presets = persistedPresetURLs(defaults)
        #expect(presets.count == 2)
        #expect(presets.contains("https://test.example.com/channel1.m3u8"))
        #expect(presets.contains("https://test.example.com/channel2.m3u8"))

        // Should still be marked as managed since we got valid presets
        #expect(defaults.bool(forKey: ContentView.channelPresetsManagedKey) == true)
    }

    @Test func emptyChannelPresetsAreRejected() async throws {
        await resetDefaults()

        let defaults = UserDefaults.standard

        // Load config with empty ChannelPresets
        await MainActor.run {
            AppConfig.loadConfigurationFromFile("EmptyManagedConfig", logger: TestLogger())
        }

        // Empty presets should be rejected
        #expect(defaults.object(forKey: ContentView.channelPresetsKey) == nil)
        #expect(defaults.bool(forKey: ContentView.channelPresetsManagedKey) == false)
    }

    @Test func negativeRetryTimeoutIsRejected() async throws {
        await resetDefaults()

        let defaults = UserDefaults.standard

        // Load config with negative RetryTimeout
        await MainActor.run {
            AppConfig.loadConfigurationFromFile("NegativeRetryTimeoutConfig", logger: TestLogger())
        }

        // Negative timeout should be rejected
        #expect(defaults.object(forKey: ContentView.retryTimeoutKey) == nil)
    }

    @Test func malformedConfigDoesNotCrashApp() async throws {
        await resetDefaults()

        // Attempt to load non-existent file should not crash
        await MainActor.run {
            AppConfig.loadConfigurationFromFile("NonExistentConfig", logger: TestLogger())
        }

        let defaults = UserDefaults.standard
        // App should remain in clean state
        #expect(defaults.bool(forKey: ContentView.channelPresetsManagedKey) == false)
    }

    @Test func managedConfigWithValidAndInvalidMixture() async throws {
        await resetDefaults()

        let defaults = UserDefaults.standard

        // Create a config with mix of valid and invalid entries
        let mixedConfig: [String: Any] = [
            AppConfigKeys.playOnOpen: true,           // Valid
            AppConfigKeys.retryTimeout: "invalid",    // Invalid (String instead of Double)
            AppConfigKeys.autoResume: false,          // Valid
            AppConfigKeys.channelPresets: [           // Valid with one invalid entry
                "https://test.example.com/valid1.m3u8",
                12345,  // Invalid (Integer)
                "https://test.example.com/valid2.m3u8"
            ]
        ]

        await MainActor.run {
            defaults.set(mixedConfig, forKey: "com.apple.configuration.managed")
            AppConfig.applyConfiguration(logger: TestLogger())
        }

        // Valid settings should be applied
        #expect(defaults.bool(forKey: ContentView.playOnOpenKey) == true)
        #expect(defaults.bool(forKey: ContentView.autoResumeKey) == false)

        // Invalid settings should be ignored
        #expect(defaults.object(forKey: ContentView.retryTimeoutKey) == nil)

        // Valid presets should be extracted
        let presets = persistedPresetURLs(defaults)
        #expect(presets.count == 2)
        #expect(defaults.bool(forKey: ContentView.channelPresetsManagedKey) == true)
    }

    // MARK: - Unmanaged Mode Preset Management Tests

    @Test func unmanagedModeCanAddEditAndRemovePresets() async throws {
        await resetDefaults()

        let defaults = UserDefaults.standard
        defaults.set(false, forKey: ContentView.channelPresetsManagedKey)
        defaults.set(["https://example.com/preset1.m3u8"], forKey: ContentView.channelPresetsKey)

        @MainActor func makeViewModel() -> StreamViewModel {
            StreamViewModel(logger: TestLogger())
        }

        // Initial state: one preset
        var vm = await MainActor.run { makeViewModel() }
        #expect(vm.channelPresets.count == 1)
        #expect(vm.canAddMorePresets == true)

        // Add a preset
        await MainActor.run {
            vm.addChannelPreset()
        }
        #expect(vm.channelPresets.count == 2)
        #expect(persistedPresetURLs(defaults).count == 2)

        // Simulate returning to main screen and back
        vm.stopRetryTimer()
        vm = await MainActor.run { makeViewModel() }
        #expect(vm.channelPresets.count == 2)

        // Edit the newly added preset
        await MainActor.run {
            vm.updateChannelPreset(at: 1, url: "https://example.com/preset2.m3u8")
        }
        let editedPresets = persistedPresetURLs(defaults)
        #expect(editedPresets[1] == "https://example.com/preset2.m3u8")

        // Simulate returning to main screen
        vm.stopRetryTimer()
        vm = await MainActor.run { makeViewModel() }

        // Remove the newly added preset
        await MainActor.run {
            vm.removeChannelPreset(at: 1)
        }
        #expect(vm.channelPresets.count == 1)
        let finalPresets = persistedPresetURLs(defaults)
        #expect(finalPresets.count == 1)
        #expect(finalPresets[0] == "https://example.com/preset1.m3u8")

        vm.stopRetryTimer()
    }

    @Test func unmanagedModePresetOperationsArePersisted() async throws {
        await resetDefaults()

        let defaults = UserDefaults.standard
        defaults.set(false, forKey: ContentView.channelPresetsManagedKey)
        defaults.set(["https://example.com/original.m3u8"], forKey: ContentView.channelPresetsKey)

        @MainActor func makeViewModel() -> StreamViewModel {
            StreamViewModel(logger: TestLogger())
        }

        var vm = await MainActor.run { makeViewModel() }

        // Add three presets in sequence
        await MainActor.run {
            vm.addChannelPreset()
            vm.updateChannelPreset(at: 1, url: "https://example.com/new1.m3u8")
        }

        vm.stopRetryTimer()
        vm = await MainActor.run { makeViewModel() }

        #expect(vm.channelPresets.count == 2)

        await MainActor.run {
            vm.addChannelPreset()
            vm.updateChannelPreset(at: 2, url: "https://example.com/new2.m3u8")
        }

        vm.stopRetryTimer()
        vm = await MainActor.run { makeViewModel() }

        // Verify all three presets persist
        #expect(vm.channelPresets.count == 3)
        #expect(vm.channelPresets[0].url == "https://example.com/original.m3u8")
        #expect(vm.channelPresets[1].url == "https://example.com/new1.m3u8")
        #expect(vm.channelPresets[2].url == "https://example.com/new2.m3u8")

        vm.stopRetryTimer()
    }

    // MARK: - Managed Mode Preset Management Tests

    @Test func managedModeCannotAddPresets() async throws {
        await resetDefaults()

        let defaults = UserDefaults.standard

        // Set up managed configuration
        let managedPresets = [
            "https://admin.example.com/channel1.m3u8",
            "https://admin.example.com/channel2.m3u8"
        ]
        defaults.set(managedPresets, forKey: ContentView.channelPresetsKey)
        defaults.set(true, forKey: ContentView.channelPresetsManagedKey)

        let vm = StreamViewModel(logger: TestLogger())

        // Verify managed state
        #expect(vm.channelPresetsManaged == true)
        #expect(vm.canAddMorePresets == false)
        #expect(vm.channelPresets.count == 2)

        // Attempt to add preset (should be ignored)
        vm.addChannelPreset()

        // Presets should remain unchanged
        #expect(vm.channelPresets.count == 2)
        #expect(persistedPresetURLs(defaults).count == 2)

        vm.stopRetryTimer()
    }

    @Test func managedModeCannotRemovePresets() async throws {
        await resetDefaults()

        let defaults = UserDefaults.standard

        // Set up managed configuration
        let managedPresets = [
            "https://admin.example.com/channel1.m3u8",
            "https://admin.example.com/channel2.m3u8",
            "https://admin.example.com/channel3.m3u8"
        ]
        defaults.set(managedPresets, forKey: ContentView.channelPresetsKey)
        defaults.set(true, forKey: ContentView.channelPresetsManagedKey)

        let vm = StreamViewModel(logger: TestLogger())

        // Verify initial state
        #expect(vm.channelPresets.count == 3)

        // Attempt to remove preset (should be ignored)
        vm.removeChannelPreset(at: 1)

        // Presets should remain unchanged
        #expect(vm.channelPresets.count == 3)
        #expect(persistedPresetURLs(defaults).count == 3)

        vm.stopRetryTimer()
    }

    @Test func managedModeCannotEditPresets() async throws {
        await resetDefaults()

        let defaults = UserDefaults.standard

        // Set up managed configuration
        let managedPresets = [
            "https://admin.example.com/channel1.m3u8",
            "https://admin.example.com/channel2.m3u8"
        ]
        defaults.set(managedPresets, forKey: ContentView.channelPresetsKey)
        defaults.set(true, forKey: ContentView.channelPresetsManagedKey)

        let vm = StreamViewModel(logger: TestLogger())

        // Verify initial state
        #expect(vm.channelPresets[0].url == managedPresets[0])

        // Attempt to edit preset (should be ignored)
        vm.updateChannelPreset(at: 0, url: "https://hacker.example.com/bad.m3u8")

        // Preset should remain unchanged
        #expect(vm.channelPresets[0].url == managedPresets[0])
        let persistedValue = persistedPresetURLs(defaults).first ?? ""
        #expect(persistedValue == managedPresets[0])

        vm.stopRetryTimer()
    }

    @Test func managedModeOperationsIgnoredAcrossScreenTransitions() async throws {
        await resetDefaults()

        let defaults = UserDefaults.standard

        // Set up managed configuration
        let managedPresets = [
            "https://admin.example.com/channel1.m3u8",
            "https://admin.example.com/channel2.m3u8"
        ]
        defaults.set(managedPresets, forKey: ContentView.channelPresetsKey)
        defaults.set(true, forKey: ContentView.channelPresetsManagedKey)

        @MainActor func makeViewModel() -> StreamViewModel {
            StreamViewModel(logger: TestLogger())
        }

        var vm = await MainActor.run { makeViewModel() }

        // Attempt to add
        await MainActor.run {
            vm.addChannelPreset()
        }
        #expect(vm.channelPresets.count == 2)

        // Return to main screen
        vm.stopRetryTimer()
        vm = await MainActor.run { makeViewModel() }

        // Verify still 2 presets
        #expect(vm.channelPresets.count == 2)

        // Attempt to remove
        await MainActor.run {
            vm.removeChannelPreset(at: 0)
        }
        #expect(vm.channelPresets.count == 2)

        // Return to main screen again
        vm.stopRetryTimer()
        vm = await MainActor.run { makeViewModel() }

        // Verify still 2 presets and still managed
        #expect(vm.channelPresets.count == 2)
        #expect(vm.channelPresetsManaged == true)

        vm.stopRetryTimer()
    }

    // MARK: - Named Preset Support

    @Test func managedConfigAcceptsDictPresetsWithNames() async throws {
        await resetDefaults()
        let defaults = UserDefaults.standard

        let config: [String: Any] = [
            AppConfigKeys.channelPresets: [
                ["Name": "Local News", "URL": "https://a.example.com/1.m3u8"],
                ["URL": "https://b.example.com/2.m3u8"],                       // Name omitted
                ["Name": "", "URL": "https://c.example.com/3.m3u8"],           // empty Name allowed
                ["Name": "Ignored (no URL)"],                                  // dropped — URL required
                ["Name": "Ignored (empty URL)", "URL": "  "]                   // dropped — URL blank
            ]
        ]

        await MainActor.run {
            defaults.set(config, forKey: "com.apple.configuration.managed")
            AppConfig.applyConfiguration(logger: TestLogger())
        }

        let vm = await MainActor.run { StreamViewModel(logger: TestLogger()) }
        #expect(vm.channelPresets.count == 3)
        #expect(vm.channelPresets[0] == ChannelPreset(name: "Local News", url: "https://a.example.com/1.m3u8"))
        #expect(vm.channelPresets[1] == ChannelPreset(name: "", url: "https://b.example.com/2.m3u8"))
        #expect(vm.channelPresets[2] == ChannelPreset(name: "", url: "https://c.example.com/3.m3u8"))
        #expect(vm.channelPresetsManaged == true)
        vm.stopRetryTimer()
    }

    @Test func legacyStringPresetsMigrateOnRead() async throws {
        await resetDefaults()
        let defaults = UserDefaults.standard
        // Simulate a pre-migration install: presets stored as [String].
        defaults.set(false, forKey: ContentView.channelPresetsManagedKey)
        defaults.set(
            ["https://legacy.example.com/a.m3u8", "https://legacy.example.com/b.m3u8"],
            forKey: ContentView.channelPresetsKey
        )

        let vm = await MainActor.run { StreamViewModel(logger: TestLogger()) }
        #expect(vm.channelPresets.count == 2)
        #expect(vm.channelPresets[0] == ChannelPreset(name: "", url: "https://legacy.example.com/a.m3u8"))
        #expect(vm.channelPresets[1] == ChannelPreset(name: "", url: "https://legacy.example.com/b.m3u8"))
        // Init should have rewritten the value in the new dict form.
        #expect(defaults.array(forKey: ContentView.channelPresetsKey) is [[String: String]])
        vm.stopRetryTimer()
    }

    @Test func nameEditPersistsAndRoundTrips() async throws {
        await resetDefaults()
        let defaults = UserDefaults.standard
        defaults.set(false, forKey: ContentView.channelPresetsManagedKey)
        defaults.set(
            [["Name": "", "URL": "https://a.example.com/1.m3u8"]],
            forKey: ContentView.channelPresetsKey
        )

        @MainActor func makeVM() -> StreamViewModel { StreamViewModel(logger: TestLogger()) }

        var vm = await MainActor.run { makeVM() }
        await MainActor.run { vm.updateChannelPresetName(at: 0, name: "Homepage") }
        #expect(vm.channelPresets[0].name == "Homepage")

        // Re-init and check the name survived.
        vm.stopRetryTimer()
        vm = await MainActor.run { makeVM() }
        #expect(vm.channelPresets[0].name == "Homepage")
        #expect(vm.channelPresets[0].url == "https://a.example.com/1.m3u8")
        vm.stopRetryTimer()
    }

    // MARK: - View Only Mode

    @Test func viewOnlyModeDefaultsOffAndPersists() async throws {
        await resetDefaults()
        let defaults = UserDefaults.standard

        @MainActor func makeVM() -> StreamViewModel { StreamViewModel(logger: TestLogger()) }

        var vm = await MainActor.run { makeVM() }
        #expect(vm.viewOnlyMode == false)

        await MainActor.run { vm.updateViewOnlyMode(true) }
        #expect(defaults.bool(forKey: ContentView.viewOnlyModeKey) == true)

        vm.stopRetryTimer()
        vm = await MainActor.run { makeVM() }
        #expect(vm.viewOnlyMode == true)
        vm.stopRetryTimer()
    }

    @Test func managedViewOnlyModeRejectsIntegerBoolean() async throws {
        await resetDefaults()
        let defaults = UserDefaults.standard

        // A real CFBoolean is accepted.
        await MainActor.run {
            defaults.set([AppConfigKeys.viewOnlyMode: true],
                         forKey: "com.apple.configuration.managed")
            AppConfig.applyConfiguration(logger: TestLogger())
        }
        #expect(defaults.bool(forKey: ContentView.viewOnlyModeKey) == true)

        // An integer must be rejected: NSNumber(1) casts to Bool in Swift, so
        // without the objCType check this would silently read as true.
        await resetDefaults()
        await MainActor.run {
            defaults.set([AppConfigKeys.viewOnlyMode: NSNumber(value: 1)],
                         forKey: "com.apple.configuration.managed")
            AppConfig.applyConfiguration(logger: TestLogger())
        }
        #expect(defaults.object(forKey: ContentView.viewOnlyModeKey) == nil)
    }

    @Test func managedConfigRemovalClearsViewOnlyMode() async throws {
        await resetDefaults()
        let defaults = UserDefaults.standard

        await MainActor.run {
            defaults.set(
                [AppConfigKeys.viewOnlyMode: true,
                 AppConfigKeys.channelPresets: [["Name": "A", "URL": "https://a.example/1.m3u8"]]],
                forKey: "com.apple.configuration.managed"
            )
            AppConfig.applyConfiguration(logger: TestLogger())
        }
        #expect(defaults.bool(forKey: ContentView.viewOnlyModeKey) == true)

        await MainActor.run {
            defaults.removeObject(forKey: "com.apple.configuration.managed")
            AppConfig.applyConfiguration(logger: TestLogger())
        }
        #expect(defaults.object(forKey: ContentView.viewOnlyModeKey) == nil)
    }

    // MARK: - Settings PIN

    @Test func settingsUnlockedWhenNoPINSet() async throws {
        await resetDefaults()
        let vm = await MainActor.run { StreamViewModel(logger: TestLogger()) }
        #expect(vm.settingsLocked == false)
        // With no PIN configured, any candidate passes so the gate never blocks.
        #expect(vm.isCorrectSettingsPIN(""))
        #expect(vm.isCorrectSettingsPIN("anything"))
        vm.stopRetryTimer()
    }

    @Test func settingsPINGatesAndTolerLatesWhitespace() async throws {
        await resetDefaults()
        let defaults = UserDefaults.standard

        @MainActor func makeVM() -> StreamViewModel { StreamViewModel(logger: TestLogger()) }

        var vm = await MainActor.run { makeVM() }
        await MainActor.run { vm.setSettingsPIN("482159") }
        #expect(vm.settingsLocked)
        #expect(defaults.string(forKey: ContentView.settingsPINKey) == "482159")

        #expect(vm.isCorrectSettingsPIN("482159"))
        // A stray space from the on-screen keyboard should not read as wrong.
        #expect(vm.isCorrectSettingsPIN(" 482159 "))
        #expect(!vm.isCorrectSettingsPIN("123456"))
        #expect(!vm.isCorrectSettingsPIN(""))

        vm.stopRetryTimer()
        vm = await MainActor.run { makeVM() }
        #expect(vm.settingsLocked, "PIN must survive a relaunch.")

        // Removing the lock is now an explicit action, not a blank write.
        await MainActor.run { vm.clearSettingsPIN() }
        #expect(vm.settingsLocked == false)
        #expect(defaults.object(forKey: ContentView.settingsPINKey) == nil)
        vm.stopRetryTimer()
    }

    /// Regression guard for the lockout that shipped: the PIN field wrote through on
    /// every keystroke, so typing the first digit of a longer PIN stored a
    /// one-character PIN — locking the very screen needed to undo it.
    @Test func shortOrNonNumericPINsAreRefused() async throws {
        await resetDefaults()
        let defaults = UserDefaults.standard
        let vm = await MainActor.run { StreamViewModel(logger: TestLogger()) }

        for rejected in ["1", "12", "123", "1234", "12345", "", "   ", "12a4", "abcd", "12 34"] {
            let applied = await MainActor.run { vm.setSettingsPIN(rejected) }
            #expect(!applied, "\"\(rejected)\" must not be accepted as a PIN.")
            #expect(vm.settingsLocked == false)
            #expect(defaults.object(forKey: ContentView.settingsPINKey) == nil)
        }

        // Six digits is the floor.
        let applied = await MainActor.run { vm.setSettingsPIN("123456") }
        #expect(applied)
        #expect(vm.settingsLocked)
        #expect(defaults.string(forKey: ContentView.settingsPINKey) == "123456")
        vm.stopRetryTimer()
    }

    @Test func managedPINShorterThanTheMinimumIsRejected() async throws {
        await resetDefaults()
        let defaults = UserDefaults.standard

        // A short managed PIN locks a fleet out just as effectively.
        await MainActor.run {
            defaults.set([AppConfigKeys.settingsPIN: "1"],
                         forKey: "com.apple.configuration.managed")
            AppConfig.applyConfiguration(logger: TestLogger())
        }
        #expect(defaults.object(forKey: ContentView.settingsPINKey) == nil)
        #expect(defaults.bool(forKey: ContentView.settingsPINManagedKey) == false)

        // Managed PINs need not be numeric — an administrator may use a passphrase —
        // but they do have to clear the length floor.
        await resetDefaults()
        await MainActor.run {
            defaults.set([AppConfigKeys.settingsPIN: "lobby-2026"],
                         forKey: "com.apple.configuration.managed")
            AppConfig.applyConfiguration(logger: TestLogger())
        }
        #expect(defaults.string(forKey: ContentView.settingsPINKey) == "lobby-2026")
    }

    @Test func managedSettingsPINCannotBeChangedOnDevice() async throws {
        await resetDefaults()
        let defaults = UserDefaults.standard

        await MainActor.run {
            defaults.set([AppConfigKeys.settingsPIN: "  999911  "],
                         forKey: "com.apple.configuration.managed")
            AppConfig.applyConfiguration(logger: TestLogger())
        }
        // Trimmed on apply, and flagged as administrator-owned.
        #expect(defaults.string(forKey: ContentView.settingsPINKey) == "999911")
        #expect(defaults.bool(forKey: ContentView.settingsPINManagedKey) == true)

        let vm = await MainActor.run { StreamViewModel(logger: TestLogger()) }
        #expect(vm.settingsPINManaged)
        #expect(vm.isCorrectSettingsPIN("999911"))

        // A local user must not be able to change or clear it.
        await MainActor.run { vm.setSettingsPIN("000022") }
        #expect(vm.settingsPIN == "999911")
        await MainActor.run { vm.clearSettingsPIN() }
        #expect(vm.settingsPIN == "999911")
        vm.stopRetryTimer()
    }

    @Test func managedSettingsPINRejectsBlankAndWrongType() async throws {
        await resetDefaults()
        let defaults = UserDefaults.standard

        await MainActor.run {
            defaults.set([AppConfigKeys.settingsPIN: "   "],
                         forKey: "com.apple.configuration.managed")
            AppConfig.applyConfiguration(logger: TestLogger())
        }
        #expect(defaults.object(forKey: ContentView.settingsPINKey) == nil)
        #expect(defaults.bool(forKey: ContentView.settingsPINManagedKey) == false)

        await resetDefaults()
        await MainActor.run {
            defaults.set([AppConfigKeys.settingsPIN: 4821],
                         forKey: "com.apple.configuration.managed")
            AppConfig.applyConfiguration(logger: TestLogger())
        }
        #expect(defaults.object(forKey: ContentView.settingsPINKey) == nil)
    }

    @Test func droppingSettingsPINFromAPayloadClearsIt() async throws {
        await resetDefaults()
        let defaults = UserDefaults.standard
        let presets = [["Name": "A", "URL": "https://a.example/1.m3u8"]]

        // A managed PIN is in force.
        await MainActor.run {
            defaults.set([AppConfigKeys.settingsPIN: "482159",
                          AppConfigKeys.channelPresets: presets],
                         forKey: "com.apple.configuration.managed")
            AppConfig.applyConfiguration(logger: TestLogger())
        }
        #expect(defaults.string(forKey: ContentView.settingsPINKey) == "482159")
        #expect(defaults.bool(forKey: ContentView.settingsPINManagedKey) == true)

        // The administrator pushes a payload that still exists but no longer carries
        // SettingsPIN. This is the lockout-recovery path, and it must clear the PIN:
        // settingsPINManaged is reset regardless, so a lingering value would look
        // like a user-set PIN that nobody on site knows.
        await MainActor.run {
            defaults.set([AppConfigKeys.channelPresets: presets],
                         forKey: "com.apple.configuration.managed")
            AppConfig.applyConfiguration(logger: TestLogger())
        }
        #expect(defaults.object(forKey: ContentView.settingsPINKey) == nil)
        #expect(defaults.bool(forKey: ContentView.settingsPINManagedKey) == false)

        let vm = await MainActor.run { StreamViewModel(logger: TestLogger()) }
        #expect(vm.settingsLocked == false)
        vm.stopRetryTimer()
    }

    @Test func managedPayloadOverridesAUserSetPIN() async throws {
        await resetDefaults()
        let defaults = UserDefaults.standard

        // A user sets a PIN on-device and forgets it.
        let vm = await MainActor.run { StreamViewModel(logger: TestLogger()) }
        await MainActor.run { vm.setSettingsPIN("735192") }
        #expect(defaults.string(forKey: ContentView.settingsPINKey) == "735192")
        vm.stopRetryTimer()

        // Pushing a known PIN overrides it, which is the device-side recovery route.
        await MainActor.run {
            defaults.set([AppConfigKeys.settingsPIN: "000022"],
                         forKey: "com.apple.configuration.managed")
            AppConfig.applyConfiguration(logger: TestLogger())
        }
        #expect(defaults.string(forKey: ContentView.settingsPINKey) == "000022")

        let recovered = await MainActor.run { StreamViewModel(logger: TestLogger()) }
        #expect(recovered.isCorrectSettingsPIN("000022"))
        #expect(!recovered.isCorrectSettingsPIN("735192"))
        recovered.stopRetryTimer()
    }

    /// A user-set PIN with no MDM history is *not* cleared by a payload that omits
    /// SettingsPIN — there is no managed flag to key off. Pinning that here so the
    /// limitation is deliberate rather than discovered during an outage.
    @Test func payloadWithoutPINLeavesAUserSetPINAlone() async throws {
        await resetDefaults()
        let defaults = UserDefaults.standard

        let vm = await MainActor.run { StreamViewModel(logger: TestLogger()) }
        await MainActor.run { vm.setSettingsPIN("864209") }
        vm.stopRetryTimer()

        await MainActor.run {
            defaults.set([AppConfigKeys.channelPresets: [["Name": "A", "URL": "https://a.example/1.m3u8"]]],
                         forKey: "com.apple.configuration.managed")
            AppConfig.applyConfiguration(logger: TestLogger())
        }
        #expect(defaults.string(forKey: ContentView.settingsPINKey) == "864209",
                "Recovery requires pushing a known PIN, or reinstalling the app.")
    }

    @Test func managedConfigRemovalClearsSettingsPIN() async throws {
        await resetDefaults()
        let defaults = UserDefaults.standard

        await MainActor.run {
            defaults.set([AppConfigKeys.settingsPIN: "482159"],
                         forKey: "com.apple.configuration.managed")
            AppConfig.applyConfiguration(logger: TestLogger())
        }
        #expect(defaults.string(forKey: ContentView.settingsPINKey) == "482159")

        // Pulling the payload must not strand Settings behind a PIN nobody on site
        // knows. The managed flag alone is enough to trigger the reset, even with no
        // managed presets involved.
        await MainActor.run {
            defaults.removeObject(forKey: "com.apple.configuration.managed")
            AppConfig.applyConfiguration(logger: TestLogger())
        }
        #expect(defaults.object(forKey: ContentView.settingsPINKey) == nil)
        #expect(defaults.bool(forKey: ContentView.settingsPINManagedKey) == false)

        let vm = await MainActor.run { StreamViewModel(logger: TestLogger()) }
        #expect(vm.settingsLocked == false)
        vm.stopRetryTimer()
    }

    // MARK: - Display Title

    @Test func displayTitleFallsBackToDefaultWhenUnset() async throws {
        await resetDefaults()
        let vm = await MainActor.run { StreamViewModel(logger: TestLogger()) }
        #expect(vm.displayTitle == "")
        #expect(vm.effectiveDisplayTitle == StreamViewModel.defaultDisplayTitle)
        vm.stopRetryTimer()
    }

    @Test func displayTitleUpdatePersistsAndBlankClearsIt() async throws {
        await resetDefaults()
        let defaults = UserDefaults.standard

        @MainActor func makeVM() -> StreamViewModel { StreamViewModel(logger: TestLogger()) }

        var vm = await MainActor.run { makeVM() }
        await MainActor.run { vm.updateDisplayTitle("Lobby Display") }
        #expect(vm.effectiveDisplayTitle == "Lobby Display")
        #expect(defaults.string(forKey: ContentView.displayTitleKey) == "Lobby Display")

        vm.stopRetryTimer()
        vm = await MainActor.run { makeVM() }
        #expect(vm.effectiveDisplayTitle == "Lobby Display")

        // Blank input clears the override rather than storing an empty heading, so
        // the field doubles as "reset to default".
        await MainActor.run { vm.updateDisplayTitle("   ") }
        #expect(vm.displayTitle == "")
        #expect(defaults.object(forKey: ContentView.displayTitleKey) == nil)
        #expect(vm.effectiveDisplayTitle == StreamViewModel.defaultDisplayTitle)
        vm.stopRetryTimer()
    }

    @Test func managedDisplayTitleIsAppliedAndTrimmed() async throws {
        await resetDefaults()
        let defaults = UserDefaults.standard

        await MainActor.run {
            defaults.set(
                [AppConfigKeys.displayTitle: "  Engineering Quad — Lobby  "],
                forKey: "com.apple.configuration.managed"
            )
            AppConfig.applyConfiguration(logger: TestLogger())
        }

        #expect(defaults.string(forKey: ContentView.displayTitleKey) == "Engineering Quad — Lobby")

        let vm = await MainActor.run { StreamViewModel(logger: TestLogger()) }
        #expect(vm.effectiveDisplayTitle == "Engineering Quad — Lobby")
        vm.stopRetryTimer()
    }

    @Test func managedDisplayTitleRejectsBlankAndWrongType() async throws {
        await resetDefaults()
        let defaults = UserDefaults.standard

        // Whitespace only: rejected, so the default heading stands rather than an
        // empty one.
        await MainActor.run {
            defaults.set([AppConfigKeys.displayTitle: "   "],
                         forKey: "com.apple.configuration.managed")
            AppConfig.applyConfiguration(logger: TestLogger())
        }
        #expect(defaults.object(forKey: ContentView.displayTitleKey) == nil)

        // Wrong type: also rejected.
        await resetDefaults()
        await MainActor.run {
            defaults.set([AppConfigKeys.displayTitle: 42],
                         forKey: "com.apple.configuration.managed")
            AppConfig.applyConfiguration(logger: TestLogger())
        }
        #expect(defaults.object(forKey: ContentView.displayTitleKey) == nil)
    }

    @Test func managedConfigRemovalClearsDisplayTitle() async throws {
        await resetDefaults()
        let defaults = UserDefaults.standard

        await MainActor.run {
            defaults.set(
                [AppConfigKeys.displayTitle: "Managed Heading",
                 AppConfigKeys.channelPresets: [["Name": "A", "URL": "https://a.example/1.m3u8"]]],
                forKey: "com.apple.configuration.managed"
            )
            AppConfig.applyConfiguration(logger: TestLogger())
        }
        #expect(defaults.string(forKey: ContentView.displayTitleKey) == "Managed Heading")

        // DisplayTitle is MDM-settable, so it must not outlive the payload.
        await MainActor.run {
            defaults.removeObject(forKey: "com.apple.configuration.managed")
            AppConfig.applyConfiguration(logger: TestLogger())
        }
        #expect(defaults.object(forKey: ContentView.displayTitleKey) == nil)

        let vm = await MainActor.run { StreamViewModel(logger: TestLogger()) }
        #expect(vm.effectiveDisplayTitle == StreamViewModel.defaultDisplayTitle)
        vm.stopRetryTimer()
    }

    // MARK: - Stopping Playback

    @Test func stopPlaybackClearsThePlayer() async throws {
        await resetDefaults()
        let defaults = UserDefaults.standard
        defaults.set("https://a.example.com/1.m3u8", forKey: ContentView.lastStreamURLKey)
        defaults.set(true, forKey: ContentView.playOnOpenKey)

        let vm = await MainActor.run { StreamViewModel(logger: TestLogger()) }
        await MainActor.run { vm.startStreamIfNeeded() }
        #expect(vm.player != nil)

        await MainActor.run { vm.stopPlayback() }
        #expect(vm.player == nil)
        vm.stopRetryTimer()
    }

    @Test func stopPlaybackSurvivesSceneReactivation() async throws {
        await resetDefaults()
        let defaults = UserDefaults.standard
        defaults.set("https://a.example.com/1.m3u8", forKey: ContentView.lastStreamURLKey)
        defaults.set(true, forKey: ContentView.playOnOpenKey)
        // autoResume on is the dangerous combination: the retry timer's resume
        // condition is `currentItem == nil`, which a nil player also satisfies.
        defaults.set(true, forKey: ContentView.autoResumeKey)

        let vm = await MainActor.run { StreamViewModel(logger: TestLogger()) }
        await MainActor.run { vm.startStreamIfNeeded() }
        await MainActor.run { vm.stopPlayback() }
        #expect(vm.player == nil)

        // ContentView calls this on every scenePhase == .active transition.
        await MainActor.run { vm.startStreamIfNeeded() }
        #expect(vm.player == nil, "An explicit stop must not be undone by reactivation.")

        vm.stopRetryTimer()
    }

    @Test func playStreamClearsTheStoppedFlag() async throws {
        await resetDefaults()
        let defaults = UserDefaults.standard
        defaults.set("https://a.example.com/1.m3u8", forKey: ContentView.lastStreamURLKey)

        let vm = await MainActor.run { StreamViewModel(logger: TestLogger()) }
        await MainActor.run { vm.startStreamIfNeeded() }
        await MainActor.run { vm.stopPlayback() }
        #expect(vm.player == nil)

        // Pressing Play Stream is explicit intent and must work after a stop.
        await MainActor.run { vm.playStream() }
        #expect(vm.player != nil)

        // ...and reactivation should work normally again from here.
        await MainActor.run { vm.startStreamIfNeeded() }
        #expect(vm.player != nil)
        vm.stopRetryTimer()
    }

    @Test func playingPresetCannotBeDeleted() async throws {
        await resetDefaults()
        let defaults = UserDefaults.standard
        defaults.set(false, forKey: ContentView.channelPresetsManagedKey)
        defaults.set(
            [["Name": "A", "URL": "https://a.example.com/1.m3u8"],
             ["Name": "B", "URL": "https://b.example.com/2.m3u8"]],
            forKey: ContentView.channelPresetsKey
        )

        let vm = await MainActor.run { StreamViewModel(logger: TestLogger()) }
        await MainActor.run {
            vm.selectPreset(at: 1)
            vm.playStream()
        }
        #expect(vm.player != nil)
        #expect(vm.isPlayingPreset(at: 1))
        #expect(!vm.isPlayingPreset(at: 0))

        // The playing entry is protected...
        await MainActor.run { vm.removeChannelPreset(at: 1) }
        #expect(vm.channelPresets.count == 2)

        // ...but the others are not.
        await MainActor.run { vm.removeChannelPreset(at: 0) }
        #expect(vm.channelPresets.count == 1)

        // Once stopped, it can be removed.
        await MainActor.run {
            vm.stopPlayback()
            vm.removeChannelPreset(at: 0)
        }
        #expect(vm.channelPresets.isEmpty)
        vm.stopRetryTimer()
    }

    @Test func playingPresetCannotBeEdited() async throws {
        await resetDefaults()
        let defaults = UserDefaults.standard
        defaults.set(false, forKey: ContentView.channelPresetsManagedKey)
        defaults.set(
            [["Name": "A", "URL": "https://a.example.com/1.m3u8"],
             ["Name": "B", "URL": "https://b.example.com/2.m3u8"]],
            forKey: ContentView.channelPresetsKey
        )

        let vm = await MainActor.run { StreamViewModel(logger: TestLogger()) }
        await MainActor.run {
            vm.selectPreset(at: 0)
            vm.playStream()
        }
        #expect(vm.isPlayingPreset(at: 0))

        // The playing entry is frozen...
        await MainActor.run {
            vm.updateChannelPresetName(at: 0, name: "Renamed")
            vm.updateChannelPreset(at: 0, url: "https://z.example.com/z.m3u8")
        }
        #expect(vm.channelPresets[0] == ChannelPreset(name: "A", url: "https://a.example.com/1.m3u8"))

        // ...while the others stay editable.
        await MainActor.run { vm.updateChannelPresetName(at: 1, name: "Renamed B") }
        #expect(vm.channelPresets[1].name == "Renamed B")

        // Stopping releases the lock.
        await MainActor.run {
            vm.stopPlayback()
            vm.updateChannelPresetName(at: 0, name: "Renamed A")
        }
        #expect(vm.channelPresets[0].name == "Renamed A")
        vm.stopRetryTimer()
    }

    // MARK: - Deselecting a Preset

    @Test func deselectPresetClearsSelectionAndURL() async throws {
        await resetDefaults()
        let defaults = UserDefaults.standard
        defaults.set(false, forKey: ContentView.channelPresetsManagedKey)
        defaults.set(
            [["Name": "A", "URL": "https://a.example/1.m3u8"],
             ["Name": "B", "URL": "https://b.example/2.m3u8"]],
            forKey: ContentView.channelPresetsKey
        )

        let vm = await MainActor.run { StreamViewModel(logger: TestLogger()) }
        await MainActor.run { vm.selectPreset(at: 1) }
        #expect(vm.selectedPresetIndex == 1)
        #expect(vm.streamURL == "https://b.example/2.m3u8")

        await MainActor.run { vm.deselectPreset() }
        #expect(vm.selectedPresetIndex == nil)
        #expect(vm.streamURL == "")
        #expect(defaults.object(forKey: ContentView.selectedPresetIndexKey) == nil)
        #expect(defaults.object(forKey: ContentView.lastStreamURLKey) == nil)
        vm.stopRetryTimer()
    }

    @Test func deselectSurvivesReinitialization() async throws {
        await resetDefaults()
        let defaults = UserDefaults.standard
        defaults.set(false, forKey: ContentView.channelPresetsManagedKey)
        defaults.set(
            [["Name": "A", "URL": "https://a.example/1.m3u8"]],
            forKey: ContentView.channelPresetsKey
        )

        @MainActor func makeVM() -> StreamViewModel { StreamViewModel(logger: TestLogger()) }

        var vm = await MainActor.run { makeVM() }
        await MainActor.run { vm.selectPreset(at: 0) }
        await MainActor.run { vm.deselectPreset() }
        vm.stopRetryTimer()

        // Regression guard: init() re-derives selectedPresetIndex by matching the
        // stored URL against the presets, so a deselect that left streamURL intact
        // would resurrect the selection here.
        vm = await MainActor.run { makeVM() }
        #expect(vm.selectedPresetIndex == nil)
        #expect(vm.streamURL == "")
        vm.stopRetryTimer()
    }

    @Test func clearStreamClearsATypedURLWithNoSelection() async throws {
        await resetDefaults()
        let defaults = UserDefaults.standard
        defaults.set(false, forKey: ContentView.channelPresetsManagedKey)
        defaults.set(
            [["Name": "A", "URL": "https://a.example.com/1.m3u8"]],
            forKey: ContentView.channelPresetsKey
        )

        let vm = await MainActor.run { StreamViewModel(logger: TestLogger()) }
        // A URL that matches no preset — the manual-entry case.
        await MainActor.run { vm.updateStreamURL("https://typed.example.com/x.m3u8") }
        #expect(vm.selectedPresetIndex == nil)
        #expect(vm.canClearStream)

        await MainActor.run { vm.clearStream() }
        #expect(vm.streamURL == "")
        #expect(defaults.object(forKey: ContentView.lastStreamURLKey) == nil)
        #expect(!vm.canClearStream, "Nothing left to clear.")
        vm.stopRetryTimer()
    }

    @Test func canClearStreamIsFalseWhenEmptyOrManaged() async throws {
        await resetDefaults()
        let defaults = UserDefaults.standard

        // Nothing selected, nothing typed.
        defaults.set(false, forKey: ContentView.channelPresetsManagedKey)
        defaults.set(
            [["Name": "A", "URL": "https://a.example.com/1.m3u8"]],
            forKey: ContentView.channelPresetsKey
        )
        let empty = await MainActor.run { StreamViewModel(logger: TestLogger()) }
        #expect(empty.streamURL == "")
        #expect(!empty.canClearStream)
        empty.stopRetryTimer()

        // Managed: the administrator owns the selection, so clearing is unavailable
        // even though a stream is set.
        await resetDefaults()
        defaults.set(
            [["Name": "Locked", "URL": "https://admin.example.com/1.m3u8"]],
            forKey: ContentView.channelPresetsKey
        )
        defaults.set(true, forKey: ContentView.channelPresetsManagedKey)
        defaults.set(0, forKey: ContentView.selectedPresetIndexKey)
        let managed = await MainActor.run { StreamViewModel(logger: TestLogger()) }
        #expect(managed.selectedPresetIndex == 0)
        #expect(!managed.canClearStream)

        await MainActor.run { managed.clearStream() }
        #expect(managed.selectedPresetIndex == 0, "Managed selection must survive.")
        managed.stopRetryTimer()
    }

    @Test func managedModeCannotDeselect() async throws {
        await resetDefaults()
        let defaults = UserDefaults.standard
        defaults.set(
            [["Name": "Locked", "URL": "https://admin.example/1.m3u8"]],
            forKey: ContentView.channelPresetsKey
        )
        defaults.set(true, forKey: ContentView.channelPresetsManagedKey)
        defaults.set(0, forKey: ContentView.selectedPresetIndexKey)

        let vm = await MainActor.run { StreamViewModel(logger: TestLogger()) }
        #expect(vm.selectedPresetIndex == 0)

        await MainActor.run { vm.deselectPreset() }
        #expect(vm.selectedPresetIndex == 0)
        #expect(vm.streamURL == "https://admin.example/1.m3u8")
        vm.stopRetryTimer()
    }

    // MARK: - Confirm Before Deleting

    @Test func confirmBeforeDeleteDefaultsToOn() async throws {
        await resetDefaults()
        let defaults = UserDefaults.standard
        // Key absent entirely — must come up ON, not false-by-omission.
        #expect(defaults.object(forKey: ContentView.confirmBeforeDeleteKey) == nil)

        let vm = await MainActor.run { StreamViewModel(logger: TestLogger()) }
        #expect(vm.confirmBeforeDelete == true)
        // init() should have seeded the key so the default survives a relaunch.
        #expect(defaults.bool(forKey: ContentView.confirmBeforeDeleteKey) == true)
        vm.stopRetryTimer()
    }

    @Test func confirmBeforeDeleteRespectsStoredOff() async throws {
        await resetDefaults()
        let defaults = UserDefaults.standard
        defaults.set(false, forKey: ContentView.confirmBeforeDeleteKey)

        let vm = await MainActor.run { StreamViewModel(logger: TestLogger()) }
        #expect(vm.confirmBeforeDelete == false)
        vm.stopRetryTimer()
    }

    @Test func confirmBeforeDeleteUpdatePersists() async throws {
        await resetDefaults()
        let defaults = UserDefaults.standard

        @MainActor func makeVM() -> StreamViewModel { StreamViewModel(logger: TestLogger()) }

        var vm = await MainActor.run { makeVM() }
        #expect(vm.confirmBeforeDelete == true)

        await MainActor.run { vm.updateConfirmBeforeDelete(false) }
        #expect(vm.confirmBeforeDelete == false)
        #expect(defaults.bool(forKey: ContentView.confirmBeforeDeleteKey) == false)

        // Survives a re-init.
        vm.stopRetryTimer()
        vm = await MainActor.run { makeVM() }
        #expect(vm.confirmBeforeDelete == false)
        vm.stopRetryTimer()
    }

    @Test func managedConfigRemovalLeavesConfirmBeforeDeleteAlone() async throws {
        await resetDefaults()
        let defaults = UserDefaults.standard

        // User turned confirmation off, then a managed payload arrives and later departs.
        defaults.set(false, forKey: ContentView.confirmBeforeDeleteKey)
        await MainActor.run {
            defaults.set(
                [AppConfigKeys.channelPresets: [["Name": "A", "URL": "https://a.example/1.m3u8"]]],
                forKey: "com.apple.configuration.managed"
            )
            AppConfig.applyConfiguration(logger: TestLogger())
        }
        await MainActor.run {
            defaults.removeObject(forKey: "com.apple.configuration.managed")
            AppConfig.applyConfiguration(logger: TestLogger())
        }

        // It is not an MDM-settable key, so the managed→unmanaged reset must not touch it.
        #expect(defaults.bool(forKey: ContentView.confirmBeforeDeleteKey) == false)
    }

    @Test func addChannelPresetWithValuesAppendsCompleteEntry() async throws {
        await resetDefaults()
        let defaults = UserDefaults.standard
        defaults.set(false, forKey: ContentView.channelPresetsManagedKey)
        defaults.set(
            [["Name": "First", "URL": "https://a.example.com/1.m3u8"]],
            forKey: ContentView.channelPresetsKey
        )

        @MainActor func makeVM() -> StreamViewModel { StreamViewModel(logger: TestLogger()) }

        var vm = await MainActor.run { makeVM() }
        let newIndex = await MainActor.run {
            vm.addChannelPreset(name: "Second", url: "https://b.example.com/2.m3u8")
        }

        // Returned index lets the caller scroll to (and announce) the new row.
        #expect(newIndex == 1)
        #expect(vm.channelPresets.count == 2)
        #expect(vm.channelPresets[1] == ChannelPreset(name: "Second", url: "https://b.example.com/2.m3u8"))

        vm.stopRetryTimer()
        vm = await MainActor.run { makeVM() }
        #expect(vm.channelPresets[1].name == "Second")
        #expect(vm.channelPresets[1].url == "https://b.example.com/2.m3u8")
        vm.stopRetryTimer()
    }

    @Test func addChannelPresetReturnsNilWhenManagedOrAtCap() async throws {
        await resetDefaults()
        let defaults = UserDefaults.standard

        // Managed: refuses outright.
        defaults.set(
            [["Name": "Locked", "URL": "https://admin.example.com/1.m3u8"]],
            forKey: ContentView.channelPresetsKey
        )
        defaults.set(true, forKey: ContentView.channelPresetsManagedKey)
        let managed = await MainActor.run { StreamViewModel(logger: TestLogger()) }
        #expect(managed.addChannelPreset(name: "X", url: "https://x.example.com/x.m3u8") == nil)
        #expect(managed.channelPresets.count == 1)
        managed.stopRetryTimer()

        // At the cap: also refuses, so the caller has no index to scroll to.
        await resetDefaults()
        let full = (0..<StreamViewModel.maxChannelPresets).map {
            ["Name": "P\($0)", "URL": "https://a.example.com/\($0).m3u8"]
        }
        defaults.set(false, forKey: ContentView.channelPresetsManagedKey)
        defaults.set(full, forKey: ContentView.channelPresetsKey)
        let capped = await MainActor.run { StreamViewModel(logger: TestLogger()) }
        #expect(capped.channelPresets.count == StreamViewModel.maxChannelPresets)
        #expect(capped.addChannelPreset(name: "Extra", url: "https://a.example.com/extra.m3u8") == nil)
        #expect(capped.channelPresets.count == StreamViewModel.maxChannelPresets)
        capped.stopRetryTimer()
    }

    @Test func urlEditPersistsAndRoundTrips() async throws {
        await resetDefaults()
        let defaults = UserDefaults.standard
        defaults.set(false, forKey: ContentView.channelPresetsManagedKey)
        defaults.set(
            [["Name": "Lobby", "URL": "https://a.example.com/old.m3u8"]],
            forKey: ContentView.channelPresetsKey
        )

        @MainActor func makeVM() -> StreamViewModel { StreamViewModel(logger: TestLogger()) }

        var vm = await MainActor.run { makeVM() }
        await MainActor.run { vm.updateChannelPreset(at: 0, url: "https://a.example.com/new.m3u8") }
        #expect(vm.channelPresets[0].url == "https://a.example.com/new.m3u8")

        // The name must survive a URL edit, and vice versa.
        #expect(vm.channelPresets[0].name == "Lobby")

        vm.stopRetryTimer()
        vm = await MainActor.run { makeVM() }
        #expect(vm.channelPresets[0].url == "https://a.example.com/new.m3u8")
        #expect(vm.channelPresets[0].name == "Lobby")
        vm.stopRetryTimer()
    }

    @Test func managedModeIgnoresNameEditAttempts() async throws {
        await resetDefaults()
        let defaults = UserDefaults.standard
        defaults.set(
            [["Name": "Locked", "URL": "https://admin.example.com/1.m3u8"]],
            forKey: ContentView.channelPresetsKey
        )
        defaults.set(true, forKey: ContentView.channelPresetsManagedKey)

        let vm = await MainActor.run { StreamViewModel(logger: TestLogger()) }
        #expect(vm.channelPresets[0].name == "Locked")
        vm.updateChannelPresetName(at: 0, name: "Hijacked")
        #expect(vm.channelPresets[0].name == "Locked")
        vm.stopRetryTimer()
    }
}
