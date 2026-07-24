//
//  SettingsView.swift
//  AutoSignDisplay
//
//  Created by Michael Bino on 4/20/25.
//

import SwiftUI

private struct FocusAwareLabel: View {
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
                    FocusAwareLabel(title: "Retry Timeout (seconds):", fieldFocused: retryTimeoutFocused)
                    TextField("Timeout", value: $retryTimeout, formatter: NumberFormatter())
                        .keyboardType(.numberPad)
                        .focused($retryTimeoutFocused)
                        .onChangeOld(of: retryTimeout) { _, newValue in
                            UserDefaults.standard.set(newValue, forKey: ContentView.retryTimeoutKey)
                            onRetryTimeoutChanged()
                        }
                        .disabled(settingsDisabled)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}
