//
//  AutostreamTests.swift
//  AutostreamTests
//
//  Created by migration agent.
//

import Foundation
import Testing
@testable import Autostream

@MainActor
struct AutostreamTests {

    private func resetDefaults() async {
        await MainActor.run {
            let defaults = UserDefaults.standard
            let identifiers = [
                Bundle.main.bundleIdentifier,
                "edu.princeton.orfe.Autostream"
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
}
