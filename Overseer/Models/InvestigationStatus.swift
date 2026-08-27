//
//  InvestigationStatus.swift
//  Overseer
//
//  A player's griefing/theft triage state. Deliberately just a label an
//  admin sets by hand (from the Suspicious Inventory flag, a perf-report
//  diff finding, or manually) — vanilla keeps no block-change log, so
//  nothing in this app can *prove* anything; this only tracks "who's
//  been flagged for a look," not "who's guilty."
//

import Foundation

enum InvestigationStatus: String, Codable, CaseIterable, Identifiable {
    case clear
    case watching
    case investigating
    case confirmed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .clear: return "Clear"
        case .watching: return "Watching"
        case .investigating: return "Investigating"
        case .confirmed: return "Confirmed"
        }
    }

    var systemImage: String {
        switch self {
        case .clear: return "checkmark.circle"
        case .watching: return "eye"
        case .investigating: return "magnifyingglass"
        case .confirmed: return "exclamationmark.octagon.fill"
        }
    }
}
