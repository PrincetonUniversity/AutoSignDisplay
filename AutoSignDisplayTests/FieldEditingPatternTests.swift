//
//  FieldEditingPatternTests.swift
//  AutoSignDisplayTests
//
//  Guards the presentation rules that make text-field editing behave on tvOS.
//
//  Background: editing a preset's Name or URL used to leave the field stuck in
//  tvOS's compact editing presentation — a blank white bar with small, faint
//  text — whenever the user backed out of the keyboard without committing. The
//  main screen's stream URL field never had the problem. After eliminating
//  colors, spacing, focus state, bindings, and array churn as causes, the one
//  remaining difference was the presentation context: every broken field lived
//  inside a presented modal (`.sheet`, then `.fullScreenCover`), and the working
//  field was reached by a plain navigation push. Making the preset screens pushes
//  fixed it.
//
//  That failure is invisible to a unit test — it is a rendering state, not data —
//  and tvOS focus automation is too flaky to assert on in a UI test. The rules
//  themselves are structural, though, so they are enforced here against the
//  source. These tests exist to stop the pattern being undone by accident.
//

import Foundation
import Testing

struct FieldEditingPatternTests {

    // MARK: - Source access

    /// The app's source directory, derived from this file's location. Tests run
    /// from a checkout, so the sources are always alongside them.
    private static var appSourceDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // AutoSignDisplayTests/
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("AutoSignDisplay")
    }

    private func source(of fileName: String) throws -> String {
        let url = Self.appSourceDirectory.appendingPathComponent(fileName)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func allAppSources() throws -> [(name: String, text: String)] {
        let dir = Self.appSourceDirectory
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.hasSuffix(".swift") }
            .sorted()
        return try names.map { (name: $0, text: try source(of: $0)) }
    }

    /// Strips `//` line comments so the guards match real code and not the
    /// explanatory comments that describe the very patterns being banned.
    private func codeOnly(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                guard let range = line.range(of: "//") else { return String(line) }
                return String(line[line.startIndex..<range.lowerBound])
            }
            .joined(separator: "\n")
    }

    // MARK: - Presentation context

    @Test func settingsAndPresetsAreReachedByNavigationPush() throws {
        let code = codeOnly(try source(of: "ContentView.swift"))

        #expect(
            code.contains("NavigationLink"),
            """
            ContentView must reach Settings and Manage Stream Presets with \
            NavigationLink. A text field inside a presented modal does not get its \
            editing presentation torn down on tvOS when the user cancels out of the \
            keyboard.
            """
        )

        #expect(
            code.contains("ChannelPresetsView("),
            "ContentView should still construct ChannelPresetsView( as a push destination."
        )

        // Settings is reached through SettingsGateView, which shows the PIN prompt
        // when one is configured and SettingsView otherwise. Both contain text
        // fields, so both have to be pushed rather than presented.
        #expect(
            code.contains("SettingsGateView("),
            "ContentView should reach Settings through SettingsGateView( as a push destination."
        )

        let settingsSource = codeOnly(try source(of: "SettingsView.swift"))
        #expect(
            settingsSource.contains("SettingsView("),
            "SettingsGateView should construct SettingsView once unlocked."
        )
    }

    @Test func onlyTheVideoPlayerIsPresentedAsAFullScreenCover() throws {
        for (name, text) in try allAppSources() {
            let code = codeOnly(text)
            var searchRange = code.startIndex..<code.endIndex

            while let found = code.range(of: "fullScreenCover", range: searchRange) {
                // The video player is the one legitimate cover: it is not a form,
                // it holds no text fields, and full-screen is the point of it.
                let lineStart = code[code.startIndex..<found.lowerBound]
                    .lastIndex(of: "\n")
                    .map { code.index(after: $0) } ?? code.startIndex
                let lineEnd = code[found.upperBound...]
                    .firstIndex(of: "\n") ?? code.endIndex
                let line = String(code[lineStart..<lineEnd])

                #expect(
                    line.contains("$showPlayer"),
                    """
                    \(name) presents a fullScreenCover that is not the video player: \
                    \(line.trimmingCharacters(in: .whitespaces)). Screens containing \
                    text fields must be pushed, not presented — see this file's header.
                    """
                )

                searchRange = found.upperBound..<code.endIndex
            }
        }
    }

    @Test func noScreenIsPresentedAsASheet() throws {
        for (name, text) in try allAppSources() {
            #expect(
                !codeOnly(text).contains(".sheet("),
                """
                \(name) uses .sheet. tvOS renders a sheet as a narrow centered card \
                that truncates stream URLs, and text fields inside one exhibit the \
                stuck-editing-presentation bug. Push instead.
                """
            )
        }
    }

    // MARK: - Text field styling

    @Test func textFieldsDoNotOverrideColorFromFocusState() throws {
        for (name, text) in try allAppSources() {
            let code = codeOnly(text)

            #expect(
                !code.contains("focused ?"),
                """
                \(name) colors a control from a @FocusState flag. On tvOS, focus and \
                editing are separate states; keying a text field's color off focus \
                alone desynced from the system and rendered values light-on-light. \
                Text fields are left plain — tvOS handles their contrast. Button \
                labels are the exception and read ambient \\.isFocused instead (see \
                RowLabel / CenteredRowLabel / DestructiveRowLabel).
                """
            )
        }
    }

    @Test func presetFieldsUseTheSharedPlainTextFieldWrapper() throws {
        let code = codeOnly(try source(of: "ChannelPresetsView.swift"))

        #expect(
            code.contains("LabeledTextField("),
            "Preset rows should edit through LabeledTextField, which is deliberately plain."
        )
        #expect(
            !code.contains("@FocusState"),
            """
            ChannelPresetsView declares @FocusState. Per-row focus tracking is what \
            first masked this bug; the fields need no focus plumbing at all.
            """
        )
    }

    @Test func labeledTextFieldStaysPlain() throws {
        let code = codeOnly(try source(of: "SettingsView.swift"))

        guard let start = code.range(of: "struct LabeledTextField: View {") else {
            Issue.record("LabeledTextField not found in SettingsView.swift")
            return
        }
        // Read to the start of the next top-level declaration.
        let rest = code[start.upperBound...]
        let end = rest.range(of: "\nstruct ")?.lowerBound ?? rest.endIndex
        let body = String(rest[rest.startIndex..<end])

        // Only focus plumbing is banned. The row's *label* legitimately colors
        // itself `.secondary`; it is the TextField that must stay unstyled. With no
        // focus state to read, the focus-keyed color that caused the bug cannot be
        // reintroduced here anyway — and `textFieldsDoNotOverrideColorFromFocusState`
        // guards that form across every source file.
        for banned in ["@FocusState", ".focused("] {
            #expect(
                !body.contains(banned),
                """
                LabeledTextField contains \(banned). It must stay plain so tvOS owns \
                the field's focused background and text contrast — every attempt to \
                manage those by hand reintroduced the stuck-white-field bug.
                """
            )
        }
    }
}
