//
//  SuspicionEngine.swift
//  Overseer
//
//  Flags "valuable items in the hands of someone who hasn't been around
//  long enough to plausibly have earned them" — an honest, circumstantial
//  triage signal, not proof. Vanilla keeps no block-change log, so this
//  app can never show *how* a player got an item; it can only combine
//  two things it genuinely has (a parsed inventory, and tracked
//  playtime) into "this is worth a look."
//

import Foundation

struct SuspicionFlag {
    var watchlistedItems: [InventoryItemStack]
    var playTimeSeconds: Double
    var lowPlaytimeThresholdSeconds: Double

    var hasWatchlistedItems: Bool { !watchlistedItems.isEmpty }

    /// The actual "flag this" signal — valuable items paired with too
    /// little tracked playtime to have plausibly earned them legitimately.
    var isLowPlaytimeWithValuables: Bool {
        hasWatchlistedItems && playTimeSeconds < lowPlaytimeThresholdSeconds
    }
}

enum SuspicionEngine {
    static func evaluate(
        player: ParsedPlayerData,
        playTimeSeconds: Double,
        lowPlaytimeThresholdSeconds: Double = 2 * 3600
    ) -> SuspicionFlag {
        let matches = player.allItems.filter { ValuableItemWatchlist.matches($0.itemID) }
        return SuspicionFlag(
            watchlistedItems: matches,
            playTimeSeconds: playTimeSeconds,
            lowPlaytimeThresholdSeconds: lowPlaytimeThresholdSeconds
        )
    }
}
