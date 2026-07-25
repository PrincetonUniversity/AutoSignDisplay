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
