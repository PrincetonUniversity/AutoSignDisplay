//
//  ChannelPresetsView.swift
//  AutoSignDisplay
//
//  Created for managing channel presets.
//

import SwiftUI

struct ChannelPresetsView: View {
    @ObservedObject var viewModel: StreamViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section {
                    if viewModel.channelPresets.isEmpty {
                        Text("No presets available.")
                    } else {
                        ForEach(Array(viewModel.channelPresets.enumerated()), id: \.offset) { index, _ in
                            PresetRow(
                                index: index,
                                text: binding(for: index),
                                managed: viewModel.channelPresetsManaged,
                                onRemove: { viewModel.removeChannelPreset(at: index) },
                                onSelect: {
                                    viewModel.selectPreset(at: index)
                                    dismiss()
                                }
                            )
                        }
                    }
                }

                if viewModel.channelPresetsManaged {
                    Text("Stream presets are managed by your administrator.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                } else {
                    Button {
                        viewModel.addChannelPreset()
                    } label: {
                        FocusAwareLabel(title: "Add Preset")
                    }
                    .disabled(!viewModel.canAddMorePresets)

                    if !viewModel.canAddMorePresets {
                        Text("You can store up to 20 channel presets.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }

                // Done at the bottom rather than a top-toolbar item — remotes travel down.
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
            .formStyle(.grouped)
            .navigationTitle("Stream Presets")
        }
    }

    private func binding(for index: Int) -> Binding<String> {
        Binding(
            get: {
                if viewModel.channelPresets.indices.contains(index) {
                    return viewModel.channelPresets[index]
                }
                return ""
            },
            set: { newValue in
                viewModel.updateChannelPreset(at: index, with: newValue)
            }
        )
    }
}

private struct PresetRow: View {
    let index: Int
    @Binding var text: String
    let managed: Bool
    let onRemove: () -> Void
    let onSelect: () -> Void
    @FocusState private var textFieldFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            TextField("Preset \(index + 1)", text: $text)
                .textContentType(.URL)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .focused($textFieldFocused)
                // Same white-on-white problem as the Settings toggles: when the row
                // lights up on focus, default `.primary` text is invisible.
                .foregroundColor(textFieldFocused ? .black : .primary)
                .accessibilityLabel("Preset \(index + 1) URL")
                .disabled(managed)

            if !managed {
                Button(role: .destructive) {
                    onRemove()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Delete preset \(index + 1)")
            }

            Button {
                onSelect()
            } label: {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 20))
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Play preset \(index + 1)")
        }
    }
}
