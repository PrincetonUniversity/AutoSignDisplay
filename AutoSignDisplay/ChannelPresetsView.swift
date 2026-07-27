//
//  ChannelPresetsView.swift
//  AutoSignDisplay
//
//  Created for managing channel presets.
//

import SwiftUI

struct ChannelPresetsView: View {
    @ObservedObject var viewModel: StreamViewModel

    /// Where to scroll once the Add Preset screen pops back.
    private enum ScrollDestination: Equatable {
        case newestPreset
        case top
    }

    private static let topAnchor = "top"

    /// Index awaiting delete confirmation. Non-nil drives the confirmation alert.
    @State private var pendingDeleteIndex: Int?
    @State private var scrollDestination: ScrollDestination?

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
                    .id(Self.topAnchor)

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
                        NavigationLink {
                            AddPresetView(
                                onSave: { name, url in
                                    if let newIndex = viewModel.addChannelPreset(name: name, url: url) {
                                        AccessibilityNotification.Announcement(
                                            "Added preset \(newIndex + 1)"
                                        ).post()
                                    }
                                    scrollDestination = .newestPreset
                                },
                                onCancel: { scrollDestination = .top }
                            )
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
                            isPlaying: viewModel.selectedPresetIndex == index
                                && viewModel.player != nil,
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
        // Applied after the Add Preset screen pops: Save lands on the new entry,
        // Cancel returns to the top. Set from the child rather than scrolled there
        // directly, because the proxy only exists inside this ScrollViewReader.
        .onChangeOld(of: scrollDestination) { _, destination in
            guard let destination else { return }
            withAnimation {
                switch destination {
                case .newestPreset:
                    if let last = viewModel.channelPresets.indices.last {
                        proxy.scrollTo(last, anchor: .bottom)
                    }
                case .top:
                    proxy.scrollTo(Self.topAnchor, anchor: .top)
                }
            }
            scrollDestination = nil
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
        // `spokenDescriptor` rather than the raw URL: this message is read aloud
        // before a destructive confirmation, and a full HLS URL spelled out character
        // by character is unusable. Falls back to the URL's filename or host.
        guard let descriptor = viewModel.channelPresets[index].spokenDescriptor else {
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
    /// This preset is the one currently on screen. Blocks deletion and relabels
    /// the marker, matching the main screen.
    let isPlaying: Bool
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
                    Text(isPlaying ? "PLAYING" : "SELECTED")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .tracking(1.5)
                        .foregroundColor(.accentColor)
                        .accessibilityHidden(true)
                }
            }

            // Locked while this preset is on screen, for the same reason the main
            // screen locks its URL field: the text would describe something other
            // than what is actually playing.
            LabeledTextField(
                label: "Name",
                placeholder: "Optional",
                text: $name,
                disabled: managed || isPlaying,
                accessibilityLabelText: "Preset \(index + 1) name"
            )

            LabeledTextField(
                label: "URL",
                placeholder: "https://example.com/stream.m3u8",
                text: $url,
                disabled: managed || isPlaying,
                isURL: true,
                accessibilityLabelText: "Preset \(index + 1) URL"
            )

            if isPlaying {
                Text("Stop the stream to edit this preset.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

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
                // Deleting the stream that is currently on screen would leave the
                // player running against an entry that no longer exists.
                .disabled(isPlaying)
                .accessibilityHint(isPlaying ? "Stop the stream to delete this preset" : "")
            }
        }
        .accessibilityElement(children: .contain)
        // Carries the state the SELECTED/PLAYING marker shows visually. That marker is
        // hidden from accessibility to keep it out of the child labels, so without this
        // a VoiceOver user could not tell which preset is selected or on screen.
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var accessibilityLabel: String {
        let position = "Preset \(index + 1)"
        guard isSelected else { return position }
        return isPlaying ? "\(position), playing" : "\(position), selected"
    }
}

/// Full-screen Add Preset form, reached by a navigation push.
///
/// Adding used to append a blank row directly to the list, which landed
/// off-screen below the fold and read as "nothing happened". Collecting the
/// values first means the list only ever gains a complete entry.
private struct AddPresetView: View {
    let onSave: (String, String) -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var url = ""

    /// A preset with no URL cannot play, so Save stays disabled until there is one.
    /// Name is genuinely optional — the list falls back to showing the URL.
    private var canSave: Bool {
        !url.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        ZStack {
            ModalBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: ScreenMetrics.groupSpacing) {
                    Text("Add Preset")
                        .font(.largeTitle)
                        .fontWeight(.semibold)
                        .padding(.bottom, ScreenMetrics.titleSpacing)
                        .accessibilityAddTraits(.isHeader)

                    VStack(alignment: .leading, spacing: ScreenMetrics.fieldSpacing) {
                        SectionHeader("New Preset")

                        LabeledTextField(
                            label: "Name",
                            placeholder: "Optional",
                            text: $name,
                            accessibilityLabelText: "New preset name"
                        )

                        LabeledTextField(
                            label: "URL",
                            placeholder: "https://example.com/stream.m3u8",
                            text: $url,
                            isURL: true,
                            accessibilityLabelText: "New preset URL"
                        )

                        Text("A name is optional. Without one, the list shows the URL.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, ScreenMetrics.fieldSpacing)
                    }

                    HStack(spacing: ScreenMetrics.buttonSpacing) {
                        Button {
                            onSave(name.trimmingCharacters(in: .whitespaces),
                                   url.trimmingCharacters(in: .whitespaces))
                            dismiss()
                        } label: {
                            CenteredRowLabel(title: "Save")
                        }
                        .disabled(!canSave)
                        .accessibilityHint(canSave ? "" : "Enter a URL first")

                        Button {
                            onCancel()
                            dismiss()
                        } label: {
                            CenteredRowLabel(title: "Cancel")
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, ScreenMetrics.horizontalPadding)
                .padding(.vertical, ScreenMetrics.verticalPadding)
            }
        }
    }
}
