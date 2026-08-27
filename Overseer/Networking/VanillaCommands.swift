//
//  VanillaCommands.swift
//  Overseer
//
//  Single source of truth for every command string this app can send
//  over RCON. STRICTLY vanilla — no Paper/Spigot/Essentials commands
//  (no /tps, /broadcast, /heal, /fly, /mute, ...). Every UI trigger and
//  every automation trigger goes through this file, so "did we
//  accidentally generate a plugin command" is a one-file audit instead
//  of a UI-wide one.
//
//  App-generated broadcasts (ad-window synergy, Happy Hour, playtime
//  milestones) go through `/tellraw` so they can carry vanilla JSON
//  text component color/formatting — never a plugin's `/broadcast`.
//  User-authored scheduled broadcasts (see BroadcastMessage) use plain
//  `/say` instead, since those are free text an admin typed, not
//  app-generated JSON.
//

import Foundation

enum VanillaCommands {

    // MARK: - Performance profiling

    /// Vanilla's own tick manager query (added as part of the tick
    /// control command set) — the strictly-vanilla replacement for a
    /// plugin's `/tps`.
    static let tickQuery = "/tick query"

    // MARK: - Roster check

    /// Vanilla's own online-player roster — used as an RCON-only
    /// fallback/cross-check for "who's online" alongside GS4/SLP, since
    /// it works even when GS4 query is disabled on the server.
    static let listPlayers = "/list"

    // MARK: - Rewards

    static func giveDiamondBlock(to username: String, count: Int = 1) -> String {
        "/give \(username) minecraft:diamond_block \(count)"
    }

    static func announcePlaytimeMilestone(username: String, hours: Int) -> String {
        tellraw(
            target: "@a",
            text: "[System] \(username) has reached \(hours) hours of playtime!",
            color: "green"
        )
    }

    // MARK: - App-generated chat broadcasts (never /say, never /broadcast)

    static func tellraw(target: String = "@a", text: String, color: String, bold: Bool = false) -> String {
        var component = "{\"text\":\"\(jsonEscape(text))\",\"color\":\"\(color)\""
        if bold { component += ",\"bold\":true" }
        component += "}"
        return "/tellraw \(target) \(component)"
    }

    static let adWindowBroadcast = tellraw(
        text: "[Server] Server traffic is peaking! Help us grow by sharing the IP!",
        color: "gold",
        bold: true
    )

    // MARK: - User-authored scheduled broadcasts

    /// Plain vanilla `/say` — deliberately distinct from `tellraw`
    /// above: these are free-text messages an admin typed into the
    /// Broadcasts screen (see BroadcastMessage / BroadcastScheduler),
    /// not app-generated JSON text components.
    static func say(_ message: String) -> String {
        "/say \(message)"
    }

    // MARK: - Happy Hour

    /// `minecraft:luck` for players online during a "Happy Hour" window.
    /// Vanilla's `/effect give` duration argument is in *seconds*
    /// (not ticks), so the default of 3600 is a full real-time hour.
    static func happyHourLuckEffect(durationSeconds: Int = 3600, amplifier: Int = 1) -> String {
        "/effect give @a minecraft:luck \(durationSeconds) \(amplifier)"
    }

    // MARK: - World / time / weather quick actions

    static let setTimeDay = "/time set day"
    static let clearWeather = "/weather clear"

    // MARK: - Whitelist

    static let whitelistOn = "/whitelist on"
    static let whitelistOff = "/whitelist off"
    static let whitelistReload = "/whitelist reload"
    static let whitelistList = "/whitelist list"

    static func whitelistAdd(_ username: String) -> String { "/whitelist add \(username)" }
    static func whitelistRemove(_ username: String) -> String { "/whitelist remove \(username)" }

    // MARK: - Ban list

    /// Vanilla's own ban roster (name, banning source, reason) — see
    /// BanListParser for the response format.
    static let banList = "/banlist"

    // MARK: - Schematic building

    /// Every block placed by the schematic builder (see
    /// Schematic/RCONCommandPlanner.swift) goes through these two, so
    /// the "is this vanilla" audit stays true of the whole build
    /// pipeline, not just individual quick actions.
    static func setBlock(x: Int, y: Int, z: Int, blockState: String) -> String {
        "/setblock \(x) \(y) \(z) \(blockState)"
    }

    static func fill(x1: Int, y1: Int, z1: Int, x2: Int, y2: Int, z2: Int, blockState: String) -> String {
        "/fill \(x1) \(y1) \(z1) \(x2) \(y2) \(z2) \(blockState)"
    }

    /// Queries a player's exact position — used by the schematic
    /// builder's "Fetch Player Position" button. See
    /// EntityPositionParser for the response format.
    static func getEntityPosition(_ playerName: String) -> String {
        "/data get entity \(playerName) Pos"
    }

    // MARK: - Config drift watchdog

    /// `/gamerule <rule>` with no value argument queries the current
    /// value instead of changing it — same vanilla command, just an
    /// omitted second argument.
    static func queryGamerule(_ rule: String) -> String {
        "/gamerule \(rule)"
    }

    /// `/difficulty` with no argument queries the current difficulty.
    static let queryDifficulty = "/difficulty"

    // MARK: - Moderation

    static func kick(_ username: String, reason: String? = nil) -> String {
        guard let reason, !reason.isEmpty else { return "/kick \(username)" }
        return "/kick \(username) \(reason)"
    }

    static func ban(_ username: String, reason: String? = nil) -> String {
        guard let reason, !reason.isEmpty else { return "/ban \(username)" }
        return "/ban \(username) \(reason)"
    }

    /// Reverses a `/ban` — vanilla's own command, not to be confused
    /// with Essentials' `/unban`.
    static func pardon(_ username: String) -> String {
        "/pardon \(username)"
    }

    static func tagAddAdmin(_ username: String) -> String {
        "/tag \(username) add admin"
    }

    /// Vanilla gamemode, one of survival/creative/adventure/spectator.
    enum GameMode: String, CaseIterable, Identifiable {
        case survival, creative, adventure, spectator
        var id: String { rawValue }
        var displayName: String { rawValue.capitalized }
    }

    static func gamemode(_ mode: GameMode, for username: String) -> String {
        "/gamemode \(mode.rawValue) \(username)"
    }

    /// Empties a player's inventory. Vanilla's `/clear` — the strictly-
    /// vanilla stand-in for a plugin "clear inventory" command.
    static func clearInventory(_ username: String) -> String {
        "/clear \(username)"
    }

    // MARK: - Give item

    /// `itemID` must already be namespaced (e.g. "minecraft:diamond"),
    /// as every entry in `MinecraftItemCatalog` is.
    static func giveItem(to username: String, itemID: String, count: Int = 1) -> String {
        "/give \(username) \(itemID) \(max(1, count))"
    }

    // MARK: - Entity cleanup ("clear lag")

    /// Vanilla `/kill` targeting every entity of one type via a target
    /// selector — the strictly-vanilla equivalent of a clearlag
    /// plugin's item/mob sweep. `typeSelector` is either a namespaced
    /// entity ID ("minecraft:item") or an entity type tag
    /// ("#minecraft:raiders") — see EntityCleanupCatalog.
    static func killEntities(ofType typeSelector: String) -> String {
        "/kill @e[type=\(typeSelector)]"
    }

    /// App-generated pre-clear warning — `/tellraw`, not `/say`, for the
    /// same reason as `announcePlaytimeMilestone`/`adWindowBroadcast`:
    /// this is an app-generated system message, not admin-typed free text.
    static func entityCleanupWarning(_ message: String) -> String {
        tellraw(text: message, color: "yellow", bold: true)
    }

    // MARK: - Panic Mode / emergency lockdown

    /// Kicks everyone without the `admin` tag (see `tagAddAdmin`), with
    /// a vanilla JSON kick reason.
    static let kickAllExceptAdmins = "/kick @a[tag=!admin] {\"text\":\"The server is on emergency lockdown.\",\"color\":\"red\"}"
    static let enableKeepInventory = "/gamerule keepInventory true"
    static let saveAll = "/save-all"

    // MARK: - Auto Updater

    /// Plain vanilla shutdown — the only command the Auto Updater ever
    /// sends. It deliberately does NOT try to start the server back up;
    /// that's the hosting panel's cron job's job (see
    /// AutoUpdaterCoordinator's file-level comment).
    static let stopServer = "/stop"

    /// The full, ordered emergency-lockdown sequence.
    static let panicModeSequence: [String] = [
        whitelistOn,
        kickAllExceptAdmins,
        enableKeepInventory,
        saveAll
    ]

    // MARK: - Guard rail

    /// Non-exhaustive denylist of well-known Paper/Spigot/Essentials
    /// command roots, used only defensively (e.g. to reject a raw
    /// command typed into the admin console). Vanilla command
    /// construction above never needs this — it's a backstop, not the
    /// primary enforcement mechanism.
    static let disallowedCommandRoots: Set<String> = [
        "tps", "broadcast", "heal", "fly", "mute", "warp", "essentials",
        "eco", "kit", "spawnmob", "nick", "god", "feed", "vanish"
    ]

    static func isStrictlyVanilla(_ command: String) -> Bool {
        let trimmed = command.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("/") else { return true } // not a slash command at all
        let root = trimmed
            .dropFirst()
            .split(separator: " ", maxSplits: 1)
            .first
            .map(String.init)?
            .lowercased() ?? ""
        return !disallowedCommandRoots.contains(root)
    }

    private static func jsonEscape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
