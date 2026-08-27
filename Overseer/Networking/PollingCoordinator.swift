//
//  PollingCoordinator.swift
//  Overseer
//
//  Bridges the pure-networking `ServerQueryEngine` actor to SwiftData.
//  Owns the recurring poll timer (with exponential backoff while the
//  server is unreachable), writes each `ServerSnapshot`, and runs the
//  session-boundary diff described in PlayerSession.swift.
//
//  Runs on @MainActor because SwiftData's `ModelContext` is not
//  Sendable across threads; the actual network I/O still happens off
//  the main actor inside `ServerQueryEngine`, which we only ever
//  `await` here.
//

import Foundation
import SwiftData
import Observation
import AppKit

@MainActor
@Observable
final class PollingCoordinator {
    private(set) var isPolling = false
    private(set) var lastResult: ServerQueryEngine.PollResult?
    private(set) var consecutiveFailures = 0

    private let engine: ServerQueryEngine
    private let modelContext: ModelContext
    private var pollInterval: TimeInterval
    private var pollTask: Task<Void, Never>?
    private var wakeObserver: NSObjectProtocol?

    /// Optional RCON automation coordinator. When set, session closes
    /// feed it playtime-milestone checks and each saved snapshot feeds
    /// it a fresh traffic-velocity reading for the ad-window/Happy Hour
    /// triggers. Left nil (e.g. in tests) this class behaves exactly as
    /// it did before the RCON extension existed.
    var automation: RCONAutomationCoordinator?

    /// Backoff never waits longer than this between retries while the
    /// server stays unreachable.
    private let maxBackoffInterval: TimeInterval = 300

    init(modelContext: ModelContext, engine: ServerQueryEngine = ServerQueryEngine(), pollInterval: TimeInterval = 30) {
        self.modelContext = modelContext
        self.engine = engine
        self.pollInterval = pollInterval
    }

    func updatePollInterval(_ interval: TimeInterval) {
        pollInterval = interval
    }

    func updateTarget(host: String, fallbackHost: String?, port: UInt16, timeout: TimeInterval = 5) {
        Task {
            await engine.updateConfiguration(
                .init(host: host, fallbackHost: fallbackHost, port: port, timeout: timeout)
            )
        }
    }

    func start() {
        guard pollTask == nil else { return }
        isPolling = true
        pollTask = Task { [weak self] in
            await self?.runLoop()
        }
        observeSystemWake()
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        isPolling = false
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
    }

    /// Real system sleep (lid closed, Energy Saver) — as opposed to App
    /// Nap, see AppNapPreventer — suspends the poll loop for however
    /// long the Mac was actually asleep. `Task.sleep` correctly resumes
    /// on wake rather than firing early, but that means the dashboard
    /// could sit on a stale reading for up to one more `pollInterval`
    /// after wake before the loop naturally comes back around. Polling
    /// immediately on wake instead closes that gap.
    private func observeSystemWake() {
        guard wakeObserver == nil else { return }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.pollNow()
            }
        }
    }

    /// Triggers a single out-of-band poll immediately (e.g. a manual
    /// "Refresh Now" button) without disturbing the recurring timer.
    func pollNow() async {
        let result = await engine.poll()
        handle(result)
    }

    private func runLoop() async {
        while !Task.isCancelled {
            let result = await engine.poll()
            handle(result)
            let delay = nextDelay(after: result)
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
    }

    private func nextDelay(after result: ServerQueryEngine.PollResult) -> TimeInterval {
        if result.isOnline {
            consecutiveFailures = 0
            return pollInterval
        }
        consecutiveFailures += 1
        // Exponential backoff: pollInterval * 2^failures, capped.
        let backoff = pollInterval * pow(2, Double(consecutiveFailures))
        return min(backoff, maxBackoffInterval)
    }

    // MARK: - Persistence

    private func handle(_ result: ServerQueryEngine.PollResult) {
        lastResult = result

        let snapshot = ServerSnapshot(
            timestamp: result.timestamp,
            playerCount: onlinePlayerNames(from: result).count,
            pingMs: result.pingMs ?? -1,
            maxPlayers: result.fullStat?.maxPlayers ?? result.slpStatus?.players.max ?? 0,
            mapName: result.fullStat?.mapName ?? "",
            isOnline: result.isOnline
        )
        modelContext.insert(snapshot)

        if result.isOnline {
            PlayerRosterSync.apply(
                onlineNames: onlinePlayerNames(from: result),
                at: result.timestamp,
                modelContext: modelContext,
                automation: automation
            )
        }

        try? modelContext.save()

        if let automation, result.isOnline {
            let velocity15 = AnalyticsEngine.velocity(snapshots: recentSnapshotsForVelocity(), windowMinutes: 15)
            automation.evaluateTriggers(velocityPerMinute15: velocity15, now: result.timestamp)
        }
    }

    /// Ascending-by-timestamp window of recent snapshots, sized to
    /// comfortably cover the longest velocity window AnalyticsEngine
    /// computes (60 minutes) even at the fastest supported poll rate.
    private func recentSnapshotsForVelocity() -> [ServerSnapshot] {
        var descriptor = FetchDescriptor<ServerSnapshot>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        descriptor.fetchLimit = 400
        let recent = (try? modelContext.fetch(descriptor)) ?? []
        return recent.sorted { $0.timestamp < $1.timestamp }
    }

    /// GS4's full stat gives an authoritative, un-sampled roster; SLP's
    /// `sample` array is a fallback (some servers cap or omit it) used
    /// only when GS4 querying is unavailable.
    private func onlinePlayerNames(from result: ServerQueryEngine.PollResult) -> Set<String> {
        if let players = result.fullStat?.players {
            return Set(players)
        }
        if let sample = result.slpStatus?.players.sample {
            return Set(sample.map(\.name))
        }
        return []
    }
}
