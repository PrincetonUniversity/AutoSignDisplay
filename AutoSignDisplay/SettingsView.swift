//
//  SettingsView.swift
//  AutoSignDisplay
//
//  Created by Michael Bino on 4/20/25.
//

import SwiftUI

/// Shared layout scale. Every screen — main and modal — reads from this so the
/// three don't drift apart.
enum ScreenMetrics {
    static let horizontalPadding: CGFloat = 48
    static let verticalPadding: CGFloat = 36
    /// Between sibling rows inside one group.
    static let rowSpacing: CGFloat = 12
    /// Between labeled groups.
    static let groupSpacing: CGFloat = 24
    /// Between fields that belong to the same record (e.g. a preset's Name and
    /// URL). Slightly tighter than `rowSpacing` so a preset reads as one unit —
    /// but not below ~12pt: a focused tvOS control scales up and casts a shadow,
    /// and at 6pt that halo bled onto the neighbouring field, lighting up both.
    static let fieldSpacing: CGFloat = 12
    /// Between side-by-side buttons.
    static let buttonSpacing: CGFloat = 16
    /// Gap under a screen title.
    static let titleSpacing: CGFloat = 12
}

/// Opaque backdrop for a full-screen secondary screen, so nothing behind it can
/// show through.
struct ModalBackground: View {
    var body: some View {
        Color(white: 0.09)
            .ignoresSafeArea()
    }
}

/// One "label on the left, value on the right" row rendered inside a focusable
/// Button. Used for the boolean settings — pressing the row flips the value,
/// which is how tvOS Form toggles behave natively.
struct SettingToggleRow: View {
    let title: String
    @Binding var isOn: Bool
    var disabled: Bool = false
    var onChange: (Bool) -> Void

    var body: some View {
        Button {
            isOn.toggle()
            onChange(isOn)
        } label: {
            RowLabel(title: title, value: isOn ? "On" : "Off")
        }
        .disabled(disabled)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

/// Row content for a focusable settings/preset row. Reads ambient focus so both
/// the title and trailing value invert against the light focused background.
struct RowLabel: View {
    let title: String
    var value: String?
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        HStack(spacing: 24) {
            Text(title)
                .foregroundColor(isFocused ? .black : .primary)
            Spacer(minLength: 24)
            if let value {
                Text(value)
                    .foregroundColor(isFocused ? .black.opacity(0.65) : .secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A focusable row that steps a numeric setting through a fixed set of choices
/// on each press. Typing into a TextField with the on-screen keyboard is painful
/// on a remote, and these values are set once by an administrator — so cycling
/// beats free-form entry. A value pushed by MDM that isn't in `options` still
/// displays correctly; the next press moves to the closest larger option.
struct SettingCycleRow: View {
    let title: String
    let options: [Double]
    let unitSuffix: String
    @Binding var value: Double
    var disabled: Bool = false
    var onChange: (Double) -> Void

    var body: some View {
        Button {
            value = nextOption()
            onChange(value)
        } label: {
            RowLabel(title: title, value: format(value))
        }
        .disabled(disabled)
        .accessibilityValue(format(value))
        .accessibilityHint("Changes the value")
    }

    private func nextOption() -> Double {
        guard let first = options.first else { return value }
        return options.first(where: { $0 > value }) ?? first
    }

    private func format(_ v: Double) -> String {
        let rounded = v.rounded()
        let isWhole = abs(v - rounded) < 0.01
        let number = isWhole ? String(Int(rounded)) : String(format: "%.1f", v)
        return number + unitSuffix
    }
}

/// Center-aligned focusable button label with an explicit foreground color.
///
/// Button labels inherit the accent color by default, so once AccentColor was
/// given real components every plain `Text` inside a `Button` turned blue. These
/// label types state their color outright rather than inheriting the tint.
struct CenteredRowLabel: View {
    let title: String
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        Text(title)
            .foregroundColor(isFocused ? .black : .primary)
            .frame(maxWidth: .infinity)
    }
}

/// Row label for a destructive action. Red text on the standard focusable card
/// rather than a red fill, so the warning reads without dominating the screen.
/// Inverts to a darker red when focused, since the focused card is near-white.
struct DestructiveRowLabel: View {
    let title: String
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        Text(title)
            .foregroundColor(isFocused
                             ? Color(red: 0.62, green: 0.09, blue: 0.09)
                             : Color(red: 1.0, green: 0.45, blue: 0.42))
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// "Label on the left, editable text field on the right."
///
/// Deliberately plain — no `@FocusState`, no `.focused()`, no foreground color,
/// no `Group` wrapper. That matches the main screen's stream URL field, which
/// renders correctly. Text fields only misbehaved here while this screen was
/// presented as a modal; reached by a navigation push, tvOS tears their editing
/// presentation down properly on its own.
struct LabeledTextField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var disabled: Bool = false
    var isURL: Bool = false
    var accessibilityLabelText: String

    var body: some View {
        HStack(spacing: 24) {
            Text(label)
                .foregroundColor(.secondary)
                .frame(width: 120, alignment: .leading)
                .accessibilityHidden(true)

            if isURL {
                TextField(placeholder, text: $text)
                    .textContentType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .accessibilityLabel(accessibilityLabelText)
                    .disabled(disabled)
            } else {
                TextField(placeholder, text: $text)
                    .accessibilityLabel(accessibilityLabelText)
                    .disabled(disabled)
            }
        }
    }
}

struct SettingsView: View {
    /// Retry intervals offered in the UI. An MDM-pushed value outside this list is
    /// still honored and displayed — the list only governs what pressing the row cycles to.
    static let retryTimeoutOptions: [Double] = [3, 5, 10, 15, 30, 60]

    @Binding var isPlayingOnOpen: Bool
    @Binding var retryTimeout: Double
    @Binding var autoResume: Bool
    @Binding var settingsDisabled: Bool
    @Binding var confirmBeforeDelete: Bool
    /// Presets are read-only under MDM, so the delete-confirmation preference has
    /// nothing to act on and is hidden entirely rather than shown disabled.
    var channelPresetsManaged: Bool
    var onRetryTimeoutChanged: () -> Void
    var onConfirmBeforeDeleteChanged: (Bool) -> Void

    var body: some View {
        ZStack {
            ModalBackground()
            settingsContent
        }
    }

    private var settingsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ScreenMetrics.groupSpacing) {
                Text("Settings")
                    .font(.largeTitle)
                    .fontWeight(.semibold)
                    .padding(.bottom, ScreenMetrics.titleSpacing)
                    .accessibilityAddTraits(.isHeader)

                VStack(alignment: .leading, spacing: ScreenMetrics.rowSpacing) {
                    SectionHeader("Playback")

                    SettingToggleRow(
                        title: "Play on App Open",
                        isOn: $isPlayingOnOpen,
                        disabled: settingsDisabled
                    ) { newValue in
                        UserDefaults.standard.set(newValue, forKey: ContentView.playOnOpenKey)
                        onRetryTimeoutChanged()
                    }

                    SettingToggleRow(
                        title: "Auto Resume on Network Interrupt",
                        isOn: $autoResume,
                        disabled: settingsDisabled
                    ) { newValue in
                        UserDefaults.standard.set(newValue, forKey: ContentView.autoResumeKey)
                        onRetryTimeoutChanged()
                    }
                }

                VStack(alignment: .leading, spacing: ScreenMetrics.rowSpacing) {
                    SectionHeader("Recovery")

                    SettingCycleRow(
                        title: "Retry Timeout",
                        options: SettingsView.retryTimeoutOptions,
                        unitSuffix: "s",
                        value: $retryTimeout,
                        disabled: settingsDisabled
                    ) { newValue in
                        UserDefaults.standard.set(newValue, forKey: ContentView.retryTimeoutKey)
                        onRetryTimeoutChanged()
                    }

                    Text("How long to wait before retrying a stalled stream.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Only meaningful when the user can actually delete presets.
                if !channelPresetsManaged {
                    VStack(alignment: .leading, spacing: ScreenMetrics.rowSpacing) {
                        SectionHeader("Stream Presets")

                        SettingToggleRow(
                            title: "Confirm Before Deleting",
                            isOn: $confirmBeforeDelete,
                            disabled: settingsDisabled
                        ) { newValue in
                            onConfirmBeforeDeleteChanged(newValue)
                        }

                        Text("Ask for confirmation before removing a stream preset.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // No Done button: the Menu button dismisses, which is the tvOS
                // convention, and every setting here persists the moment it changes —
                // so an on-screen Done would only duplicate Menu while adding a
                // focusable element below the content.
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, ScreenMetrics.horizontalPadding)
            .padding(.vertical, ScreenMetrics.verticalPadding)
        }
    }
}
