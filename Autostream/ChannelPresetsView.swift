//
//  ChannelPresetsView.swift
//  Autostream
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
                            HStack {
                                TextField(
                                    "Preset \(index + 1)",
                                    text: binding(for: index)
                                )
                                .textContentType(.URL)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .disabled(viewModel.channelPresetsManaged)

                                Button("Use") {
                                    viewModel.selectPreset(at: index)
                                    dismiss()
                                }
                                .buttonStyle(.borderless)

                                if !viewModel.channelPresetsManaged {
                                    Button(role: .destructive) {
                                        viewModel.removeChannelPreset(at: index)
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                    .buttonStyle(.borderless)
                                }
                            }
                        }
                    }
                }

                if viewModel.channelPresetsManaged {
                    Text("Stream presets are managed by your administrator.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                } else {
                    Button("Add Preset") {
                        viewModel.addChannelPreset()
                    }
                    .disabled(!viewModel.canAddMorePresets)

                    if !viewModel.canAddMorePresets {
                        Text("You can store up to 20 channel presets.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Stream Presets")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
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
