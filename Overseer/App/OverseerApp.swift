//
//  OverseerApp.swift
//  Overseer
//
//  App entry point: wires the shared SwiftData container to a single
//  ServerQueryEngine / PollingCoordinator, exposed to both the main
//  window (NavigationSplitView) and the MenuBarExtra.
//

import SwiftUI
import SwiftData

@main
struct OverseerApp: App {
    @State private var settings = AppSettings()
    private let coordinator: PollingCoordinator
    private let dashboardViewModel: DashboardViewModel
    private let rconCoordinator: RCONAutomationCoordinator
    private let sftpCoordinator: SFTPSyncCoordinator
    private let autoUpdaterCoordinator: AutoUpdaterCoordinator
    private let worldMapCache = WorldMapCache()
    private let container: ModelContainer

    init() {
        // Must happen before the poll loops start below — see
        // AppNapPreventer's doc comment for why an always-on monitoring
        // app needs this.
        AppNapPreventer.begin()

        let stack = SwiftDataStack.shared
        container = stack.container

        let settings = AppSettings()

        let engine = ServerQueryEngine(configuration: settings.engineConfiguration)
        let coordinator = PollingCoordinator(
            modelContext: stack.container.mainContext,
            engine: engine,
            pollInterval: settings.pollInterval
        )

        // RCON runs over its own TCP connection, entirely independent
        // of the GS4/SLP engine above — its own actor, own reconnect
        // policy, own failure domain.
        let rconClient = RCONClient(configuration: settings.rconConfiguration)
        let rconCoordinator = RCONAutomationCoordinator(
            rcon: rconClient,
            modelContext: stack.container.mainContext,
            tickPollInterval: settings.rconTickPollInterval
        )
        rconCoordinator.automationEnabled = settings.rconAutomationEnabled
        rconCoordinator.entityCleanupEnabled = settings.entityCleanupEnabled
        rconCoordinator.entityCleanupIntervalMinutes = settings.entityCleanupIntervalMinutes
        rconCoordinator.entityCleanupCategories = settings.entityCleanupCategories
        rconCoordinator.entityCleanupWarnBeforeClear = settings.entityCleanupWarnBeforeClear
        rconCoordinator.entityCleanupWarnLeadSeconds = settings.entityCleanupWarnLeadSeconds
        rconCoordinator.entityCleanupWarnMessage = settings.entityCleanupWarnMessage
        rconCoordinator.positionTrackingEnabled = settings.positionTrackingEnabled
        rconCoordinator.positionTrackingIntervalMinutes = settings.positionTrackingIntervalMinutes
        rconCoordinator.configWatchdogEnabled = settings.configWatchdogEnabled
        coordinator.automation = rconCoordinator

        // SFTP sync is entirely independent of RCON/GS4 — its own
        // connection, its own failure domain — so a laggy or unreachable
        // SFTP host can never affect the live monitoring loops above.
        let sftpCoordinator = SFTPSyncCoordinator(modelContext: stack.container.mainContext)
        sftpCoordinator.host = settings.sftpHost
        sftpCoordinator.port = settings.sftpPort
        sftpCoordinator.username = settings.sftpUsername
        sftpCoordinator.password = settings.sftpPassword
        sftpCoordinator.syncIntervalMinutes = settings.sftpSyncIntervalMinutes
        sftpCoordinator.syncLocationEnabled = settings.sftpSyncLocationEnabled
        sftpCoordinator.syncPlaytimeEnabled = settings.sftpSyncPlaytimeEnabled
        sftpCoordinator.syncInventoryEnabled = settings.sftpSyncInventoryEnabled
        sftpCoordinator.syncPerformanceEnabled = settings.sftpSyncPerformanceEnabled
        sftpCoordinator.syncWorldMapEnabled = settings.sftpSyncWorldMapEnabled
        sftpCoordinator.logsBackfillCompleted = settings.sftpLogsBackfillCompleted

        let dashboardViewModel = DashboardViewModel(coordinator: coordinator)

        // Reads the live-reported running version straight off the same
        // poll DashboardViewModel already surfaces — see
        // AutoUpdaterCoordinator's file-level comment for why that
        // (rather than "whatever was last deployed") is the right
        // ground truth to check against.
        let autoUpdaterCoordinator = AutoUpdaterCoordinator(
            rconCoordinator: rconCoordinator,
            modelContext: stack.container.mainContext,
            currentServerVersion: { [dashboardViewModel] in dashboardViewModel.serverVersion }
        )
        autoUpdaterCoordinator.enabled = settings.autoUpdaterEnabled
        autoUpdaterCoordinator.checkIntervalMinutes = settings.autoUpdaterIntervalMinutes
        autoUpdaterCoordinator.host = settings.sftpHost
        autoUpdaterCoordinator.port = settings.sftpPort
        autoUpdaterCoordinator.username = settings.sftpUsername
        autoUpdaterCoordinator.password = settings.sftpPassword

        self._settings = State(initialValue: settings)
        self.coordinator = coordinator
        self.dashboardViewModel = dashboardViewModel
        self.rconCoordinator = rconCoordinator
        self.sftpCoordinator = sftpCoordinator
        self.autoUpdaterCoordinator = autoUpdaterCoordinator

        // Persists the one-time logs.zip backfill flag back to
        // AppSettings — the same settings/coordinator split used for
        // every other cross-cutting toggle in this app (see
        // EntityManagementView's onChange wiring for the precedent);
        // captured here since only the App struct holds both objects
        // at init time.
        sftpCoordinator.onBackfillCompletedChange = { [settings] completed in
            settings.sftpLogsBackfillCompleted = completed
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView(settings: settings, coordinator: coordinator, dashboardViewModel: dashboardViewModel, rconCoordinator: rconCoordinator, sftpCoordinator: sftpCoordinator, autoUpdaterCoordinator: autoUpdaterCoordinator, worldMapCache: worldMapCache)
        }
        .modelContainer(container)
        .commands {
            CommandGroup(replacing: .newItem) { } // single-window monitoring app; no "New Window"
        }

        MenuBarExtra {
            MenuBarExtraContentView(viewModel: dashboardViewModel, coordinator: coordinator)
        } label: {
            MenuBarExtraLabel(viewModel: dashboardViewModel)
        }
        .menuBarExtraStyle(.window)
    }
}
