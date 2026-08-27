//
//  SettingsView.swift
//  Overseer
//
//  Ships with every field blank — fill in your own server's details.
//  Changing host/port/poll interval here pushes straight through to
//  the live PollingCoordinator.
//
//  Each Form section is its own computed property, and the onChange
//  wiring below is split across two ViewModifiers rather than one long
//  chain on `body` — both purely to keep the type-checker's per-
//  expression workload small; a single Form with every section inline
//  plus a 20-deep .onChange chain was slow enough to trip Swift's
//  "unable to type-check in reasonable time" limit.
//

import SwiftUI

struct SettingsView: View {
    @Bindable var settings: AppSettings
    var coordinator: PollingCoordinator
    var rconCoordinator: RCONAutomationCoordinator
    var sftpCoordinator: SFTPSyncCoordinator
    var autoUpdaterCoordinator: AutoUpdaterCoordinator

    @State private var portText: String = ""
    @State private var rconPortText: String = ""
    @State private var sftpPortText: String = ""
    @State private var showRconPassword = false
    @State private var showSftpPassword = false
    @State private var showAutoUpdaterConfirm = false

    var body: some View {
        Form {
            targetServerSection
            pollingSection
            actionsSection
            rconSection
            leaderboardSection
            rconAutomationSection
            sftpSyncSection
            autoUpdaterSection
            monitoringSection
        }
        .formStyle(.grouped)
        .frame(minWidth: 420, minHeight: 360)
        .modifier(CoreChangeHandlers(settings: settings, coordinator: coordinator, rconCoordinator: rconCoordinator))
        .modifier(MonitoringChangeHandlers(settings: settings, rconCoordinator: rconCoordinator, sftpCoordinator: sftpCoordinator))
        .modifier(AutoUpdaterChangeHandlers(settings: settings, autoUpdaterCoordinator: autoUpdaterCoordinator))
        .confirmationDialog(
            "Enable Auto Updater?",
            isPresented: $showAutoUpdaterConfirm,
            titleVisibility: .visible
        ) {
            Button("Enable Auto Updater", role: .destructive) {
                settings.autoUpdaterEnabled = true
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Every \(Int(settings.autoUpdaterIntervalMinutes)) minutes, this checks Mojang for a newer snapshot than what's running. If one exists, it downloads it, uploads it over SFTP, deletes the current server.jar, replaces it, and stops the server via RCON — fully unattended, with no confirmation step and no backup of the old jar. Your hosting panel's cron job is expected to bring the server back up. A newer snapshot may already be available right now, which would trigger this immediately.")
        }
    }

    // MARK: - Sections

    private var targetServerSection: some View {
        Section("Target Server") {
            TextField("Host / IP", text: $settings.host)
                .textFieldStyle(.roundedBorder)
            Toggle("Fall back to DNS if unreachable", isOn: $settings.useFallbackDNS)
            if settings.useFallbackDNS {
                TextField("Fallback hostname", text: $settings.fallbackHost)
                    .textFieldStyle(.roundedBorder)
            }
            TextField("Port", text: $portText)
                .textFieldStyle(.roundedBorder)
                .onAppear { portText = String(settings.port) }
                .onChange(of: portText) { _, newValue in
                    if let value = UInt16(newValue.filter(\.isNumber)) {
                        settings.port = value
                    }
                }
            Text("Enter your server's IP or hostname above. Standard Java Edition port is 25565 — only change this if your server uses a custom query/ping port.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var pollingSection: some View {
        Section("Polling") {
            Stepper(value: $settings.pollInterval, in: 10...300, step: 5) {
                Text("Poll every \(Int(settings.pollInterval))s")
            }
            Toggle("Auto-start monitoring on launch", isOn: $settings.autoStartOnLaunch)
        }
    }

    private var actionsSection: some View {
        Section {
            HStack {
                Button(coordinator.isPolling ? "Stop Monitoring" : "Start Monitoring") {
                    if coordinator.isPolling {
                        coordinator.stop()
                    } else {
                        applyAndStart()
                    }
                }
                Spacer()
                Button("Restore Defaults", role: .destructive) {
                    settings.restoreDefaults()
                    portText = String(settings.port)
                    rconPortText = String(settings.rconPort)
                    applyAndStart()
                }
            }
        }
    }

    private var rconSection: some View {
        Section("RCON") {
            TextField("RCON Host / IP", text: $settings.rconHost)
                .textFieldStyle(.roundedBorder)
            TextField("RCON Port", text: $rconPortText)
                .textFieldStyle(.roundedBorder)
                .onAppear { rconPortText = String(settings.rconPort) }
                .onChange(of: rconPortText) { _, newValue in
                    if let value = UInt16(newValue.filter(\.isNumber)) {
                        settings.rconPort = value
                    }
                }
            HStack {
                if showRconPassword {
                    TextField("Password", text: $settings.rconPassword)
                } else {
                    SecureField("Password", text: $settings.rconPassword)
                }
                Button(showRconPassword ? "Hide" : "Show") {
                    showRconPassword.toggle()
                }
                .buttonStyle(.borderless)
            }
            .textFieldStyle(.roundedBorder)
            Text("Distinct from the Query port (\(settings.port)). Stored in the Keychain, never in preferences.")
                .font(.caption)
                .foregroundStyle(.secondary)
            StatusIndicator(isOnline: rconCoordinator.isConnected, label: rconCoordinator.isConnected ? "RCON Connected" : "RCON Disconnected")
        }
    }

    private var leaderboardSection: some View {
        Section("Leaderboards") {
            TextField("Excluded usernames (comma-separated)", text: $settings.excludedLeaderboardUsernamesRaw)
                .textFieldStyle(.roundedBorder)
            Text("Hidden from leaderboards, the dashboard's Top Playtime list, and the average-playtime stat — so the server owner/admin's own hours online don't skew what's meant to reflect the player community.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var rconAutomationSection: some View {
        Section("RCON Automation") {
            Toggle("Enable automated triggers (milestones, ad windows, Happy Hour)", isOn: $settings.rconAutomationEnabled)
            Stepper(value: $settings.rconTickPollInterval, in: 60...300, step: 30) {
                Text("Poll /tick query and /list every \(Int(settings.rconTickPollInterval))s")
            }
        }
    }

    private var sftpSyncSection: some View {
        Section("SFTP Sync") {
            Toggle("Automate log/playtime/inventory/perf-report imports over SFTP", isOn: $settings.sftpEnabled)
            Text("Automates the manual \"Select Folder…\" import in Location, Playtime Importer, Inventory Analyzer, and Performance. Manual import always stays available as a fallback. Entirely separate from RCON/GS4 — its own connection, its own failure domain.")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("SFTP Host", text: $settings.sftpHost)
                .textFieldStyle(.roundedBorder)
            TextField("SFTP Port", text: $sftpPortText)
                .textFieldStyle(.roundedBorder)
                .onAppear { sftpPortText = String(settings.sftpPort) }
                .onChange(of: sftpPortText) { _, newValue in
                    if let value = Int(newValue.filter(\.isNumber)) {
                        settings.sftpPort = value
                    }
                }
            TextField("Username", text: $settings.sftpUsername)
                .textFieldStyle(.roundedBorder)
            HStack {
                if showSftpPassword {
                    TextField("Password", text: $settings.sftpPassword)
                } else {
                    SecureField("Password", text: $settings.sftpPassword)
                }
                Button(showSftpPassword ? "Hide" : "Show") {
                    showSftpPassword.toggle()
                }
                .buttonStyle(.borderless)
            }
            .textFieldStyle(.roundedBorder)
            Text("Stored in the Keychain, never in preferences — same as the RCON password.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Stepper(value: $settings.sftpSyncIntervalMinutes, in: 5...120, step: 5) {
                Text("Sync every \(Int(settings.sftpSyncIntervalMinutes)) minutes")
            }

            Toggle("Location (logs/)", isOn: $settings.sftpSyncLocationEnabled)
            Toggle("Playtime (world/players/stats)", isOn: $settings.sftpSyncPlaytimeEnabled)
            Toggle("Inventory (world/players/data)", isOn: $settings.sftpSyncInventoryEnabled)
            Toggle("Performance (debug/profiling)", isOn: $settings.sftpSyncPerformanceEnabled)
            Toggle("World Map (world/region)", isOn: $settings.sftpSyncWorldMapEnabled)

            sftpSyncNowRow
            sftpSyncLogDisclosure
        }
    }

    private var sftpSyncNowRow: some View {
        HStack {
            Button("Sync Now") {
                Task { await sftpCoordinator.syncNow() }
            }
            .buttonStyle(.bordered)
            .disabled(sftpCoordinator.isSyncing)
            if sftpCoordinator.isSyncing {
                ProgressView().controlSize(.small)
            }
            Spacer()
            if let lastSync = sftpCoordinator.lastSyncDate {
                Text("Last synced \(lastSync, format: .relative(presentation: .named))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var sftpSyncLogDisclosure: some View {
        if !sftpCoordinator.syncLog.isEmpty {
            DisclosureGroup("Sync Log") {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(sftpCoordinator.syncLog.suffix(20).reversed()) { entry in
                        Text("\(entry.timestamp.formatted(.dateTime.hour().minute())) — \(entry.text)")
                            .font(.caption)
                            .foregroundStyle(entry.isError ? .red : .secondary)
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    private var autoUpdaterSection: some View {
        Section("Auto Updater") {
            Toggle("Auto-detect, download, and deploy new snapshots", isOn: Binding(
                get: { settings.autoUpdaterEnabled },
                set: { newValue in
                    if newValue {
                        showAutoUpdaterConfirm = true
                    } else {
                        settings.autoUpdaterEnabled = false
                    }
                }
            ))
            Stepper(value: $settings.autoUpdaterIntervalMinutes, in: 1...120, step: 1) {
                Text("Check every \(Int(settings.autoUpdaterIntervalMinutes)) minute\(Int(settings.autoUpdaterIntervalMinutes) == 1 ? "" : "s")")
            }
            Text("Reuses the SFTP connection configured above. When a newer snapshot than the live-reported running version exists: downloads it from Mojang, uploads it, deletes the old server.jar, replaces it, then sends /stop — no restart, no backup, no confirmation. Your hosting panel's cron is what actually brings the server back up.")
                .font(.caption)
                .foregroundStyle(.secondary)

            autoUpdaterStatusRow
            autoUpdaterLogDisclosure
        }
    }

    private var autoUpdaterStatusRow: some View {
        HStack {
            Button("Check Now") {
                Task { await autoUpdaterCoordinator.checkForUpdate() }
            }
            .buttonStyle(.bordered)
            .disabled(autoUpdaterCoordinator.isChecking)
            if autoUpdaterCoordinator.isChecking {
                ProgressView().controlSize(.small)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if let latest = autoUpdaterCoordinator.lastKnownLatestVersion {
                    Text("Latest known: \(latest)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let checked = autoUpdaterCoordinator.lastCheckedAt {
                    Text("Checked \(checked, format: .relative(presentation: .named))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if let pending = autoUpdaterCoordinator.pendingDeployVersion {
                    Text("Waiting for \(pending) to come back online…")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    @ViewBuilder
    private var autoUpdaterLogDisclosure: some View {
        if !autoUpdaterCoordinator.updateLog.isEmpty {
            DisclosureGroup("Update Log") {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(autoUpdaterCoordinator.updateLog.suffix(20).reversed()) { entry in
                        Text("\(entry.timestamp.formatted(.dateTime.hour().minute())) — \(entry.text)")
                            .font(.caption)
                            .foregroundStyle(entry.isError ? .red : .secondary)
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    private var monitoringSection: some View {
        Section("Monitoring") {
            Toggle("Track player positions (World Map breadcrumbs)", isOn: $settings.positionTrackingEnabled)
            Stepper(value: $settings.positionTrackingIntervalMinutes, in: 1...60, step: 1) {
                Text("Record a position every \(Int(settings.positionTrackingIntervalMinutes)) minute\(Int(settings.positionTrackingIntervalMinutes) == 1 ? "" : "s")")
            }
            Text("One /data get entity query per online player, on its own schedule — independent of the RCON poll interval above.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle("Watch for config drift (gamerules, difficulty)", isOn: $settings.configWatchdogEnabled)
            Text("Checks mobGriefing, keepInventory, doDaylightCycle, doMobSpawning, doFireTick, and difficulty every 30 minutes and flags any unexpected change.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Actions

    private func applyAndStart() {
        coordinator.updateTarget(
            host: settings.host,
            fallbackHost: settings.useFallbackDNS ? settings.fallbackHost : nil,
            port: settings.port
        )
        coordinator.updatePollInterval(settings.pollInterval)
        coordinator.start()
    }
}

/// Host/RCON target sync — split out from MonitoringChangeHandlers
/// purely to keep each ViewModifier's own onChange chain short enough
/// for the type-checker (see this file's header comment).
private struct CoreChangeHandlers: ViewModifier {
    var settings: AppSettings
    var coordinator: PollingCoordinator
    var rconCoordinator: RCONAutomationCoordinator

    func body(content: Content) -> some View {
        content
            .onChange(of: settings.host) { _, _ in applyTarget() }
            .onChange(of: settings.fallbackHost) { _, _ in applyTarget() }
            .onChange(of: settings.useFallbackDNS) { _, _ in applyTarget() }
            .onChange(of: settings.port) { _, _ in applyTarget() }
            .onChange(of: settings.pollInterval) { _, newValue in coordinator.updatePollInterval(newValue) }
            .onChange(of: settings.rconHost) { _, _ in applyRconTarget() }
            .onChange(of: settings.rconPort) { _, _ in applyRconTarget() }
            .onChange(of: settings.rconPassword) { _, _ in applyRconTarget() }
            .onChange(of: settings.rconAutomationEnabled) { _, newValue in rconCoordinator.automationEnabled = newValue }
            .onChange(of: settings.rconTickPollInterval) { _, newValue in rconCoordinator.updateTickPollInterval(newValue) }
    }

    private func applyTarget() {
        coordinator.updateTarget(
            host: settings.host,
            fallbackHost: settings.useFallbackDNS ? settings.fallbackHost : nil,
            port: settings.port
        )
    }

    private func applyRconTarget() {
        rconCoordinator.updateConfiguration(settings.rconConfiguration)
    }
}

/// Monitoring toggles (position tracking, config watchdog) + every SFTP
/// sync setting — see this file's header comment for why this is split
/// from CoreChangeHandlers rather than one long chain.
private struct MonitoringChangeHandlers: ViewModifier {
    var settings: AppSettings
    var rconCoordinator: RCONAutomationCoordinator
    var sftpCoordinator: SFTPSyncCoordinator

    func body(content: Content) -> some View {
        content
            .onChange(of: settings.positionTrackingEnabled) { _, newValue in rconCoordinator.positionTrackingEnabled = newValue }
            .onChange(of: settings.positionTrackingIntervalMinutes) { _, newValue in rconCoordinator.positionTrackingIntervalMinutes = newValue }
            .onChange(of: settings.configWatchdogEnabled) { _, newValue in rconCoordinator.configWatchdogEnabled = newValue }
            .onChange(of: settings.sftpEnabled) { _, newValue in
                if newValue { sftpCoordinator.startScheduler() } else { sftpCoordinator.stopScheduler() }
            }
            .onChange(of: settings.sftpHost) { _, newValue in sftpCoordinator.host = newValue }
            .onChange(of: settings.sftpPort) { _, newValue in sftpCoordinator.port = newValue }
            .onChange(of: settings.sftpUsername) { _, newValue in sftpCoordinator.username = newValue }
            .onChange(of: settings.sftpPassword) { _, newValue in sftpCoordinator.password = newValue }
            .modifier(SFTPFeatureToggleChangeHandlers(settings: settings, sftpCoordinator: sftpCoordinator))
    }
}

private struct SFTPFeatureToggleChangeHandlers: ViewModifier {
    var settings: AppSettings
    var sftpCoordinator: SFTPSyncCoordinator

    func body(content: Content) -> some View {
        content
            .onChange(of: settings.sftpSyncIntervalMinutes) { _, newValue in sftpCoordinator.syncIntervalMinutes = newValue }
            .onChange(of: settings.sftpSyncLocationEnabled) { _, newValue in sftpCoordinator.syncLocationEnabled = newValue }
            .onChange(of: settings.sftpSyncPlaytimeEnabled) { _, newValue in sftpCoordinator.syncPlaytimeEnabled = newValue }
            .onChange(of: settings.sftpSyncInventoryEnabled) { _, newValue in sftpCoordinator.syncInventoryEnabled = newValue }
            .onChange(of: settings.sftpSyncPerformanceEnabled) { _, newValue in sftpCoordinator.syncPerformanceEnabled = newValue }
            .onChange(of: settings.sftpSyncWorldMapEnabled) { _, newValue in sftpCoordinator.syncWorldMapEnabled = newValue }
    }
}

/// Auto Updater toggle/interval + credentials — mirrors whatever SFTP
/// connection details are configured above (see sftpSyncSection), since
/// this deploys to the same server over the same protocol.
private struct AutoUpdaterChangeHandlers: ViewModifier {
    var settings: AppSettings
    var autoUpdaterCoordinator: AutoUpdaterCoordinator

    func body(content: Content) -> some View {
        content
            .onChange(of: settings.autoUpdaterEnabled) { _, newValue in autoUpdaterCoordinator.enabled = newValue }
            .onChange(of: settings.autoUpdaterIntervalMinutes) { _, newValue in autoUpdaterCoordinator.checkIntervalMinutes = newValue }
            .onChange(of: settings.sftpHost) { _, newValue in autoUpdaterCoordinator.host = newValue }
            .onChange(of: settings.sftpPort) { _, newValue in autoUpdaterCoordinator.port = newValue }
            .onChange(of: settings.sftpUsername) { _, newValue in autoUpdaterCoordinator.username = newValue }
            .onChange(of: settings.sftpPassword) { _, newValue in autoUpdaterCoordinator.password = newValue }
    }
}
