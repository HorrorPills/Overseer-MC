//
//  RCONAutomationCoordinator.swift
//  Overseer
//
//  Bridges the pure `RCONClient` actor to the rest of the app: owns the
//  tick-polling timer (which also drives the `/list` roster check — see
//  pollPlayerListOnce), the scheduled-broadcast timer (user-authored
//  BroadcastMessage rows, sent via vanilla /say — see
//  checkDueBroadcasts), the admin console's command log/history, and
//  the automation triggers (playtime milestones, ad-window synergy,
//  Happy Hour) — each of which decides *whether* to fire via the pure
//  functions in AutomationTriggers.swift and, if so, dispatches the
//  corresponding VanillaCommands string here.
//
//  Mostly independent of PollingCoordinator's GS4/SLP loop — milestone
//  checks are only called *from* there, reacting to state it already
//  computed — except that both feed the same PlayerRosterSync pipeline:
//  GS4/SLP is the primary, higher-frequency "who's online" source, and
//  `/list` is an RCON-only fallback for servers with GS4 query disabled
//  (vanilla's own server.properties default).
//

import Foundation
import SwiftData
import Observation

@MainActor
@Observable
final class RCONAutomationCoordinator {

    struct LogEntry: Identifiable {
        enum Kind { case sent, received, error, system }
        let id = UUID()
        let timestamp: Date
        let kind: Kind
        let text: String
    }

    private(set) var isConnected = false
    private(set) var commandLog: [LogEntry] = []
    private(set) var lastTickReading: TickReading?
    private(set) var lastError: String?

    /// How many callers are currently waiting behind an in-flight RCON
    /// command — every scheduler in this class (tick-poll, position
    /// tracking, entity cleanup, config watchdog, broadcasts) and the
    /// console all funnel through the same underlying queue (see
    /// RCONClient.execute's FIFO mutex), so this is a real, live number,
    /// not an estimate. Surfaced in the console so queuing is visible
    /// rather than just a design claim.
    private(set) var queuedCommandCount = 0

    /// Latest `/banlist` snapshot — refreshed explicitly (refreshBanList)
    /// rather than polled, since bans change far less often than the
    /// online roster.
    private(set) var bannedPlayers: [BanEntry] = []

    /// Latest `/whitelist list` snapshot — refreshed explicitly, same
    /// reasoning as `bannedPlayers`.
    private(set) var whitelistedPlayers: [String] = []

    /// Master switch for automated side effects (milestones, ad
    /// broadcasts, Happy Hour). The console and quick-action buttons
    /// stay live regardless — this only gates the "app decides on its
    /// own to run a command" paths.
    var automationEnabled = true

    private let rcon: RCONClient
    private let modelContext: ModelContext
    private var tickPollInterval: TimeInterval
    private var tickPollTask: Task<Void, Never>?
    private var broadcastPollTask: Task<Void, Never>?
    private var tempBanPollTask: Task<Void, Never>?

    private var lastAdBroadcast: Date?
    private var lastHappyHour: Date?

    /// Whether to poll `/data get entity <player> Pos` for every online
    /// player alongside the existing `/list` roster check — feeds
    /// PlayerPositionSample for the world-activity heatmap. Piggybacks
    /// on the tick-poll cadence rather than its own scheduler, so it
    /// never runs more often than the interval already established as
    /// safe for RCON's main-thread command dispatch.
    var positionTrackingEnabled = true

    var configWatchdogEnabled = true
    private var configWatchdogTask: Task<Void, Never>?
    private var lastKnownConfigState: WatchedConfigState?
    private static let configWatchdogInterval: TimeInterval = 1800 // 30 min — config drift is rare; no need to poll it often

    private static let logCap = 500

    init(rcon: RCONClient, modelContext: ModelContext, tickPollInterval: TimeInterval = 120) {
        self.rcon = rcon
        self.modelContext = modelContext
        self.tickPollInterval = tickPollInterval
    }

    func updateConfiguration(_ configuration: RCONClient.Configuration) {
        Task { await rcon.updateConfiguration(configuration) }
    }

    func updateTickPollInterval(_ interval: TimeInterval) {
        tickPollInterval = interval
    }

    // MARK: - Console

    /// Every RCON dispatch in this class — console input, quick actions,
    /// panic mode, and automation triggers alike — funnels through here
    /// so the log is a complete audit trail and connection state stays
    /// consistent no matter who initiated the command. This is also
    /// where VanillaCommands.isStrictlyVanilla is actually enforced —
    /// every command *built* by this file is already guaranteed vanilla
    /// (see VanillaCommandsTests), so the only thing this can ever
    /// reject in practice is free text typed into RCONConsoleView.
    @discardableResult
    func sendConsoleCommand(_ raw: String) async -> String {
        let command = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return "" }
        guard VanillaCommands.isStrictlyVanilla(command) else {
            log(.error, "Rejected — not a strictly-vanilla command: \(command)")
            return ""
        }
        log(.sent, command)
        queuedCommandCount = await rcon.queuedCommandCount
        do {
            let response = try await rcon.execute(command)
            isConnected = true
            queuedCommandCount = await rcon.queuedCommandCount
            log(.received, response.isEmpty ? "(no output)" : response)
            return response
        } catch {
            isConnected = false
            queuedCommandCount = await rcon.queuedCommandCount
            let message = error.localizedDescription
            log(.error, message)
            lastError = message
            return ""
        }
    }

    private func log(_ kind: LogEntry.Kind, _ text: String) {
        commandLog.append(LogEntry(timestamp: .now, kind: kind, text: text))
        if commandLog.count > Self.logCap {
            commandLog.removeFirst(commandLog.count - Self.logCap)
        }
    }

    // MARK: - Tick profiling (vanilla /tick query, the strictly-vanilla /tps replacement)

    func startTickPolling() {
        guard tickPollTask == nil else { return }
        tickPollTask = Task { [weak self] in
            await self?.tickPollLoop()
        }
    }

    func stopTickPolling() {
        tickPollTask?.cancel()
        tickPollTask = nil
    }

    private func tickPollLoop() async {
        while !Task.isCancelled {
            await pollTickOnce()
            await pollPlayerListOnce()
            try? await Task.sleep(nanoseconds: UInt64(tickPollInterval * 1_000_000_000))
        }
    }

    private func pollTickOnce() async {
        let response = await sendConsoleCommand(VanillaCommands.tickQuery)
        guard let reading = try? TickProfiler.parse(response) else { return }
        lastTickReading = reading
        modelContext.insert(TickSample(targetTps: reading.targetTps, actualTps: reading.actualTps, mspt: reading.mspt))
        try? modelContext.save()
    }

    // MARK: - Roster check (vanilla /list — RCON-only fallback for "who's online")

    /// GS4/SLP (PollingCoordinator) is the primary roster source, but
    /// GS4 query is disabled on plenty of vanilla servers by default
    /// and SLP's player sample can be capped or omitted. `/list` only
    /// needs RCON — which the app already requires — so it's polled
    /// independently and fed through the same PlayerRosterSync pipeline,
    /// with joins/leaves surfaced right in the console log.
    private func pollPlayerListOnce() async {
        let response = await sendConsoleCommand(VanillaCommands.listPlayers)
        guard let onlineNames = try? PlayerListParser.parse(response) else { return }
        let result = PlayerRosterSync.apply(onlineNames: onlineNames, at: .now, modelContext: modelContext, automation: self)
        for username in result.joined {
            log(.system, "🟢 \(username) joined the game")
        }
        for username in result.left {
            log(.system, "🔴 \(username) left the game")
        }
    }

    // MARK: - Position tracking (World Map breadcrumbs)

    /// Its own scheduler, deliberately independent of the tick-poll
    /// loop above — World Map's breadcrumb trail wants a predictable,
    /// user-configurable cadence of its own (5 min by default) rather
    /// than silently inheriting whatever the tick-poll interval happens
    /// to be set to.
    var positionTrackingIntervalMinutes: Double = 5
    private var positionTrackingTask: Task<Void, Never>?

    /// World Map's breadcrumb trail is a "where has this player been
    /// *recently*" griefing tool, not a permanent movement log — beyond
    /// about half a day a trail stops being useful for that and just
    /// becomes accumulating dead weight in the store. Enforced
    /// unconditionally on every loop tick (regardless of
    /// `positionTrackingEnabled`), so retention keeps getting applied
    /// even while live tracking is temporarily toggled off.
    private static let positionRetention: TimeInterval = 12 * 60 * 60

    func startPositionTracking() {
        guard positionTrackingTask == nil else { return }
        positionTrackingTask = Task { [weak self] in
            await self?.positionTrackingLoop()
        }
    }

    func stopPositionTracking() {
        positionTrackingTask?.cancel()
        positionTrackingTask = nil
    }

    private func positionTrackingLoop() async {
        while !Task.isCancelled {
            purgeStalePositions()
            if positionTrackingEnabled {
                let response = await sendConsoleCommand(VanillaCommands.listPlayers)
                if let onlineNames = try? PlayerListParser.parse(response) {
                    await recordPositions(for: onlineNames)
                }
            }
            let interval = max(positionTrackingIntervalMinutes, 1) * 60
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
        }
    }

    /// Deletes every `PlayerPositionSample` older than the 12-hour
    /// retention window. Runs at the top of every position-tracking
    /// tick (every 5 min by default) — cheap, and means stale data
    /// never lingers for more than one cycle past its cutoff.
    private func purgeStalePositions() {
        let cutoff = Date.now.addingTimeInterval(-Self.positionRetention)
        let descriptor = FetchDescriptor<PlayerPositionSample>(predicate: #Predicate { $0.timestamp < cutoff })
        guard let stale = try? modelContext.fetch(descriptor), !stale.isEmpty else { return }
        for sample in stale { modelContext.delete(sample) }
        try? modelContext.save()
    }

    /// One `/data get entity ... Pos` round trip per online player.
    /// Feeds World Map's breadcrumb trail (see PlayerPositionSample).
    /// Silently skips any player whose position can't be parsed (e.g.
    /// between dimensions) rather than failing the whole batch.
    private func recordPositions(for onlineNames: Set<String>) async {
        guard !onlineNames.isEmpty else { return }
        for username in onlineNames {
            let response = await sendConsoleCommand(VanillaCommands.getEntityPosition(username))
            guard let position = try? EntityPositionParser.parse(response) else { continue }
            modelContext.insert(PlayerPositionSample(username: username, x: position.x, z: position.z))
        }
        try? modelContext.save()
    }

    // MARK: - Scheduled broadcasts (user-authored, vanilla /say)

    /// Checked far more often than any individual message's own
    /// interval is likely to be (minimum 1 minute in the UI), so a
    /// message fires within a few seconds of becoming due rather than
    /// drifting by however long the RCON tick-poll loop takes.
    private static let broadcastCheckInterval: TimeInterval = 10

    func startBroadcastScheduler() {
        guard broadcastPollTask == nil else { return }
        broadcastPollTask = Task { [weak self] in
            await self?.broadcastSchedulerLoop()
        }
    }

    func stopBroadcastScheduler() {
        broadcastPollTask?.cancel()
        broadcastPollTask = nil
    }

    private func broadcastSchedulerLoop() async {
        while !Task.isCancelled {
            await checkDueBroadcasts()
            try? await Task.sleep(nanoseconds: UInt64(Self.broadcastCheckInterval * 1_000_000_000))
        }
    }

    private func checkDueBroadcasts() async {
        guard let messages = try? modelContext.fetch(FetchDescriptor<BroadcastMessage>()) else { return }
        let due = BroadcastScheduler.due(messages)
        guard !due.isEmpty else { return }
        for message in due {
            await sendConsoleCommand(VanillaCommands.say(message.text))
            message.lastSentAt = .now
        }
        try? modelContext.save()
    }

    /// Sends `message` immediately, independent of its schedule, and
    /// resets the schedule from this send — so a manual "Send Now"
    /// doesn't get followed by an automatic fire moments later.
    func sendBroadcastNow(_ message: BroadcastMessage) async {
        await sendConsoleCommand(VanillaCommands.say(message.text))
        message.lastSentAt = .now
        try? modelContext.save()
    }

    // MARK: - Temp-bans (app-tracked expiry, real vanilla /ban + /pardon)

    private static let tempBanCheckInterval: TimeInterval = 30

    func startTempBanScheduler() {
        guard tempBanPollTask == nil else { return }
        tempBanPollTask = Task { [weak self] in
            await self?.tempBanSchedulerLoop()
        }
    }

    func stopTempBanScheduler() {
        tempBanPollTask?.cancel()
        tempBanPollTask = nil
    }

    private func tempBanSchedulerLoop() async {
        while !Task.isCancelled {
            await checkExpiredTempBans()
            try? await Task.sleep(nanoseconds: UInt64(Self.tempBanCheckInterval * 1_000_000_000))
        }
    }

    private func checkExpiredTempBans() async {
        guard let bans = try? modelContext.fetch(FetchDescriptor<TempBan>(predicate: #Predicate { !$0.pardoned })) else { return }
        let due = TempBanScheduler.expired(bans)
        guard !due.isEmpty else { return }
        for ban in due {
            await sendConsoleCommand(VanillaCommands.pardon(ban.username))
            ban.pardoned = true
            recordModeration(username: ban.username, kind: .pardon, detail: "Temp-ban expired")
            log(.system, "⏰ Temp-ban for \(ban.username) expired — auto-pardoned")
        }
        try? modelContext.save()
        await refreshBanList()
    }

    /// Bans `username` with a real vanilla `/ban`, and additionally
    /// records a TempBan so the scheduler loop above auto-`/pardon`s
    /// them once `durationMinutes` has elapsed.
    func tempBan(_ username: String, reason: String?, durationMinutes: Double) async {
        let trimmedReason = reason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        await sendConsoleCommand(VanillaCommands.ban(username, reason: trimmedReason.isEmpty ? nil : trimmedReason))
        let detail = trimmedReason.isEmpty
            ? "Temp-ban (\(Int(durationMinutes))m)"
            : "\(trimmedReason) — temp-ban (\(Int(durationMinutes))m)"
        recordModeration(username: username, kind: .ban, detail: detail)
        modelContext.insert(TempBan(username: username, reason: trimmedReason, expiresAt: Date().addingTimeInterval(durationMinutes * 60)))
        try? modelContext.save()
        await refreshBanList()
    }

    /// Manual early pardon of a tracked temp-ban from the Access
    /// Control screen.
    func pardonTempBan(_ tempBan: TempBan) async {
        await pardon(tempBan.username)
        tempBan.pardoned = true
        try? modelContext.save()
    }

    // MARK: - Entity cleanup ("clear lag")

    struct EntityCleanupResult {
        var timestamp: Date
        var perCategory: [LagClearCategory: Int]
        var totalKilled: Int
    }

    /// Master switch for the *automatic* schedule below — the manual
    /// "Clear Now" action (see runEntityCleanup) stays available either
    /// way, same relationship `automationEnabled` has to the console.
    var entityCleanupEnabled = true
    var entityCleanupIntervalMinutes: Double = 10
    var entityCleanupCategories: Set<LagClearCategory> = [.droppedItems, .experienceOrbs]
    var entityCleanupWarnBeforeClear = false
    var entityCleanupWarnLeadSeconds: Double = 15
    var entityCleanupWarnMessage = "Clearing dropped items and other debris shortly!"

    private(set) var lastEntityCleanupResult: EntityCleanupResult?
    private(set) var isRunningEntityCleanup = false
    private var entityCleanupPollTask: Task<Void, Never>?

    private static let entityCleanupCheckInterval: TimeInterval = 10

    func startEntityCleanupScheduler() {
        guard entityCleanupPollTask == nil else { return }
        entityCleanupPollTask = Task { [weak self] in
            await self?.entityCleanupSchedulerLoop()
        }
    }

    func stopEntityCleanupScheduler() {
        entityCleanupPollTask?.cancel()
        entityCleanupPollTask = nil
    }

    private func entityCleanupSchedulerLoop() async {
        while !Task.isCancelled {
            await checkEntityCleanupDue()
            try? await Task.sleep(nanoseconds: UInt64(Self.entityCleanupCheckInterval * 1_000_000_000))
        }
    }

    /// A nil `lastEntityCleanupResult` (never run yet) counts as due
    /// immediately once enabled, same "no history = due now" rule
    /// BroadcastMessage's nil `lastSentAt` uses.
    private func checkEntityCleanupDue() async {
        guard entityCleanupEnabled, entityCleanupIntervalMinutes > 0, !isRunningEntityCleanup else { return }
        if let last = lastEntityCleanupResult?.timestamp {
            guard Date().timeIntervalSince(last) >= entityCleanupIntervalMinutes * 60 else { return }
        }
        await runEntityCleanup(categories: entityCleanupCategories)
    }

    /// Runs one sweep immediately — used by both the scheduler above and
    /// the "Clear Now" button, so there's exactly one code path that
    /// actually dispatches `/kill` commands. Sequential, not
    /// rate-limited like SchematicBuildQueue: this is at most ~35 quick
    /// commands (one per hostile mob type, worst case), not thousands.
    @discardableResult
    func runEntityCleanup(categories: Set<LagClearCategory>) async -> EntityCleanupResult {
        isRunningEntityCleanup = true
        defer { isRunningEntityCleanup = false }

        if entityCleanupWarnBeforeClear, !categories.isEmpty {
            let message = entityCleanupWarnMessage.trimmingCharacters(in: .whitespacesAndNewlines)
            if !message.isEmpty {
                await sendConsoleCommand(VanillaCommands.entityCleanupWarning(message))
                let leadNanos = UInt64(max(0, entityCleanupWarnLeadSeconds) * 1_000_000_000)
                if leadNanos > 0 { try? await Task.sleep(nanoseconds: leadNanos) }
            }
        }

        var perCategory: [LagClearCategory: Int] = [:]
        // Mob/TNT categories run before item/orb cleanup — see
        // EntityCleanupCatalog's sweepOrdered doc — so loot a mob kill
        // just produced gets swept in this same run, not left for the
        // next scheduled sweep.
        for category in LagClearCategory.sweepOrdered(categories) {
            var killedInCategory = 0
            for selector in EntityCleanupCatalog.selectors(for: category) {
                let response = await sendConsoleCommand(VanillaCommands.killEntities(ofType: selector))
                killedInCategory += KillCommandResponseParser.parseKilledCount(response)
            }
            perCategory[category] = killedInCategory
        }

        let result = EntityCleanupResult(timestamp: .now, perCategory: perCategory, totalKilled: perCategory.values.reduce(0, +))
        lastEntityCleanupResult = result
        log(.system, "🧹 Entity cleanup: \(result.totalKilled) entities removed (\(categories.map(\.label).sorted().joined(separator: ", ")))")
        return result
    }

    // MARK: - Config drift watchdog

    /// The handful of gamerules + difficulty worth watching for
    /// unexpected changes on a vanilla survival server — `mobGriefing`/
    /// `keepInventory` flipping is as serious as a griefing incident
    /// itself. Not persisted directly; only diffs between consecutive
    /// polls are (see ConfigChangeEvent) — this struct just holds the
    /// most recent poll's readings in memory to diff the next one against.
    private struct WatchedConfigState: Equatable {
        var mobGriefing: Bool?
        var keepInventory: Bool?
        var doDaylightCycle: Bool?
        var doMobSpawning: Bool?
        var doFireTick: Bool?
        var difficulty: String?
    }

    func startConfigWatchdog() {
        guard configWatchdogTask == nil else { return }
        configWatchdogTask = Task { [weak self] in
            await self?.configWatchdogLoop()
        }
    }

    func stopConfigWatchdog() {
        configWatchdogTask?.cancel()
        configWatchdogTask = nil
    }

    private func configWatchdogLoop() async {
        while !Task.isCancelled {
            if configWatchdogEnabled {
                await checkConfigDrift()
            }
            try? await Task.sleep(nanoseconds: UInt64(Self.configWatchdogInterval * 1_000_000_000))
        }
    }

    /// Queries every watched key, then diffs against the previous poll.
    /// The very first poll after launch only establishes a baseline —
    /// with no prior reading to compare against, logging every value as
    /// a "change" would be a false positive, not a real drift signal.
    private func checkConfigDrift() async {
        var next = WatchedConfigState()
        next.mobGriefing = ServerConfigQueryParser.parseBoolean(await sendConsoleCommand(VanillaCommands.queryGamerule("mobGriefing")))
        next.keepInventory = ServerConfigQueryParser.parseBoolean(await sendConsoleCommand(VanillaCommands.queryGamerule("keepInventory")))
        next.doDaylightCycle = ServerConfigQueryParser.parseBoolean(await sendConsoleCommand(VanillaCommands.queryGamerule("doDaylightCycle")))
        next.doMobSpawning = ServerConfigQueryParser.parseBoolean(await sendConsoleCommand(VanillaCommands.queryGamerule("doMobSpawning")))
        next.doFireTick = ServerConfigQueryParser.parseBoolean(await sendConsoleCommand(VanillaCommands.queryGamerule("doFireTick")))
        next.difficulty = ServerConfigQueryParser.parseDifficulty(await sendConsoleCommand(VanillaCommands.queryDifficulty))

        defer { lastKnownConfigState = next }
        guard let previous = lastKnownConfigState else { return }

        recordDrift(key: "mobGriefing", oldValue: previous.mobGriefing, newValue: next.mobGriefing)
        recordDrift(key: "keepInventory", oldValue: previous.keepInventory, newValue: next.keepInventory)
        recordDrift(key: "doDaylightCycle", oldValue: previous.doDaylightCycle, newValue: next.doDaylightCycle)
        recordDrift(key: "doMobSpawning", oldValue: previous.doMobSpawning, newValue: next.doMobSpawning)
        recordDrift(key: "doFireTick", oldValue: previous.doFireTick, newValue: next.doFireTick)
        recordDrift(key: "difficulty", oldValue: previous.difficulty, newValue: next.difficulty)
    }

    private func recordDrift<T: Equatable>(key: String, oldValue: T?, newValue: T?) {
        guard let oldValue, let newValue, oldValue != newValue else { return }
        modelContext.insert(ConfigChangeEvent(key: key, oldValue: "\(oldValue)", newValue: "\(newValue)"))
        try? modelContext.save()
        log(.system, "⚠️ Config changed: \(key) went from \(oldValue) to \(newValue)")
    }

    // MARK: - Ban list / whitelist (explicit refresh, not polled)

    func refreshBanList() async {
        let response = await sendConsoleCommand(VanillaCommands.banList)
        guard let entries = try? BanListParser.parse(response) else { return }
        bannedPlayers = entries
    }

    func refreshWhitelist() async {
        let response = await sendConsoleCommand(VanillaCommands.whitelistList)
        guard let names = try? WhitelistParser.parse(response) else { return }
        whitelistedPlayers = names.sorted()
    }

    func whitelistAdd(_ username: String) async {
        await sendConsoleCommand(VanillaCommands.whitelistAdd(username))
        await refreshWhitelist()
    }

    func whitelistRemove(_ username: String) async {
        await sendConsoleCommand(VanillaCommands.whitelistRemove(username))
        await refreshWhitelist()
    }

    // MARK: - Reward system

    /// Called by PollingCoordinator right after it closes a
    /// PlayerSession (i.e. `player.playTimeSeconds` is already final
    /// for that session).
    func checkMilestones(for player: Player) {
        guard automationEnabled else { return }
        let alreadyAwarded = Set(player.awardedMilestoneHours)
        let newMilestones = MilestoneEvaluator.newlyCrossedMilestones(
            playTimeSeconds: player.playTimeSeconds,
            alreadyAwardedHours: alreadyAwarded
        )
        guard !newMilestones.isEmpty else { return }
        player.awardedMilestoneHours.append(contentsOf: newMilestones)

        let username = player.username
        Task {
            for hours in newMilestones {
                await self.sendConsoleCommand(VanillaCommands.giveDiamondBlock(to: username))
                await self.sendConsoleCommand(VanillaCommands.announcePlaytimeMilestone(username: username, hours: hours))
            }
        }
    }

    // MARK: - Ad-window synergy + Happy Hour

    /// Called by PollingCoordinator after each snapshot is saved, with
    /// the freshly-computed 15-minute velocity.
    func evaluateTriggers(velocityPerMinute15: Double?, now: Date = .now) {
        guard automationEnabled else { return }

        if AdWindowTrigger.shouldBroadcast(velocityPerMinute: velocityPerMinute15, lastBroadcast: lastAdBroadcast, now: now) {
            lastAdBroadcast = now
            Task { await self.sendConsoleCommand(VanillaCommands.adWindowBroadcast) }
        }

        if HappyHourWindow.shouldTrigger(now: now, lastTriggered: lastHappyHour) {
            lastHappyHour = now
            Task {
                await self.sendConsoleCommand(VanillaCommands.happyHourLuckEffect())
                await self.sendConsoleCommand(
                    VanillaCommands.tellraw(text: "[Server] Happy Hour! Enjoy a Luck boost while it lasts.", color: "gold", bold: true)
                )
            }
        }
    }

    // MARK: - Panic Mode / emergency lockdown

    @discardableResult
    func panicMode() async -> [String] {
        log(.system, "🚨 PANIC MODE ENGAGED — running emergency lockdown sequence")
        var responses: [String] = []
        for command in VanillaCommands.panicModeSequence {
            responses.append(await sendConsoleCommand(command))
        }
        log(.system, "Lockdown sequence complete.")
        return responses
    }

    // MARK: - Quick actions

    func setTimeDay() async { await sendConsoleCommand(VanillaCommands.setTimeDay) }
    func clearWeather() async { await sendConsoleCommand(VanillaCommands.clearWeather) }
    func setWhitelist(enabled: Bool) async {
        await sendConsoleCommand(enabled ? VanillaCommands.whitelistOn : VanillaCommands.whitelistOff)
    }
    func reloadWhitelist() async { await sendConsoleCommand(VanillaCommands.whitelistReload) }

    func kick(_ username: String, reason: String?) async {
        await sendConsoleCommand(VanillaCommands.kick(username, reason: reason))
        recordModeration(username: username, kind: .kick, detail: reason ?? "")
    }
    func ban(_ username: String, reason: String?) async {
        await sendConsoleCommand(VanillaCommands.ban(username, reason: reason))
        recordModeration(username: username, kind: .ban, detail: reason ?? "")
        await refreshBanList()
    }
    func pardon(_ username: String) async {
        await sendConsoleCommand(VanillaCommands.pardon(username))
        recordModeration(username: username, kind: .pardon)
        markTempBansPardoned(for: username)
        await refreshBanList()
    }

    /// Keeps any app-tracked TempBan rows in sync when a player is
    /// pardoned through a path other than `pardonTempBan(_:)` (context
    /// menu, detail page, console quick action) — otherwise the
    /// scheduler loop would try to `/pardon` an already-pardoned player
    /// again once its tracked expiry passes. Harmless either way
    /// (`/pardon` on a non-banned player is a no-op), but keeps the
    /// Access Control screen's temp-ban list accurate.
    private func markTempBansPardoned(for username: String) {
        let descriptor = FetchDescriptor<TempBan>(predicate: #Predicate { $0.username == username && !$0.pardoned })
        guard let bans = try? modelContext.fetch(descriptor), !bans.isEmpty else { return }
        for ban in bans { ban.pardoned = true }
        try? modelContext.save()
    }
    func tagAdmin(_ username: String) async {
        await sendConsoleCommand(VanillaCommands.tagAddAdmin(username))
        recordModeration(username: username, kind: .tagAdmin)
    }
    func setGamemode(_ mode: VanillaCommands.GameMode, for username: String) async {
        await sendConsoleCommand(VanillaCommands.gamemode(mode, for: username))
        recordModeration(username: username, kind: .gamemodeChange, detail: mode.displayName)
    }
    func clearInventory(_ username: String) async {
        await sendConsoleCommand(VanillaCommands.clearInventory(username))
        recordModeration(username: username, kind: .clearInventory)
    }
    func giveItem(to username: String, item: MinecraftItem, count: Int) async {
        await sendConsoleCommand(VanillaCommands.giveItem(to: username, itemID: item.id, count: count))
        recordModeration(username: username, kind: .giveItem, detail: "\(count)x \(item.displayName)")
    }

    // MARK: - Moderation audit trail

    /// Every moderation action funnels through here, regardless of
    /// which UI surface (console quick action, player context menu,
    /// player detail page) triggered it, so `ModerationEvent` is a
    /// complete record no matter the entry point.
    private func recordModeration(username: String, kind: ModerationEvent.Kind, detail: String = "") {
        modelContext.insert(ModerationEvent(username: username, kind: kind, detail: detail))
        try? modelContext.save()
    }
}
