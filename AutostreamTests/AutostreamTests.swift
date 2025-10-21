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
            let bundleIdentifiers = [
                Bundle.main.bundleIdentifier,
                "edu.princeton.orfe.Autostream"
            ].compactMap { $0 }

            for identifier in bundleIdentifiers {
                defaults.removePersistentDomain(forName: identifier)
                if let suiteDefaults = UserDefaults(suiteName: identifier) {
                    suiteDefaults.removePersistentDomain(forName: identifier)
                    suiteDefaults.synchronize()
                }
            }

            defaults.removeObject(forKey: ContentView.lastStreamURLKey)
            defaults.removeObject(forKey: ContentView.playOnOpenKey)
            defaults.removeObject(forKey: ContentView.retryTimeoutKey)
            defaults.removeObject(forKey: ContentView.autoResumeKey)
            defaults.removeObject(forKey: ContentView.settingsDisabledKey)
            defaults.removeObject(forKey: ContentView.channelPresetsKey)
            defaults.removeObject(forKey: ContentView.channelPresetsManagedKey)
            defaults.removeObject(forKey: ContentView.defaultChannelKey)
            defaults.removeObject(forKey: ContentView.selectedPresetIndexKey)
            defaults.removeObject(forKey: "com.apple.configuration.managed")

            defaults.synchronize()

        }
    }

    private struct TestLogger: Logger {
        func log(_ message: String) {}
    }

    @Test func autoplayCreatesPlayer() async throws {
        await resetDefaults()
        // Prepare UserDefaults for test
        await MainActor.run {
            UserDefaults.standard.set("https://example.com/stream.m3u8", forKey: ContentView.lastStreamURLKey)
            UserDefaults.standard.set(true, forKey: ContentView.playOnOpenKey)
        }

        let vm = StreamViewModel()

        // Initially no player
        #expect(vm.player == nil)

        // Trigger start which should create the player if PlayOnAppOpen is true
        vm.startStreamIfNeeded()

        // After starting, a player should be created
        #expect(vm.player != nil)
    }

    @Test func seedsDefaultChannelPresets() async throws {
        await resetDefaults()

        let vm = StreamViewModel()

        #expect(vm.channelPresets == StreamViewModel.defaultPresets)
        let persisted: [String]? = await MainActor.run {
            UserDefaults.standard.stringArray(forKey: ContentView.channelPresetsKey)
        }
        #expect(persisted == StreamViewModel.defaultPresets)
    }

    @Test func managePresetsEnabledWhenUnmanaged() async throws {
        await resetDefaults()

        let vm = StreamViewModel()

        #expect(vm.channelPresetsManaged == false)
        #expect(vm.canAddMorePresets)
    }

    @Test func unmanagedDefaultsUseExamplePresetList() async throws {
        await resetDefaults()

        let vm = StreamViewModel()

        let expected = Array(repeating: "https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8", count: 4)
        #expect(vm.channelPresets == expected)
        #expect(vm.channelPresets.count == 4)

        let persisted: [String]? = await MainActor.run {
            UserDefaults.standard.stringArray(forKey: ContentView.channelPresetsKey)
        }
        #expect(persisted == expected)
    }

    @Test func limitsChannelPresetCount() async throws {
        await resetDefaults()

        let vm = StreamViewModel()
        for _ in 0..<30 {
            vm.addChannelPreset()
        }

        #expect(vm.channelPresets.count == StreamViewModel.maxChannelPresets)
    }

    @Test func managedConfigOverridesPresets() async throws {
        await resetDefaults()

        let managedPresets = (0..<25).map { index in
            "https://admin.example/channel\(index).m3u8"
        }
        await MainActor.run {
            UserDefaults.standard.set([
                AppConfigKeys.channelPresets: managedPresets,
                AppConfigKeys.defaultChannel: "https://admin.example/channel5.m3u8"
            ], forKey: "com.apple.configuration.managed")
        }

        AppConfig.applyConfiguration(logger: TestLogger())

        let vm = StreamViewModel()

        #expect(vm.channelPresetsManaged)
        #expect(vm.channelPresets.count == StreamViewModel.maxChannelPresets)
        #expect(vm.channelPresets.first == managedPresets.first)
        #expect(vm.streamURL == "https://admin.example/channel5.m3u8")
        #expect(vm.selectedPresetIndex == 5)

        await resetDefaults()
    }

    @Test func managedMessageMatchesConfigurationState() async throws {
        await resetDefaults()

        let unmanagedVM = StreamViewModel()
        #expect(unmanagedVM.channelPresetsManaged == false)

        let managedPresets = ["https://admin.example/channel0.m3u8"]
        await MainActor.run {
            UserDefaults.standard.set([
                AppConfigKeys.channelPresets: managedPresets,
                AppConfigKeys.defaultChannel: "https://admin.example/channel0.m3u8"
            ], forKey: "com.apple.configuration.managed")
        }

        AppConfig.applyConfiguration(logger: TestLogger())

        let managedVM = StreamViewModel()
        #expect(managedVM.channelPresetsManaged)
        #expect(managedVM.selectedPresetIndex == 0)

        await resetDefaults()
    }

    @Test func managedConfigRemovalRestoresDefaults() async throws {
        await resetDefaults()

        let managedPresets = [
            "https://admin.example/channel0.m3u8",
            "https://admin.example/channel1.m3u8"
        ]

        await MainActor.run {
            UserDefaults.standard.set([
                AppConfigKeys.channelPresets: managedPresets,
                AppConfigKeys.defaultChannel: "https://admin.example/channel0.m3u8"
            ], forKey: "com.apple.configuration.managed")
        }

        AppConfig.applyConfiguration(logger: TestLogger())

        let managedVM = StreamViewModel()
        #expect(managedVM.channelPresetsManaged)
        #expect(managedVM.channelPresets == Array(managedPresets.prefix(StreamViewModel.maxChannelPresets)))

        await MainActor.run {
            UserDefaults.standard.removeObject(forKey: "com.apple.configuration.managed")
        }

        AppConfig.applyConfiguration(logger: TestLogger())

        let unmanagedVM = StreamViewModel()
        #expect(unmanagedVM.channelPresetsManaged == false)
        #expect(unmanagedVM.channelPresets == StreamViewModel.defaultPresets)
        #expect(unmanagedVM.selectedPresetIndex == nil)

        await resetDefaults()
    }

    @Test func selectingPresetPersistsIndex() async throws {
        await resetDefaults()

        let presets = [
            "https://example.com/one.m3u8",
            "https://example.com/two.m3u8",
            "https://example.com/three.m3u8"
        ]

        await MainActor.run {
            UserDefaults.standard.set(presets, forKey: ContentView.channelPresetsKey)
        }

        let vm = StreamViewModel()
        vm.selectPreset(at: 1)

        #expect(vm.streamURL == presets[1])
        #expect(vm.selectedPresetIndex == 1)

        let persistedIndex: Int? = await MainActor.run {
            UserDefaults.standard.object(forKey: ContentView.selectedPresetIndexKey) as? Int
        }
        #expect(persistedIndex == 1)

        await resetDefaults()
    }

    @Test func matchingStreamURLAssignsSelection() async throws {
        await resetDefaults()

        let presets = [
            "https://example.com/alpha.m3u8",
            "https://example.com/bravo.m3u8",
            "https://example.com/charlie.m3u8"
        ]

        await MainActor.run {
            UserDefaults.standard.set(presets, forKey: ContentView.channelPresetsKey)
            UserDefaults.standard.set(false, forKey: ContentView.channelPresetsManagedKey)
        }

        let vm = StreamViewModel()

        vm.updateStreamURL("https://example.com/charlie.m3u8")

        #expect(vm.selectedPresetIndex == 2)

        await resetDefaults()
    }

}
