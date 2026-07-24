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

        let presets = defaults.stringArray(forKey: ContentView.channelPresetsKey) ?? []
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
        let presets = defaults.stringArray(forKey: ContentView.channelPresetsKey) ?? []
        #expect(presets.count == 2)
        #expect(presets.contains(where: { $0 == "https://test.example.com/channel1.m3u8" }))
        #expect(presets.contains(where: { $0 == "https://test.example.com/channel2.m3u8" }))

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
        let presets = defaults.stringArray(forKey: ContentView.channelPresetsKey) ?? []
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
        let persistedCount = defaults.stringArray(forKey: ContentView.channelPresetsKey)?.count ?? 0
        #expect(persistedCount == 2)

        // Simulate returning to main screen and back
        vm.stopRetryTimer()
        vm = await MainActor.run { makeViewModel() }
        #expect(vm.channelPresets.count == 2)

        // Edit the newly added preset
        await MainActor.run {
            vm.updateChannelPreset(at: 1, with: "https://example.com/preset2.m3u8")
        }
        let editedPresets = defaults.stringArray(forKey: ContentView.channelPresetsKey) ?? []
        #expect(editedPresets[1] == "https://example.com/preset2.m3u8")

        // Simulate returning to main screen
        vm.stopRetryTimer()
        vm = await MainActor.run { makeViewModel() }

        // Remove the newly added preset
        await MainActor.run {
            vm.removeChannelPreset(at: 1)
        }
        #expect(vm.channelPresets.count == 1)
        let finalPresets = defaults.stringArray(forKey: ContentView.channelPresetsKey) ?? []
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
            vm.updateChannelPreset(at: 1, with: "https://example.com/new1.m3u8")
        }

        vm.stopRetryTimer()
        vm = await MainActor.run { makeViewModel() }

        #expect(vm.channelPresets.count == 2)

        await MainActor.run {
            vm.addChannelPreset()
            vm.updateChannelPreset(at: 2, with: "https://example.com/new2.m3u8")
        }

        vm.stopRetryTimer()
        vm = await MainActor.run { makeViewModel() }

        // Verify all three presets persist
        #expect(vm.channelPresets.count == 3)
        #expect(vm.channelPresets[0] == "https://example.com/original.m3u8")
        #expect(vm.channelPresets[1] == "https://example.com/new1.m3u8")
        #expect(vm.channelPresets[2] == "https://example.com/new2.m3u8")

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
        let persistedCount = defaults.stringArray(forKey: ContentView.channelPresetsKey)?.count ?? 0
        #expect(persistedCount == 2)

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
        let persistedCount = defaults.stringArray(forKey: ContentView.channelPresetsKey)?.count ?? 0
        #expect(persistedCount == 3)

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
        #expect(vm.channelPresets[0] == managedPresets[0])

        // Attempt to edit preset (should be ignored)
        vm.updateChannelPreset(at: 0, with: "https://hacker.example.com/bad.m3u8")

        // Preset should remain unchanged
        #expect(vm.channelPresets[0] == managedPresets[0])
        let persistedValue = defaults.stringArray(forKey: ContentView.channelPresetsKey)?[0] ?? ""
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
}
