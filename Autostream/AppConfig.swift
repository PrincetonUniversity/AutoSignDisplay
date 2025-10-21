//
//  AppConfig.swift
//  Autostream
//
//  Created by Michael Bino on 4/20/25.

import Foundation

struct AppConfigKeys {
    static let playOnOpen = "PlayOnAppOpen"
    static let retryTimeout = "RetryTimeout"
    static let streamURL = "StreamURL"
    static let autoResume = "AutoResume"
    static let settingsDisabled = "SettingsDisabled"
    static let channelPresets = "ChannelPresets"
    static let defaultChannel = "DefaultChannel"
}

class AppConfig {
    // Allow injecting a logger for tests. Defaults to PrintLogger.
    static func applyConfiguration(logger: Logger = PrintLogger()) {
        let defaults = UserDefaults.standard
        let previouslyManaged = defaults.bool(forKey: ContentView.channelPresetsManagedKey)

        defaults.set(false, forKey: ContentView.channelPresetsManagedKey)

        guard let managedConfig = defaults.dictionary(forKey: "com.apple.configuration.managed") else {
            if previouslyManaged {
                defaults.set(StreamViewModel.defaultPresets, forKey: ContentView.channelPresetsKey)
                defaults.removeObject(forKey: ContentView.defaultChannelKey)
                defaults.removeObject(forKey: ContentView.lastStreamURLKey)
                defaults.removeObject(forKey: ContentView.selectedPresetIndexKey)
                logger.log("Cleared managed presets after configuration removal.")
            } else {
                logger.log("No managed configuration found.")
            }
            return
        }

        var sanitizedPresets: [String] = []
        var hasManagedPresets = false

        if let playOnOpenValue = managedConfig[AppConfigKeys.playOnOpen] as? Bool {
            defaults.set(playOnOpenValue, forKey: ContentView.playOnOpenKey)
            logger.log("Applied managed PlayOnAppOpen: \(playOnOpenValue)")
        }

        if let retryTimeoutValue = managedConfig[AppConfigKeys.retryTimeout] as? Double {
            defaults.set(retryTimeoutValue, forKey: ContentView.retryTimeoutKey)
            logger.log("Applied managed RetryTimeout: \(retryTimeoutValue)")
        }

        if let autoResumeValue = managedConfig[AppConfigKeys.autoResume] as? Bool {
            defaults.set(autoResumeValue, forKey: ContentView.autoResumeKey)
            logger.log("Applied managed AutoResume: \(autoResumeValue)")
        }

        if let settingsDisabledValue = managedConfig[AppConfigKeys.settingsDisabled] as? Bool {
            defaults.set(settingsDisabledValue, forKey: ContentView.settingsDisabledKey)
            logger.log("Applied managed SettingsDisabled: \(settingsDisabledValue)")
        }

        if let streamURLValue = managedConfig[AppConfigKeys.streamURL] as? String {
            defaults.set(streamURLValue, forKey: ContentView.lastStreamURLKey)
            logger.log("Applied managed StreamURL: \(streamURLValue)")
        }

        if let presets = managedConfig[AppConfigKeys.channelPresets] as? [String] {
            let sanitized = Array(presets.prefix(StreamViewModel.maxChannelPresets))
            defaults.set(sanitized, forKey: ContentView.channelPresetsKey)
            defaults.set(true, forKey: ContentView.channelPresetsManagedKey)
            logger.log("Applied managed ChannelPresets: \(sanitized.count) entries")
            sanitizedPresets = sanitized
            hasManagedPresets = true
        }

        var selectedPresetIndex: Int?
        if let defaultChannelValue = managedConfig[AppConfigKeys.defaultChannel] as? String {
            defaults.set(defaultChannelValue, forKey: ContentView.defaultChannelKey)
            defaults.set(defaultChannelValue, forKey: ContentView.lastStreamURLKey)
            logger.log("Applied managed DefaultChannel: \(defaultChannelValue)")
            if hasManagedPresets {
                selectedPresetIndex = sanitizedPresets.firstIndex(of: defaultChannelValue)
            }
        } else {
            defaults.removeObject(forKey: ContentView.defaultChannelKey)
        }

        if hasManagedPresets, selectedPresetIndex == nil {
            if let lastURL = defaults.string(forKey: ContentView.lastStreamURLKey) {
                selectedPresetIndex = sanitizedPresets.firstIndex(of: lastURL)
            }
        }

        if let index = selectedPresetIndex {
            defaults.set(index, forKey: ContentView.selectedPresetIndexKey)
        } else {
            defaults.removeObject(forKey: ContentView.selectedPresetIndexKey)
        }
    }
}
