//
//  PlayerDetailView.swift
//  Overseer
//
//  Individual player historical statistics + moderation actions.
//  Reached via NavigationLink(value: player) from PlayerRosterView,
//  PlayerDirectoryView, or a player's context menu (see
//  RootView.navigationDestination(for: Player.self)).
//
//  Action-bar entries that require the player resolvable in-world
//  (gamemode, give item, clear inventory) are disabled while offline;
//  Kick/Ban/Pardon/Tag Admin stay available either way, matching
//  PlayerContextMenuContent's gating.
//

import SwiftUI
import SwiftData

struct PlayerDetailView: View {
    var player: Player
    var rconCoordinator: RCONAutomationCoordinator
    var viewModel: DashboardViewModel

    @Environment(\.modelContext) private var modelContext
    @Query private var moderationEvents: [ModerationEvent]
    @Query private var investigationNotes: [InvestigationNote]

    @State private var showClearConfirm = false
    @State private var showGiveItem = false
    @State private var showTempBan = false
    @State private var moderationAction: ModerationReasonSheet.Action = .kick
    @State private var showModerationSheet = false
    @State private var newInvestigationNoteText = ""

    init(player: Player, rconCoordinator: RCONAutomationCoordinator, viewModel: DashboardViewModel) {
        self.player = player
        self.rconCoordinator = rconCoordinator
        self.viewModel = viewModel
        let username = player.username
        _moderationEvents = Query(
            filter: #Predicate<ModerationEvent> { $0.username == username },
            sort: \ModerationEvent.timestamp,
            order: .reverse
        )
        _investigationNotes = Query(
            filter: #Predicate<InvestigationNote> { $0.username == username },
            sort: \InvestigationNote.timestamp,
            order: .reverse
        )
    }

    private var sortedSessions: [PlayerSession] {
        player.sessions.sorted { $0.startTime > $1.startTime }
    }

    private var statsSummary: PlayerStatsEngine.Summary {
        PlayerStatsEngine.summary(
            sessions: player.sessions,
            firstSeen: player.firstSeen,
            totalPlaytimeSeconds: player.playTimeSeconds
        )
    }

    private var dailyPlaytime: [PlayerStatsEngine.DailyPlaytime] {
        PlayerStatsEngine.dailyPlaytime(sessions: player.sessions)
    }

    private var loginFrequency: [PlayerStatsEngine.HourlyLoginFrequency] {
        PlayerStatsEngine.weeklyLoginFrequency(sessions: player.sessions)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                actionBar
                Divider()
                statsGrid
                milestonesSection
                Divider()
                playtimeChartSection
                Divider()
                activeHoursSection
                Divider()
                sessionsSection
                Divider()
                investigationSection
                Divider()
                moderationSection
            }
            .padding(20)
        }
        .navigationTitle(player.username)
        .sheet(isPresented: $showModerationSheet) {
            ModerationReasonSheet(username: player.username, action: moderationAction, coordinator: rconCoordinator, isPresented: $showModerationSheet)
        }
        .confirmationDialog(
            "Clear \(player.username)'s inventory?",
            isPresented: $showClearConfirm,
            titleVisibility: .visible
        ) {
            Button("Clear Inventory", role: .destructive) {
                Task { await rconCoordinator.clearInventory(player.username) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Permanently removes every item they're carrying.")
        }
        .sheet(isPresented: $showGiveItem) {
            GiveItemSheet(username: player.username, coordinator: rconCoordinator, isPresented: $showGiveItem)
        }
        .sheet(isPresented: $showTempBan) {
            TempBanSheet(username: player.username, coordinator: rconCoordinator, isPresented: $showTempBan)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            avatarView
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    Text(player.username).font(.largeTitle.weight(.bold))
                    if player.investigationStatus != .clear {
                        Label(player.investigationStatus.label, systemImage: player.investigationStatus.systemImage)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(investigationTint(player.investigationStatus))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(investigationTint(player.investigationStatus).opacity(0.12), in: Capsule())
                    }
                }
                StatusIndicator(isOnline: player.isOnline, label: player.isOnline ? "Online now" : "Offline")
                Text("First joined \(player.firstSeen, format: .dateTime.month().day().year())")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Last seen \(player.lastSeen, format: .relative(presentation: .named))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var avatarView: some View {
        if let image = viewModel.avatarImage(for: player) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.none)
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.quaternary)
                .frame(width: 64, height: 64)
                .overlay(Image(systemName: "person.fill").font(.title).foregroundStyle(.secondary))
        }
    }

    // MARK: - Actions

    private var actionBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button {
                    moderationAction = .kick
                    showModerationSheet = true
                } label: {
                    Label("Kick", systemImage: "arrow.right.circle")
                }
                .buttonStyle(.bordered)

                Button {
                    moderationAction = .ban
                    showModerationSheet = true
                } label: {
                    Label("Ban", systemImage: "hand.raised.fill")
                }
                .buttonStyle(.bordered)
                .tint(.red)

                Button {
                    showTempBan = true
                } label: {
                    Label("Temp Ban…", systemImage: "hourglass")
                }
                .buttonStyle(.bordered)
                .tint(.orange)

                actionButton("Pardon", "checkmark.circle") { await rconCoordinator.pardon(player.username) }

                Menu {
                    ForEach(VanillaCommands.GameMode.allCases) { mode in
                        Button(mode.displayName) {
                            Task { await rconCoordinator.setGamemode(mode, for: player.username) }
                        }
                    }
                } label: {
                    Label("Gamemode", systemImage: "person.fill.viewfinder")
                }
                .disabled(!player.isOnline)

                Button {
                    showGiveItem = true
                } label: {
                    Label("Give Item…", systemImage: "shippingbox.fill")
                }
                .buttonStyle(.bordered)
                .disabled(!player.isOnline)

                Button {
                    showClearConfirm = true
                } label: {
                    Label("Clear Inventory", systemImage: "trash.fill")
                }
                .buttonStyle(.bordered)
                .disabled(!player.isOnline)

                actionButton("Tag Admin", "star.fill") { await rconCoordinator.tagAdmin(player.username) }
            }
        }
    }

    private func actionButton(_ title: String, _ systemImage: String, action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            Label(title, systemImage: systemImage)
        }
        .buttonStyle(.bordered)
    }

    // MARK: - Stats

    private var statsGrid: some View {
        let summary = statsSummary
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
            SummaryCard(title: "Total Playtime", value: formatDuration(summary.totalPlaytimeSeconds), systemImage: "clock.fill", tint: .green)
            SummaryCard(title: "Sessions", value: "\(summary.closedSessionCount)", systemImage: "arrow.left.arrow.right", tint: .blue)
            SummaryCard(title: "Avg Session", value: formatDuration(summary.averageSessionSeconds), systemImage: "timer", tint: .purple)
            SummaryCard(title: "Longest Session", value: formatDuration(summary.longestSessionSeconds), systemImage: "flame.fill", tint: .orange)
            SummaryCard(title: "Sessions / Week", value: String(format: "%.1f", summary.averageSessionsPerWeek), systemImage: "calendar", tint: .pink)
        }
    }

    private var milestonesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Playtime Milestones").font(.headline)
            HStack(spacing: 14) {
                ForEach(MilestoneEvaluator.thresholdsHours, id: \.self) { hours in
                    milestoneBadge(hours: hours)
                }
            }
        }
    }

    private func milestoneBadge(hours: Int) -> some View {
        let achieved = player.awardedMilestoneHours.contains(hours)
        return VStack(spacing: 4) {
            Image(systemName: achieved ? "trophy.fill" : "trophy")
                .font(.title2)
                .foregroundStyle(achieved ? .yellow : .secondary)
            Text("\(hours)h")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(width: 48)
    }

    // MARK: - Chart

    private var playtimeChartSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Daily Playtime (Last 30 Days)").font(.headline)
            PlayerDailyPlaytimeChart(points: dailyPlaytime)
                .frame(height: 160)
        }
    }

    private var activeHoursSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Weekly Login-Time Fingerprint").font(.headline)
            Text("When this player tends to be online, Poland time — a rough, IP-free proxy for what timezone they're likely in.")
                .font(.caption)
                .foregroundStyle(.secondary)
            PlayerActiveHoursHeatmap(matrix: loginFrequency)
                .frame(height: 200)
        }
    }

    // MARK: - Sessions

    private var sessionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent Sessions").font(.headline)
            if sortedSessions.isEmpty {
                Text("No sessions recorded yet.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Table(Array(sortedSessions.prefix(25))) {
                    TableColumn("Start") { session in
                        Text(session.startTime, format: .dateTime.month().day().hour().minute())
                    }
                    TableColumn("End") { session in
                        if let endTime = session.endTime {
                            Text(endTime, format: .dateTime.month().day().hour().minute())
                        } else {
                            Text("Online now").foregroundStyle(.green)
                        }
                    }
                    TableColumn("Duration") { session in
                        Text(formatDuration(session.durationSeconds ?? Date().timeIntervalSince(session.startTime)))
                    }
                }
                .frame(height: min(CGFloat(sortedSessions.count) * 28 + 40, 320))
            }
        }
    }

    // MARK: - Notes

    /// Purely local; never sent over RCON, and nothing here implies proof
    /// of anything — vanilla keeps no block-change log, so this is a
    /// triage/tracking tool, not a verdict. Three parts: a status (set
    /// here, or bumped automatically by "Add to Investigation" from the
    /// Inventory Analyzer's Suspicious Inventory flag), a single pinned
    /// free-text summary (`player.notes`, saved on every edit like the
    /// rest of the app's toggle-style bindings), and an append-only
    /// timestamped evidence log fed by that same "Add to Investigation"
    /// action or entered by hand.
    private var investigationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Investigation").font(.headline)

            Picker("Status", selection: Binding(
                get: { player.investigationStatus },
                set: { player.investigationStatus = $0; try? modelContext.save() }
            )) {
                ForEach(InvestigationStatus.allCases) { status in
                    Label(status.label, systemImage: status.systemImage).tag(status)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 420)

            Text("Pinned Summary").font(.caption.weight(.medium)).foregroundStyle(.secondary)
            TextEditor(text: Binding(
                get: { player.notes },
                set: { player.notes = $0; try? modelContext.save() }
            ))
            .font(.callout)
            .frame(height: 60)
            .padding(6)
            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.quaternary, lineWidth: 1))

            Text("Evidence Log").font(.caption.weight(.medium)).foregroundStyle(.secondary)
            evidenceLog

            HStack(spacing: 8) {
                TextField("Add a finding…", text: $newInvestigationNoteText)
                    .textFieldStyle(.roundedBorder)
                Button("Add") { addInvestigationNote() }
                    .buttonStyle(.bordered)
                    .disabled(newInvestigationNoteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    @ViewBuilder
    private var evidenceLog: some View {
        if investigationNotes.isEmpty {
            Text("No findings logged yet.").font(.caption).foregroundStyle(.secondary)
        } else {
            VStack(spacing: 0) {
                ForEach(investigationNotes) { note in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: evidenceSourceIcon(note.source))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 16)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(note.text).font(.callout)
                            Text(note.timestamp, format: .relative(presentation: .named))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 6)
                    if note.id != investigationNotes.last?.id { Divider() }
                }
            }
            .padding(10)
            .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private func evidenceSourceIcon(_ source: String) -> String {
        switch source {
        case "inventory": return "shippingbox.fill"
        case "perf-diff": return "arrow.left.arrow.right"
        default: return "pencil"
        }
    }

    private func addInvestigationNote() {
        let trimmed = newInvestigationNoteText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        modelContext.insert(InvestigationNote(username: player.username, text: trimmed, source: "manual"))
        try? modelContext.save()
        newInvestigationNoteText = ""
    }

    // MARK: - Moderation log

    private var moderationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent Actions").font(.headline)
            if moderationEvents.isEmpty {
                Text("No moderation actions recorded for this player yet.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(moderationEvents.prefix(20)) { event in
                        HStack {
                            Image(systemName: event.kind.systemImage)
                                .foregroundStyle(.secondary)
                                .frame(width: 20)
                            Text(event.kind.label)
                            if !event.detail.isEmpty {
                                Text("— \(event.detail)")
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(event.timestamp, format: .relative(presentation: .named))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .font(.callout)
                        .padding(.vertical, 4)
                        if event.id != moderationEvents.prefix(20).last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
    }
}

/// Shared by PlayerDetailView (header badge, PlayerDirectoryView, and
/// PlayerRosterView row badges) so the color for a given
/// InvestigationStatus never drifts between the three places it's shown.
func investigationTint(_ status: InvestigationStatus) -> Color {
    switch status {
    case .clear: return .secondary
    case .watching: return .yellow
    case .investigating: return .orange
    case .confirmed: return .red
    }
}

/// Shared by PlayerDetailView (session durations) and its stats grid —
/// "12h 34m" above an hour, "34m 12s" below.
func formatDuration(_ seconds: Double) -> String {
    let formatter = DateComponentsFormatter()
    formatter.allowedUnits = seconds >= 3600 ? [.hour, .minute] : [.minute, .second]
    formatter.unitsStyle = .abbreviated
    formatter.maximumUnitCount = 2
    formatter.zeroFormattingBehavior = .dropLeading
    return formatter.string(from: max(0, seconds)) ?? "0m"
}
