//
//  PerformanceView.swift
//  Overseer
//
//  Reads a manually-downloaded vanilla `/perf start` … `/perf stop`
//  report folder (system.txt + a server/ subfolder — there's no RCON
//  command that reads any of this back live) and surfaces the parts of
//  it an admin actually wants during a lag investigation: mob and block
//  entity counts, which chunks they're piled up in, tick times, which
//  profiler node is actually burning the CPU, and (Compare tab) a diff
//  against an earlier report.
//
//  File reads happen off-main via a batch of small pure parsers (see
//  Performance/), same split as InventoryAnalyzerView/SchematicBuilderView:
//  this view owns directory enumeration and security-scoped access,
//  everything else stays pure and unit-testable.
//
//  Exactly one .fileImporter exists below, shared by both the primary
//  and baseline folder pickers via `pickerTarget`. An earlier version
//  had two separate .fileImporter modifiers (one per picker) — even
//  moved onto distinct view nodes to dodge the usual "two .sheet-style
//  modifiers on one view" SwiftUI footgun, the second one still didn't
//  reliably present on macOS. Rather than chase the exact mechanism,
//  the fix is structural: there is now only one such modifier in this
//  view, so there's nothing for it to conflict with.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct PerformanceView: View {
    var sftpCoordinator: SFTPSyncCoordinator

    @Environment(\.modelContext) private var modelContext

    /// Everything one loaded report needs — used for both the primary
    /// report and the Compare tab's baseline, so the two folder-load
    /// flows share one shape instead of drifting as two parallel sets
    /// of near-identical @State vars.
    private struct ReportSlot {
        var folderName: String?
        var isScanning = false
        var report: ParsedPerfReport?
        var scanError: String?
    }

    @State private var primary = ReportSlot()
    @State private var baseline = ReportSlot()

    private enum PickerTarget {
        case primary
        case baseline
    }
    @State private var showFolderPicker = false
    @State private var pickerTarget: PickerTarget = .primary

    @State private var selectedDimension: String?
    @State private var selectedDiffDimension: String?
    @State private var selectedTab: Tab = .overview
    @State private var entityFilterText = ""
    @State private var configFilterText = ""

    enum Tab: String, CaseIterable, Identifiable {
        case overview = "Overview"
        case entities = "Entities"
        case chunks = "Chunk Hotspots"
        case cpu = "CPU Offenders"
        case compare = "Compare"
        case config = "Config"
        var id: String { rawValue }
    }

    private var dimensionDiffs: [DimensionDiff]? {
        guard let current = primary.report, let base = baseline.report else { return nil }
        return PerfReportDiff.diff(before: base, after: current)
    }

    private var selectedDim: DimensionReport? {
        guard let report = primary.report else { return nil }
        if let selectedDimension, let match = report.dimensions.first(where: { $0.name == selectedDimension }) {
            return match
        }
        return report.dimensions.first
    }

    var body: some View {
        VStack(spacing: 0) {
            folderBar
            Divider()
            if let report = primary.report {
                Picker("", selection: $selectedTab) {
                    ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(14)
                Divider()
                ScrollView {
                    content(for: report)
                        .padding(20)
                }
            } else {
                emptyState
            }
        }
        .navigationTitle("Performance")
        .fileImporter(isPresented: $showFolderPicker, allowedContentTypes: [.folder]) { result in
            switch pickerTarget {
            case .primary: handlePrimaryFolderImport(result)
            case .baseline: handleBaselineFolderImport(result)
            }
        }
    }

    @ViewBuilder
    private func content(for report: ParsedPerfReport) -> some View {
        switch selectedTab {
        case .overview: overviewTab(report)
        case .entities: entitiesTab(report)
        case .chunks: chunksTab(report)
        case .cpu: cpuTab(report)
        case .compare: compareTab()
        case .config: configTab(report)
        }
    }

    // MARK: - Folder loading

    private var folderBar: some View {
        HStack(spacing: 10) {
            Button {
                pickerTarget = .primary
                showFolderPicker = true
            } label: {
                Label("Select Perf Report Folder…", systemImage: "folder.badge.plus")
            }
            .buttonStyle(.borderedProminent)
            .disabled(primary.isScanning)

            syncedReportsMenu(into: .primary)

            if primary.isScanning {
                ProgressView().controlSize(.small)
            }
            if let folderName = primary.folderName {
                Text(folderName).font(.callout).foregroundStyle(.secondary)
            }
            if let scanError = primary.scanError {
                Label(scanError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            Spacer()
        }
        .padding(14)
    }

    /// Reports SFTPSyncCoordinator has already mirrored + unzipped
    /// locally under Application Support (see its debug/profiling
    /// sync), newest first by folder name (which starts with the
    /// report's timestamp) — an alternative to manually downloading
    /// and unzipping one from the host yourself.
    private var syncedReportNames: [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: sftpCoordinator.performanceMirrorDirectory.path)) ?? []
        return names.sorted(by: >)
    }

    private func syncedReportsMenu(into target: PickerTarget) -> some View {
        Menu {
            if syncedReportNames.isEmpty {
                Text("No synced reports yet")
            } else {
                ForEach(syncedReportNames, id: \.self) { name in
                    Button(name) { loadSyncedReport(name, into: target) }
                }
            }
        } label: {
            Label("Synced Reports", systemImage: "arrow.triangle.2.circlepath")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func loadSyncedReport(_ name: String, into target: PickerTarget) {
        let url = sftpCoordinator.performanceMirrorDirectory.appendingPathComponent(name, isDirectory: true)
        switch target {
        case .primary:
            primary.scanError = nil
            primary.folderName = name
            selectedDimension = nil
            primary.isScanning = true
            Task {
                let outcome = await Self.loadReport(rootURL: url)
                primary.isScanning = false
                switch outcome {
                case .success(let parsed): primary.report = parsed
                case .failure(let message): primary.scanError = message; primary.report = nil
                }
            }
        case .baseline:
            baseline.scanError = nil
            baseline.folderName = name
            baseline.isScanning = true
            Task {
                let outcome = await Self.loadReport(rootURL: url)
                baseline.isScanning = false
                switch outcome {
                case .success(let parsed): baseline.report = parsed
                case .failure(let message): baseline.scanError = message; baseline.report = nil
                }
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No Perf Report Loaded",
            systemImage: "speedometer",
            description: Text("Run /perf start, then /perf stop on the server, download the resulting report folder (it contains system.txt and a server/ folder), and select it here. Nothing is sent anywhere.")
        )
        .frame(maxHeight: .infinity)
    }

    private func handlePrimaryFolderImport(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let error):
            primary.scanError = error.localizedDescription
        case .success(let url):
            primary.scanError = nil
            primary.folderName = url.lastPathComponent
            selectedDimension = nil
            primary.isScanning = true
            Task {
                let outcome = await Self.loadReport(rootURL: url)
                primary.isScanning = false
                switch outcome {
                case .success(let parsed):
                    primary.report = parsed
                case .failure(let message):
                    primary.scanError = message
                    primary.report = nil
                }
            }
        }
    }

    private func handleBaselineFolderImport(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let error):
            baseline.scanError = error.localizedDescription
        case .success(let url):
            baseline.scanError = nil
            baseline.folderName = url.lastPathComponent
            baseline.isScanning = true
            Task {
                let outcome = await Self.loadReport(rootURL: url)
                baseline.isScanning = false
                switch outcome {
                case .success(let parsed):
                    baseline.report = parsed
                case .failure(let message):
                    baseline.scanError = message
                    baseline.report = nil
                }
            }
        }
    }

    private enum LoadOutcome {
        case success(ParsedPerfReport)
        case failure(String)
    }

    private static func loadReport(rootURL: URL) async -> LoadOutcome {
        await Task.detached(priority: .userInitiated) {
            let didAccess = rootURL.startAccessingSecurityScopedResource()
            defer { if didAccess { rootURL.stopAccessingSecurityScopedResource() } }

            let fileManager = FileManager.default
            func text(_ relativePath: String) -> String? {
                guard let data = try? Data(contentsOf: rootURL.appendingPathComponent(relativePath)) else { return nil }
                return String(decoding: data, as: UTF8.self)
            }

            let hasSystemInfo = fileManager.fileExists(atPath: rootURL.appendingPathComponent("system.txt").path)
            var isServerDir: ObjCBool = false
            let hasServerFolder = fileManager.fileExists(atPath: rootURL.appendingPathComponent("server").path, isDirectory: &isServerDir) && isServerDir.boolValue
            guard hasSystemInfo || hasServerFolder else {
                return .failure("That doesn't look like a /perf report folder — select the folder containing system.txt and a server/ subfolder.")
            }

            let systemInfo = text("system.txt").map { KeyValueTextParser.parse($0, separator: ":") } ?? []
            let profilingText = text("server/profiling.txt") ?? ""
            let runSummary = RunSummaryParser.parse(profilingText)
            let topOffenders = ProfilerTreeParser.topSelfTime(ProfilerTreeParser.parse(profilingText))
            let tickStats = text("server/stats.txt").map(ServerStatsParser.parse)
                ?? ServerTickStats(pendingTasks: nil, averageTickTimeMs: nil, tickTimesNanos: [])
            let gamerules = text("server/gamerules.txt").map { KeyValueTextParser.parse($0, separator: "=") } ?? []
            let serverProperties = text("server/server.properties.txt").map { KeyValueTextParser.parse($0, separator: "=") } ?? []

            var dimensions: [DimensionReport] = []
            let levelsRoot = rootURL.appendingPathComponent("server/levels/minecraft")
            if let dimFolders = try? fileManager.contentsOfDirectory(at: levelsRoot, includingPropertiesForKeys: nil) {
                for dimURL in dimFolders.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                    var isDir: ObjCBool = false
                    guard fileManager.fileExists(atPath: dimURL.path, isDirectory: &isDir), isDir.boolValue else { continue }
                    func dimText(_ file: String) -> String {
                        guard let data = try? Data(contentsOf: dimURL.appendingPathComponent(file)) else { return "" }
                        return String(decoding: data, as: UTF8.self)
                    }
                    let entitiesCSV = dimText("entities.csv")
                    let blockEntitiesCSV = dimText("block_entities.csv")
                    let chunksCSV = dimText("chunks.csv")
                    let entityChunksCSV = dimText("entity_chunks.csv")

                    guard !entitiesCSV.isEmpty || !chunksCSV.isEmpty else { continue }

                    dimensions.append(DimensionReport(
                        name: dimURL.lastPathComponent,
                        entityCounts: EntityCensusParser.count(csv: entitiesCSV),
                        blockEntityCounts: EntityCensusParser.count(csv: blockEntitiesCSV),
                        entityHotspots: ChunkHotspotParser.entityHotspots(csv: entityChunksCSV),
                        blockEntityHotspots: ChunkHotspotParser.blockEntityHotspots(csv: chunksCSV),
                        totalLoadedChunks: ChunkHotspotParser.totalLoadedChunks(csv: chunksCSV),
                        totalBlockTicks: ChunkHotspotParser.sum(csv: chunksCSV, column: "block_ticks"),
                        totalFluidTicks: ChunkHotspotParser.sum(csv: chunksCSV, column: "fluid_ticks"),
                        levelStats: KeyValueTextParser.parse(dimText("stats.txt"), separator: ":")
                    ))
                }
            }

            return .success(ParsedPerfReport(
                runSummary: runSummary, systemInfo: systemInfo, tickStats: tickStats,
                gamerules: gamerules, serverProperties: serverProperties,
                topOffenders: topOffenders, dimensions: dimensions
            ))
        }.value
    }

    // MARK: - Overview

    private func overviewTab(_ report: ParsedPerfReport) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 10)], spacing: 10) {
                SummaryCard(title: "Minecraft Version", value: report.runSummary.version ?? "—", systemImage: "shippingbox.fill", tint: .blue)
                SummaryCard(title: "Time Span", value: report.runSummary.timeSpanMs.map { String(format: "%.1fs", Double($0) / 1000) } ?? "—", systemImage: "clock.fill", tint: .purple)
                SummaryCard(title: "Tick Span", value: report.runSummary.tickSpan.map { "\($0)" } ?? "—", systemImage: "timer", tint: .orange)
                SummaryCard(title: "Approx. TPS", value: report.runSummary.approxTPS.map { String(format: "%.1f", $0) } ?? "—", systemImage: "gauge.with.dots.needle.67percent", tint: tpsColor(report.runSummary.approxTPS))
            }

            tickTimeSection(report.tickStats)

            if !report.systemInfo.isEmpty {
                DisclosureGroup("System Info") {
                    keyValueTable(report.systemInfo)
                }
                .font(.headline)
            }
        }
    }

    private func tpsColor(_ tps: Double?) -> Color {
        guard let tps else { return .accentColor }
        if tps >= 19 { return .green }
        if tps >= 15 { return .orange }
        return .red
    }

    @ViewBuilder
    private func tickTimeSection(_ stats: ServerTickStats) -> some View {
        if !stats.tickTimesMs.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Tick Times (last \(stats.tickTimesMs.count) ticks recorded)").font(.headline)
                TickTimeChart(millis: stats.tickTimesMs)
                    .frame(height: 160)
                HStack(spacing: 12) {
                    SummaryCard(title: "Average", value: String(format: "%.1f ms", stats.tickTimesMs.reduce(0, +) / Double(stats.tickTimesMs.count)), systemImage: "chart.bar.fill", tint: .blue)
                    SummaryCard(title: "Worst Tick", value: String(format: "%.1f ms", stats.tickTimesMs.max() ?? 0), systemImage: "exclamationmark.triangle.fill", tint: .red)
                    SummaryCard(title: "Lag Spikes (>50ms)", value: "\(stats.tickTimesMs.filter { $0 > 50 }.count)", systemImage: "bolt.trianglebadge.exclamationmark.fill", tint: .orange)
                    if let reported = stats.averageTickTimeMs {
                        SummaryCard(title: "Server-Reported Avg", value: String(format: "%.1f ms", reported), systemImage: "server.rack", tint: .secondary)
                    }
                }
            }
        }
    }

    private func keyValueTable(_ pairs: [KeyValuePair]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(pairs) { pair in
                HStack(alignment: .top) {
                    Text(pair.key).font(.caption.weight(.medium)).foregroundStyle(.secondary).frame(width: 200, alignment: .leading)
                    Text(pair.value).font(.caption).textSelection(.enabled)
                    Spacer()
                }
            }
        }
        .padding(.top, 6)
    }

    // MARK: - Entities

    private func entitiesTab(_ report: ParsedPerfReport) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            namePicker(names: report.dimensions.map(\.name), selection: $selectedDimension)
            TextField("Filter by type", text: $entityFilterText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 260)

            if let dim = selectedDim {
                HStack(alignment: .top, spacing: 20) {
                    entityCountColumn(title: "Entities", total: dim.totalEntities, counts: dim.entityCounts)
                    entityCountColumn(title: "Block Entities", total: dim.totalBlockEntities, counts: dim.blockEntityCounts)
                }
            } else {
                Text("No dimension data in this report.").foregroundStyle(.secondary)
            }
        }
    }

    private func entityCountColumn(title: String, total: Int, counts: [EntityTypeCount]) -> some View {
        let filtered = entityFilterText.isEmpty ? counts : counts.filter { $0.type.localizedCaseInsensitiveContains(entityFilterText) }
        return VStack(alignment: .leading, spacing: 6) {
            Text("\(title) (\(total) total)").font(.headline)
            VStack(spacing: 0) {
                ForEach(filtered) { entry in
                    HStack {
                        Text(minecraftDisplayName(entry.type)).font(.callout)
                        Spacer()
                        Text("\(entry.count)").font(.callout.monospacedDigit().weight(.medium))
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    Divider()
                }
                if filtered.isEmpty {
                    Text("None").font(.caption).foregroundStyle(.secondary).padding(8)
                }
            }
            .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Chunk hotspots

    private func chunksTab(_ report: ParsedPerfReport) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            namePicker(names: report.dimensions.map(\.name), selection: $selectedDimension)

            if let dim = selectedDim {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                    SummaryCard(title: "Loaded Chunks", value: "\(dim.totalLoadedChunks)", systemImage: "square.grid.3x3.fill", tint: .blue)
                    SummaryCard(title: "Block Ticks", value: "\(dim.totalBlockTicks)", systemImage: "cube.fill", tint: .green)
                    SummaryCard(title: "Fluid Ticks", value: "\(dim.totalFluidTicks)", systemImage: "drop.fill", tint: .cyan)
                }

                HStack(alignment: .top, spacing: 20) {
                    hotspotColumn(title: "Most Entities (chunk section)", hotspots: dim.entityHotspots)
                    hotspotColumn(title: "Most Block Entities (chunk column)", hotspots: dim.blockEntityHotspots)
                }

                if !dim.levelStats.isEmpty {
                    DisclosureGroup("Level Stats") {
                        keyValueTable(dim.levelStats)
                    }
                    .font(.headline)
                }
            } else {
                Text("No dimension data in this report.").foregroundStyle(.secondary)
            }
        }
    }

    private func hotspotColumn(title: String, hotspots: [ChunkHotspot]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            VStack(spacing: 0) {
                ForEach(hotspots) { spot in
                    HStack {
                        Text(spot.y != nil ? "\(spot.x), \(spot.y!), \(spot.z)" : "\(spot.x), \(spot.z)")
                            .font(.callout.monospaced())
                            .textSelection(.enabled)
                        Spacer()
                        Text("\(spot.value)").font(.callout.monospacedDigit().weight(.medium))
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    Divider()
                }
                if hotspots.isEmpty {
                    Text("None").font(.caption).foregroundStyle(.secondary).padding(8)
                }
            }
            .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - CPU offenders

    private func cpuTab(_ report: ParsedPerfReport) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Top profiler nodes by self-time — time spent in that specific system, excluding its children.")
                .font(.caption)
                .foregroundStyle(.secondary)
            VStack(spacing: 0) {
                ForEach(report.topOffenders) { node in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(node.name).font(.callout.weight(.medium))
                            Spacer()
                            Text(String(format: "%.2f%% self", node.selfPercent)).font(.callout.monospacedDigit()).foregroundStyle(.red)
                            Text(String(format: "%.2f%% total", node.totalPercent)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        Text(node.breadcrumb)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    Divider()
                }
                if report.topOffenders.isEmpty {
                    Text("No profiler data in this report.").font(.caption).foregroundStyle(.secondary).padding(8)
                }
            }
            .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    // MARK: - Compare

    private func compareTab() -> some View {
        VStack(alignment: .leading, spacing: 14) {
            baselineFolderBar
            if let diffs = dimensionDiffs {
                if diffs.allSatisfy({ $0.entityDeltas.isEmpty && $0.blockEntityDeltas.isEmpty }) {
                    ContentUnavailableView(
                        "No Changes Detected",
                        systemImage: "checkmark.circle",
                        description: Text("Entity and block entity counts match between the two reports.")
                    )
                } else {
                    namePicker(names: diffs.map(\.name), selection: $selectedDiffDimension)
                    if let dim = selectedDiff(diffs) {
                        HStack(alignment: .top, spacing: 20) {
                            diffColumn(title: "Entities", dimensionName: dim.name, deltas: dim.entityDeltas)
                            diffColumn(title: "Block Entities", dimensionName: dim.name, deltas: dim.blockEntityDeltas)
                        }
                    }
                }
            } else {
                ContentUnavailableView(
                    "Select a Baseline",
                    systemImage: "arrow.left.arrow.right",
                    description: Text("Load a second report from before a suspected incident to compare against the one loaded above. Only aggregate entity/block-entity counts per dimension are compared — those are exhaustive (every row in entities.csv/block_entities.csv), not just the top-15 hotspot lists, so the numbers here are trustworthy even though exact chunk locations aren't diffed.")
                )
            }
        }
    }

    private var baselineFolderBar: some View {
        HStack(spacing: 10) {
            Button {
                pickerTarget = .baseline
                showFolderPicker = true
            } label: {
                Label("Select Baseline Report…", systemImage: "folder.badge.plus")
            }
            .buttonStyle(.bordered)
            .disabled(baseline.isScanning)

            syncedReportsMenu(into: .baseline)

            if baseline.isScanning {
                ProgressView().controlSize(.small)
            }
            if let baselineFolderName = baseline.folderName {
                Text("Baseline: \(baselineFolderName)").font(.callout).foregroundStyle(.secondary)
            }
            if let baselineScanError = baseline.scanError {
                Label(baselineScanError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            Spacer()
        }
    }

    private func selectedDiff(_ diffs: [DimensionDiff]) -> DimensionDiff? {
        if let selectedDiffDimension, let match = diffs.first(where: { $0.name == selectedDiffDimension }) {
            return match
        }
        return diffs.first
    }

    private func diffColumn(title: String, dimensionName: String, deltas: [CountDelta]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            if deltas.isEmpty {
                Text("No change").font(.caption).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(deltas) { delta in
                        HStack {
                            Text(minecraftDisplayName(delta.type)).font(.callout)
                            Spacer()
                            Text("\(delta.before) → \(delta.after)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Text(delta.delta > 0 ? "+\(delta.delta)" : "\(delta.delta)")
                                .font(.callout.monospacedDigit().weight(.semibold))
                                .foregroundStyle(delta.delta < 0 ? .red : .green)
                                .frame(width: 50, alignment: .trailing)
                            Button {
                                addDiffToInvestigation(dimensionName: dimensionName, delta: delta)
                            } label: {
                                Image(systemName: "doc.badge.plus")
                            }
                            .buttonStyle(.plain)
                            .help("Add to Investigation")
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        Divider()
                    }
                }
                .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Not attributed to a player — a diff finding is a location/dimension
    /// fact, not proof anyone specific did it — so this logs a general
    /// note (nil username) rather than forcing a guess onto someone's page.
    private func addDiffToInvestigation(dimensionName: String, delta: CountDelta) {
        let direction = delta.delta > 0 ? "increased" : "decreased"
        let text = "\(minecraftDisplayName(delta.type)) in \(dimensionName.replacingOccurrences(of: "_", with: " ")) \(direction) from \(delta.before) to \(delta.after) (\(delta.delta > 0 ? "+" : "")\(delta.delta)) between the two loaded perf reports."
        modelContext.insert(InvestigationNote(username: nil, text: text, source: "perf-diff"))
        try? modelContext.save()
    }

    // MARK: - Config

    private func configTab(_ report: ParsedPerfReport) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField("Filter", text: $configFilterText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 260)
            HStack(alignment: .top, spacing: 20) {
                configColumn(title: "Gamerules", pairs: report.gamerules)
                configColumn(title: "Server Properties", pairs: report.serverProperties)
            }
        }
    }

    private func configColumn(title: String, pairs: [KeyValuePair]) -> some View {
        let filtered = configFilterText.isEmpty ? pairs : pairs.filter { $0.key.localizedCaseInsensitiveContains(configFilterText) }
        return VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            keyValueTable(filtered)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Shared

    /// Segmented dimension picker, shared by the Entities/Chunks tabs
    /// (over a report's own dimensions) and the Compare tab (over a
    /// diff's dimensions) — both are just "a list of names, pick one."
    private func namePicker(names: [String], selection: Binding<String?>) -> some View {
        Group {
            if names.count > 1 {
                Picker("Dimension", selection: Binding(
                    get: { selection.wrappedValue ?? names.first ?? "" },
                    set: { selection.wrappedValue = $0 }
                )) {
                    ForEach(names, id: \.self) { name in
                        Text(name.replacingOccurrences(of: "_", with: " ").capitalized).tag(name)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 420)
            }
        }
    }

    private func minecraftDisplayName(_ id: String) -> String {
        let bare = id.split(separator: ":").last.map(String.init) ?? id
        return bare.split(separator: "_").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }
}

// MARK: - Tick time chart

private struct TickTimeChart: View {
    var millis: [Double]

    var body: some View {
        GeometryReader { geo in
            let maxValue = max(millis.max() ?? 1, 50)
            let barWidth = millis.isEmpty ? 0 : geo.size.width / CGFloat(millis.count)
            ZStack(alignment: .bottomLeading) {
                Path { path in
                    let y = geo.size.height * (1 - 50 / maxValue)
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: geo.size.width, y: y))
                }
                .stroke(Color.red.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

                HStack(alignment: .bottom, spacing: 1) {
                    ForEach(Array(millis.enumerated()), id: \.offset) { _, value in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(value > 50 ? Color.red : Color.accentColor)
                            .frame(width: max(1, barWidth - 1), height: max(1, geo.size.height * CGFloat(value / maxValue)))
                    }
                }
            }
        }
    }
}
