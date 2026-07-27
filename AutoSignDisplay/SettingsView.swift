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
    /// Masks the entered value. Uses `SecureField`, which is the platform's own
    /// masking — hand-rolling it would mean showing one string while storing
    /// another, and custom text-field manipulation is what broke editing on tvOS
    /// repeatedly. Note the mask renders as dots, not literal asterisks; the
    /// character is not configurable.
    var isSecure: Bool = false
    var accessibilityLabelText: String
    /// Fires when the user commits from the keyboard screen (Done), not per
    /// keystroke. Acting on every character meant a screen could pop out from under
    /// the still-open keyboard the instant its value became acceptable.
    var onSubmit: (() -> Void)?

    var body: some View {
        HStack(spacing: 24) {
            Text(label)
                .foregroundColor(.secondary)
                .frame(width: 120, alignment: .leading)
                .accessibilityHidden(true)

            if isSecure {
                SecureField(placeholder, text: $text)
                    .onSubmit { onSubmit?() }
                    .accessibilityLabel(accessibilityLabelText)
                    .disabled(disabled)
            } else if isURL {
                TextField(placeholder, text: $text)
                    .textContentType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onSubmit { onSubmit?() }
                    .accessibilityLabel(accessibilityLabelText)
                    .disabled(disabled)
            } else {
                TextField(placeholder, text: $text)
                    .onSubmit { onSubmit?() }
                    .accessibilityLabel(accessibilityLabelText)
                    .disabled(disabled)
            }
        }
    }
}

/// Stands in front of `SettingsView` when a PIN is configured.
///
/// Owns the wiring that used to live at the call site, so the caller only needs to
/// hand over the view model. Unlock state is per-visit `@State`: leaving Settings
/// and coming back asks again, which is the point of a kiosk lock.
struct SettingsGateView: View {
    @ObservedObject var viewModel: StreamViewModel

    @State private var enteredPIN = ""
    @State private var unlocked = false
    @State private var showMismatch = false

    var body: some View {
        Group {
            if unlocked {
                settings
            } else {
                pinPrompt
            }
        }
        // Decided once, on entry. Evaluating `settingsLocked` continuously meant
        // that setting a PIN from inside Settings immediately swapped the screen for
        // the PIN prompt — ejecting the user mid-session and demanding the PIN they
        // had just created. Leaving and returning re-runs this and asks again.
        .onAppear {
            if !viewModel.settingsLocked {
                unlocked = true
            }
        }
    }

    private var pinPrompt: some View {
        ZStack {
            ModalBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: ScreenMetrics.groupSpacing) {
                    Text("Enter PIN")
                        .font(.largeTitle)
                        .fontWeight(.semibold)
                        .padding(.bottom, ScreenMetrics.titleSpacing)
                        .accessibilityAddTraits(.isHeader)

                    VStack(alignment: .leading, spacing: ScreenMetrics.rowSpacing) {
                        SectionHeader("Settings Are Locked")

                        LabeledTextField(
                            label: "PIN",
                            placeholder: "Required",
                            text: $enteredPIN,
                            isSecure: true,
                            accessibilityLabelText: "Settings PIN"
                        )

                        if showMismatch {
                            Text("Incorrect PIN.")
                                .font(.caption)
                                .foregroundColor(Color(red: 1.0, green: 0.45, blue: 0.42))
                        } else {
                            Text("Ask an administrator if you do not have the PIN.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Button {
                        if viewModel.isCorrectSettingsPIN(enteredPIN) {
                            unlocked = true
                            showMismatch = false
                            enteredPIN = ""
                            AccessibilityNotification.Announcement("Settings unlocked").post()
                        } else {
                            showMismatch = true
                            enteredPIN = ""
                            AccessibilityNotification.Announcement("Incorrect PIN").post()
                        }
                    } label: {
                        CenteredRowLabel(title: "Unlock")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(enteredPIN.isEmpty)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, ScreenMetrics.horizontalPadding)
                .padding(.vertical, ScreenMetrics.verticalPadding)
            }
        }
    }

    private var settings: some View {
        SettingsView(
            isPlayingOnOpen: $viewModel.isPlayingOnOpen,
            retryTimeout: $viewModel.retryTimeout,
            autoResume: $viewModel.autoResume,
            settingsDisabled: $viewModel.settingsDisabled,
            confirmBeforeDelete: $viewModel.confirmBeforeDelete,
            displayTitle: $viewModel.displayTitle,
            viewOnlyMode: $viewModel.viewOnlyMode,
            settingsPIN: $viewModel.settingsPIN,
            settingsPINManaged: viewModel.settingsPINManaged,
            channelPresetsManaged: viewModel.channelPresetsManaged,
            onRetryTimeoutChanged: {
                viewModel.updateSettings(
                    isPlayingOnOpen: viewModel.isPlayingOnOpen,
                    retryTimeout: viewModel.retryTimeout,
                    autoResume: viewModel.autoResume,
                    settingsDisabled: viewModel.settingsDisabled
                )
            },
            onConfirmBeforeDeleteChanged: { viewModel.updateConfirmBeforeDelete($0) },
            onDisplayTitleChanged: { viewModel.updateDisplayTitle($0) },
            onViewOnlyModeChanged: { viewModel.updateViewOnlyMode($0) },
            onSetPIN: { viewModel.setSettingsPIN($0) },
            onClearPIN: { viewModel.clearSettingsPIN() }
        )
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
    @Binding var displayTitle: String
    @Binding var viewOnlyMode: Bool
    /// Current PIN, read only to show whether one is set. Never bound to a field —
    /// see `newPIN`.
    @Binding var settingsPIN: String
    /// The PIN came from MDM, so it cannot be changed here.
    var settingsPINManaged: Bool
    /// Presets are read-only under MDM, so the delete-confirmation preference has
    /// nothing to act on and is hidden entirely rather than shown disabled.
    var channelPresetsManaged: Bool
    var onRetryTimeoutChanged: () -> Void
    var onConfirmBeforeDeleteChanged: (Bool) -> Void
    var onDisplayTitleChanged: (String) -> Void
    var onViewOnlyModeChanged: (Bool) -> Void
    var onSetPIN: (String) -> Bool
    var onClearPIN: () -> Void

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
                    SectionHeader("Appearance")

                    LabeledTextField(
                        label: "Title",
                        placeholder: StreamViewModel.defaultDisplayTitle,
                        text: Binding(
                            get: { displayTitle },
                            set: { onDisplayTitleChanged($0) }
                        ),
                        disabled: settingsDisabled,
                        accessibilityLabelText: "Main screen title"
                    )

                    Text("Heading shown at the top of the main screen. Leave blank for \"\(StreamViewModel.defaultDisplayTitle)\".")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

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

                VStack(alignment: .leading, spacing: ScreenMetrics.rowSpacing) {
                    SectionHeader("Access")

                    SettingToggleRow(
                        title: "View Only Mode",
                        isOn: $viewOnlyMode,
                        disabled: settingsDisabled
                    ) { newValue in
                        onViewOnlyModeChanged(newValue)
                    }

                    Text("Reduces the main screen to the preset list. Stream URL entry and preset management are hidden; pressing a preset plays it.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    RowLabel(
                        title: "Settings PIN",
                        value: settingsPIN.isEmpty ? "Not set" : "Set"
                    )
                    .padding(.top, ScreenMetrics.fieldSpacing)

                    if settingsPINManaged {
                        Text("Your administrator set this PIN. It cannot be changed here.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else if settingsPIN.isEmpty {
                        // Pushed, not presented: a text field inside a modal does not
                        // get its editing presentation torn down on tvOS when the user
                        // backs out of the keyboard.
                        NavigationLink {
                            SettingsPINEditorView(onSave: onSetPIN)
                        } label: {
                            RowLabel(title: "Set PIN")
                        }
                        .disabled(settingsDisabled)
                        .accessibilityHint("Opens the PIN editor")

                        Text("Requires a PIN to open Settings.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Button {
                            onClearPIN()
                            AccessibilityNotification.Announcement("PIN removed").post()
                        } label: {
                            DestructiveRowLabel(title: "Remove PIN")
                        }
                        .disabled(settingsDisabled)

                        Text("Settings will open without a PIN once removed.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
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

/// Full-screen PIN editor, reached by a navigation push.
///
/// No Save or Cancel: the PIN is applied and the screen pops when the user presses
/// Done on the keyboard and the two entries agree. Backing out with Menu without
/// matching entries is the cancel path, and nothing is written until they match.
///
/// Evaluating per keystroke instead popped this screen out from under the still-open
/// keyboard the moment the values happened to match.
///
/// Kept separate from Settings so the PIN is only ever written once. An earlier
/// version put these fields inline and bound them straight to storage, which meant
/// the first digit of a longer PIN took effect on its own and locked the user out
/// of the screen needed to undo it.
private struct SettingsPINEditorView: View {
    let onSave: (String) -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var newPIN = ""
    @State private var confirmPIN = ""
    @State private var errorMessage: String?

    private var bothEntered: Bool { !newPIN.isEmpty && !confirmPIN.isEmpty }

    /// Says what is still needed, or what went wrong.
    private var guidance: String {
        if let errorMessage { return errorMessage }
        if newPIN.isEmpty {
            return "Enter a PIN of \(StreamViewModel.minimumSettingsPINLength) digits or more."
        }
        if !StreamViewModel.isValidSettingsPIN(newPIN) {
            return "Use at least \(StreamViewModel.minimumSettingsPINLength) digits, numbers only."
        }
        if confirmPIN.isEmpty { return "Re-enter the same PIN to confirm." }
        return "Press Done on the keyboard to apply."
    }

    var body: some View {
        ZStack {
            ModalBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: ScreenMetrics.groupSpacing) {
                    Text("Set PIN")
                        .font(.largeTitle)
                        .fontWeight(.semibold)
                        .padding(.bottom, ScreenMetrics.titleSpacing)
                        .accessibilityAddTraits(.isHeader)

                    VStack(alignment: .leading, spacing: ScreenMetrics.fieldSpacing) {
                        SectionHeader("New Settings PIN")

                        LabeledTextField(
                            label: "PIN",
                            placeholder: "\(StreamViewModel.minimumSettingsPINLength)+ digits",
                            text: $newPIN,
                            isSecure: true,
                            accessibilityLabelText: "New settings PIN",
                            onSubmit: { evaluate() }
                        )

                        LabeledTextField(
                            label: "Confirm",
                            placeholder: "Re-enter",
                            text: $confirmPIN,
                            isSecure: true,
                            accessibilityLabelText: "Confirm new settings PIN",
                            onSubmit: { evaluate() }
                        )

                        Text(guidance)
                            .font(.caption)
                            .foregroundColor(errorMessage == nil
                                             ? .secondary
                                             : Color(red: 1.0, green: 0.45, blue: 0.42))
                            .padding(.top, ScreenMetrics.fieldSpacing)

                        Text("Leave without matching entries to cancel.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, ScreenMetrics.horizontalPadding)
                .padding(.vertical, ScreenMetrics.verticalPadding)
            }
        }
    }

    /// Applies the PIN when both entries agree. Called from each field's Done, so a
    /// half-typed confirmation is never judged mid-entry.
    private func evaluate() {
        guard bothEntered else {
            errorMessage = nil
            return
        }
        guard StreamViewModel.isValidSettingsPIN(newPIN) else {
            errorMessage = nil   // the guidance already explains the length rule
            return
        }
        guard newPIN == confirmPIN else {
            errorMessage = "The two entries do not match."
            return
        }
        if onSave(newPIN) {
            errorMessage = nil
            AccessibilityNotification.Announcement("PIN set").post()
            dismiss()
        } else {
            errorMessage = "Could not set that PIN. Try another."
        }
    }
}
