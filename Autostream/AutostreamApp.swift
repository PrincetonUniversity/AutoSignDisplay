// Autostream.swift
import SwiftUI

@main
struct Autostream: App {
    init() {
        AppConfig.applyConfiguration()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
