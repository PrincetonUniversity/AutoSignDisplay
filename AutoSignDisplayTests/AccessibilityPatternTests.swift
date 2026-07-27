//
//  AccessibilityPatternTests.swift
//  AutoSignDisplayTests
//
//  Guards the VoiceOver rules that an audit found broken twice in two files.
//
//  Background: the app renders state visually in ways VoiceOver cannot see — a
//  trailing "On", a "SELECTED" marker, a caption that changes to an error. The
//  correct handling is to hide the visual element from accessibility and re-expose
//  the state on the focusable container. Hiding without re-exposing is the bug, and
//  it happened independently in SettingsView (`RowLabel`'s value, spoken twice
//  because the visible Text merged into the Button's label *and* the wrapper set
//  `.accessibilityValue`) and ChannelPresetsView (`PresetGroup`'s SELECTED marker,
//  hidden and never replaced, so selection was inaudible).
//
//  What VoiceOver actually speaks is not observable from a unit test, and tvOS focus
//  automation is too flaky to assert on in a UI test. The rules are structural,
//  though, so they are enforced here against the source — the same approach, and the
//  same reasoning, as FieldEditingPatternTests.
//
//  `ChannelPreset.spokenDescriptor` is real logic rather than a pattern, so it is
//  tested behaviorally below instead.
//

import Foundation
import Testing
@testable import AutoSignDisplay

struct AccessibilityPatternTests {

    // MARK: - Spoken descriptor

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

    // MARK: - Source access

    private static var appSourceDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // AutoSignDisplayTests/
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("AutoSignDisplay")
    }

    /// Comment-stripped source, so guards match real code and not the comments that
    /// describe the very patterns being enforced.
    private func code(of fileName: String) throws -> String {
        let url = Self.appSourceDirectory.appendingPathComponent(fileName)
        let text = try String(contentsOf: url, encoding: .utf8)
        return text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                guard let range = line.range(of: "//") else { return String(line) }
                return String(line[line.startIndex..<range.lowerBound])
            }
            .joined(separator: "\n")
    }

    /// Text inside the braces of the declaration introduced by `header`, found by
    /// brace matching. Comments are already stripped, so no brace inside one can
    /// throw off the count.
    private func body(after header: String, in code: String) -> String? {
        guard let headerRange = code.range(of: header),
              let open = code[headerRange.lowerBound...].firstIndex(of: "{") else {
            return nil
        }
        var depth = 0
        var index = open
        while index < code.endIndex {
            if code[index] == "{" { depth += 1 }
            if code[index] == "}" {
                depth -= 1
                if depth == 0 { return String(code[code.index(after: open)..<index]) }
            }
            index = code.index(after: index)
        }
        return nil
    }

    /// A window of source following `needle`, for asserting that a modifier appears
    /// alongside the thing it has to accompany.
    private func region(after needle: String, in code: String, length: Int = 400) -> String? {
        guard let range = code.range(of: needle) else { return nil }
        let end = code.index(range.upperBound, offsetBy: length, limitedBy: code.endIndex)
            ?? code.endIndex
        return String(code[range.upperBound..<end])
    }

    // MARK: - Hide the visual value, speak it on the container

    @Test func rowLabelHidesItsTrailingValueFromAccessibility() throws {
        let settings = try code(of: "SettingsView.swift")
        guard let rowLabel = body(after: "struct RowLabel: View {", in: settings) else {
            Issue.record("RowLabel not found in SettingsView.swift")
            return
        }

        #expect(
            rowLabel.contains(".accessibilityHidden(true)"),
            """
            RowLabel's trailing value is not hidden from accessibility. SwiftUI merges \
            a Button's child Text views into a single label, so a visible "On" here \
            plus the .accessibilityValue("On") set by SettingToggleRow makes VoiceOver \
            say "Play on App Open On, On". Hide it here; the wrapper speaks it.
            """
        )
    }

    @Test func focusableValueRowsSpeakTheirValue() throws {
        let settings = try code(of: "SettingsView.swift")

        for row in ["struct SettingToggleRow: View {", "struct SettingCycleRow: View {"] {
            guard let declaration = body(after: row, in: settings) else {
                Issue.record("\(row) not found in SettingsView.swift")
                continue
            }
            #expect(
                declaration.contains(".accessibilityValue("),
                """
                \(row) draws its value through RowLabel, which hides that text from \
                accessibility. Without .accessibilityValue the setting's value is \
                inaudible — the row would announce only its title.
                """
            )
        }
    }

    @Test func theSettingsPINStatusRowSpeaksItsOwnValue() throws {
        let settings = try code(of: "SettingsView.swift")
        guard let following = region(after: "title: \"Settings PIN\"", in: settings) else {
            Issue.record("Settings PIN status row not found in SettingsView.swift")
            return
        }

        #expect(
            following.contains(".accessibilityValue("),
            """
            The Settings PIN status row uses RowLabel outside a Button, so nothing \
            speaks its value: RowLabel hides the trailing text and there is no wrapper \
            to supply .accessibilityValue. Set/Not set would be silent.
            """
        )
    }

    @Test func presetGroupConveysSelectionAndPlayback() throws {
        let presets = try code(of: "ChannelPresetsView.swift")
        guard let group = body(after: "private struct PresetGroup: View {", in: presets) else {
            Issue.record("PresetGroup not found in ChannelPresetsView.swift")
            return
        }

        // The visual marker is hidden so it stays out of the child labels…
        #expect(
            group.contains(".accessibilityHidden(true)"),
            "PresetGroup's SELECTED/PLAYING marker should stay out of accessibility."
        )

        // …so the container's label has to carry the state instead. Assert against the
        // label's own body, not the whole view: `isSelected` and `isPlaying` are stored
        // properties here, so searching the view would match their declarations and pass
        // even with a constant label.
        guard let label = body(after: "private var accessibilityLabel: String {", in: group) else {
            Issue.record(
                """
                PresetGroup has no accessibilityLabel computed property. It hides its \
                SELECTED/PLAYING marker, so without a state-dependent label a VoiceOver \
                user cannot tell which preset is selected or on screen.
                """
            )
            return
        }

        #expect(
            label.contains("isSelected"),
            """
            PresetGroup's accessibilityLabel does not vary with isSelected, so selection \
            is inaudible while still being shown visually.
            """
        )
        #expect(
            label.contains("playing") && label.contains("selected"),
            """
            PresetGroup's accessibility label should distinguish a selected preset from \
            the one actually playing, as the visible marker does.
            """
        )
    }

    // MARK: - Never fail silently

    @Test func everyVisiblePINErrorIsAlsoAnnounced() throws {
        let settings = try code(of: "SettingsView.swift")
        guard let evaluate = body(after: "private func evaluate() {", in: settings) else {
            Issue.record("SettingsPINEditorView.evaluate() not found in SettingsView.swift")
            return
        }

        // On failure this screen neither pops nor moves focus; only a caption changes.
        // Every branch that sets a visible message must also announce it, or a
        // VoiceOver user pressing Done gets no signal that anything went wrong.
        var searchRange = evaluate.startIndex..<evaluate.endIndex
        var assignments = 0
        while let found = evaluate.range(of: "errorMessage = \"", range: searchRange) {
            assignments += 1
            let end = evaluate.index(found.upperBound, offsetBy: 300, limitedBy: evaluate.endIndex)
                ?? evaluate.endIndex
            #expect(
                evaluate[found.upperBound..<end].contains("Announcement("),
                """
                A branch of evaluate() sets a visible errorMessage without posting an \
                announcement. The PIN editor is the one screen where leaving a \
                VoiceOver user guessing means locking them out.
                """
            )
            searchRange = found.upperBound..<evaluate.endIndex
        }

        #expect(assignments > 0, "Expected evaluate() to still set visible error messages.")
        #expect(
            evaluate.contains("PIN set"),
            "evaluate() should still announce success, not only its failures."
        )
    }

    // MARK: - Do not read raw URLs aloud

    @Test func theDeleteConfirmationDoesNotSpellOutAURL() throws {
        let presets = try code(of: "ChannelPresetsView.swift")
        guard let message = body(
            after: "private func deleteConfirmationMessage(for index: Int) -> String {",
            in: presets
        ) else {
            Issue.record("deleteConfirmationMessage not found in ChannelPresetsView.swift")
            return
        }

        #expect(
            message.contains("spokenDescriptor"),
            """
            deleteConfirmationMessage should describe the preset with \
            ChannelPreset.spokenDescriptor. This string is read aloud before a \
            destructive confirmation, and falling back to preset.url makes VoiceOver \
            spell out an entire HLS URL first.
            """
        )
        #expect(
            !message.contains("preset.url"),
            "deleteConfirmationMessage should not fall back to the raw URL."
        )
    }

    // MARK: - Say why a control is unavailable

    @Test func disabledPlayStreamExplainsWhatIsMissing() throws {
        let content = try code(of: "ContentView.swift")
        guard let following = region(
            after: ".disabled(viewModel.streamURL.isEmpty)",
            in: content
        ) else {
            Issue.record("Play Stream's disabled modifier not found in ContentView.swift")
            return
        }

        #expect(
            following.contains(".accessibilityHint("),
            """
            Play Stream is disabled with no hint, so VoiceOver says only "Play Stream, \
            dimmed" and never what is missing. Every other disabled control in the app \
            explains itself.
            """
        )
    }
}
