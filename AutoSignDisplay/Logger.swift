//
//  Logger.swift
//  AutoSignDisplay
//
//  Small, shared logger protocol and default implementation used across the app
//  so logging can be injected in tests.
//

import Foundation
import os

protocol Logger {
    func log(_ message: String)
    /// Verbose, high-frequency detail. Captured only when the unified log is streamed
    /// at debug level, so it costs nothing in normal operation:
    ///   log stream --level debug --predicate 'subsystem == "edu.princeton.autosigndisplay"'
    func debug(_ message: String)
}

extension Logger {
    // Default no-op so test loggers need not care.
    func debug(_ message: String) {}
}

/// Writes to the unified log rather than stdout.
///
/// `print()` goes to the process's stdout, which is reachable only when something is
/// attached to it — so it is invisible on a deployed Apple TV, and unreliable even
/// under `simctl launch --console-pty`. An unattended kiosk that cannot be asked what
/// went wrong is the whole problem this app has to avoid.
///
/// Retrieve with:
///   xcrun simctl spawn <udid> log stream --predicate 'subsystem == "edu.princeton.autosigndisplay"'
///   log show --last 30m --predicate 'subsystem == "edu.princeton.autosigndisplay"'   (on device)
struct PrintLogger: Logger {
    private static let osLog = os.Logger(
        subsystem: "edu.princeton.autosigndisplay",
        category: "playback"
    )

    func log(_ message: String) {
        // `privacy: .public` is required: os_log redacts interpolated strings by
        // default, which would reduce every one of these to "<private>".
        Self.osLog.notice("\(message, privacy: .public)")
    }

    func debug(_ message: String) {
        Self.osLog.debug("\(message, privacy: .public)")
    }
}
