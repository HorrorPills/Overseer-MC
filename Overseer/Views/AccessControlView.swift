//
//  AccessControlView.swift
//  Overseer
//
//  Bans, temp-bans, and the whitelist in one place — previously only
//  reachable by typing `/banlist` / `/whitelist list` into the console
//  and reading raw text. Banned/whitelisted rosters are fetched
//  on-demand over RCON (refreshBanList/refreshWhitelist) rather than
//  polled, since they change far less often than the online roster;
//  temp-bans are app-tracked (see TempBan) and read straight from
//  SwiftData, so that list is always current.
//

import SwiftUI
import SwiftData

struct AccessControlView: View {
    var rconCoordinator: RCONAutomationCoordinator

    @Query(filter: #Predicate<TempBan> { !$0.pardoned }, sort: \TempBan.expiresAt) private var activeTempBans: [TempBan]
    @Query(sort: \ConfigChangeEvent.timestamp, order: .reverse) private var configChanges: [ConfigChangeEvent]

    @State private var newBanUsername = ""
    @State private var newBanReason = ""
    @State private var tempBanDurationMinutes: Double = 60
    @State private var newWhitelistUsername = ""
    @State private var isRefreshing = false

    private static let durationPresets: [(label: String, minutes: Double)] = [
        ("10 minutes", 10), ("30 minutes", 30), ("1 hour", 60),
        ("6 hours", 360), ("1 day", 1440), ("3 days", 4320), ("7 days", 10080)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                banSection
                Divider()
                tempBanSection
                Divider()
                whitelistSection
                Divider()
                configWatchdogSection
            }
            .padding(20)
        }
        .navigationTitle("Access Control")
        .toolbar {
            ToolbarItem {
                Button {
                    Task { await refreshAll() }
                } label: {
                    if isRefreshing {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(isRefreshing)
            }
        }
        .task { await refreshAll() }
    }

    private func refreshAll() async {
        isRefreshing = true
        await rconCoordinator.refreshBanList()
        await rconCoordinator.refreshWhitelist()
        isRefreshing = false
    }

    // MARK: - Bans

    private var banSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Banned Players").font(.headline)
            HStack(spacing: 10) {
                TextField("Username", text: $newBanUsername)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)
                TextField("Reason (optional)", text: $newBanReason)
                    .textFieldStyle(.roundedBorder)
                Button("Ban") {
                    Task {
                        await rconCoordinator.ban(newBanUsername, reason: newBanReason.isEmpty ? nil : newBanReason)
                        newBanUsername = ""; newBanReason = ""
                    }
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .disabled(newBanUsername.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if rconCoordinator.bannedPlayers.isEmpty {
                Text("No banned players.").font(.callout).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(rconCoordinator.bannedPlayers) { entry in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.username).font(.body.weight(.medium))
                                Text("Banned by \(entry.bannedBy)\(entry.reason.isEmpty ? "" : ": \(entry.reason)")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Pardon") {
                                Task { await rconCoordinator.pardon(entry.username) }
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(.vertical, 4)
                        Divider()
                    }
                }
            }
        }
    }

    // MARK: - Temp bans

    private var tempBanSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Temporary Bans").font(.headline)
            Text("App-tracked — vanilla bans don't expire on their own, so this auto-/pardons once the timer runs out.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                TextField("Username", text: $newBanUsername)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)
                Picker("Duration", selection: $tempBanDurationMinutes) {
                    ForEach(Self.durationPresets, id: \.minutes) { preset in
                        Text(preset.label).tag(preset.minutes)
                    }
                }
                .frame(width: 140)
                .labelsHidden()
                Button("Temp Ban") {
                    Task {
                        await rconCoordinator.tempBan(newBanUsername, reason: newBanReason.isEmpty ? nil : newBanReason, durationMinutes: tempBanDurationMinutes)
                        newBanUsername = ""; newBanReason = ""
                    }
                }
                .buttonStyle(.bordered)
                .tint(.orange)
                .disabled(newBanUsername.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if activeTempBans.isEmpty {
                Text("No active temp-bans.").font(.callout).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(activeTempBans) { ban in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(ban.username).font(.body.weight(.medium))
                                Text("Expires \(ban.expiresAt, format: .relative(presentation: .named))\(ban.reason.isEmpty ? "" : " — \(ban.reason)")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Pardon Now") {
                                Task { await rconCoordinator.pardonTempBan(ban) }
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(.vertical, 4)
                        Divider()
                    }
                }
            }
        }
    }

    // MARK: - Whitelist

    private var whitelistSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Whitelisted Players").font(.headline)
            HStack(spacing: 10) {
                TextField("Username", text: $newWhitelistUsername)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)
                Button("Add") {
                    Task {
                        await rconCoordinator.whitelistAdd(newWhitelistUsername)
                        newWhitelistUsername = ""
                    }
                }
                .buttonStyle(.bordered)
                .disabled(newWhitelistUsername.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if rconCoordinator.whitelistedPlayers.isEmpty {
                Text("No whitelisted players.").font(.callout).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(rconCoordinator.whitelistedPlayers, id: \.self) { username in
                        HStack {
                            Text(username).font(.body.weight(.medium))
                            Spacer()
                            Button("Remove", role: .destructive) {
                                Task { await rconCoordinator.whitelistRemove(username) }
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(.vertical, 4)
                        Divider()
                    }
                }
            }
        }
    }

    // MARK: - Config drift watchdog

    private var configWatchdogSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Config Watchdog").font(.headline)
            Text("Checks mobGriefing, keepInventory, doDaylightCycle, doMobSpawning, doFireTick, and difficulty every 30 minutes. On a vanilla server these are as consequential as a griefing incident if someone with console/OP access flips one — this is the paper trail. Toggle it off in Settings.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if configChanges.isEmpty {
                Text("No config changes detected since monitoring started.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(configChanges.prefix(20)) { event in
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(event.key).font(.body.weight(.medium))
                                Text("\(event.oldValue) → \(event.newValue)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(event.timestamp, format: .relative(presentation: .named))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                        if event.id != configChanges.prefix(20).last?.id { Divider() }
                    }
                }
            }
        }
    }
}
