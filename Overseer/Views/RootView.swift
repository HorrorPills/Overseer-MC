//
//  RootView.swift
//  Overseer
//
//  NavigationSplitView shell: Dashboard / Historical Analytics /
//  Settings in the sidebar, matching the native macOS idiom the spec
//  asks for.
//

import SwiftUI

enum RootSection: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case players = "Players"
    case leaderboards = "Leaderboards"
    case broadcasts = "Broadcasts"
    case accessControl = "Access Control"
    case schematics = "Schematic Builder"
    case inventoryAnalyzer = "Inventory Analyzer"
    case playtimeImporter = "Playtime Importer"
    case performance = "Performance"
    case entityManagement = "Entity Management"
    case location = "Location"
    case worldMap = "World Map"
    case history = "Server History"
    case rconConsole = "RCON Console"
    case settings = "Settings"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .dashboard: return "gauge.with.dots.needle.67percent"
        case .players: return "person.3.fill"
        case .leaderboards: return "trophy.fill"
        case .broadcasts: return "megaphone.fill"
        case .accessControl: return "lock.shield.fill"
        case .schematics: return "cube.transparent"
        case .inventoryAnalyzer: return "shippingbox.fill"
        case .playtimeImporter: return "clock.arrow.circlepath"
        case .performance: return "speedometer"
        case .entityManagement: return "trash.circle.fill"
        case .location: return "globe.americas.fill"
        case .worldMap: return "map.fill"
        case .history: return "chart.xyaxis.line"
        case .rconConsole: return "terminal.fill"
        case .settings: return "gearshape"
        }
    }
}

struct RootView: View {
    var settings: AppSettings
    var coordinator: PollingCoordinator
    var dashboardViewModel: DashboardViewModel
    var rconCoordinator: RCONAutomationCoordinator
    var sftpCoordinator: SFTPSyncCoordinator
    var autoUpdaterCoordinator: AutoUpdaterCoordinator
    var worldMapCache: WorldMapCache

    @State private var selection: RootSection? = .dashboard

    var body: some View {
        NavigationSplitView {
            List(RootSection.allCases, selection: $selection) { section in
                Label(section.rawValue, systemImage: section.systemImage)
                    .tag(section)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            // Each section gets its own NavigationStack (rather than one
            // shared stack around the switch) so a pushed PlayerDetailView
            // doesn't linger when the sidebar selection changes — leaving
            // "Players" for "Settings" and back should always land back
            // on the roster, not wherever the push stack was left.
            switch selection ?? .dashboard {
            case .dashboard:
                NavigationStack {
                    DashboardView(viewModel: dashboardViewModel, settings: settings, rconCoordinator: rconCoordinator)
                        .navigationDestination(for: Player.self) { player in
                            PlayerDetailView(player: player, rconCoordinator: rconCoordinator, viewModel: dashboardViewModel)
                        }
                }
            case .players:
                NavigationStack {
                    PlayerDirectoryView(rconCoordinator: rconCoordinator, viewModel: dashboardViewModel)
                        .navigationDestination(for: Player.self) { player in
                            PlayerDetailView(player: player, rconCoordinator: rconCoordinator, viewModel: dashboardViewModel)
                        }
                }
            case .leaderboards:
                NavigationStack {
                    LeaderboardView(viewModel: dashboardViewModel, settings: settings)
                        .navigationDestination(for: Player.self) { player in
                            PlayerDetailView(player: player, rconCoordinator: rconCoordinator, viewModel: dashboardViewModel)
                        }
                }
            case .broadcasts:
                NavigationStack {
                    BroadcastMessagesView(rconCoordinator: rconCoordinator)
                }
            case .accessControl:
                NavigationStack {
                    AccessControlView(rconCoordinator: rconCoordinator)
                }
            case .schematics:
                NavigationStack {
                    SchematicBuilderView(rconCoordinator: rconCoordinator)
                }
            case .inventoryAnalyzer:
                NavigationStack {
                    InventoryAnalyzerView(sftpCoordinator: sftpCoordinator)
                }
            case .playtimeImporter:
                NavigationStack {
                    PlaytimeImporterView()
                }
            case .performance:
                NavigationStack {
                    PerformanceView(sftpCoordinator: sftpCoordinator)
                }
            case .entityManagement:
                NavigationStack {
                    EntityManagementView(settings: settings, rconCoordinator: rconCoordinator)
                }
            case .location:
                NavigationStack {
                    LocationView(sftpCoordinator: sftpCoordinator)
                }
            case .worldMap:
                NavigationStack {
                    WorldMapView(sftpCoordinator: sftpCoordinator, cache: worldMapCache)
                }
            case .history:
                NavigationStack {
                    ServerHistoryView()
                }
            case .rconConsole:
                NavigationStack {
                    RCONConsoleView(coordinator: rconCoordinator)
                }
            case .settings:
                NavigationStack {
                    SettingsView(settings: settings, coordinator: coordinator, rconCoordinator: rconCoordinator, sftpCoordinator: sftpCoordinator, autoUpdaterCoordinator: autoUpdaterCoordinator)
                }
            }
        }
        .task {
            if settings.autoStartOnLaunch {
                coordinator.updatePollInterval(settings.pollInterval)
                coordinator.start()
                rconCoordinator.updateTickPollInterval(settings.rconTickPollInterval)
                rconCoordinator.startTickPolling()
                rconCoordinator.startBroadcastScheduler()
                rconCoordinator.startTempBanScheduler()
                rconCoordinator.startEntityCleanupScheduler()
                rconCoordinator.startConfigWatchdog()
                rconCoordinator.startPositionTracking()
            }
            if settings.sftpEnabled {
                sftpCoordinator.startScheduler()
            }
            // Always started, regardless of settings.autoUpdaterEnabled —
            // the coordinator's own checkLoop no-ops each cycle unless
            // `enabled` is on, so flipping the Settings toggle at runtime
            // takes effect on the very next tick rather than needing an
            // app relaunch.
            autoUpdaterCoordinator.startChecking()
        }
    }
}
