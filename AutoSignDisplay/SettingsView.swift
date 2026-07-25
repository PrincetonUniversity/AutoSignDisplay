//
//  SettingsView.swift
//  AutoSignDisplay
//
//  Created by Michael Bino on 4/20/25.
//

import SwiftUI

/// Text that flips foreground color to `.black` when the enclosing focusable control
/// is focused. Needed on tvOS: focused Form rows / Toggle & Button labels get a light
/// background, and the default `.primary` (white in dark mode) disappears on it.
/// Pass `fieldFocused: true` when the ambient `\.isFocused` doesn't cover the case
/// (e.g. a TextField whose label lives in a sibling view).
struct FocusAwareLabel: View {
    let title: String
    var fieldFocused: Bool = false
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        Text(title)
            .foregroundColor((isFocused || fieldFocused) ? .black : .primary)
    }
}

/// Shared metrics so the modal screens line up with the main screen.
enum ScreenMetrics {
    static let horizontalPadding: CGFloat = 48
    static let verticalPadding: CGFloat = 36
    static let rowSpacing: CGFloat = 12
    static let groupSpacing: CGFloat = 32
}

/// Opaque backdrop for a full-screen modal. `fullScreenCover` does not supply a
/// background of its own, so without this the presenting screen shows through.
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

/// Row label for a confirming/dismissing action. Accent-tinted so it reads as an
/// action rather than another setting row sharing the same card treatment.
struct AccentRowLabel: View {
    let title: String
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        Text(title)
            .foregroundColor(isFocused ? .black : .accentColor)
            .frame(maxWidth: .infinity, alignment: .leading)
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

/// "Label on the left, text field on the right." The label lives outside the
/// focusable TextField, so focus has to be threaded in explicitly rather than
/// read from the environment.
struct LabeledTextField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var disabled: Bool = false
    var isURL: Bool = false
    var accessibilityLabelText: String
    var onChange: ((String) -> Void)?

    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 24) {
            Text(label)
                .foregroundColor(.secondary)
                .frame(width: 160, alignment: .leading)
                .accessibilityHidden(true)

            Group {
                if isURL {
                    TextField(placeholder, text: $text)
                        .textContentType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } else {
                    TextField(placeholder, text: $text)
                }
            }
            .focused($focused)
            .foregroundColor(focused ? .black : .primary)
            .accessibilityLabel(accessibilityLabelText)
            .disabled(disabled)
        }
    }
}

struct SettingsView: View {
    /// Retry intervals offered in the UI. An MDM-pushed value outside this list is
    /// still honored and displayed — the list only governs what pressing the row cycles to.
    static let retryTimeoutOptions: [Double] = [3, 5, 10, 15, 30, 60]

    @Environment(\.dismiss) private var dismiss
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
                    .padding(.bottom, ScreenMetrics.rowSpacing)
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

                // Done sits at the bottom: on tvOS a top-toolbar Done forces users to
                // page focus back up past every control to dismiss. Accent-tinted so it
                // reads as an action rather than another setting row.
                Button {
                    dismiss()
                } label: {
                    AccentRowLabel(title: "Done")
                }
                .padding(.top, ScreenMetrics.groupSpacing)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, ScreenMetrics.horizontalPadding)
            .padding(.vertical, ScreenMetrics.verticalPadding)
        }
    }
}
