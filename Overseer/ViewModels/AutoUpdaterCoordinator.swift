//
//  AutoUpdaterCoordinator.swift
//  Overseer
//
//  Checks Mojang's real version manifest on a schedule; when the
//  currently-running server (per Server List Ping — see
//  DashboardViewModel.serverVersion) is behind the latest snapshot,
//  downloads that snapshot's server.jar, uploads it over SFTP, deletes
//  the old server.jar, and stops the server via RCON. It does NOT ever
//  attempt to start the server back up — that's deliberately left to
//  Rafal's hosting-panel cron job, which polls for the process being
//  offline and restarts it. This coordinator's job ends at `/stop`.
//
//  This is a fully-automatic, no-backup, no-approval pipeline against a
//  live production server, at Rafal's explicit and informed request
//  (he considered — and turned down — a staged/manual-confirm
//  alternative). Two things below exist purely for engineering
//  correctness, not as a reintroduction of the safety net he declined:
//
//   1. Size-verified download — the downloaded byte count is checked
//      against the size Mojang's manifest itself reports before
//      anything is uploaded. A truncated/corrupt download must never
//      reach the server.
//   2. Upload-to-temp-then-swap — the new jar is written to
//      `server.jar.new` first and only swapped over the old one (via
//      SFTP `remove` + `rename`) after the FULL upload has succeeded.
//      A connection drop mid-upload can never leave the server with no
//      jar at all — it just leaves `server.jar.new` to be cleaned up
//      (or picked up again) next cycle, while `server.jar` is
//      untouched. This is not backup retention (the old jar is still
//      deleted, per spec, the moment the new one is confirmed fully
//      written) — it's just ordering the two unavoidable filesystem
//      operations so a mid-transfer failure can't strand the server
//      with neither file.
//
//  Deploy/offline-restart race: once a deploy completes, the server
//  goes offline for its own restart cycle (up to Self.deployTimeout).
//  During that window `serverVersion` briefly reads nil/stale — without
//  guarding against it, the next check could easily misread "offline"
//  as "still needs updating" and fire a second, redundant deploy while
//  the first is still landing. `pendingDeployVersion` blocks new deploy
//  attempts until either the server confirms it's back on the version
//  just shipped, or the timeout elapses (logged, not retried blindly).
//

import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class AutoUpdaterCoordinator {
    struct UpdateLogEntry: Identifiable {
        let id = UUID()
        var timestamp: Date
        var text: String
        var isError: Bool
    }

    private(set) var isChecking = false
    private(set) var lastCheckedAt: Date?
    private(set) var lastKnownLatestVersion: String?
    private(set) var updateLog: [UpdateLogEntry] = []
    private(set) var pendingDeployVersion: String?

    var enabled = false
    var checkIntervalMinutes: Double = 10
    var host = ""
    var port = 22
    var username = ""
    var password = ""

    /// How long to wait for the server to come back reporting the
    /// deployed version before giving up on tracking that specific
    /// deploy and allowing the next cycle to evaluate fresh. A vanilla
    /// restart is normally well under a minute; 30 minutes is a
    /// deliberately generous ceiling for a slow world-save/host cron.
    private static let deployTimeout: TimeInterval = 30 * 60
    private static let logCap = 200

    private var checkTask: Task<Void, Never>?
    private var pendingDeployStartedAt: Date?
    private let sftp = MCSFTPClient()
    private let rconCoordinator: RCONAutomationCoordinator
    private let modelContext: ModelContext
    private let currentServerVersion: () -> String?

    init(rconCoordinator: RCONAutomationCoordinator, modelContext: ModelContext, currentServerVersion: @escaping () -> String?) {
        self.rconCoordinator = rconCoordinator
        self.modelContext = modelContext
        self.currentServerVersion = currentServerVersion
    }

    // MARK: - Scheduler

    func startChecking() {
        guard checkTask == nil else { return }
        checkTask = Task { [weak self] in
            await self?.checkLoop()
        }
    }

    func stopChecking() {
        checkTask?.cancel()
        checkTask = nil
    }

    private func checkLoop() async {
        while !Task.isCancelled {
            if enabled { await checkForUpdate() }
            let interval = max(checkIntervalMinutes, 1) * 60
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
        }
    }

    // MARK: - Check

    @discardableResult
    func checkForUpdate() async -> Bool {
        guard !isChecking else { return false }
        isChecking = true
        defer { isChecking = false }
        lastCheckedAt = .now

        // A deploy is already in flight — only ever check whether it's
        // landed (or timed out), never start a second one on top of it.
        if let pendingVersion = pendingDeployVersion, let startedAt = pendingDeployStartedAt {
            if let running = currentServerVersion(), Self.versionsMatch(running, pendingVersion) {
                log("✅ Confirmed running \(pendingVersion).")
                pendingDeployVersion = nil
                pendingDeployStartedAt = nil
            } else if Date.now.timeIntervalSince(startedAt) > Self.deployTimeout {
                log("⚠️ \(pendingVersion) was deployed \(Int(Self.deployTimeout / 60)) min ago and the server hasn't confirmed running it yet — resuming normal checks.", isError: true)
                pendingDeployVersion = nil
                pendingDeployStartedAt = nil
            }
            return true
        }

        do {
            let manifest = try await VersionManifestService.shared.fetchManifest()
            let latest = manifest.latest.snapshot
            lastKnownLatestVersion = latest

            guard let running = currentServerVersion(), !running.isEmpty else {
                log("Server version unknown (offline or not yet polled) — skipping this check.")
                return false
            }
            guard !Self.versionsMatch(running, latest) else {
                log("✅ Up to date — running \(running), latest is \(latest).")
                return true
            }

            guard let entry = manifest.versions.first(where: { $0.id == latest }) else {
                log("❌ \(latest) is Mojang's reported latest snapshot but isn't in the version list — skipping.", isError: true)
                return false
            }

            log("🆕 New snapshot detected: \(latest) (currently running \(running)). Starting deploy…")
            try await deploy(versionID: latest, detailURL: entry.url)
            return true
        } catch {
            log("❌ Update check failed: \(error.localizedDescription)", isError: true)
            return false
        }
    }

    /// Mojang's manifest reports version IDs like "26.3-snapshot-9", but
    /// this server's Server List Ping reports the same version in
    /// human-readable form — "26.3 Snapshot 9" — confirmed live: a plain
    /// `==` comparison between the two never matches even when they're
    /// the same build, which caused a real incident (2026-08-18): every
    /// check cycle treated an up-to-date server as needing an update and
    /// redeployed/stopped it. Normalizing both sides to a lowercase,
    /// punctuation-collapsed form before comparing fixes that without
    /// depending on either side's exact separator/casing convention.
    private static func versionsMatch(_ a: String, _ b: String) -> Bool {
        normalizeVersionString(a) == normalizeVersionString(b)
    }

    private static func normalizeVersionString(_ raw: String) -> String {
        let normalized = raw.lowercased().replacingOccurrences(
            of: "[^a-z0-9]+",
            with: "-",
            options: .regularExpression
        )
        return normalized.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    // MARK: - Deploy

    private static let remoteJarPath = "/server.jar"
    private static let remoteStagingPath = "/server.jar.new"

    private func deploy(versionID: String, detailURL: String) async throws {
        let runningVersion = currentServerVersion() ?? "unknown"

        let detail = try await VersionManifestService.shared.fetchVersionDetail(url: detailURL)
        guard let server = detail.downloads.server else {
            let message = "\(versionID) has no server.jar download listed — aborting."
            log("❌ \(message)", isError: true)
            recordEvent(from: runningVersion, to: versionID, succeeded: false, detail: message)
            return
        }

        log("⬇️ Downloading \(versionID) server.jar (\(server.size / 1_000_000) MB)…")
        let jarData = try await VersionManifestService.shared.downloadServerJar(from: server.url)
        guard jarData.count == server.size else {
            let message = "Downloaded \(jarData.count) bytes but Mojang's manifest says \(server.size) — aborted, server.jar left untouched."
            log("❌ \(message)", isError: true)
            recordEvent(from: runningVersion, to: versionID, succeeded: false, detail: message)
            return
        }

        guard !host.isEmpty, !username.isEmpty else {
            let message = "SFTP not configured — set host/username in Settings. Deploy aborted, server.jar left untouched."
            log("❌ \(message)", isError: true)
            recordEvent(from: runningVersion, to: versionID, succeeded: false, detail: message)
            return
        }

        do {
            try await sftp.connect(host: host, port: port, username: username, password: password)
        } catch {
            let message = "SFTP connection failed: \(error.localizedDescription). Deploy aborted, server.jar left untouched."
            log("❌ \(message)", isError: true)
            recordEvent(from: runningVersion, to: versionID, succeeded: false, detail: message)
            return
        }
        defer { Task { await self.sftp.disconnect() } }

        do {
            log("⬆️ Uploading \(versionID) server.jar over SFTP…")
            try await sftp.uploadFile(jarData, atPath: Self.remoteStagingPath)

            log("🔁 Swapping in the new server.jar…")
            try await sftp.deleteFile(atPath: Self.remoteJarPath)
            try await sftp.renameFile(atPath: Self.remoteStagingPath, to: Self.remoteJarPath)
        } catch {
            let message = "Upload/swap failed: \(error.localizedDescription)."
            log("❌ \(message)", isError: true)
            recordEvent(from: runningVersion, to: versionID, succeeded: false, detail: message)
            return
        }

        pendingDeployVersion = versionID
        pendingDeployStartedAt = .now
        recordEvent(from: runningVersion, to: versionID, succeeded: true)

        log("🛑 Stopping the server via RCON so the hosting panel's restart cron can bring it back up on \(versionID)…")
        await rconCoordinator.sendConsoleCommand(VanillaCommands.stopServer)
        log("✅ \(versionID) deployed. Waiting for the server to come back before checking again.")
    }

    /// Durable counterpart to `log()` — the in-memory `updateLog` above
    /// resets every relaunch, which is fine for a live console but not
    /// for "what versions has this server actually run, and when" — the
    /// kind of question Server History's event timeline exists to
    /// answer (see ServerEventTimeline).
    private func recordEvent(from: String, to: String, succeeded: Bool, detail: String = "") {
        modelContext.insert(ServerUpdateEvent(fromVersion: from, toVersion: to, succeeded: succeeded, detail: detail))
        try? modelContext.save()
    }

    // MARK: - Log

    private func log(_ text: String, isError: Bool = false) {
        updateLog.append(UpdateLogEntry(timestamp: .now, text: text, isError: isError))
        if updateLog.count > Self.logCap {
            updateLog.removeFirst(updateLog.count - Self.logCap)
        }
    }
}
