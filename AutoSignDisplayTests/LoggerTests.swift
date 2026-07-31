import Foundation
import Testing
@testable import AutoSignDisplay

struct LoggerTests {
    class TestLogger: Logger {
        var messages: [String] = []
        func log(_ message: String) { messages.append(message) }
    }

    @Test func autoResumeLogEmitted() async throws {
        // Deliberately touches no UserDefaults. It used to seed lastStreamURLKey and
        // then overwrite vm.streamURL on the next line anyway, so the write bought
        // nothing — but it made this suite a second writer of the shared defaults
        // domain, and Swift Testing runs top-level suites concurrently. Serializing
        // AutoSignDisplayTests would not have protected against this one.
        let testLogger = TestLogger()
        let vm = StreamViewModel(logger: testLogger)
        vm.streamURL = "https://example.com/stream.m3u8"
        vm.emitAutoResumeLogForTesting()

        #expect(testLogger.messages.count == 1)
        #expect(testLogger.messages.first
                == "Auto-resuming stream (no player item): https://example.com/stream.m3u8")
    }
}
