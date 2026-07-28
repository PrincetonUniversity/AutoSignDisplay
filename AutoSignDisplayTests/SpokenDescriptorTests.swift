//
//  SpokenDescriptorTests.swift
//  AutoSignDisplayTests
//
//  `ChannelPreset.spokenDescriptor` reduces a preset to something VoiceOver can read
//  aloud. A full HLS URL spelled character by character is unusable, so an unnamed
//  preset falls back to the URL's filename, then its host. Two callers share it — the
//  main screen's row labels and the delete-confirmation alert, which is read out
//  before a destructive action.
//
//  This file is what remains of AccessibilityPatternTests. The rest of that suite
//  checked source text rather than behaviour, and moved to
//  scripts/check-source-patterns.py: those checks located the repository through
//  `#filePath`, which resolves to the build machine's path, and the test bundle runs
//  in an environment that no longer has the checkout. They passed locally, where the
//  simulator shares the developer's filesystem, and failed in Xcode Cloud.
//

import Foundation
import Testing
@testable import AutoSignDisplay

struct SpokenDescriptorTests {

    @Test func aNamedPresetSpeaksItsName() {
        let preset = ChannelPreset(name: "Lobby", url: "https://example.com/a/b.m3u8")
        #expect(preset.spokenDescriptor == "Lobby")
    }

    @Test func anUnnamedPresetSpeaksItsFilenameNotTheWholeURL() {
        let preset = ChannelPreset(name: "", url: "https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8")
        #expect(preset.spokenDescriptor == "x36xhzz.m3u8")
    }

    @Test func anUnnamedPresetWithNoPathFallsBackToItsHost() {
        #expect(ChannelPreset(name: "", url: "https://example.com").spokenDescriptor == "example.com")
        // A bare trailing slash is not a filename worth reading out.
        #expect(ChannelPreset(name: "", url: "https://example.com/").spokenDescriptor == "example.com")
    }

    @Test func aPresetWithNothingToSayReturnsNil() {
        // Drives the "Preset 1 will be removed." / "Preset 1, empty" fallbacks.
        #expect(ChannelPreset(name: "", url: "").spokenDescriptor == nil)
    }
}
