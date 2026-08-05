//
//  ManagedConfigurationWatcher.swift
//  AutoSignDisplay
//
//  Makes the MDM payload declarative: the app reconciles to it while running, rather
//  than reading it once in App.init() and needing a restart to notice a change.
//

import Foundation

/// Watches `com.apple.configuration.managed` and reports when it actually changes.
///
/// The gating is the whole design. `UserDefaults.didChangeNotification` fires for
/// *every* defaults write, and `StreamViewModel` writes on nearly every mutation — so
/// reacting to the notification directly would mean the app's own writes trigger a
/// reconcile, which writes again, without bound. Comparing the managed dictionary
/// against the last applied one breaks that loop: an app-owned key changing is
/// invisible here.
final class ManagedConfigurationWatcher {

    /// Coalescing window. A single Jamf push can write the dictionary more than once,
    /// and reconciling twice would visibly switch the channel twice.
    static let defaultDebounce: TimeInterval = 1.5

    /// True when the payload differs in a way worth acting on.
    ///
    /// Pure and static so the rule is testable without a UserDefaults or a clock.
    /// Handles all four transitions: absent to present, present to changed, present to
    /// absent, and identical (the common case, when MDM re-pushes an unchanged payload).
    static func needsReconcile(previous: [String: Any]?, current: [String: Any]?) -> Bool {
        switch (previous, current) {
        case (nil, nil):
            return false
        case (nil, _), (_, nil):
            return true
        case let (previous?, current?):
            // NSDictionary equality is deep, which is what is wanted: a changed nested
            // ChannelPresets array has to count as a change.
            return !(previous as NSDictionary).isEqual(to: current)
        }
    }

    private let defaults: UserDefaults
    private let debounce: TimeInterval
    private let onReconcile: () -> Void
    private let logger: Logger

    private var lastApplied: [String: Any]?
    private var observer: NSObjectProtocol?
    private var pendingWork: DispatchWorkItem?

    init(defaults: UserDefaults = .standard,
         debounce: TimeInterval = ManagedConfigurationWatcher.defaultDebounce,
         logger: Logger = PrintLogger(),
         onReconcile: @escaping () -> Void) {
        self.defaults = defaults
        self.debounce = debounce
        self.logger = logger
        self.onReconcile = onReconcile
        // Seed from what is already applied: the app has just read this payload during
        // launch, so it must not immediately reconcile against it.
        self.lastApplied = defaults.dictionary(forKey: AppConfigKeys.managedConfiguration)
    }

    deinit {
        stop()
    }

    func start() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: defaults,
            queue: nil
        ) { [weak self] _ in
            // The notification can arrive on any thread; everything downstream touches
            // published state, so hop to main before looking at anything.
            DispatchQueue.main.async { self?.payloadMayHaveChanged() }
        }
        logger.log("Watching managed configuration for changes (debounce \(debounce)s)")
    }

    func stop() {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
        observer = nil
        pendingWork?.cancel()
        pendingWork = nil
    }

    /// Re-checks the payload through the normal debounced path.
    ///
    /// Called from the playback watchdog's existing tick, which makes the notification
    /// an optimisation rather than a dependency. That matters because
    /// `UserDefaults.didChangeNotification` firing for a *externally* written payload is
    /// not something this project has been able to verify — and an unattended display
    /// never backgrounds, so the foreground fallback would rarely fire either. A
    /// dictionary comparison every few seconds is cheap insurance against the whole
    /// feature silently not working in the field.
    func poll() {
        payloadMayHaveChanged()
    }

    /// Checks the payload now, bypassing the debounce. Used on foreground, where a
    /// change may have landed while the app was suspended and no notification arrived.
    func checkNow() {
        pendingWork?.cancel()
        pendingWork = nil
        reconcileIfChanged()
    }

    private func payloadMayHaveChanged() {
        let current = defaults.dictionary(forKey: AppConfigKeys.managedConfiguration)
        // Cheap comparison first, so the app's own writes cost nothing beyond this.
        guard Self.needsReconcile(previous: lastApplied, current: current) else { return }

        pendingWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.reconcileIfChanged() }
        pendingWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + debounce, execute: work)
    }

    private func reconcileIfChanged() {
        let current = defaults.dictionary(forKey: AppConfigKeys.managedConfiguration)
        guard Self.needsReconcile(previous: lastApplied, current: current) else { return }

        logger.log("Managed configuration changed — reconciling"
                   + (current == nil ? " (payload removed)" : " (\(current?.count ?? 0) keys)"))
        lastApplied = current
        onReconcile()
    }
}
