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

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var isPlayingOnOpen: Bool
    @Binding var retryTimeout: Double
    @Binding var autoResume: Bool
    @Binding var settingsDisabled: Bool
    var onRetryTimeoutChanged: () -> Void

    @FocusState private var retryTimeoutFocused: Bool

    var body: some View {
        NavigationView {
            Form {
                Toggle(isOn: $isPlayingOnOpen) {
                    FocusAwareLabel(title: "Play on App Open")
                }
                .onChangeOld(of: isPlayingOnOpen) { _, newValue in
                    UserDefaults.standard.set(newValue, forKey: ContentView.playOnOpenKey)
                    onRetryTimeoutChanged()
                }
                .disabled(settingsDisabled)

                Toggle(isOn: $autoResume) {
                    FocusAwareLabel(title: "Auto Resume on Network Interrupt")
                }
                .onChangeOld(of: autoResume) { _, newValue in
                    UserDefaults.standard.set(newValue, forKey: ContentView.autoResumeKey)
                    onRetryTimeoutChanged()
                }
                .disabled(settingsDisabled)

                HStack {
                    // Visible label for sighted users; hidden from VoiceOver so the row reads
                    // as a single "Retry timeout in seconds, <value>, text field" element.
                    FocusAwareLabel(title: "Retry Timeout (seconds):", fieldFocused: retryTimeoutFocused)
                        .accessibilityHidden(true)
                    TextField("Timeout", value: $retryTimeout, formatter: NumberFormatter())
                        .keyboardType(.numberPad)
                        .focused($retryTimeoutFocused)
                        .accessibilityLabel("Retry timeout in seconds")
                        .onChangeOld(of: retryTimeout) { _, newValue in
                            UserDefaults.standard.set(newValue, forKey: ContentView.retryTimeoutKey)
                            onRetryTimeoutChanged()
                        }
                        .disabled(settingsDisabled)
                }

                // Done sits at the bottom of the form: on tvOS the top-right toolbar
                // placement forces users to navigate all the way back up past the last
                // control to dismiss, which is awkward on a remote.
                Section {
                    Button {
                        dismiss()
                    } label: {
                        Text("Done")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .navigationTitle("Settings")
        }
    }
}
