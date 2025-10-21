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
}

class AppConfig {
    static func applyConfiguration() {
    guard let managedConfig = UserDefaults.standard.dictionary(forKey: "com.apple.configuration.managed") else {
            print("No managed configuration found.")
            return
        }

        if let playOnOpenValue = managedConfig[AppConfigKeys.playOnOpen] as? Bool {
            UserDefaults.standard.set(playOnOpenValue, forKey: ContentView.playOnOpenKey)
            print("Applied managed PlayOnAppOpen: \\(playOnOpenValue)")
        }

        if let retryTimeoutValue = managedConfig[AppConfigKeys.retryTimeout] as? Double {
            UserDefaults.standard.set(retryTimeoutValue, forKey: ContentView.retryTimeoutKey)
            print("Applied managed RetryTimeout: \\(retryTimeoutValue)")
        }

        if let autoResumeValue = managedConfig[AppConfigKeys.autoResume] as? Bool {
            UserDefaults.standard.set(autoResumeValue, forKey: ContentView.autoResumeKey)
            print("Applied managed AutoResume: \\(autoResumeValue)")
        }

            if let settingsDisabledValue = managedConfig[AppConfigKeys.settingsDisabled] as? Bool {
                UserDefaults.standard.set(settingsDisabledValue, forKey: ContentView.settingsDisabledKey)
                print("Applied managed SettingsDisabled: \\(settingsDisabledValue)")
            }

        if let streamURLValue = managedConfig[AppConfigKeys.streamURL] as? String {
            UserDefaults.standard.set(streamURLValue, forKey: ContentView.lastStreamURLKey)
            print("Applied managed StreamURL: \\(streamURLValue)")
        }
    }
}
