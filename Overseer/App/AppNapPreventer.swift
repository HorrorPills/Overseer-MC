//
//  AppNapPreventer.swift
//  Overseer
//
//  Keeps this process exempt from App Nap for its entire lifetime.
//
//  Overseer is meant to run unattended for days at a stretch,
//  continuously polling GS4/SLP/RCON on background Tasks. Without this,
//  macOS App Nap throttles those Tasks hard once the main window goes
//  unfocused/occluded for a while — minimized, covered by another
//  window, or just not the frontmost app on an always-on Mac — coalescing
//  the poll loop's timers into rare, unpredictable wakeups instead of
//  firing on `pollInterval`. That's exactly the "stopped refreshing for
//  10 hours overnight" symptom this exists to fix.
//
//  `.userInitiatedAllowingIdleSystemSleep` opts the process out of App
//  Nap specifically, without forcing the Mac itself to stay awake — if
//  the machine actually goes to sleep (lid closed, Energy Saver), that
//  still happens normally and polling correctly pauses/resumes around
//  it instead of fighting the user's power settings.
//

import Foundation

enum AppNapPreventer {
    /// Retained for the process's entire lifetime — releasing this
    /// token is what would re-enable App Nap, so it must never be
    /// allowed to deallocate. `begin()` is only ever called once, from
    /// the app's `init()` before any concurrent work starts, so the
    /// unguarded write here is safe despite not being actor-isolated.
    nonisolated(unsafe) private static var activityToken: NSObjectProtocol?

    static func begin() {
        guard activityToken == nil else { return }
        activityToken = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep],
            reason: "Continuous server polling (GS4/SLP/RCON)"
        )
    }
}
