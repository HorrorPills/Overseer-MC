//
//  VanillaCommandsTests.swift
//  OverseerTests
//
//  Asserts every generated command string is exactly what's expected
//  AND contains no Paper/Spigot/Essentials command root — the "strictly
//  vanilla" requirement is a testable property, not just a code review
//  convention.
//

import Testing
@testable import Overseer

@Suite("VanillaCommands")
struct VanillaCommandsTests {

    @Test("Reward commands are exact vanilla /give and /tellraw")
    func rewardCommands() {
        #expect(VanillaCommands.giveDiamondBlock(to: "Alice") == "/give Alice minecraft:diamond_block 1")
        #expect(VanillaCommands.giveDiamondBlock(to: "Alice", count: 3) == "/give Alice minecraft:diamond_block 3")

        let announcement = VanillaCommands.announcePlaytimeMilestone(username: "Alice", hours: 50)
        #expect(announcement == "/tellraw @a {\"text\":\"[System] Alice has reached 50 hours of playtime!\",\"color\":\"green\"}")
    }

    @Test("Ad-window and Happy Hour broadcasts use /tellraw and /effect, never /broadcast")
    func broadcastCommands() {
        #expect(VanillaCommands.adWindowBroadcast.hasPrefix("/tellraw @a"))
        #expect(VanillaCommands.adWindowBroadcast.contains("\"bold\":true"))
        #expect(!VanillaCommands.adWindowBroadcast.contains("/broadcast"))

        #expect(VanillaCommands.happyHourLuckEffect() == "/effect give @a minecraft:luck 3600 1")
        #expect(VanillaCommands.happyHourLuckEffect(durationSeconds: 1800, amplifier: 2) == "/effect give @a minecraft:luck 1800 2")
    }

    @Test("Whitelist/time/weather quick actions are exact vanilla strings")
    func quickActions() {
        #expect(VanillaCommands.setTimeDay == "/time set day")
        #expect(VanillaCommands.clearWeather == "/weather clear")
        #expect(VanillaCommands.whitelistOn == "/whitelist on")
        #expect(VanillaCommands.whitelistOff == "/whitelist off")
        #expect(VanillaCommands.whitelistReload == "/whitelist reload")
    }

    @Test("Kick/ban omit the reason clause when none is given, include it when present")
    func kickBan() {
        #expect(VanillaCommands.kick("Alice") == "/kick Alice")
        #expect(VanillaCommands.kick("Alice", reason: "Griefing") == "/kick Alice Griefing")
        #expect(VanillaCommands.ban("Alice") == "/ban Alice")
        #expect(VanillaCommands.ban("Alice", reason: "Exploiting") == "/ban Alice Exploiting")
    }

    @Test("say builds a plain /say command, distinct from tellraw")
    func sayCommand() {
        #expect(VanillaCommands.say("Hello everyone!") == "/say Hello everyone!")
        #expect(!VanillaCommands.say("test").contains("tellraw"))
    }

    @Test("Pardon, gamemode, clear, and give-item build exact vanilla strings")
    func newModerationCommands() {
        #expect(VanillaCommands.pardon("Alice") == "/pardon Alice")
        #expect(VanillaCommands.clearInventory("Alice") == "/clear Alice")

        #expect(VanillaCommands.gamemode(.creative, for: "Alice") == "/gamemode creative Alice")
        #expect(VanillaCommands.gamemode(.survival, for: "Alice") == "/gamemode survival Alice")
        #expect(VanillaCommands.gamemode(.adventure, for: "Alice") == "/gamemode adventure Alice")
        #expect(VanillaCommands.gamemode(.spectator, for: "Alice") == "/gamemode spectator Alice")

        #expect(VanillaCommands.giveItem(to: "Alice", itemID: "minecraft:diamond", count: 3) == "/give Alice minecraft:diamond 3")
        #expect(VanillaCommands.giveItem(to: "Alice", itemID: "minecraft:diamond") == "/give Alice minecraft:diamond 1")
        // Count is clamped to at least 1 rather than emitting a nonsensical /give.
        #expect(VanillaCommands.giveItem(to: "Alice", itemID: "minecraft:diamond", count: 0) == "/give Alice minecraft:diamond 1")
        #expect(VanillaCommands.giveItem(to: "Alice", itemID: "minecraft:diamond", count: -5) == "/give Alice minecraft:diamond 1")
    }

    @Test("Schematic-building commands (setblock/fill/data get) build exact vanilla strings")
    func schematicBuildingCommands() {
        #expect(VanillaCommands.setBlock(x: 1, y: 2, z: 3, blockState: "minecraft:stone") == "/setblock 1 2 3 minecraft:stone")
        #expect(VanillaCommands.setBlock(x: -1, y: 0, z: -3, blockState: "minecraft:oak_stairs[facing=north]") == "/setblock -1 0 -3 minecraft:oak_stairs[facing=north]")
        #expect(VanillaCommands.fill(x1: 0, y1: 0, z1: 0, x2: 4, y2: 0, z2: 0, blockState: "minecraft:stone") == "/fill 0 0 0 4 0 0 minecraft:stone")
        #expect(VanillaCommands.getEntityPosition("Alice") == "/data get entity Alice Pos")
    }

    @Test("Panic Mode sequence is exactly the four specified vanilla commands, in order")
    func panicModeSequence() {
        #expect(VanillaCommands.panicModeSequence == [
            "/whitelist on",
            "/kick @a[tag=!admin] {\"text\":\"The server is on emergency lockdown.\",\"color\":\"red\"}",
            "/gamerule keepInventory true",
            "/save-all"
        ])
    }

    @Test("Entity cleanup commands build exact vanilla strings")
    func entityCleanupCommands() {
        #expect(VanillaCommands.killEntities(ofType: "minecraft:item") == "/kill @e[type=minecraft:item]")
        #expect(VanillaCommands.killEntities(ofType: "#minecraft:raiders") == "/kill @e[type=#minecraft:raiders]")
        #expect(VanillaCommands.entityCleanupWarning("Clearing soon!") == "/tellraw @a {\"text\":\"Clearing soon!\",\"color\":\"yellow\",\"bold\":true}")
    }

    @Test("No generated command matches a known Paper/Spigot/Essentials root", arguments: [
        VanillaCommands.tickQuery,
        VanillaCommands.killEntities(ofType: "minecraft:item"),
        VanillaCommands.entityCleanupWarning("Clearing soon!"),
        VanillaCommands.giveDiamondBlock(to: "Alice"),
        VanillaCommands.announcePlaytimeMilestone(username: "Alice", hours: 50),
        VanillaCommands.adWindowBroadcast,
        VanillaCommands.happyHourLuckEffect(),
        VanillaCommands.setTimeDay,
        VanillaCommands.clearWeather,
        VanillaCommands.whitelistOn,
        VanillaCommands.whitelistOff,
        VanillaCommands.whitelistReload,
        VanillaCommands.kick("Alice", reason: "test"),
        VanillaCommands.ban("Alice", reason: "test"),
        VanillaCommands.tagAddAdmin("Alice"),
        VanillaCommands.pardon("Alice"),
        VanillaCommands.clearInventory("Alice"),
        VanillaCommands.gamemode(.creative, for: "Alice"),
        VanillaCommands.giveItem(to: "Alice", itemID: "minecraft:diamond", count: 3),
        VanillaCommands.say("Hello everyone!"),
        VanillaCommands.setBlock(x: 1, y: 2, z: 3, blockState: "minecraft:stone"),
        VanillaCommands.fill(x1: 0, y1: 0, z1: 0, x2: 4, y2: 0, z2: 0, blockState: "minecraft:stone"),
        VanillaCommands.getEntityPosition("Alice")
    ] + VanillaCommands.panicModeSequence)
    func everyGeneratedCommandIsVanilla(_ command: String) {
        #expect(VanillaCommands.isStrictlyVanilla(command), "\(command) matched a disallowed non-vanilla command root")
    }

    @Test("Guard rail rejects known plugin commands typed into the console")
    func guardRailRejectsPluginCommands() {
        #expect(!VanillaCommands.isStrictlyVanilla("/tps"))
        #expect(!VanillaCommands.isStrictlyVanilla("/broadcast Hello"))
        #expect(!VanillaCommands.isStrictlyVanilla("/heal Alice"))
        #expect(!VanillaCommands.isStrictlyVanilla("/fly Alice"))
        #expect(VanillaCommands.isStrictlyVanilla("/tick query"))
        #expect(VanillaCommands.isStrictlyVanilla("/whitelist on"))
    }
}
