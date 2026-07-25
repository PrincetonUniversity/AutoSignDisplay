//
//  ChannelPresetsView.swift
//  AutoSignDisplay
//
//  Created for managing channel presets.
//

import SwiftUI

struct ChannelPresetsView: View {
    @ObservedObject var viewModel: StreamViewModel

    /// Index awaiting delete confirmation. Non-nil drives the confirmation alert.
    @State private var pendingDeleteIndex: Int?

    var body: some View {
        ZStack {
            ModalBackground()
            presetsList
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

    // MARK: - List

    private var presetsList: some View {
        ScrollViewReader { proxy in
            presetsScrollView(proxy: proxy)
        }
    }

    private func presetsScrollView(proxy: ScrollViewProxy) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ScreenMetrics.groupSpacing) {
                // Matches the button that opens this screen.
                Text("Manage Stream Presets")
                    .font(.largeTitle)
                    .fontWeight(.semibold)
                    .padding(.bottom, ScreenMetrics.titleSpacing)
                    .accessibilityAddTraits(.isHeader)

                if viewModel.channelPresetsManaged {
                    Text("Stream presets are managed by your administrator and cannot be changed here.")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }

                // Add sits above the list, not below it. tvOS focus travel is
                // directional, so an action stranded under 20 presets takes a long
                // swipe to reach; here it is one press away when the screen opens.
                if !viewModel.channelPresetsManaged {
                    VStack(alignment: .leading, spacing: ScreenMetrics.rowSpacing) {
                        Button {
                            viewModel.addChannelPreset()
                            // The new row is appended, so bring it into view —
                            // otherwise pressing Add appears to do nothing.
                            if let newIndex = viewModel.channelPresets.indices.last {
                                withAnimation {
                                    proxy.scrollTo(newIndex, anchor: .center)
                                }
                                AccessibilityNotification.Announcement(
                                    "Added preset \(newIndex + 1)"
                                ).post()
                            }
                        } label: {
                            RowLabel(title: "Add Preset")
                        }
                        .disabled(!viewModel.canAddMorePresets)
                        .accessibilityLabel("Add a Preset")

                        Text(viewModel.canAddMorePresets
                             ? "You can store up to \(StreamViewModel.maxChannelPresets) presets."
                             : "Preset limit reached (\(StreamViewModel.maxChannelPresets)).")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                if viewModel.channelPresets.isEmpty {
                    Text("No presets available.")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(Array(viewModel.channelPresets.enumerated()), id: \.offset) { index, preset in
                        PresetGroup(
                            index: index,
                            isSelected: viewModel.selectedPresetIndex == index,
                            preset: preset,
                            managed: viewModel.channelPresetsManaged,
                            name: nameBinding(for: index),
                            url: urlBinding(for: index),
                            onRemove: { requestDelete(at: index) }
                        )
                        .id(index)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, ScreenMetrics.horizontalPadding)
            .padding(.vertical, ScreenMetrics.verticalPadding)
        }
    }

    // MARK: - Bindings

    private func nameBinding(for index: Int) -> Binding<String> {
        Binding(
            get: {
                viewModel.channelPresets.indices.contains(index)
                    ? viewModel.channelPresets[index].name
                    : ""
            },
            set: { viewModel.updateChannelPresetName(at: index, name: $0) }
        )
    }

    private func urlBinding(for index: Int) -> Binding<String> {
        Binding(
            get: {
                viewModel.channelPresets.indices.contains(index)
                    ? viewModel.channelPresets[index].url
                    : ""
            },
            set: { viewModel.updateChannelPreset(at: index, url: $0) }
        )
    }

    // MARK: - Delete

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
}

/// One preset: a header, two rows that push an editor, and a labeled Delete.
///
/// The rows show values but are not text fields. tvOS leaves a text field stuck
/// in its compact editing presentation when the user cancels out of the keyboard,
/// and a stack of them in a list has nothing to force the re-render that would
/// clear it. Editing happens one field at a time on a pushed screen.
private struct PresetGroup: View {
    let index: Int
    let isSelected: Bool
    let preset: ChannelPreset
    let managed: Bool
    @Binding var name: String
    @Binding var url: String
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ScreenMetrics.fieldSpacing) {
            HStack(spacing: ScreenMetrics.buttonSpacing) {
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
                Button(action: onRemove) {
                    // Names the target so a row of identical "Delete" buttons can't
                    // be confused for one another. Self-describing, so no separate
                    // accessibilityLabel is needed — VoiceOver reads this text.
                    DestructiveRowLabel(title: "Delete Preset \(index + 1)")
                }
                .frame(width: 420)
                .padding(.top, ScreenMetrics.fieldSpacing)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Preset \(index + 1)")
    }
}
