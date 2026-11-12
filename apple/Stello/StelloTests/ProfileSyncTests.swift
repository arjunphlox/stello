import Testing
@testable import Stello

/// Which way each profile field goes in a sync cycle (server rule: src/lib/profile.js).
@Suite("Profile sync direction")
struct ProfileSyncTests {
    @Test func newerSideWins() {
        #expect(ProfileSync.decide(local: 200, server: 100, localEmpty: false, serverEmpty: false) == .push)
        #expect(ProfileSync.decide(local: 100, server: 200, localEmpty: false, serverEmpty: false) == .pull)
    }

    @Test func newerEmptyValueStillWins() {
        // Cleared on the web after the Mac set it: the Mac clears too.
        #expect(ProfileSync.decide(local: 100, server: 200, localEmpty: false, serverEmpty: true) == .pull)
        // Photo removed on the Mac: the web loses it too.
        #expect(ProfileSync.decide(local: 300, server: 200, localEmpty: true, serverEmpty: false) == .push)
    }

    @Test func tieFillsOnlyAnEmptySide() {
        #expect(ProfileSync.decide(local: 0, server: 0, localEmpty: true, serverEmpty: false) == .pull)
        #expect(ProfileSync.decide(local: 0, server: 0, localEmpty: false, serverEmpty: true) == .none)
        #expect(ProfileSync.decide(local: 5, server: 5, localEmpty: false, serverEmpty: false) == .none)
    }

    @Test func seededMacProfileBeatsPreClockWebProfile() {
        // A Mac profile from before syncing is seeded at clock 1; web values saved by
        // the first web build have clock 0.
        #expect(ProfileSync.decide(local: 1, server: 0, localEmpty: false, serverEmpty: false) == .push)
    }
}
