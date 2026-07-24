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
                                name: nameBinding(for: index),
                                url: urlBinding(for: index),
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

    private func nameBinding(for index: Int) -> Binding<String> {
        Binding(
            get: {
                viewModel.channelPresets.indices.contains(index)
                    ? viewModel.channelPresets[index].name
                    : ""
            },
            set: { newValue in
                viewModel.updateChannelPresetName(at: index, name: newValue)
            }
        )
    }

    private func urlBinding(for index: Int) -> Binding<String> {
        Binding(
            get: {
                viewModel.channelPresets.indices.contains(index)
                    ? viewModel.channelPresets[index].url
                    : ""
            },
            set: { newValue in
                viewModel.updateChannelPreset(at: index, url: newValue)
            }
        )
    }
}

private struct PresetRow: View {
    let index: Int
    @Binding var name: String
    @Binding var url: String
    let managed: Bool
    let onRemove: () -> Void
    let onSelect: () -> Void

    @FocusState private var nameFocused: Bool
    @FocusState private var urlFocused: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                TextField("Name (optional)", text: $name)
                    .focused($nameFocused)
                    .foregroundColor(nameFocused ? .black : .primary)
                    .accessibilityLabel("Preset \(index + 1) name")
                    .disabled(managed)

                TextField("Preset \(index + 1) URL", text: $url)
                    .textContentType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .focused($urlFocused)
                    .foregroundColor(urlFocused ? .black : .primary)
                    .accessibilityLabel("Preset \(index + 1) URL")
                    .disabled(managed)
            }

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
