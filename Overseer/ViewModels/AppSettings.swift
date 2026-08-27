//
//  AppSettings.swift
//  Overseer
//
//  UserDefaults-backed app configuration. Ships with every connection
//  field blank — fill in your own server's host/IP, ports, and
//  credentials in Settings before use. Feeds both
//  `ServerQueryEngine.Configuration` (via PollingCoordinator) and the
//  Settings view.
//

import Foundation
import Observation

@MainActor
@Observable
final class AppSettings {
    private enum Keys {
        static let host = "settings.host"
        static let fallbackHost = "settings.fallbackHost"
        static let port = "settings.port"
        static let pollInterval = "settings.pollInterval"
        static let autoStart = "settings.autoStart"
        static let useFallbackDNS = "settings.useFallbackDNS"
        static let rconHost = "settings.rconHost"
        static let rconPort = "settings.rconPort"
        static let rconTickPollInterval = "settings.rconTickPollInterval"
        static let rconAutomationEnabled = "settings.rconAutomationEnabled"
        static let entityCleanupEnabled = "settings.entityCleanupEnabled"
        static let entityCleanupIntervalMinutes = "settings.entityCleanupIntervalMinutes"
        static let entityCleanupClearItems = "settings.entityCleanupClearItems"
        static let entityCleanupClearXPOrbs = "settings.entityCleanupClearXPOrbs"
        static let entityCleanupClearProjectiles = "settings.entityCleanupClearProjectiles"
        static let entityCleanupClearTNT = "settings.entityCleanupClearTNT"
        static let entityCleanupClearHostileMobs = "settings.entityCleanupClearHostileMobs"
        static let entityCleanupClearEnderPearls = "settings.entityCleanupClearEnderPearls"
        static let entityCleanupWarnBeforeClear = "settings.entityCleanupWarnBeforeClear"
        static let entityCleanupWarnLeadSeconds = "settings.entityCleanupWarnLeadSeconds"
        static let entityCleanupWarnMessage = "settings.entityCleanupWarnMessage"
        static let excludedLeaderboardUsernames = "settings.excludedLeaderboardUsernames"
        static let positionTrackingEnabled = "settings.positionTrackingEnabled"
        static let configWatchdogEnabled = "settings.configWatchdogEnabled"
        static let sftpEnabled = "settings.sftpEnabled"
        static let sftpHost = "settings.sftpHost"
        static let sftpPort = "settings.sftpPort"
        static let sftpUsername = "settings.sftpUsername"
        static let sftpSyncIntervalMinutes = "settings.sftpSyncIntervalMinutes"
        static let sftpSyncLocationEnabled = "settings.sftpSyncLocationEnabled"
        static let sftpSyncPlaytimeEnabled = "settings.sftpSyncPlaytimeEnabled"
        static let sftpSyncInventoryEnabled = "settings.sftpSyncInventoryEnabled"
        static let sftpSyncPerformanceEnabled = "settings.sftpSyncPerformanceEnabled"
        static let sftpSyncWorldMapEnabled = "settings.sftpSyncWorldMapEnabled"
        static let sftpLogsBackfillCompleted = "settings.sftpLogsBackfillCompleted"
        static let positionTrackingIntervalMinutes = "settings.positionTrackingIntervalMinutes"
        static let autoUpdaterEnabled = "settings.autoUpdaterEnabled"
        static let autoUpdaterIntervalMinutes = "settings.autoUpdaterIntervalMinutes"
    }

    /// Account name under which the RCON password lives in the
    /// Keychain — never in UserDefaults. See KeychainStore.swift.
    private static let rconPasswordKeychainAccount = "rcon-password"

    /// Same reasoning as the RCON password: full filesystem access to
    /// the server, never written to UserDefaults' plaintext plist.
    private static let sftpPasswordKeychainAccount = "sftp-password"

    private let defaults: UserDefaults

    var host: String {
        didSet { defaults.set(host, forKey: Keys.host) }
    }

    var fallbackHost: String {
        didSet { defaults.set(fallbackHost, forKey: Keys.fallbackHost) }
    }

    /// Whether to fall back to resolving `fallbackHost` via DNS when the
    /// primary (IP) target is unreachable.
    var useFallbackDNS: Bool {
        didSet { defaults.set(useFallbackDNS, forKey: Keys.useFallbackDNS) }
    }

    var port: UInt16 {
        didSet { defaults.set(Int(port), forKey: Keys.port) }
    }

    var pollInterval: TimeInterval {
        didSet { defaults.set(pollInterval, forKey: Keys.pollInterval) }
    }

    var autoStartOnLaunch: Bool {
        didSet { defaults.set(autoStartOnLaunch, forKey: Keys.autoStart) }
    }

    // MARK: - RCON

    var rconHost: String {
        didSet { defaults.set(rconHost, forKey: Keys.rconHost) }
    }

    var rconPort: UInt16 {
        didSet { defaults.set(Int(rconPort), forKey: Keys.rconPort) }
    }

    /// Backed by the Keychain, not UserDefaults — see KeychainStore.
    var rconPassword: String {
        didSet { KeychainStore.save(password: rconPassword, account: Self.rconPasswordKeychainAccount) }
    }

    var rconTickPollInterval: TimeInterval {
        didSet { defaults.set(rconTickPollInterval, forKey: Keys.rconTickPollInterval) }
    }

    /// Master switch for automated milestone/ad-window/Happy Hour RCON
    /// triggers. Console + quick actions stay available regardless.
    var rconAutomationEnabled: Bool {
        didSet { defaults.set(rconAutomationEnabled, forKey: Keys.rconAutomationEnabled) }
    }

    // MARK: - Entity cleanup ("clear lag")

    var entityCleanupEnabled: Bool {
        didSet { defaults.set(entityCleanupEnabled, forKey: Keys.entityCleanupEnabled) }
    }

    var entityCleanupIntervalMinutes: Double {
        didSet { defaults.set(entityCleanupIntervalMinutes, forKey: Keys.entityCleanupIntervalMinutes) }
    }

    var entityCleanupClearItems: Bool {
        didSet { defaults.set(entityCleanupClearItems, forKey: Keys.entityCleanupClearItems) }
    }

    var entityCleanupClearXPOrbs: Bool {
        didSet { defaults.set(entityCleanupClearXPOrbs, forKey: Keys.entityCleanupClearXPOrbs) }
    }

    var entityCleanupClearProjectiles: Bool {
        didSet { defaults.set(entityCleanupClearProjectiles, forKey: Keys.entityCleanupClearProjectiles) }
    }

    var entityCleanupClearTNT: Bool {
        didSet { defaults.set(entityCleanupClearTNT, forKey: Keys.entityCleanupClearTNT) }
    }

    var entityCleanupClearHostileMobs: Bool {
        didSet { defaults.set(entityCleanupClearHostileMobs, forKey: Keys.entityCleanupClearHostileMobs) }
    }

    /// Off by default — see LagClearCategory.enderPearls' riskNote.
    /// Exists specifically so an admin can override that default if
    /// pearls are genuinely piling up on their server.
    var entityCleanupClearEnderPearls: Bool {
        didSet { defaults.set(entityCleanupClearEnderPearls, forKey: Keys.entityCleanupClearEnderPearls) }
    }

    var entityCleanupWarnBeforeClear: Bool {
        didSet { defaults.set(entityCleanupWarnBeforeClear, forKey: Keys.entityCleanupWarnBeforeClear) }
    }

    var entityCleanupWarnLeadSeconds: Double {
        didSet { defaults.set(entityCleanupWarnLeadSeconds, forKey: Keys.entityCleanupWarnLeadSeconds) }
    }

    var entityCleanupWarnMessage: String {
        didSet { defaults.set(entityCleanupWarnMessage, forKey: Keys.entityCleanupWarnMessage) }
    }

    /// Categories currently enabled, derived from the five bools above
    /// (UserDefaults has no native Set<LagClearCategory> storage) —
    /// the shape RCONAutomationCoordinator's runEntityCleanup expects.
    var entityCleanupCategories: Set<LagClearCategory> {
        var categories: Set<LagClearCategory> = []
        if entityCleanupClearItems { categories.insert(.droppedItems) }
        if entityCleanupClearXPOrbs { categories.insert(.experienceOrbs) }
        if entityCleanupClearProjectiles { categories.insert(.projectiles) }
        if entityCleanupClearTNT { categories.insert(.primedTNT) }
        if entityCleanupClearHostileMobs { categories.insert(.hostileMobs) }
        if entityCleanupClearEnderPearls { categories.insert(.enderPearls) }
        return categories
    }

    // MARK: - Leaderboard exclusions

    /// Comma-separated usernames — server owner/admins — hidden from
    /// leaderboards and playtime averages. Those are meant to reflect
    /// player community engagement, not the admin account's own
    /// testing/moderation time online, which would otherwise dominate
    /// raw playtime rankings. Empty by default — add your own.
    var excludedLeaderboardUsernamesRaw: String {
        didSet { defaults.set(excludedLeaderboardUsernamesRaw, forKey: Keys.excludedLeaderboardUsernames) }
    }

    /// Parsed, trimmed, lowercased for case-insensitive comparison —
    /// see `isExcludedFromLeaderboards`. Empty by default.
    var excludedLeaderboardUsernames: Set<String> {
        Set(
            excludedLeaderboardUsernamesRaw
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                .filter { !$0.isEmpty }
        )
    }

    func isExcludedFromLeaderboards(_ username: String) -> Bool {
        excludedLeaderboardUsernames.contains(username.lowercased())
    }

    // MARK: - World-activity & config drift monitoring

    var positionTrackingEnabled: Bool {
        didSet { defaults.set(positionTrackingEnabled, forKey: Keys.positionTrackingEnabled) }
    }

    /// Independent of rconTickPollInterval — World Map's breadcrumb
    /// trail wants its own predictable cadence (5 min by default)
    /// rather than inheriting whatever the tick-poll interval happens
    /// to be set to.
    var positionTrackingIntervalMinutes: Double {
        didSet { defaults.set(positionTrackingIntervalMinutes, forKey: Keys.positionTrackingIntervalMinutes) }
    }

    var configWatchdogEnabled: Bool {
        didSet { defaults.set(configWatchdogEnabled, forKey: Keys.configWatchdogEnabled) }
    }

    // MARK: - SFTP sync (automates every manual local-folder-import feature)

    /// Master switch — off leaves every feature exactly as it was
    /// (manual "Select Folder…" import), on starts the 15-minute
    /// (default) scheduler pulling from the server directly.
    var sftpEnabled: Bool {
        didSet { defaults.set(sftpEnabled, forKey: Keys.sftpEnabled) }
    }

    var sftpHost: String {
        didSet { defaults.set(sftpHost, forKey: Keys.sftpHost) }
    }

    var sftpPort: Int {
        didSet { defaults.set(sftpPort, forKey: Keys.sftpPort) }
    }

    var sftpUsername: String {
        didSet { defaults.set(sftpUsername, forKey: Keys.sftpUsername) }
    }

    /// Backed by the Keychain, not UserDefaults — see KeychainStore.
    var sftpPassword: String {
        didSet { KeychainStore.save(password: sftpPassword, account: Self.sftpPasswordKeychainAccount) }
    }

    var sftpSyncIntervalMinutes: Double {
        didSet { defaults.set(sftpSyncIntervalMinutes, forKey: Keys.sftpSyncIntervalMinutes) }
    }

    /// Location's logs/ folder — the feature that motivated SFTP sync.
    var sftpSyncLocationEnabled: Bool {
        didSet { defaults.set(sftpSyncLocationEnabled, forKey: Keys.sftpSyncLocationEnabled) }
    }

    /// world/players/stats (renamed from world/stats in the 2026
    /// version rename — see ServerLogJoinParser's file-level comment on
    /// that same rename for logs).
    var sftpSyncPlaytimeEnabled: Bool {
        didSet { defaults.set(sftpSyncPlaytimeEnabled, forKey: Keys.sftpSyncPlaytimeEnabled) }
    }

    /// world/players/data (renamed from world/playerdata).
    var sftpSyncInventoryEnabled: Bool {
        didSet { defaults.set(sftpSyncInventoryEnabled, forKey: Keys.sftpSyncInventoryEnabled) }
    }

    /// debug/profiling/*.zip.
    var sftpSyncPerformanceEnabled: Bool {
        didSet { defaults.set(sftpSyncPerformanceEnabled, forKey: Keys.sftpSyncPerformanceEnabled) }
    }

    /// world/region/*.mca — feeds the World Map's terrain/biome layer.
    var sftpSyncWorldMapEnabled: Bool {
        didSet { defaults.set(sftpSyncWorldMapEnabled, forKey: Keys.sftpSyncWorldMapEnabled) }
    }

    /// Whether the one-time full-history `logs.zip` backfill has run —
    /// after that, ongoing sync only ever pulls `latest.log`, not the
    /// whole (large, ever-growing) rotated-log history every cycle.
    var sftpLogsBackfillCompleted: Bool {
        didSet { defaults.set(sftpLogsBackfillCompleted, forKey: Keys.sftpLogsBackfillCompleted) }
    }

    // MARK: - Auto Updater

    /// Master switch — off by default even though Rafal's asked for the
    /// fully-automatic behavior once turned on. A feature that deletes
    /// the running server.jar and stops the live server unattended
    /// shouldn't ever activate itself just because this build shipped;
    /// he opts in explicitly in Settings.
    var autoUpdaterEnabled: Bool {
        didSet { defaults.set(autoUpdaterEnabled, forKey: Keys.autoUpdaterEnabled) }
    }

    /// How often to check Mojang's version manifest against the live
    /// running version. Configurable per Rafal's request; defaults to
    /// the 10 minutes he specified.
    var autoUpdaterIntervalMinutes: Double {
        didSet { defaults.set(autoUpdaterIntervalMinutes, forKey: Keys.autoUpdaterIntervalMinutes) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.host = defaults.string(forKey: Keys.host) ?? ""
        self.fallbackHost = defaults.string(forKey: Keys.fallbackHost) ?? ""
        self.useFallbackDNS = defaults.object(forKey: Keys.useFallbackDNS) as? Bool ?? false
        let storedPort = defaults.object(forKey: Keys.port) as? Int
        self.port = UInt16(storedPort ?? 25565)
        self.pollInterval = defaults.object(forKey: Keys.pollInterval) as? TimeInterval ?? 30
        self.autoStartOnLaunch = defaults.object(forKey: Keys.autoStart) as? Bool ?? true

        self.rconHost = defaults.string(forKey: Keys.rconHost) ?? ""
        let storedRconPort = defaults.object(forKey: Keys.rconPort) as? Int
        self.rconPort = UInt16(storedRconPort ?? 25575)
        self.rconTickPollInterval = defaults.object(forKey: Keys.rconTickPollInterval) as? TimeInterval ?? 120
        self.rconAutomationEnabled = defaults.object(forKey: Keys.rconAutomationEnabled) as? Bool ?? true

        self.entityCleanupEnabled = defaults.object(forKey: Keys.entityCleanupEnabled) as? Bool ?? true
        self.entityCleanupIntervalMinutes = defaults.object(forKey: Keys.entityCleanupIntervalMinutes) as? Double ?? 10
        self.entityCleanupClearItems = defaults.object(forKey: Keys.entityCleanupClearItems) as? Bool ?? true
        self.entityCleanupClearXPOrbs = defaults.object(forKey: Keys.entityCleanupClearXPOrbs) as? Bool ?? true
        self.entityCleanupClearProjectiles = defaults.object(forKey: Keys.entityCleanupClearProjectiles) as? Bool ?? false
        self.entityCleanupClearTNT = defaults.object(forKey: Keys.entityCleanupClearTNT) as? Bool ?? false
        self.entityCleanupClearHostileMobs = defaults.object(forKey: Keys.entityCleanupClearHostileMobs) as? Bool ?? false
        self.entityCleanupClearEnderPearls = defaults.object(forKey: Keys.entityCleanupClearEnderPearls) as? Bool ?? false
        self.entityCleanupWarnBeforeClear = defaults.object(forKey: Keys.entityCleanupWarnBeforeClear) as? Bool ?? false
        self.entityCleanupWarnLeadSeconds = defaults.object(forKey: Keys.entityCleanupWarnLeadSeconds) as? Double ?? 15
        self.entityCleanupWarnMessage = defaults.string(forKey: Keys.entityCleanupWarnMessage) ?? "Clearing dropped items and other debris shortly!"
        self.excludedLeaderboardUsernamesRaw = defaults.string(forKey: Keys.excludedLeaderboardUsernames) ?? ""
        self.positionTrackingEnabled = defaults.object(forKey: Keys.positionTrackingEnabled) as? Bool ?? true
        self.positionTrackingIntervalMinutes = defaults.object(forKey: Keys.positionTrackingIntervalMinutes) as? Double ?? 5
        self.configWatchdogEnabled = defaults.object(forKey: Keys.configWatchdogEnabled) as? Bool ?? true

        self.sftpEnabled = defaults.object(forKey: Keys.sftpEnabled) as? Bool ?? false
        self.sftpHost = defaults.string(forKey: Keys.sftpHost) ?? ""
        self.sftpPort = defaults.object(forKey: Keys.sftpPort) as? Int ?? 22
        self.sftpUsername = defaults.string(forKey: Keys.sftpUsername) ?? ""
        self.sftpSyncIntervalMinutes = defaults.object(forKey: Keys.sftpSyncIntervalMinutes) as? Double ?? 15
        self.sftpSyncLocationEnabled = defaults.object(forKey: Keys.sftpSyncLocationEnabled) as? Bool ?? true
        self.sftpSyncPlaytimeEnabled = defaults.object(forKey: Keys.sftpSyncPlaytimeEnabled) as? Bool ?? true
        self.sftpSyncInventoryEnabled = defaults.object(forKey: Keys.sftpSyncInventoryEnabled) as? Bool ?? true
        self.sftpSyncPerformanceEnabled = defaults.object(forKey: Keys.sftpSyncPerformanceEnabled) as? Bool ?? true
        self.sftpSyncWorldMapEnabled = defaults.object(forKey: Keys.sftpSyncWorldMapEnabled) as? Bool ?? true
        self.sftpLogsBackfillCompleted = defaults.object(forKey: Keys.sftpLogsBackfillCompleted) as? Bool ?? false

        self.autoUpdaterEnabled = defaults.object(forKey: Keys.autoUpdaterEnabled) as? Bool ?? false
        self.autoUpdaterIntervalMinutes = defaults.object(forKey: Keys.autoUpdaterIntervalMinutes) as? Double ?? 10

        // No password ships with this template — read whatever's
        // already in the Keychain (e.g. from a previous run), otherwise
        // start blank. Set these in Settings; every subsequent
        // read/write goes through the Keychain, never UserDefaults.
        self.rconPassword = KeychainStore.loadPassword(account: Self.rconPasswordKeychainAccount) ?? ""
        self.sftpPassword = KeychainStore.loadPassword(account: Self.sftpPasswordKeychainAccount) ?? ""
    }

    var engineConfiguration: ServerQueryEngine.Configuration {
        .init(
            host: host,
            fallbackHost: useFallbackDNS ? fallbackHost : nil,
            port: port,
            timeout: 5
        )
    }

    var rconConfiguration: RCONClient.Configuration {
        .init(host: rconHost, port: rconPort, password: rconPassword, timeout: 8)
    }

    func restoreDefaults() {
        host = ""
        fallbackHost = ""
        useFallbackDNS = false
        port = 25565
        pollInterval = 30
        autoStartOnLaunch = true
        rconHost = ""
        rconPort = 25575
        rconTickPollInterval = 120
        rconAutomationEnabled = true
        entityCleanupEnabled = true
        entityCleanupIntervalMinutes = 10
        entityCleanupClearItems = true
        entityCleanupClearXPOrbs = true
        entityCleanupClearProjectiles = false
        entityCleanupClearTNT = false
        entityCleanupClearHostileMobs = false
        entityCleanupClearEnderPearls = false
        entityCleanupWarnBeforeClear = false
        entityCleanupWarnLeadSeconds = 15
        entityCleanupWarnMessage = "Clearing dropped items and other debris shortly!"
        excludedLeaderboardUsernamesRaw = ""
        positionTrackingEnabled = true
        positionTrackingIntervalMinutes = 5
        configWatchdogEnabled = true
        sftpEnabled = false
        sftpHost = ""
        sftpPort = 22
        sftpUsername = ""
        sftpSyncIntervalMinutes = 15
        sftpSyncLocationEnabled = true
        sftpSyncPlaytimeEnabled = true
        sftpSyncInventoryEnabled = true
        sftpSyncPerformanceEnabled = true
        sftpSyncWorldMapEnabled = true
        autoUpdaterIntervalMinutes = 10
        // Deliberately does not reset autoUpdaterEnabled — restoring
        // defaults shouldn't silently switch off (or on) a running
        // production auto-deploy pipeline.
        // Deliberately does not reset sftpLogsBackfillCompleted or
        // sftpPassword — restoring defaults shouldn't force a multi-
        // hundred-file re-download or overwrite a rotated password.
        // Deliberately does not reset rconPassword — restoring defaults
        // shouldn't silently overwrite a password the admin may have
        // since rotated on the server.
    }
}
