//
//  Logger.swift
//  Autostream
//
//  Small, shared logger protocol and default implementation used across the app
//  so logging can be injected in tests.
//

import Foundation

protocol Logger {
    func log(_ message: String)
}

struct PrintLogger: Logger {
    func log(_ message: String) { print(message) }
}
