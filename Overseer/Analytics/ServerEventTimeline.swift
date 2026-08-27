//
//  ServerEventTimeline.swift
//  Overseer
//
//  Merges every kind of "something happened on the server" record this
//  app already keeps — outages, config/gamerule drift, Auto Updater
//  deploys, and moderation actions — into one chronological feed. Each
//  of those lived in total isolation before this file existed: an
//  admin trying to answer "what happened around 9pm last Tuesday" had
//  to separately check the Dashboard's outage table, Access Control's
//  config-drift log, Settings' Auto Updater log, and every individual
//  player's moderation history. This is the single place that answers
//  it in one scroll.
//
//  Pure and side-effect-free, like AnalyticsEngine/PlayerStatsEngine —
//  takes plain arrays already fetched via @Query, filters/merges/sorts.
//

import Foundation

enum ServerEventCategory: String, CaseIterable, Identifiable {
    case outage = "Outages"
    case configChange = "Config Changes"
    case update = "Updates"
    case moderation = "Moderation"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .outage: return "exclamationmark.triangle.fill"
        case .configChange: return "slider.horizontal.3"
        case .update: return "arrow.down.circle.fill"
        case .moderation: return "hand.raised.fill"
        }
    }
}

struct ServerTimelineEntry: Identifiable, Equatable {
    var id: String
    var timestamp: Date
    var category: ServerEventCategory
    var title: String
    var detail: String
    /// Drives the row's accent color — red for something worth a second
    /// look (a real outage, a failed deploy, a ban), neutral otherwise
    /// (a scheduled restart, a successful deploy, a config change that
    /// might be entirely intentional).
    var isNotable: Bool
}

enum ServerEventTimeline {
    static func build(
        outages: [AnalyticsEngine.OutageEvent],
        configChanges: [ConfigChangeEvent],
        updates: [ServerUpdateEvent],
        moderation: [ModerationEvent],
        categories: Set<ServerEventCategory> = Set(ServerEventCategory.allCases),
        since start: Date? = nil
    ) -> [ServerTimelineEntry] {
        var entries: [ServerTimelineEntry] = []

        if categories.contains(.outage) {
            for outage in outages where start == nil || outage.start >= start! {
                entries.append(makeEntry(outage))
            }
        }
        if categories.contains(.configChange) {
            for change in configChanges where start == nil || change.timestamp >= start! {
                entries.append(makeEntry(change))
            }
        }
        if categories.contains(.update) {
            for update in updates where start == nil || update.timestamp >= start! {
                entries.append(makeEntry(update))
            }
        }
        if categories.contains(.moderation) {
            for event in moderation where start == nil || event.timestamp >= start! {
                entries.append(makeEntry(event))
            }
        }

        return entries.sorted { $0.timestamp > $1.timestamp }
    }

    // MARK: - Per-source-type entry construction (split out from `build`
    // to keep each mapping trivial for the type-checker — see this
    // project's established precedent, e.g. SettingsView's file header).

    private static func makeEntry(_ outage: AnalyticsEngine.OutageEvent) -> ServerTimelineEntry {
        ServerTimelineEntry(
            id: "outage-\(outage.start.timeIntervalSinceReferenceDate)",
            timestamp: outage.start,
            category: .outage,
            title: outage.isLikelyScheduledRestart ? "Scheduled restart" : "Server outage",
            detail: "Offline for \(formatDuration(outage.durationSeconds))",
            isNotable: !outage.isLikelyScheduledRestart
        )
    }

    private static func makeEntry(_ change: ConfigChangeEvent) -> ServerTimelineEntry {
        ServerTimelineEntry(
            id: "config-\(change.timestamp.timeIntervalSinceReferenceDate)-\(change.key)",
            timestamp: change.timestamp,
            category: .configChange,
            title: "\(change.key) changed",
            detail: "\(change.oldValue) → \(change.newValue)",
            isNotable: true // any drift on a strictly-vanilla server is worth a look — see ConfigChangeEvent's doc comment
        )
    }

    private static func makeEntry(_ update: ServerUpdateEvent) -> ServerTimelineEntry {
        let title = update.succeeded ? "Deployed \(update.toVersion)" : "Deploy to \(update.toVersion) failed"
        let detail = update.succeeded ? "Was running \(update.fromVersion)" : update.detail
        return ServerTimelineEntry(
            id: "update-\(update.timestamp.timeIntervalSinceReferenceDate)",
            timestamp: update.timestamp,
            category: .update,
            title: title,
            detail: detail,
            isNotable: !update.succeeded
        )
    }

    private static func makeEntry(_ event: ModerationEvent) -> ServerTimelineEntry {
        ServerTimelineEntry(
            id: "mod-\(event.timestamp.timeIntervalSinceReferenceDate)-\(event.username)",
            timestamp: event.timestamp,
            category: .moderation,
            title: "\(event.kind.label): \(event.username)",
            detail: event.detail,
            isNotable: event.kind == .ban || event.kind == .kick
        )
    }
}
