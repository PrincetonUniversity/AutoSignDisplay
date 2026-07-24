import Foundation
import Testing
@testable import AutoSignDisplay

struct LoggerTests {
    class TestLogger: Logger {
        var messages: [String] = []
        func log(_ message: String) { messages.append(message) }
    }

    @Test func autoResumeLogEmitted() async throws {
        // Prepare user defaults
        await MainActor.run {
            UserDefaults.standard.set("https://example.com/stream.m3u8", forKey: ContentView.lastStreamURLKey)
        }

        let testLogger = TestLogger()
        let vm = StreamViewModel(logger: testLogger)
        vm.streamURL = "https://example.com/stream.m3u8"
        vm.emitAutoResumeLogForTesting()

        #expect(testLogger.messages.count == 1)
        #expect(testLogger.messages.first == "Auto-resuming stream: https://example.com/stream.m3u8")
    }
}
