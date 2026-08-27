//
//  PlaytimeImporterView.swift
//  Overseer
//
//  Reconciles this app's session-tracked playtime against vanilla's own
//  authoritative record — world/stats/<uuid>.json's `minecraft:play_time`
//  — for the times session tracking can't cover: the app wasn't running,
//  a crash/restart dropped an open session without closing it cleanly,
//  or a player joined before this app ever saw the server. The stats
//  file has no login/logout timestamps (only the running total), so
//  this can correct the total but can't reconstruct individual
//  PlayerSession rows — it's a one-way "set the total to what the
//  server says," applied manually per player or in bulk, never
//  automatic.
//
//  File read + JSON parse happen off-main via PlayerStatsFolderScanner,
//  same split as InventoryAnalyzerView/SchematicBuilderView.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct PlaytimeImporterView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Player.username) private var knownPlayers: [Player]

    @State private var showFolderImporter = false
    @State private var isScanning = false
    @State private var folderName: String?
    @State private var scanResult: PlayerStatsScanResult?
    @State private var scanError: String?
    @State private var onlyShowDifferences = true
    @State private var lastAppliedCount: Int?

    @State private var resolvedUsernames: [String: String] = [:]
    @State private var unresolvableUUIDs: Set<String> = []

    private struct Row: Identifiable {
        var uuid: String
        var player: Player?
        var fileSeconds: Double?
        var id: String { uuid }

        var currentSeconds: Double { player?.playTimeSeconds ?? 0 }
        var deltaSeconds: Double { (fileSeconds ?? 0) - currentSeconds }
        var differsMeaningfully: Bool { fileSeconds != nil && abs(deltaSeconds) >= 60 }
    }

    private var rows: [Row] {
        guard let scanResult else { return [] }
        return scanResult.stats
            .map { stat in
                Row(uuid: stat.uuid, player: knownPlayer(for: stat.uuid), fileSeconds: stat.playTimeSeconds)
            }
            .sorted { displayName(for: $0).localizedCaseInsensitiveCompare(displayName(for: $1)) == .orderedAscending }
    }

    private var visibleRows: [Row] {
        onlyShowDifferences ? rows.filter { $0.differsMeaningfully } : rows
    }

    var body: some View {
        VStack(spacing: 0) {
            folderBar
            Divider()
            if rows.isEmpty {
                emptyState
            } else {
                controlsBar
                Divider()
                rowList
            }
        }
        .navigationTitle("Playtime Importer")
        .fileImporter(isPresented: $showFolderImporter, allowedContentTypes: [.folder], onCompletion: handleFolderImport)
    }

    // MARK: - Folder loading

    private var folderBar: some View {
        HStack(spacing: 10) {
            Button {
                showFolderImporter = true
            } label: {
                Label("Select Stats Folder…", systemImage: "folder.badge.plus")
            }
            .buttonStyle(.borderedProminent)
            .disabled(isScanning)

            if isScanning {
                ProgressView().controlSize(.small)
            }
            if let folderName {
                Text(folderName).font(.callout).foregroundStyle(.secondary)
            }
            if let result = scanResult {
                Text("\(result.stats.count) file\(result.stats.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !result.failures.isEmpty {
                    Label("\(result.failures.count) couldn't be read", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .help(result.failures.map { "\($0.uuid): \($0.message)" }.joined(separator: "\n"))
                }
            }
            if let scanError {
                Label(scanError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            Spacer()
        }
        .padding(14)
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No Stats Loaded",
            systemImage: "clock.arrow.circlepath",
            description: Text("Download world/stats from your server, then select that folder. This reconciles the app's tracked playtime against vanilla's own record — nothing is sent anywhere.")
        )
        .frame(maxHeight: .infinity)
    }

    private func handleFolderImport(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let error):
            scanError = error.localizedDescription
        case .success(let url):
            scanError = nil
            folderName = url.lastPathComponent
            lastAppliedCount = nil
            resolvedUsernames = [:]
            unresolvableUUIDs = []
            isScanning = true
            Task {
                let outcome = await Self.readAndScan(folderURL: url)
                isScanning = false
                switch outcome {
                case .success(let scan):
                    scanResult = scan
                case .failure(let message):
                    scanError = message
                    scanResult = nil
                }
            }
        }
    }

    private enum ScanOutcome {
        case success(PlayerStatsScanResult)
        case failure(String)
    }

    private static func readAndScan(folderURL: URL) async -> ScanOutcome {
        await Task.detached(priority: .userInitiated) {
            let didAccess = folderURL.startAccessingSecurityScopedResource()
            defer { if didAccess { folderURL.stopAccessingSecurityScopedResource() } }

            let fileManager = FileManager.default
            guard let fileURLs = try? fileManager.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil) else {
                return .failure("Couldn't read that folder's contents.")
            }
            let statsFiles = fileURLs.filter(PlayerStatsFolderScanner.isStatsFile)
            guard !statsFiles.isEmpty else {
                return .failure("No .json files found in that folder — select world/stats, not the world folder itself.")
            }

            var entries: [PlayerStatsScanEntry] = []
            for fileURL in statsFiles {
                guard let data = try? Data(contentsOf: fileURL) else { continue }
                let uuid = fileURL.deletingPathExtension().lastPathComponent
                entries.append(PlayerStatsScanEntry(uuid: uuid, data: data, fileURL: fileURL))
            }
            return .success(PlayerStatsFolderScanner.scan(entries: entries))
        }.value
    }

    // MARK: - Identity

    private func knownPlayer(for uuid: String) -> Player? {
        knownPlayers.first { UUIDMatching.matches($0.uuid, uuid) }
    }

    private func displayName(for row: Row) -> String {
        if let player = row.player { return player.username }
        if let resolved = resolvedUsernames[row.uuid] { return resolved }
        return row.uuid
    }

    private func resolveIfNeeded(_ row: Row) {
        guard row.player == nil, resolvedUsernames[row.uuid] == nil, !unresolvableUUIDs.contains(row.uuid) else { return }
        Task {
            if let name = await MojangAPI.shared.resolveUsername(for: row.uuid) {
                resolvedUsernames[row.uuid] = name
            } else {
                unresolvableUUIDs.insert(row.uuid)
            }
        }
    }

    // MARK: - Controls

    private var controlsBar: some View {
        HStack(spacing: 12) {
            Toggle("Only show differences ≥ 1 minute", isOn: $onlyShowDifferences)
                .toggleStyle(.checkbox)
                .font(.caption)
            Spacer()
            if let lastAppliedCount {
                Text("Updated \(lastAppliedCount) player\(lastAppliedCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
            Button("Apply All Updates") { applyAll() }
                .buttonStyle(.borderedProminent)
                .disabled(!rows.contains { $0.player != nil && $0.differsMeaningfully })
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func applyAll() {
        var count = 0
        for row in rows where row.player != nil && row.differsMeaningfully {
            apply(row)
            count += 1
        }
        try? modelContext.save()
        lastAppliedCount = count
    }

    private func apply(_ row: Row) {
        guard let fileSeconds = row.fileSeconds else { return }
        if let player = row.player {
            player.playTimeSeconds = fileSeconds
        } else {
            let username = resolvedUsernames[row.uuid] ?? row.uuid
            let player = Player(username: username, uuid: row.uuid, playTimeSeconds: fileSeconds)
            modelContext.insert(player)
        }
        try? modelContext.save()
    }

    // MARK: - Row list

    private var rowList: some View {
        Group {
            if visibleRows.isEmpty {
                ContentUnavailableView(
                    "Everything's In Sync",
                    systemImage: "checkmark.circle",
                    description: Text("No player differs from their stats file by more than a minute.")
                )
            } else {
                List(visibleRows) { row in
                    rowView(row)
                        .task { resolveIfNeeded(row) }
                }
                .listStyle(.inset)
            }
        }
    }

    private func rowView(_ row: Row) -> some View {
        HStack(spacing: 12) {
            PlayerAvatarView(username: row.player?.username ?? resolvedUsernames[row.uuid])
            VStack(alignment: .leading, spacing: 2) {
                Text(displayName(for: row)).font(.body.weight(.medium))
                if row.player == nil {
                    Text("Not tracked yet").font(.caption2).foregroundStyle(.orange)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("App: \(formatDuration(row.currentSeconds))").font(.caption).foregroundStyle(.secondary)
                Text("Stats file: \(row.fileSeconds.map(formatDuration) ?? "—")").font(.callout.weight(.medium))
            }
            if let fileSeconds = row.fileSeconds {
                deltaLabel(currentSeconds: row.currentSeconds, fileSeconds: fileSeconds)
            }
            Button(row.player == nil ? "Create" : "Update") { apply(row) }
                .buttonStyle(.bordered)
                .disabled(row.fileSeconds == nil)
        }
        .padding(.vertical, 4)
    }

    private func deltaLabel(currentSeconds: Double, fileSeconds: Double) -> some View {
        let delta = fileSeconds - currentSeconds
        let tint: Color = abs(delta) < 60 ? .secondary : (delta > 0 ? .green : .red)
        let sign = delta >= 0 ? "+" : "−"
        return Text("\(sign)\(formatDuration(abs(delta)))")
            .font(.caption.monospacedDigit())
            .foregroundStyle(tint)
            .frame(width: 90, alignment: .trailing)
    }
}
