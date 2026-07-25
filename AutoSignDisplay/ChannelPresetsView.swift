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

    /// Index awaiting delete confirmation. Non-nil drives the confirmation alert.
    @State private var pendingDeleteIndex: Int?

    var body: some View {
        ZStack {
            ModalBackground()
            presetsContent
        }
        .alert(
            "Delete Preset?",
            isPresented: Binding(
                get: { pendingDeleteIndex != nil },
                set: { if !$0 { pendingDeleteIndex = nil } }
            ),
            presenting: pendingDeleteIndex
        ) { index in
            Button("Delete", role: .destructive) {
                viewModel.removeChannelPreset(at: index)
                pendingDeleteIndex = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteIndex = nil
            }
        } message: { index in
            Text(deleteConfirmationMessage(for: index))
        }
    }

    private func deleteConfirmationMessage(for index: Int) -> String {
        guard viewModel.channelPresets.indices.contains(index) else {
            return "This preset will be removed."
        }
        let preset = viewModel.channelPresets[index]
        let descriptor = preset.name.isEmpty ? preset.url : preset.name
        if descriptor.isEmpty {
            return "Preset \(index + 1) will be removed."
        }
        return "\(descriptor) will be removed."
    }

    /// Honors the Confirm Before Deleting preference: prompt when on, delete outright when off.
    private func requestDelete(at index: Int) {
        if viewModel.confirmBeforeDelete {
            pendingDeleteIndex = index
        } else {
            viewModel.removeChannelPreset(at: index)
        }
    }

    private var presetsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ScreenMetrics.groupSpacing) {
                // Matches the button that opens this screen.
                Text("Manage Stream Presets")
                    .font(.largeTitle)
                    .fontWeight(.semibold)
                    .padding(.bottom, ScreenMetrics.rowSpacing)
                    .accessibilityAddTraits(.isHeader)

                if viewModel.channelPresetsManaged {
                    Text("Stream presets are managed by your administrator and cannot be changed here.")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }

                if viewModel.channelPresets.isEmpty {
                    Text("No presets available.")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(Array(viewModel.channelPresets.enumerated()), id: \.offset) { index, preset in
                        PresetGroup(
                            index: index,
                            isSelected: viewModel.selectedPresetIndex == index,
                            name: nameBinding(for: index),
                            url: urlBinding(for: index),
                            managed: viewModel.channelPresetsManaged,
                            onRemove: { requestDelete(at: index) }
                        )
                    }
                }

                if !viewModel.channelPresetsManaged {
                    VStack(alignment: .leading, spacing: ScreenMetrics.rowSpacing) {
                        Button {
                            viewModel.addChannelPreset()
                        } label: {
                            RowLabel(title: "Add Preset")
                        }
                        .disabled(!viewModel.canAddMorePresets)

                        Text(viewModel.canAddMorePresets
                             ? "You can store up to \(StreamViewModel.maxChannelPresets) presets."
                             : "Preset limit reached (\(StreamViewModel.maxChannelPresets)).")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Button {
                    dismiss()
                } label: {
                    RowLabel(title: "Done")
                }
                .padding(.top, ScreenMetrics.rowSpacing)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, ScreenMetrics.horizontalPadding)
            .padding(.vertical, ScreenMetrics.verticalPadding)
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

/// One preset as a labeled group: a header that names the row, the two editable
/// fields, and a labeled Delete action. Choosing which preset to play is done on
/// the main screen, so this screen is purely for editing.
private struct PresetGroup: View {
    let index: Int
    let isSelected: Bool
    @Binding var name: String
    @Binding var url: String
    let managed: Bool
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ScreenMetrics.rowSpacing) {
            HStack(spacing: 16) {
                SectionHeader("Preset \(index + 1)")
                if isSelected {
                    Text("SELECTED")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .tracking(1.5)
                        .foregroundColor(.accentColor)
                        .accessibilityHidden(true)
                }
            }

            LabeledTextField(
                label: "Name",
                placeholder: "Optional",
                text: $name,
                disabled: managed,
                accessibilityLabelText: "Preset \(index + 1) name"
            )

            LabeledTextField(
                label: "URL",
                placeholder: "https://example.com/stream.m3u8",
                text: $url,
                disabled: managed,
                isURL: true,
                accessibilityLabelText: "Preset \(index + 1) URL"
            )

            if !managed {
                // Deliberately NOT Button(role: .destructive): tvOS renders that as a
                // solid red fill, which made deleting the loudest thing on screen.
                // Red text on the standard card keeps the warning without the shouting.
                Button {
                    onRemove()
                } label: {
                    DestructiveRowLabel(title: "Delete")
                }
                .frame(width: 320)
                .accessibilityLabel("Delete preset \(index + 1)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Preset \(index + 1)")
    }
}
