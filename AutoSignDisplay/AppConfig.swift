//
//  AppConfig.swift
//  AutoSignDisplay
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
    static let displayTitle = "DisplayTitle"
}

class AppConfig {
    // Allow injecting a logger for tests. Defaults to PrintLogger.
    static func applyConfiguration(logger: Logger = PrintLogger()) {
        let defaults = UserDefaults.standard
        let previouslyManaged = defaults.bool(forKey: ContentView.channelPresetsManagedKey)

        defaults.set(false, forKey: ContentView.channelPresetsManagedKey)

        guard let managedConfig = defaults.dictionary(forKey: "com.apple.configuration.managed") else {
            if previouslyManaged {
                defaults.set(StreamViewModel.defaultPresets.map { $0.dictionaryRepresentation },
                             forKey: ContentView.channelPresetsKey)
                defaults.removeObject(forKey: ContentView.defaultChannelKey)
                defaults.removeObject(forKey: ContentView.lastStreamURLKey)
                defaults.removeObject(forKey: ContentView.selectedPresetIndexKey)
                // Any preference the managed config could have written must also be cleared —
                // otherwise SettingsDisabled=true (etc.) stays sticky after MDM goes away and
                // leaves the user unable to reach Settings in unmanaged mode.
                defaults.removeObject(forKey: ContentView.playOnOpenKey)
                defaults.removeObject(forKey: ContentView.autoResumeKey)
                defaults.removeObject(forKey: ContentView.settingsDisabledKey)
                defaults.removeObject(forKey: ContentView.retryTimeoutKey)
                defaults.removeObject(forKey: ContentView.displayTitleKey)
                logger.log("Cleared managed settings after configuration removal.")
            } else {
                logger.log("No managed configuration found.")
            }
            return
        }

        // Validate and apply configuration
        applyValidatedConfiguration(managedConfig, to: defaults, logger: logger)
    }

    // Load managed configuration from a plist file (for testing)
    // Loads from the test bundle and injects into UserDefaults
    static func loadConfigurationFromFile(_ filename: String, logger: Logger = PrintLogger()) {
        var filePath: String?
        
        // In test context, Bundle.main might be the test bundle or the app bundle
        // Try current bundle first
        filePath = Bundle(for: AppConfig.self).path(forResource: filename, ofType: "plist")
        
        // If not found, look for AutoSignDisplayTests bundle
        if filePath == nil {
            if let testsBundle = Bundle(identifier: "edu.princeton.autosigndisplay.tests") {
                filePath = testsBundle.path(forResource: filename, ofType: "plist")
            }
        }
        
        // Last resort: search in all loaded bundles
        if filePath == nil {
            for bundle in Bundle.allBundles {
                if let path = bundle.path(forResource: filename, ofType: "plist") {
                    filePath = path
                    break
                }
            }
        }
        
        guard let filePath = filePath else {
            logger.log("Configuration file '\(filename).plist' not found in bundle")
            return
        }

        guard let fileData = try? Data(contentsOf: URL(fileURLWithPath: filePath)) else {
            logger.log("Failed to read configuration file '\(filename).plist'")
            return
        }
        
        do {
            guard let fileContents = try PropertyListSerialization.propertyList(
                from: fileData,
                options: [],
                format: nil
            ) as? [String: Any] else {
                logger.log("Failed to parse configuration file '\(filename).plist'")
                return
            }

            let defaults = UserDefaults.standard
            defaults.set(fileContents, forKey: "com.apple.configuration.managed")
            defaults.synchronize()

            logger.log("Loaded configuration from '\(filename).plist'")
            applyConfiguration(logger: logger)
        } catch {
            logger.log("Error parsing configuration file '\(filename).plist': \(error)")
            return
        }
    }

    // Private helper to validate and apply configuration
    private static func applyValidatedConfiguration(
        _ managedConfig: [String: Any],
        to defaults: UserDefaults,
        logger: Logger
    ) {
        var sanitizedPresets: [ChannelPreset] = []
        var hasManagedPresets = false

        // Validate and apply PlayOnAppOpen (must be Boolean)
        if let playOnOpenValue = managedConfig[AppConfigKeys.playOnOpen] {
            if let boolValue = playOnOpenValue as? Bool {
                defaults.set(boolValue, forKey: ContentView.playOnOpenKey)
                logger.log("Applied managed PlayOnAppOpen: \(boolValue)")
            } else if let numValue = playOnOpenValue as? NSNumber {
                // NSNumber - check if it's a CFBoolean (objCType "c") 
                let objCTypeStr = String(cString: numValue.objCType)
                // Only accept CFBoolean with objCType "c", reject all integers (objCType "q", "i", etc)
                if objCTypeStr == "c" {
                    defaults.set(numValue.boolValue, forKey: ContentView.playOnOpenKey)
                    logger.log("Applied managed PlayOnAppOpen (CFBoolean): \(numValue.boolValue)")
                } else {
                    logger.log("Ignored invalid PlayOnAppOpen (NSNumber with objCType '\(objCTypeStr)', must be Boolean)")
                }
            } else {
                logger.log("Ignored invalid PlayOnAppOpen (must be Boolean, got \(type(of: playOnOpenValue)))")
            }
        }

        // Validate and apply RetryTimeout (must be Double/NSNumber)
        if let retryTimeoutValue = managedConfig[AppConfigKeys.retryTimeout] as? Double {
            if retryTimeoutValue > 0 {
                defaults.set(retryTimeoutValue, forKey: ContentView.retryTimeoutKey)
                logger.log("Applied managed RetryTimeout: \(retryTimeoutValue)")
            } else {
                logger.log("Rejected RetryTimeout: must be positive (got \(retryTimeoutValue))")
            }
        } else if managedConfig[AppConfigKeys.retryTimeout] != nil {
            logger.log("Ignored invalid RetryTimeout (must be positive Double)")
        }

        // Validate and apply AutoResume (must be Boolean)
        if let autoResumeValue = managedConfig[AppConfigKeys.autoResume] {
            // IMPORTANT: Check for NSNumber FIRST because NSNumber can be cast to Bool!
            if let numValue = autoResumeValue as? NSNumber {
                // NSNumber - check if it's a CFBoolean (objCType "c") 
                let objCTypeStr = String(cString: numValue.objCType)
                // Only accept CFBoolean with objCType "c", reject all integers (objCType "q", "i", etc)
                if objCTypeStr == "c" {
                    defaults.set(numValue.boolValue, forKey: ContentView.autoResumeKey)
                    logger.log("Applied managed AutoResume (CFBoolean): \(numValue.boolValue)")
                } else {
                    logger.log("Ignored invalid AutoResume (NSNumber with objCType '\(objCTypeStr)', must be Boolean)")
                }
            } else if let boolValue = autoResumeValue as? Bool {
                // Native Swift Bool (only if NOT NSNumber)
                defaults.set(boolValue, forKey: ContentView.autoResumeKey)
                logger.log("Applied managed AutoResume: \(boolValue)")
            } else {
                logger.log("Ignored invalid AutoResume (must be Boolean, got \(type(of: autoResumeValue)))")
            }
        }

        // Validate and apply SettingsDisabled (must be Boolean)
        if let settingsDisabledValue = managedConfig[AppConfigKeys.settingsDisabled] {
            if let boolValue = settingsDisabledValue as? Bool {
                defaults.set(boolValue, forKey: ContentView.settingsDisabledKey)
                logger.log("Applied managed SettingsDisabled: \(boolValue)")
            } else if let numValue = settingsDisabledValue as? NSNumber {
                // NSNumber - check if it's a CFBoolean (objCType "c") 
                let objCTypeStr = String(cString: numValue.objCType)
                // Only accept CFBoolean with objCType "c", reject all integers (objCType "q", "i", etc)
                if objCTypeStr == "c" {
                    defaults.set(numValue.boolValue, forKey: ContentView.settingsDisabledKey)
                    logger.log("Applied managed SettingsDisabled (CFBoolean): \(numValue.boolValue)")
                } else {
                    logger.log("Ignored invalid SettingsDisabled (NSNumber with objCType '\(objCTypeStr)', must be Boolean)")
                }
            } else {
                logger.log("Ignored invalid SettingsDisabled (must be Boolean, got \(type(of: settingsDisabledValue)))")
            }
        }

        // Validate and apply StreamURL (must be non-empty String)
        var streamURLApplied = false
        if let streamURLValue = managedConfig[AppConfigKeys.streamURL] as? String {
            if streamURLValue.trimmingCharacters(in: .whitespaces).isEmpty {
                logger.log("Rejected StreamURL: must not be empty")
            } else {
                defaults.set(streamURLValue, forKey: ContentView.lastStreamURLKey)
                logger.log("Applied managed StreamURL: \(streamURLValue)")
                streamURLApplied = true
            }
        } else if managedConfig[AppConfigKeys.streamURL] != nil {
            logger.log("Ignored invalid StreamURL (must be non-empty String)")
        }

        // Validate and apply DisplayTitle (must be non-empty String)
        if let displayTitleValue = managedConfig[AppConfigKeys.displayTitle] as? String {
            let trimmed = displayTitleValue.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                logger.log("Rejected DisplayTitle: must not be empty")
            } else {
                defaults.set(trimmed, forKey: ContentView.displayTitleKey)
                logger.log("Applied managed DisplayTitle: \(trimmed)")
            }
        } else if managedConfig[AppConfigKeys.displayTitle] != nil {
            logger.log("Ignored invalid DisplayTitle (must be non-empty String)")
        }

        // Validate and apply ChannelPresets. Each entry is either:
        //   - a dict with required URL and optional Name (preferred), or
        //   - a plain String URL (legacy — kept for backward compat).
        if let presets = managedConfig[AppConfigKeys.channelPresets] as? [Any] {
            let validPresets = presets.compactMap { item -> ChannelPreset? in
                if let dict = item as? [String: Any] {
                    guard let preset = ChannelPreset.fromDictionary(dict) else {
                        logger.log("Ignored invalid preset dict (missing/empty URL)")
                        return nil
                    }
                    return preset
                }
                if let urlString = item as? String {
                    guard let preset = ChannelPreset.fromLegacyString(urlString) else {
                        logger.log("Ignored empty preset entry")
                        return nil
                    }
                    return preset
                }
                logger.log("Ignored invalid preset entry (not a String or dict)")
                return nil
            }

            if validPresets.isEmpty {
                logger.log("Rejected ChannelPresets: must contain at least one valid preset")
            } else {
                let sanitized = Array(validPresets.prefix(StreamViewModel.maxChannelPresets))
                defaults.set(sanitized.map { $0.dictionaryRepresentation },
                             forKey: ContentView.channelPresetsKey)
                defaults.set(true, forKey: ContentView.channelPresetsManagedKey)
                logger.log("Applied managed ChannelPresets: \(sanitized.count) entries")
                sanitizedPresets = sanitized
                hasManagedPresets = true
            }
        } else if managedConfig[AppConfigKeys.channelPresets] != nil {
            logger.log("Ignored invalid ChannelPresets (must be Array of Strings or dicts)")
        }

        // Validate and apply DefaultChannel (must be String matching a preset)
        var selectedPresetIndex: Int?
        if let defaultChannelValue = managedConfig[AppConfigKeys.defaultChannel] as? String {
            if defaultChannelValue.trimmingCharacters(in: .whitespaces).isEmpty {
                logger.log("Rejected DefaultChannel: must not be empty")
            } else {
                defaults.set(defaultChannelValue, forKey: ContentView.defaultChannelKey)
                // Only set lastStreamURLKey if StreamURL wasn't already applied
                if !streamURLApplied {
                    defaults.set(defaultChannelValue, forKey: ContentView.lastStreamURLKey)
                }
                logger.log("Applied managed DefaultChannel: \(defaultChannelValue)")
                if hasManagedPresets {
                    selectedPresetIndex = sanitizedPresets.firstIndex(where: { $0.url == defaultChannelValue })
                    if selectedPresetIndex == nil {
                        logger.log("Warning: DefaultChannel not found in ChannelPresets")
                    }
                }
            }
        } else {
            defaults.removeObject(forKey: ContentView.defaultChannelKey)
        }

        if hasManagedPresets, selectedPresetIndex == nil {
            if let lastURL = defaults.string(forKey: ContentView.lastStreamURLKey) {
                selectedPresetIndex = sanitizedPresets.firstIndex(where: { $0.url == lastURL })
            }
        }

        if let index = selectedPresetIndex {
            defaults.set(index, forKey: ContentView.selectedPresetIndexKey)
        } else {
            defaults.removeObject(forKey: ContentView.selectedPresetIndexKey)
        }
    }
}
