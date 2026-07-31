//
//  PlaybackRecoveryTests.swift
//  AutoSignDisplayTests
//
//  Rules for when an unattended display rebuilds its player.
//
//  Background. Auto Resume used to trigger on `player?.currentItem == nil`, and that
//  condition is unreachable in practice: AVPlayer does not nil `currentItem` when a
//  stream fails — a failed item stays put with `status == .failed`, and a frozen one
//  just stops advancing. The only code that nils the player is `stopPlayback()`, which
//  also stops the retry timer. So the feature recovered from nothing.
//
//  That matters because these displays play Kaltura HLS reached through a redirect,
//  and the variant playlists Kaltura hands back are CloudFront-signed with a 24-hour
//  expiry. A display left running goes black at the 24-hour mark and, before this,
//  stayed black until somebody power-cycled it.
//
//  The rules live in a pure function precisely so they can be tested. Driving a real
//  AVPlayer into an expired signature or a frozen origin is not something a unit test
//  can arrange; every input that decides the outcome is a plain value.
//

import Foundation
import Testing
@testable import AutoSignDisplay

struct PlaybackRecoveryTests {

    /// Healthy live playback: an item, not paused, time moving.
    private func healthy(secondsSinceProgress: TimeInterval = 0) -> PlaybackSnapshot {
        PlaybackSnapshot(hasPlayer: true, hasItem: true, itemFailed: false,
                         isPaused: false, secondsSinceProgress: secondsSinceProgress)
    }

    private func decide(_ snapshot: PlaybackSnapshot,
                        autoResume: Bool = true,
                        stoppedByUser: Bool = false,
                        stallThreshold: TimeInterval = 15) -> PlaybackRecovery {
        StreamViewModel.recoveryDecision(for: snapshot,
                                         autoResume: autoResume,
                                         stoppedByUser: stoppedByUser,
                                         stallThreshold: stallThreshold)
    }

    // MARK: - The failure that motivated all of this

    @Test func aFrozenStreamIsRecovered() {
        // The 24-hour signature expiry looks exactly like this: an item still present,
        // still nominally playing, but time no longer advancing.
        let decision = decide(healthy(secondsSinceProgress: 15))
        guard case .reload(let reason) = decision else {
            Issue.record("A stream frozen past the threshold must be rebuilt, got \(decision)")
            return
        }
        #expect(reason.contains("stalled"))
    }

    @Test func aFailedItemIsRecoveredWithoutWaitingForTheStallThreshold() {
        // A 403 on a segment can mark the item failed outright. No reason to sit
        // through the stall window when the player has already given up.
        var snapshot = healthy()
        snapshot.itemFailed = true
        #expect(decide(snapshot) == .reload(reason: "player item failed"))
    }

    @Test func aMissingItemIsRecovered() {
        var snapshot = healthy()
        snapshot.hasItem = false
        #expect(decide(snapshot) == .reload(reason: "no player item"))
    }

    @Test func aMissingPlayerIsRecovered() {
        let snapshot = PlaybackSnapshot(hasPlayer: false, hasItem: false, itemFailed: false,
                                        isPaused: true, secondsSinceProgress: 0)
        // Note this outranks the isPaused check: a snapshot with no player reports
        // paused, and it still has to be repaired.
        #expect(decide(snapshot) == .reload(reason: "no player"))
    }

    // MARK: - What must NOT be disturbed

    @Test func healthyPlaybackIsLeftAlone() {
        #expect(decide(healthy()) == .leaveAlone)
    }

    @Test func anOrdinaryRebufferIsNotTreatedAsAFailure() {
        // Live streams stall for a few seconds routinely. Rebuilding on every hiccup
        // would make the display worse, not better — so anything short of the
        // threshold is ignored, including the instant just before it.
        #expect(decide(healthy(secondsSinceProgress: 0)) == .leaveAlone)
        #expect(decide(healthy(secondsSinceProgress: 14.9)) == .leaveAlone)
    }

    @Test func aDeliberatelyPausedPlayerIsNotAStalledOne() {
        // A player can legitimately exist and be paused: startStreamIfNeeded() creates
        // one without playing when PlayOnAppOpen is off. Its clock is not advancing,
        // and that is not a fault.
        var snapshot = healthy(secondsSinceProgress: 3600)
        snapshot.isPaused = true
        #expect(decide(snapshot) == .leaveAlone)
    }

    @Test func anExplicitStopIsNeverUndone() {
        // Pressing Stop Stream leaves the main screen with no player. The watchdog
        // treats a missing player as a fault, so without this the display would
        // resurrect the stream the user just ended.
        let stopped = PlaybackSnapshot(hasPlayer: false, hasItem: false, itemFailed: false,
                                       isPaused: true, secondsSinceProgress: 0)
        #expect(decide(stopped, stoppedByUser: true) == .leaveAlone)

        // And it outranks every other fault, not just the missing player.
        var failed = healthy(secondsSinceProgress: 600)
        failed.itemFailed = true
        #expect(decide(failed, stoppedByUser: true) == .leaveAlone)
    }

    @Test func autoResumeOffDisablesEveryRepair() {
        // The setting means what it says: a site that wants a frozen display rather
        // than an unexpected reconnection gets one.
        var failed = healthy(secondsSinceProgress: 600)
        failed.itemFailed = true
        #expect(decide(failed, autoResume: false) == .leaveAlone)
        #expect(decide(healthy(secondsSinceProgress: 600), autoResume: false) == .leaveAlone)

        let noPlayer = PlaybackSnapshot(hasPlayer: false, hasItem: false, itemFailed: false,
                                        isPaused: true, secondsSinceProgress: 0)
        #expect(decide(noPlayer, autoResume: false) == .leaveAlone)
    }

    // MARK: - Threshold derivation

    @Test func theStallThresholdScalesWithRetryTimeoutButNeverGoesBelowFifteenSeconds() async {
        let vm = await MainActor.run { StreamViewModel(logger: SilentLogger()) }
        defer { vm.stopRetryTimer() }

        // Floor: three intervals of the 5s default is 15s, and the six values the UI
        // offers below that must not produce a hair-trigger.
        for timeout in [3.0, 5.0] {
            await MainActor.run { vm.retryTimeout = timeout }
            #expect(vm.stallThreshold == 15)
        }

        // Above the floor it tracks the timeout, so a site that deliberately chose a
        // slow retry gets a proportionally patient watchdog.
        await MainActor.run { vm.retryTimeout = 30 }
        #expect(vm.stallThreshold == 90)
    }

    @Test func theThresholdIsInclusiveAtItsBoundary() {
        // Guards an off-by-one that would leave a display frozen forever if the
        // sampled interval landed exactly on the threshold.
        #expect(decide(healthy(secondsSinceProgress: 15), stallThreshold: 15)
                == .reload(reason: "stalled for 15s"))
    }

    private struct SilentLogger: Logger {
        func log(_ message: String) {}
    }
}
