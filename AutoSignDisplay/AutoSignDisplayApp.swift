// AutoSignDisplay.swift
import SwiftUI

@main
struct AutoSignDisplay: App {
    init() {
        AppConfig.applyConfiguration()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
