//
//  LocationView.swift
//  Overseer
//
//  Where players actually connect from, and what that means for ad
//  timing — the only part of the app that touches player IP addresses.
//  Two deliberately separate, explicit admin actions:
//
//   1. "Import Server Logs…" — reads logs/latest.log and rotated
//      logs/*.log(.gz) from a locally-selected folder (same pattern as
//      Performance/Playtime Importer/Inventory Analyzer) and extracts
//      join events (username + IP + timestamp) via ServerLogJoinParser.
//      Purely local — no network call, nothing sent anywhere.
//   2. "Resolve Locations" — the only step that talks to the network:
//      sends each not-yet-cached IP to ipapi.co (GeoIPService) to
//      resolve country/region/timezone. Never automatic, and results
//      are cached indefinitely so a given IP is only ever resolved once.
//
//  This is the server's own log data about its own connections — not a
//  new exposure — but IPs are more sensitive than anything else this
//  app stores, so nothing here runs without the admin explicitly
//  clicking for it.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct LocationView: View {
    var sftpCoordinator: SFTPSyncCoordinator

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PlayerLoginRecord.timestamp, order: .reverse) private var loginRecords: [PlayerLoginRecord]
    @Query private var geoLocations: [PlayerGeoLocation]

    @State private var showFolderImporter = false
    @State private var isScanning = false
    @State private var isResolving = false
    @State private var folderName: String?
    @State private var importError: String?
    @State private var lastImportedCount: Int?
    @State private var resolveProgress: (done: Int, total: Int)?

    private var geoLookup: [String: PlayerGeoLocation] {
        Dictionary(uniqueKeysWithValues: geoLocations.map { ($0.ipAddress, $0) })
    }

    private var unresolvedIPs: [String] {
        let known = Set(geoLookup.keys)
        let candidates = Set(loginRecords.map(\.ipAddress)).filter { !GeoIPService.isPrivateOrReserved($0) }
        return Array(candidates.subtracting(known)).sorted()
    }

    private var countryDistribution: [PlayerGeographyEngine.CountryEntry] {
        PlayerGeographyEngine.countryDistribution(loginRecords: loginRecords, geoLookup: geoLookup)
    }

    private var altAccountGroups: [PlayerGeographyEngine.AltAccountGroup] {
        PlayerGeographyEngine.alternateAccountCandidates(loginRecords: loginRecords)
    }

    private var perPlayerLocations: [(username: String, geo: PlayerGeoLocation?)] {
        let usernames = Set(loginRecords.map(\.username))
        let latest = PlayerGeographyEngine.latestKnownLocation(loginRecords: loginRecords, geoLookup: geoLookup)
        return usernames.sorted().map { ($0, latest[$0]) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                importBar
                if loginRecords.isEmpty {
                    emptyState
                } else {
                    summaryGrid
                    Divider()
                    resolveBar
                    Divider()
                    countrySection
                    Divider()
                    playerSection
                    Divider()
                    altAccountsSection
                }
            }
            .padding(20)
        }
        .navigationTitle("Location")
        .fileImporter(isPresented: $showFolderImporter, allowedContentTypes: [.folder], onCompletion: handleFolderImport)
    }

    // MARK: - Import

    private var importBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            sftpStatusRow
            manualImportRow
        }
    }

    @ViewBuilder
    private var sftpStatusRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "network")
                .foregroundStyle(.secondary)
            if let lastSync = sftpCoordinator.lastSyncDate {
                Text("SFTP auto-sync last ran \(lastSync, format: .relative(presentation: .named))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("SFTP auto-sync hasn't run yet — pulls logs/latest.log every \(Int(sftpCoordinator.syncIntervalMinutes)) min when enabled in Settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if sftpCoordinator.isSyncing {
                ProgressView().controlSize(.small)
            }
            Spacer()
            Button("Sync Now") {
                Task { await sftpCoordinator.syncNow() }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(sftpCoordinator.isSyncing)
        }
    }

    private var manualImportRow: some View {
        HStack(spacing: 10) {
            Button {
                showFolderImporter = true
            } label: {
                Label("Import Server Logs Manually…", systemImage: "folder.badge.plus")
            }
            .buttonStyle(.bordered)
            .disabled(isScanning)

            if isScanning {
                ProgressView().controlSize(.small)
            }
            if let folderName {
                Text(folderName).font(.callout).foregroundStyle(.secondary)
            }
            if let lastImportedCount {
                Text("\(lastImportedCount) join event\(lastImportedCount == 1 ? "" : "s") found")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let importError {
                Label(importError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            Spacer()
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No Login Data Imported",
            systemImage: "globe",
            description: Text("Select your server's logs folder (containing latest.log and rotated .log.gz files). Purely local — nothing is sent anywhere until you explicitly resolve locations below.")
        )
        .frame(maxHeight: .infinity)
    }

    private func handleFolderImport(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let error):
            importError = error.localizedDescription
        case .success(let url):
            importError = nil
            folderName = url.lastPathComponent
            isScanning = true
            Task {
                let outcome = await Self.readAndScan(folderURL: url)
                isScanning = false
                switch outcome {
                case .success(let records):
                    lastImportedCount = records.count
                    persist(records)
                case .failure(let message):
                    importError = message
                }
            }
        }
    }

    private enum ScanOutcome {
        case success([LogJoinRecord])
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
            let logFiles = fileURLs.filter(ServerLogFolderScanner.isLogFile)
            guard !logFiles.isEmpty else {
                return .failure("No .log/.log.gz files found — select the server's logs folder.")
            }

            var entries: [LogFileEntry] = []
            for fileURL in logFiles {
                guard let data = try? Data(contentsOf: fileURL) else { continue }
                entries.append(LogFileEntry(filename: fileURL.lastPathComponent, data: data))
            }
            return .success(ServerLogFolderScanner.scan(entries: entries))
        }.value
    }

    /// De-duplicates against what's already stored (same username + IP
    /// + timestamp) so re-importing an overlapping set of log files
    /// (e.g. latest.log again) doesn't create duplicate rows — shared
    /// with SFTPSyncCoordinator's automatic import, see PlayerLoginRecordStore.
    private func persist(_ records: [LogJoinRecord]) {
        PlayerLoginRecordStore.persist(records, modelContext: modelContext)
    }

    // MARK: - Summary

    private var summaryGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
            SummaryCard(title: "Login Records", value: "\(loginRecords.count)", systemImage: "list.bullet", tint: .blue)
            SummaryCard(title: "Unique Players", value: "\(Set(loginRecords.map(\.username)).count)", systemImage: "person.3.fill", tint: .green)
            SummaryCard(title: "Countries Detected", value: "\(countryDistribution.count)", systemImage: "globe", tint: .purple)
            SummaryCard(title: "Unresolved IPs", value: "\(unresolvedIPs.count)", systemImage: "questionmark.circle", tint: unresolvedIPs.isEmpty ? .secondary : .orange)
        }
    }

    // MARK: - Resolve

    private var resolveBar: some View {
        HStack(spacing: 12) {
            Button {
                Task { await resolveAll() }
            } label: {
                if isResolving {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Resolve Locations", systemImage: "location.magnifyingglass")
                }
            }
            .buttonStyle(.bordered)
            .disabled(isResolving || unresolvedIPs.isEmpty)

            if let resolveProgress {
                Text("Resolved \(resolveProgress.done)/\(resolveProgress.total)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if unresolvedIPs.isEmpty && !geoLocations.isEmpty {
                Text("All known IPs resolved.").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text("Sends each IP to ipapi.co. Only runs when you click this — never automatic.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func resolveAll() async {
        let ips = unresolvedIPs
        guard !ips.isEmpty else { return }
        isResolving = true
        resolveProgress = (0, ips.count)
        for (index, ip) in ips.enumerated() {
            let result = await GeoIPService.shared.resolve(ip: ip)
            modelContext.insert(PlayerGeoLocation(
                ipAddress: result.ipAddress,
                country: result.country,
                countryCode: result.countryCode,
                region: result.region,
                city: result.city,
                timezoneIdentifier: result.timezoneIdentifier,
                isp: result.isp,
                resolutionFailed: result.resolutionFailed
            ))
            try? modelContext.save()
            resolveProgress = (index + 1, ips.count)
            // A light pause between requests — courteous to a free,
            // unauthenticated API rather than firing a burst.
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        isResolving = false
    }

    // MARK: - Country distribution

    private var countrySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Where Your Players Are").font(.headline)
            Text("Suggested windows assume your players are online during their own evening (18:00–22:00 local) — a starting point, not a guarantee.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if countryDistribution.isEmpty {
                Text("No resolved locations yet — click Resolve Locations above.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(countryDistribution) { entry in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.country).font(.body.weight(.medium))
                                if let tz = entry.timezoneIdentifier, let window = PlayerGeographyEngine.primeTimeInWarsaw(timezoneIdentifier: tz) {
                                    Text("Their evening ≈ \(window)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text("\(entry.playerCount) player\(entry.playerCount == 1 ? "" : "s")")
                                .font(.callout.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 6)
                        if entry.id != countryDistribution.last?.id { Divider() }
                    }
                }
            }
        }
    }

    // MARK: - Per-player

    private var playerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Per-Player Location").font(.headline)
            VStack(spacing: 0) {
                ForEach(perPlayerLocations, id: \.username) { entry in
                    HStack {
                        Text(entry.username).font(.body.weight(.medium))
                        Spacer()
                        if let geo = entry.geo {
                            Text([geo.city, geo.region, geo.country].compactMap { $0 }.joined(separator: ", "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Not resolved yet").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                    if entry.username != perPlayerLocations.last?.username { Divider() }
                }
            }
        }
    }

    // MARK: - Alt accounts

    private var altAccountsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Shared-IP Groups").font(.headline)
            Text("Usernames that have logged in from the same IP. This is NOT proof of alt accounts or ban evasion — a household sharing one internet connection looks identical. Worth a manual look, never an automatic conclusion.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if altAccountGroups.isEmpty {
                Text("No shared IPs found.").font(.callout).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(altAccountGroups) { group in
                        HStack(alignment: .top) {
                            Image(systemName: "person.2.fill").foregroundStyle(.orange).frame(width: 20)
                            Text(group.usernames.joined(separator: ", ")).font(.callout)
                            Spacer()
                        }
                        .padding(.vertical, 4)
                        if group.id != altAccountGroups.last?.id { Divider() }
                    }
                }
            }
        }
    }
}
