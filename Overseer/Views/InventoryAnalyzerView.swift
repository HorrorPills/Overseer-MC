//
//  InventoryAnalyzerView.swift
//  Overseer
//
//  Reads a manually-downloaded copy of the server's world/playerdata
//  folder (never the live server — there's no RCON command that reads
//  an inventory, vanilla or otherwise) and lets an admin browse any
//  player's items, or search every player at once for a specific item —
//  the actual workflow behind a "someone stole my stuff" report: find
//  who's holding it right now, without trusting anyone's word for it.
//
//  File read + NBT parse happen off-main via PlayerDataFolderScanner,
//  same split as SchematicBuilderView's loadAndParse: this view owns
//  directory enumeration and security-scoped access (I/O), the
//  Inventory/ files stay pure and unit-testable.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct InventoryAnalyzerView: View {
    var sftpCoordinator: SFTPSyncCoordinator

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Player.lastSeen, order: .reverse) private var knownPlayers: [Player]

    @State private var showFolderImporter = false
    @State private var isScanning = false
    @State private var folderName: String?
    @State private var scanResult: PlayerDataScanResult?
    @State private var scanError: String?

    @State private var playerFilterText = ""
    @State private var itemSearchQuery = ""
    @State private var selectedUUID: String?
    @State private var onlyActiveLast48Hours = false
    @State private var onlyFlagged = false
    @State private var lowPlaytimeThresholdHours: Double = 2

    /// Reverse-resolved usernames for UUIDs with no matching local
    /// `Player` (e.g. someone who left before this app ever saw them).
    /// Populated lazily as rows appear, never re-fetched once resolved
    /// (or once confirmed unresolvable, to avoid hammering Mojang on
    /// every list re-render).
    @State private var resolvedUsernames: [String: String] = [:]
    @State private var unresolvableUUIDs: Set<String> = []

    private var players: [ParsedPlayerData] {
        scanResult?.players.sorted { displayName(for: $0).localizedCaseInsensitiveCompare(displayName(for: $1)) == .orderedAscending } ?? []
    }

    private var filteredPlayers: [ParsedPlayerData] {
        var result = players
        if onlyActiveLast48Hours {
            result = result.filter { RecentActivityFilter.isWithin(48, modifiedAt: $0.fileModifiedAt) }
        }
        if onlyFlagged {
            result = result.filter { suspicion(for: $0)?.isLowPlaytimeWithValuables == true }
        }
        guard !playerFilterText.isEmpty else { return result }
        let query = playerFilterText.lowercased()
        return result.filter {
            displayName(for: $0).lowercased().contains(query) || $0.uuid.lowercased().contains(query)
        }
    }

    private var selectedPlayer: ParsedPlayerData? {
        guard let selectedUUID else { return nil }
        return players.first { $0.uuid == selectedUUID }
    }

    private var searchResults: [InventorySearchResult] {
        InventorySearchEngine.search(query: itemSearchQuery, in: players)
    }

    var body: some View {
        VStack(spacing: 0) {
            folderBar
            Divider()
            if players.isEmpty {
                emptyState
            } else {
                HStack(spacing: 0) {
                    sidebar
                    Divider()
                    detail
                }
            }
        }
        .navigationTitle("Inventory Analyzer")
        .fileImporter(
            isPresented: $showFolderImporter,
            allowedContentTypes: [.folder],
            onCompletion: handleFolderImport
        )
    }

    // MARK: - Folder loading

    private var folderBar: some View {
        HStack(spacing: 10) {
            Button {
                showFolderImporter = true
            } label: {
                Label("Select Data Folder…", systemImage: "folder.badge.plus")
            }
            .buttonStyle(.borderedProminent)
            .disabled(isScanning)

            Button {
                loadSyncedCopy()
            } label: {
                Label("Load Synced Copy", systemImage: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(.bordered)
            .disabled(isScanning)
            .help(sftpCoordinator.lastSyncDate.map { "Last synced \($0.formatted(.relative(presentation: .named)))" } ?? "No SFTP sync has run yet")

            if isScanning {
                ProgressView().controlSize(.small)
            }
            if let folderName {
                Text(folderName).font(.callout).foregroundStyle(.secondary)
            }
            if let result = scanResult {
                Text("\(result.players.count) player\(result.players.count == 1 ? "" : "s")")
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
            "No Player Data Loaded",
            systemImage: "shippingbox",
            description: Text("Download world/playerdata from your server, then select that folder — the app reads each player's .dat file locally, nothing is sent anywhere.")
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
            selectedUUID = nil
            resolvedUsernames = [:]
            unresolvableUUIDs = []
            isScanning = true
            Task {
                let result = await Self.readAndScan(folderURL: url)
                isScanning = false
                switch result {
                case .success(let scan):
                    scanResult = scan
                case .failure(let message):
                    scanError = message
                    scanResult = nil
                }
            }
        }
    }

    /// Points the exact same folder-scan logic at SFTPSyncCoordinator's
    /// local mirror instead of a user-picked folder — the mirror
    /// directory isn't security-scoped (it's app-owned, under
    /// Application Support), so `readAndScan` works unchanged either way.
    private func loadSyncedCopy() {
        scanError = nil
        folderName = "Synced copy (world/players/data)"
        selectedUUID = nil
        resolvedUsernames = [:]
        unresolvableUUIDs = []
        isScanning = true
        let mirrorURL = sftpCoordinator.inventoryMirrorDirectory
        Task {
            let result = await Self.readAndScan(folderURL: mirrorURL)
            isScanning = false
            switch result {
            case .success(let scan):
                scanResult = scan
            case .failure(let message):
                scanError = message
                scanResult = nil
            }
        }
    }

    private enum ScanOutcome {
        case success(PlayerDataScanResult)
        case failure(String)
    }

    private static func readAndScan(folderURL: URL) async -> ScanOutcome {
        await Task.detached(priority: .userInitiated) {
            let didAccess = folderURL.startAccessingSecurityScopedResource()
            defer { if didAccess { folderURL.stopAccessingSecurityScopedResource() } }

            let fileManager = FileManager.default
            guard let fileURLs = try? fileManager.contentsOfDirectory(
                at: folderURL, includingPropertiesForKeys: [.contentModificationDateKey]
            ) else {
                return .failure("Couldn't read that folder's contents.")
            }

            let datFiles = fileURLs.filter(PlayerDataFolderScanner.isPlayerDataFile)
            guard !datFiles.isEmpty else {
                return .failure("No .dat files found in that folder — select world/playerdata, not the world folder itself.")
            }

            var entries: [PlayerDataScanEntry] = []
            for fileURL in datFiles {
                guard let data = try? Data(contentsOf: fileURL) else { continue }
                let modified = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                let uuid = fileURL.deletingPathExtension().lastPathComponent
                entries.append(PlayerDataScanEntry(uuid: uuid, data: data, fileURL: fileURL, modifiedAt: modified))
            }
            return .success(PlayerDataFolderScanner.scan(entries: entries))
        }.value
    }

    // MARK: - Identity resolution

    private func knownPlayer(for uuid: String) -> Player? {
        knownPlayers.first { UUIDMatching.matches($0.uuid, uuid) }
    }

    private func displayName(for player: ParsedPlayerData) -> String {
        if let known = knownPlayer(for: player.uuid) { return known.username }
        if let resolved = resolvedUsernames[player.uuid] { return resolved }
        return player.uuid
    }

    private func resolveIfNeeded(_ uuid: String) {
        guard knownPlayer(for: uuid) == nil,
              resolvedUsernames[uuid] == nil,
              !unresolvableUUIDs.contains(uuid) else { return }
        Task {
            if let name = await MojangAPI.shared.resolveUsername(for: uuid) {
                resolvedUsernames[uuid] = name
            } else {
                unresolvableUUIDs.insert(uuid)
            }
        }
    }

    // MARK: - Suspicious inventory

    /// Only evaluable for players matched to a local `Player` record —
    /// playtime is what makes the signal meaningful, and there's no
    /// playtime to check for someone the app has never tracked.
    private func suspicion(for player: ParsedPlayerData) -> SuspicionFlag? {
        guard let known = knownPlayer(for: player.uuid) else { return nil }
        return SuspicionEngine.evaluate(
            player: player, playTimeSeconds: known.playTimeSeconds,
            lowPlaytimeThresholdSeconds: lowPlaytimeThresholdHours * 3600
        )
    }

    private func itemSummary(_ items: [InventoryItemStack]) -> String {
        items.map { "\($0.displayName) ×\($0.count)" }.joined(separator: ", ")
    }

    private func addToInvestigation(username: String, flag: SuspicionFlag) {
        let text = "Suspicious Inventory: only \(formatDuration(flag.playTimeSeconds)) tracked playtime, holding \(itemSummary(flag.watchlistedItems))."
        modelContext.insert(InvestigationNote(username: username, text: text, source: "inventory"))
        if let known = knownPlayers.first(where: { $0.username == username }), known.investigationStatus == .clear {
            known.investigationStatus = .watching
        }
        try? modelContext.save()
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                TextField("Filter players", text: $playerFilterText)
                    .textFieldStyle(.roundedBorder)
                Toggle("Active in last 48 hours", isOn: $onlyActiveLast48Hours)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                    .help("Filters to players whose .dat file was written in the last 48 hours — it's updated on disconnect and on every server auto-save, so this is a proxy for \"recently online,\" not exact.")
                Toggle("Flagged only", isOn: $onlyFlagged)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                    .help("Players holding a watchlisted item (netherite gear, elytra, shulker boxes, …) with less tracked playtime than the threshold below.")
                Stepper(value: $lowPlaytimeThresholdHours, in: 0.5...48, step: 0.5) {
                    Text("Flag threshold: \(lowPlaytimeThresholdHours, specifier: "%.1f")h").font(.caption)
                }
            }
            .padding(10)
            Divider()
            List(filteredPlayers, selection: $selectedUUID) { player in
                sidebarRow(for: player)
                    .tag(player.uuid)
                    .contentShape(Rectangle())
                    .onTapGesture { selectedUUID = player.uuid; itemSearchQuery = "" }
                    .task { resolveIfNeeded(player.uuid) }
            }
            .listStyle(.inset)
        }
        .frame(width: 260)
    }

    private func sidebarRow(for player: ParsedPlayerData) -> some View {
        HStack(spacing: 10) {
            PlayerAvatarView(username: knownPlayer(for: player.uuid)?.username ?? resolvedUsernames[player.uuid])
            VStack(alignment: .leading, spacing: 2) {
                Text(displayName(for: player)).font(.body.weight(.medium)).lineLimit(1)
                HStack(spacing: 4) {
                    Text("\(player.allItems.reduce(0) { $0 + $1.count }) items")
                    if let modified = player.fileModifiedAt {
                        Text("· saved \(modified, format: .relative(presentation: .named))")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer()
            if suspicion(for: player)?.isLowPlaytimeWithValuables == true {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .help("Flagged: valuable items with low tracked playtime")
            }
            if RecentActivityFilter.isWithin(48, modifiedAt: player.fileModifiedAt) {
                Circle().fill(.green).frame(width: 6, height: 6)
                    .help("File modified within the last 48 hours")
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Detail

    private var detail: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Find item across all players…", text: $itemSearchQuery)
                    .textFieldStyle(.plain)
                if !itemSearchQuery.isEmpty {
                    Button {
                        itemSearchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(10)
            .background(.quaternary.opacity(0.3))
            Divider()

            if !itemSearchQuery.isEmpty {
                searchResultsList
            } else if let selectedPlayer {
                ScrollView {
                    playerDetailContent(selectedPlayer)
                        .padding(20)
                }
            } else {
                ContentUnavailableView(
                    "No Player Selected",
                    systemImage: "person.crop.square",
                    description: Text("Choose a player on the left, or search for an item above.")
                )
                .frame(maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var searchResultsList: some View {
        Group {
            if searchResults.isEmpty {
                ContentUnavailableView.search(text: itemSearchQuery)
            } else {
                List(searchResults) { result in
                    HStack(spacing: 12) {
                        PlayerAvatarView(username: knownPlayer(for: result.player.uuid)?.username ?? resolvedUsernames[result.player.uuid])
                        VStack(alignment: .leading, spacing: 2) {
                            Text(displayName(for: result.player)).font(.body.weight(.medium))
                            Text("\(result.container.rawValue) · slot \(result.item.slot)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(result.item.displayName) ×\(result.item.count)").font(.callout)
                            if result.item.isEnchanted {
                                Text(result.item.enchantments.joined(separator: ", "))
                                    .font(.caption2)
                                    .foregroundStyle(.purple)
                            }
                        }
                        Button("View") {
                            selectedUUID = result.player.uuid
                            itemSearchQuery = ""
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.vertical, 3)
                    .task { resolveIfNeeded(result.player.uuid) }
                }
                .listStyle(.inset)
            }
        }
    }

    @ViewBuilder
    private func playerDetailContent(_ player: ParsedPlayerData) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                PlayerAvatarView(username: knownPlayer(for: player.uuid)?.username ?? resolvedUsernames[player.uuid], size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(displayName(for: player)).font(.title2.weight(.semibold))
                    Text(player.uuid).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
                Spacer()
                if let modified = player.fileModifiedAt {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("File saved").font(.caption2).foregroundStyle(.secondary)
                        Text(modified, format: .relative(presentation: .named)).font(.caption)
                    }
                }
            }

            suspicionSection(player)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 10)], spacing: 10) {
                SummaryCard(title: "Health", value: player.health.map { String(format: "%.0f / 20", $0) } ?? "—", systemImage: "heart.fill", tint: .red)
                SummaryCard(title: "Food", value: player.foodLevel.map { "\($0) / 20" } ?? "—", systemImage: "fork.knife", tint: .orange)
                SummaryCard(title: "XP Level", value: player.xpLevel.map { "\($0)" } ?? "—", systemImage: "star.fill", tint: .yellow)
                SummaryCard(title: "Game Mode", value: player.gameModeLabel, systemImage: "gamecontroller.fill", tint: .blue)
                if let dimension = player.dimension {
                    SummaryCard(title: "Dimension", value: dimension.replacingOccurrences(of: "minecraft:", with: ""), systemImage: "globe", tint: .green)
                }
                if let position = player.position {
                    SummaryCard(title: "Position", value: "\(Int(position.x)), \(Int(position.y)), \(Int(position.z))", systemImage: "location.fill", tint: .purple)
                }
            }

            inventorySection(title: "Hotbar", slots: 0...8, items: player.mainInventory, columns: 9)
            inventorySection(title: "Main Inventory", slots: 9...35, items: player.mainInventory, columns: 9)
            armorAndOffhandSection(items: player.mainInventory)
            inventorySection(title: "Ender Chest", slots: 0...26, items: player.enderChest, columns: 9)
        }
    }

    @ViewBuilder
    private func suspicionSection(_ player: ParsedPlayerData) -> some View {
        if let flag = suspicion(for: player), flag.hasWatchlistedItems {
            let isFlagged = flag.isLowPlaytimeWithValuables
            let tint: Color = isFlagged ? .red : .orange
            VStack(alignment: .leading, spacing: 8) {
                Label(isFlagged ? "Flagged — Worth a Look" : "Holds Watchlisted Items", systemImage: isFlagged ? "exclamationmark.triangle.fill" : "star.fill")
                    .font(.headline)
                    .foregroundStyle(tint)
                Text(isFlagged
                     ? "Only \(formatDuration(flag.playTimeSeconds)) of tracked playtime, but holding: \(itemSummary(flag.watchlistedItems)). Worth checking where this came from — not proof of anything on its own, since vanilla keeps no record of how it was obtained."
                     : "Holding: \(itemSummary(flag.watchlistedItems)).")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if isFlagged, let known = knownPlayer(for: player.uuid) {
                    Button {
                        addToInvestigation(username: known.username, flag: flag)
                    } label: {
                        Label("Add to Investigation", systemImage: "doc.badge.plus")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(14)
            .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(tint.opacity(0.25), lineWidth: 1))
        }
    }

    private func inventorySection(title: String, slots: ClosedRange<Int>, items: [InventoryItemStack], columns: Int) -> some View {
        let bySlot = Dictionary(items.map { ($0.slot, $0) }, uniquingKeysWith: { first, _ in first })
        return VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(56), spacing: 6), count: columns), alignment: .leading, spacing: 6) {
                ForEach(Array(slots), id: \.self) { slot in
                    ItemSlotCell(item: bySlot[slot])
                }
            }
        }
    }

    private func armorAndOffhandSection(items: [InventoryItemStack]) -> some View {
        let bySlot = Dictionary(items.map { ($0.slot, $0) }, uniquingKeysWith: { first, _ in first })
        return VStack(alignment: .leading, spacing: 8) {
            Text("Armor & Offhand").font(.headline)
            HStack(spacing: 6) {
                ForEach([103, 102, 101, 100, -106], id: \.self) { slot in
                    VStack(spacing: 3) {
                        ItemSlotCell(item: bySlot[slot])
                        Text(slot == -106 ? "Offhand" : (InventorySlotSection.armorLabel(slot) ?? ""))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

// MARK: - Item slot cell

private struct ItemSlotCell: View {
    var item: InventoryItemStack?

    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(.quaternary.opacity(0.4))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(item?.isEnchanted == true ? Color.purple.opacity(0.6) : Color.clear, lineWidth: 1.5)
            )
            .overlay(alignment: .center) {
                if let item {
                    Text(item.displayName)
                        .font(.system(size: 8, weight: .medium))
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .padding(3)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if let item, item.count > 1 {
                    Text("\(item.count)")
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 4))
                        .foregroundStyle(.white)
                        .padding(2)
                }
            }
            .frame(width: 56, height: 56)
            .help(tooltip)
    }

    private var tooltip: String {
        guard let item else { return "Empty" }
        var lines = ["\(item.displayName) ×\(item.count)", item.itemID]
        if let damage = item.damage, damage > 0 { lines.append("Damage: \(damage)") }
        if !item.enchantments.isEmpty { lines.append(item.enchantments.joined(separator: ", ")) }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Avatar

struct PlayerAvatarView: View {
    var username: String?
    var size: CGFloat = 32

    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.none)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.2, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: size * 0.2, style: .continuous)
                    .fill(.quaternary)
                    .frame(width: size, height: size)
                    .overlay(Image(systemName: "person.fill").foregroundStyle(.secondary))
            }
        }
        .task(id: username) {
            guard let username, image == nil else { return }
            if let data = await MojangAPI.shared.avatarImageData(username: username) {
                image = NSImage(data: data)
            }
        }
    }
}
