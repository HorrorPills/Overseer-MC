//
//  SFTPSyncCoordinator.swift
//  Overseer
//
//  Owns the SFTP scheduler and mirrors specific remote paths locally,
//  then runs the SAME parse/persist logic the manual "Select Folder…"
//  importers already use:
//
//   - Location and Playtime are meant to stay continuously correct, so
//     their sync methods parse and apply results directly.
//   - Inventory Analyzer and Performance are "browse a snapshot for
//     investigation" tools, not continuously-applied state, so their
//     sync methods just mirror files to local disk (Application
//     Support) and leave the existing views to load from that mirror
//     via a "Synced Copy"/"Synced Reports" option, alongside — never
//     replacing — manual folder-import.
//
//  Every sync pass opens one SFTP connection (see MCSFTPClient) and
//  closes it when done, rather than keeping one alive between cycles.
//

import Foundation
import SwiftData
import Observation

@MainActor
@Observable
final class SFTPSyncCoordinator {
    struct SyncLogEntry: Identifiable {
        let id = UUID()
        var timestamp: Date
        var text: String
        var isError: Bool
    }

    private(set) var isSyncing = false
    private(set) var lastSyncDate: Date?
    private(set) var syncLog: [SyncLogEntry] = []

    var host = ""
    var port = 22
    var username = ""
    var password = ""
    var syncIntervalMinutes: Double = 15
    var syncLocationEnabled = true
    var syncPlaytimeEnabled = true
    var syncInventoryEnabled = true
    var syncPerformanceEnabled = true
    var syncWorldMapEnabled = true

    /// Whether the one-time full-history `logs.zip` backfill has run —
    /// after that, ongoing sync only pulls `latest.log`, not the whole
    /// (large, ever-growing) rotated-log history every cycle. Mirrored
    /// back out to AppSettings via `onBackfillCompletedChange`, the same
    /// settings/coordinator split used throughout the app (see
    /// EntityManagementView's onChange wiring for precedent).
    var logsBackfillCompleted = false
    var onBackfillCompletedChange: ((Bool) -> Void)?

    private var syncTask: Task<Void, Never>?
    private let client = MCSFTPClient()
    private let modelContext: ModelContext
    private let mirrorRoot: URL
    private static let logCap = 200

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        self.mirrorRoot = base.appendingPathComponent("Overseer/SFTPMirror", isDirectory: true)
        try? FileManager.default.createDirectory(at: mirrorRoot, withIntermediateDirectories: true)
    }

    // MARK: - Mirror directories (read by PerformanceView's synced-report picker, Inventory's synced-copy button)

    var performanceMirrorDirectory: URL { mirrorRoot.appendingPathComponent("Performance", isDirectory: true) }
    var inventoryMirrorDirectory: URL { mirrorRoot.appendingPathComponent("Inventory", isDirectory: true) }
    var worldMapMirrorDirectory: URL { mirrorRoot.appendingPathComponent("WorldMap", isDirectory: true) }

    // MARK: - Scheduler

    func startScheduler() {
        guard syncTask == nil else { return }
        syncTask = Task { [weak self] in
            await self?.schedulerLoop()
        }
    }

    func stopScheduler() {
        syncTask?.cancel()
        syncTask = nil
    }

    private func schedulerLoop() async {
        while !Task.isCancelled {
            await syncNow()
            let interval = max(syncIntervalMinutes, 1) * 60
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
        }
    }

    // MARK: - Sync

    @discardableResult
    func syncNow() async -> Bool {
        guard !isSyncing else { return false }
        guard !host.isEmpty, !username.isEmpty else {
            log("❌ SFTP not configured — set host/username in Settings.", isError: true)
            return false
        }
        isSyncing = true

        do {
            try await client.connect(host: host, port: port, username: username, password: password)
        } catch {
            log("❌ Connection failed: \(error.localizedDescription)", isError: true)
            isSyncing = false
            return false
        }

        var succeededAny = false
        if syncLocationEnabled { succeededAny = await syncLocationLogs() || succeededAny }
        if syncPlaytimeEnabled { succeededAny = await syncPlaytime() || succeededAny }
        if syncInventoryEnabled { succeededAny = await syncInventory() || succeededAny }
        if syncPerformanceEnabled { succeededAny = await syncPerformance() || succeededAny }
        if syncWorldMapEnabled { succeededAny = await syncWorldMap() || succeededAny }

        await client.disconnect()
        lastSyncDate = .now
        isSyncing = false
        return succeededAny
    }

    // MARK: - Location (logs/)

    private func syncLocationLogs() async -> Bool {
        do {
            if !logsBackfillCompleted {
                log("📥 Backfilling full log history from logs.zip…")
                let zipData = try await client.downloadFile(atPath: "/logs.zip")
                let entries = try ZipReader.extractAll(from: zipData)
                var backfillRecords: [LogJoinRecord] = []
                for (path, fileData) in entries {
                    let filename = (path as NSString).lastPathComponent
                    guard filename.hasSuffix(".log") || filename.hasSuffix(".log.gz") else { continue }
                    backfillRecords.append(contentsOf: ServerLogFolderScanner.scan(entries: [LogFileEntry(filename: filename, data: fileData)]))
                }
                let inserted = PlayerLoginRecordStore.persist(backfillRecords, modelContext: modelContext)
                logsBackfillCompleted = true
                onBackfillCompletedChange?(true)
                log("✅ Backfilled \(inserted) historical join record\(inserted == 1 ? "" : "s") from logs.zip.")
            }

            let latestData = try await client.downloadFile(atPath: "/logs/latest.log")
            let records = ServerLogFolderScanner.scan(entries: [LogFileEntry(filename: "latest.log", data: latestData)])
            let inserted = PlayerLoginRecordStore.persist(records, modelContext: modelContext)
            log("🌍 Location: \(inserted) new join record\(inserted == 1 ? "" : "s") from latest.log.")
            return true
        } catch {
            log("❌ Location sync failed: \(error.localizedDescription)", isError: true)
            return false
        }
    }

    // MARK: - Playtime (world/players/stats)

    private func syncPlaytime() async -> Bool {
        do {
            let files = try await client.listDirectory(atPath: "/world/players/stats")
            var entries: [PlayerStatsScanEntry] = []
            for file in files where !file.isDirectory && file.name.hasSuffix(".json") {
                let data = try await client.downloadFile(atPath: "/world/players/stats/\(file.name)")
                let uuid = (file.name as NSString).deletingPathExtension
                entries.append(PlayerStatsScanEntry(uuid: uuid, data: data, fileURL: URL(fileURLWithPath: file.name)))
            }
            let result = PlayerStatsFolderScanner.scan(entries: entries)
            let updated = applyPlaytime(result.stats)
            log("⏱️ Playtime: synced \(entries.count) stats file\(entries.count == 1 ? "" : "s"), updated \(updated) player\(updated == 1 ? "" : "s").")
            return true
        } catch {
            log("❌ Playtime sync failed: \(error.localizedDescription)", isError: true)
            return false
        }
    }

    /// Same ≥60s-difference threshold PlaytimeImporterView's manual
    /// "Apply All Updates" uses. Unlike the manual importer, this never
    /// creates a new `Player` row for an unfamiliar UUID — that's
    /// PlayerRosterSync's job, driven by an actual observed join, not
    /// something to guess at from a stats file alone.
    private func applyPlaytime(_ stats: [ParsedPlayerStats]) -> Int {
        guard !stats.isEmpty else { return 0 }
        let knownPlayers = (try? modelContext.fetch(FetchDescriptor<Player>())) ?? []
        var updated = 0
        for stat in stats {
            guard let fileSeconds = stat.playTimeSeconds,
                  let player = knownPlayers.first(where: { UUIDMatching.matches($0.uuid, stat.uuid) }),
                  abs(fileSeconds - player.playTimeSeconds) >= 60
            else { continue }
            player.playTimeSeconds = fileSeconds
            updated += 1
        }
        if updated > 0 { try? modelContext.save() }
        return updated
    }

    // MARK: - Inventory (world/players/data) — mirrored locally, not auto-applied

    private func syncInventory() async -> Bool {
        do {
            let files = try await client.listDirectory(atPath: "/world/players/data")
            try? FileManager.default.createDirectory(at: inventoryMirrorDirectory, withIntermediateDirectories: true)
            var count = 0
            for file in files where !file.isDirectory && file.name.hasSuffix(".dat") {
                let data = try await client.downloadFile(atPath: "/world/players/data/\(file.name)")
                try data.write(to: inventoryMirrorDirectory.appendingPathComponent(file.name), options: .atomic)
                count += 1
            }
            log("🎒 Inventory: mirrored \(count) player data file\(count == 1 ? "" : "s") — load it from Inventory Analyzer's \"Load Synced Copy.\"")
            return true
        } catch {
            log("❌ Inventory sync failed: \(error.localizedDescription)", isError: true)
            return false
        }
    }

    // MARK: - Performance (debug/profiling/*.zip) — mirrored + unzipped locally, not auto-applied

    private func syncPerformance() async -> Bool {
        do {
            let files = try await client.listDirectory(atPath: "/debug/profiling")
            try? FileManager.default.createDirectory(at: performanceMirrorDirectory, withIntermediateDirectories: true)
            var newReports = 0
            for file in files where !file.isDirectory && file.name.hasSuffix(".zip") {
                let reportName = (file.name as NSString).deletingPathExtension
                let destination = performanceMirrorDirectory.appendingPathComponent(reportName, isDirectory: true)
                guard !FileManager.default.fileExists(atPath: destination.path) else { continue } // already mirrored

                let zipData = try await client.downloadFile(atPath: "/debug/profiling/\(file.name)")
                let entries = try ZipReader.extractAll(from: zipData)
                try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
                for (entryPath, entryData) in entries {
                    let entryURL = destination.appendingPathComponent(entryPath)
                    try FileManager.default.createDirectory(at: entryURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try entryData.write(to: entryURL, options: .atomic)
                }
                newReports += 1
            }
            log("📊 Performance: mirrored \(newReports) new report\(newReports == 1 ? "" : "s") — pick them from Performance's \"Synced Reports\" menu.")
            return true
        } catch {
            log("❌ Performance sync failed: \(error.localizedDescription)", isError: true)
            return false
        }
    }

    // MARK: - World Map (world/region/*.mca)

    /// Only downloads a region file when its remote modification time
    /// is newer than the locally-mirrored copy's — region files are
    /// several MB each and mostly don't change between 15-minute sync
    /// cycles, unlike every other synced category here.
    /// world/region was the overworld's region path pre-2026-rename;
    /// this version unified all three dimensions under
    /// world/dimensions/minecraft/<name>/region — verified live via
    /// SFTP (world/region no longer exists at all) the same way the
    /// players/data and players/stats renames were, rather than assumed.
    private static let overworldRegionPath = "/world/dimensions/minecraft/overworld/region"

    private struct RegionCoordinate: Hashable {
        var x: Int
        var z: Int
    }

    private func syncWorldMap() async -> Bool {
        do {
            let files = try await client.listDirectory(atPath: Self.overworldRegionPath)
            try? FileManager.default.createDirectory(at: worldMapMirrorDirectory, withIntermediateDirectories: true)

            // A server that's been up for months can easily have 100+
            // region files, several MB each — sequentially downloading
            // whatever order the SFTP listing happens to return means
            // the region an admin actually cares about (their own base,
            // wherever a breadcrumb trail leads) can sit unsynced behind
            // dozens of irrelevant ones for cycle after cycle. Spawn and
            // every region containing a recorded player position go first.
            let priorityRegions = priorityRegionCoordinates()
            let orderedFiles = files
                .filter { !$0.isDirectory }
                .compactMap { file -> (SFTPRemoteFile, (x: Int, z: Int))? in
                    guard let coords = RegionFileReader.regionCoordinates(fromFilename: file.name) else { return nil }
                    return (file, coords)
                }
                .sorted { lhs, rhs in
                    let lhsPriority = priorityRegions.contains(RegionCoordinate(x: lhs.1.x, z: lhs.1.z))
                    let rhsPriority = priorityRegions.contains(RegionCoordinate(x: rhs.1.x, z: rhs.1.z))
                    return lhsPriority && !rhsPriority
                }
                .map(\.0)

            var downloaded = 0
            for file in orderedFiles {
                let localURL = worldMapMirrorDirectory.appendingPathComponent(file.name)
                if let remoteModified = file.modificationDate,
                   let localModified = (try? FileManager.default.attributesOfItem(atPath: localURL.path))?[.modificationDate] as? Date,
                   localModified >= remoteModified {
                    continue // already have the current version
                }
                let data = try await client.downloadFile(atPath: "\(Self.overworldRegionPath)/\(file.name)")
                try data.write(to: localURL, options: .atomic)
                downloaded += 1
            }
            log("🗺️ World Map: \(downloaded) region file\(downloaded == 1 ? "" : "s") updated.")
            return true
        } catch {
            log("❌ World Map sync failed: \(error.localizedDescription)", isError: true)
            return false
        }
    }

    /// Spawn's own region, plus every region containing at least one
    /// recorded PlayerPositionSample — exactly the areas World Map's
    /// breadcrumb feature actually needs terrain for.
    private func priorityRegionCoordinates() -> Set<RegionCoordinate> {
        var regions: Set<RegionCoordinate> = [RegionCoordinate(x: 0, z: 0)]
        let positions = (try? modelContext.fetch(FetchDescriptor<PlayerPositionSample>())) ?? []
        for position in positions {
            let chunkX = Int((position.x / 16).rounded(.down))
            let chunkZ = Int((position.z / 16).rounded(.down))
            regions.insert(RegionCoordinate(x: Self.floorDiv(chunkX, 32), z: Self.floorDiv(chunkZ, 32)))
        }
        return regions
    }

    /// Swift's `/` truncates toward zero, which is wrong for region
    /// math here — e.g. chunk -172 must map to region -6
    /// (floor(-172/32)), not -5 (truncated -172/32).
    private static func floorDiv(_ a: Int, _ b: Int) -> Int {
        let quotient = a / b
        let remainder = a % b
        return (remainder != 0 && (remainder < 0) != (b < 0)) ? quotient - 1 : quotient
    }

    // MARK: - Log

    private func log(_ text: String, isError: Bool = false) {
        syncLog.append(SyncLogEntry(timestamp: .now, text: text, isError: isError))
        if syncLog.count > Self.logCap {
            syncLog.removeFirst(syncLog.count - Self.logCap)
        }
    }
}
