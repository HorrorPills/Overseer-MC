//
//  SchematicBuilderView.swift
//  Overseer
//
//  Load a Sponge Schematic (.schem), configure where/how to place it,
//  and stream it into the world over RCON. See Schematic/ for the
//  parsing/transform/planning pipeline and SchematicBuildQueue for the
//  rate-limited dispatch loop this view drives.
//
//  File read + NBT parse happen off-main (large schematics can be tens
//  of thousands of blocks); placement/command-planning are cheap enough
//  to run on MainActor but are still cached rather than recomputed on
//  every body evaluation, since this view re-renders continuously while
//  a build's progress is updating.
//

import SwiftUI
import UniformTypeIdentifiers

struct SchematicBuilderView: View {
    var rconCoordinator: RCONAutomationCoordinator

    @State private var showFileImporter = false
    @State private var isLoadingFile = false
    @State private var loadedSchematic: ParsedSchematic?
    @State private var loadedFileName: String?
    @State private var loadError: String?

    @State private var targetX = "0"
    @State private var targetY = "64"
    @State private var targetZ = "0"
    @State private var fetchPositionPlayerName = ""
    @State private var isFetchingPosition = false

    @State private var rotation: Rotation = .none
    @State private var anchor: AnchorPoint = .corner
    @State private var ignoreAir = true
    @State private var optimizeWithFill = true
    @State private var commandsPerSecond: Double = 200

    @State private var cachedPlacedBlocks: [PlacedBlock] = []
    @State private var cachedCommands: [String] = []

    @State private var buildQueue: SchematicBuildQueue?

    private var targetPosition: WorldPosition? {
        guard let x = Int(targetX), let y = Int(targetY), let z = Int(targetZ) else { return nil }
        return WorldPosition(x: x, y: y, z: z)
    }

    private var estimatedDuration: Double {
        commandsPerSecond > 0 ? Double(cachedCommands.count) / commandsPerSecond : 0
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                fileSection
                if loadedSchematic != nil {
                    Divider()
                    placementForm
                    Divider()
                    previewSection
                    startButton
                    progressSection
                }
            }
            .padding(20)
        }
        .navigationTitle("Schematic Builder")
    }

    // MARK: - File loading

    private var fileSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button {
                    showFileImporter = true
                } label: {
                    Label("Load Schematic…", systemImage: "doc.badge.plus")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isLoadingFile)

                if isLoadingFile {
                    ProgressView().controlSize(.small)
                }
                if let loadedFileName {
                    Text(loadedFileName).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
            }
            if let schematic = loadedSchematic {
                Text("\(schematic.width) × \(schematic.height) × \(schematic.length) — \(schematic.blocks.count) blocks in file")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let loadError {
                Label(loadError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [UTType(filenameExtension: "schem") ?? .data],
            onCompletion: handleFileImport
        )
    }

    private func handleFileImport(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let error):
            loadError = error.localizedDescription
        case .success(let url):
            loadError = nil
            isLoadingFile = true
            Task {
                let outcome = await Self.loadAndParse(url: url)
                isLoadingFile = false
                switch outcome {
                case .success(let schematic, let fileName):
                    loadedSchematic = schematic
                    loadedFileName = fileName
                    recomputePreview()
                case .failure(let message):
                    loadError = message
                }
            }
        }
    }

    /// Swift's `Result` requires its Failure type to conform to `Error`,
    /// which a plain `String` message doesn't — a dedicated outcome enum
    /// is simpler here than wrapping the message in a throwaway Error type.
    private enum LoadOutcome {
        case success(ParsedSchematic, String)
        case failure(String)
    }

    /// Deliberately `static` (captures no `self`) so the file read and
    /// NBT parse run on a detached task without needing this View
    /// struct itself to cross the actor boundary.
    private static func loadAndParse(url: URL) async -> LoadOutcome {
        await Task.detached(priority: .userInitiated) {
            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                let schematic = try SpongeSchematicParser.parse(data: data)
                return .success(schematic, url.lastPathComponent)
            } catch let error as LocalizedError {
                return .failure(error.errorDescription ?? "Failed to load schematic.")
            } catch {
                return .failure(error.localizedDescription)
            }
        }.value
    }

    // MARK: - Placement form

    private var placementForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Placement").font(.headline)

            HStack(spacing: 10) {
                coordinateField("X", text: $targetX)
                coordinateField("Y", text: $targetY)
                coordinateField("Z", text: $targetZ)
            }

            HStack(spacing: 8) {
                TextField("Player name", text: $fetchPositionPlayerName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)
                Button {
                    fetchPlayerPosition()
                } label: {
                    if isFetchingPosition {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Fetch Player Position", systemImage: "location.fill")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(fetchPositionPlayerName.trimmingCharacters(in: .whitespaces).isEmpty || isFetchingPosition)
            }

            Picker("Rotation", selection: $rotation) {
                ForEach(Rotation.allCases) { r in Text(r.displayName).tag(r) }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 320)
            .onChange(of: rotation) { _, _ in recomputePreview() }

            Picker("Anchor", selection: $anchor) {
                ForEach(AnchorPoint.allCases) { point in Text(point.rawValue).tag(point) }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 420)
            .onChange(of: anchor) { _, _ in recomputePreview() }

            Toggle("Ignore Air Blocks", isOn: $ignoreAir)
                .onChange(of: ignoreAir) { _, _ in recomputePreview() }
            Toggle("Optimize with /fill commands", isOn: $optimizeWithFill)
                .onChange(of: optimizeWithFill) { _, _ in recomputePreview() }

            Stepper(value: $commandsPerSecond, in: 1...2000, step: 10) {
                Text("Rate limit: \(Int(commandsPerSecond)) commands/sec")
            }
        }
        .onChange(of: targetX) { _, _ in recomputePreview() }
        .onChange(of: targetY) { _, _ in recomputePreview() }
        .onChange(of: targetZ) { _, _ in recomputePreview() }
    }

    private func coordinateField(_ label: String, text: Binding<String>) -> some View {
        HStack(spacing: 4) {
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            TextField("", text: text)
                .textFieldStyle(.roundedBorder)
                .frame(width: 70)
        }
    }

    private func fetchPlayerPosition() {
        let name = fetchPositionPlayerName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        isFetchingPosition = true
        Task {
            let response = await rconCoordinator.sendConsoleCommand(VanillaCommands.getEntityPosition(name))
            isFetchingPosition = false
            guard let position = try? EntityPositionParser.parse(response) else {
                loadError = "Couldn't read \(name)'s position — are they online?"
                return
            }
            targetX = String(Int(position.x.rounded(.down)))
            targetY = String(Int(position.y.rounded(.down)))
            targetZ = String(Int(position.z.rounded(.down)))
            recomputePreview()
        }
    }

    // MARK: - Preview

    private func recomputePreview() {
        guard let schematic = loadedSchematic, let target = targetPosition else {
            cachedPlacedBlocks = []
            cachedCommands = []
            return
        }
        let placed = SchematicPlacer.placedBlocks(
            schematic: schematic, target: target,
            rotation: rotation, anchor: anchor, ignoreAir: ignoreAir
        )
        cachedPlacedBlocks = placed
        cachedCommands = optimizeWithFill
            ? RCONCommandPlanner.optimizedCommands(for: placed)
            : RCONCommandPlanner.setBlockCommands(for: placed)
    }

    private var previewSection: some View {
        HStack(spacing: 12) {
            SummaryCard(title: "Total Blocks", value: "\(cachedPlacedBlocks.count)", systemImage: "cube.fill", tint: .blue)
            SummaryCard(title: "Commands", value: "\(cachedCommands.count)", systemImage: "terminal.fill", tint: .purple)
            SummaryCard(title: "Est. Duration", value: formatDuration(estimatedDuration), systemImage: "clock.fill", tint: .green)
        }
    }

    // MARK: - Build

    private var startButton: some View {
        Button {
            startBuild()
        } label: {
            Label("Start Build", systemImage: "play.fill")
        }
        .buttonStyle(.borderedProminent)
        .disabled(cachedCommands.isEmpty || buildQueue?.state == .running)
    }

    private func startBuild() {
        guard !cachedCommands.isEmpty else { return }
        let queue = buildQueue ?? SchematicBuildQueue(coordinator: rconCoordinator)
        buildQueue = queue
        queue.start(commands: cachedCommands, commandsPerSecond: commandsPerSecond)
    }

    @ViewBuilder
    private var progressSection: some View {
        if let buildQueue, buildQueue.state != .idle {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(statusLabel(for: buildQueue.state)).font(.headline)
                    Spacer()
                    Text("\(buildQueue.completedCommands) / \(buildQueue.totalCommands) commands")
                        .font(.callout)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: buildQueue.progress)
                HStack {
                    Text("\(Int(buildQueue.progress * 100))%")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Spacer()
                    controlButtons(for: buildQueue)
                }
            }
            .padding(14)
            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private func statusLabel(for state: SchematicBuildQueue.State) -> String {
        switch state {
        case .idle: return ""
        case .running: return "Building…"
        case .paused: return "Paused"
        case .completed: return "Build Complete"
        case .cancelled: return "Cancelled"
        }
    }

    @ViewBuilder
    private func controlButtons(for queue: SchematicBuildQueue) -> some View {
        switch queue.state {
        case .running:
            Button("Pause") { queue.pause() }.buttonStyle(.bordered)
            Button("Cancel", role: .destructive) { queue.cancel() }.buttonStyle(.bordered)
        case .paused:
            Button("Resume") { queue.resume() }.buttonStyle(.bordered)
            Button("Cancel", role: .destructive) { queue.cancel() }.buttonStyle(.bordered)
        case .completed, .cancelled:
            Button("Reset") { queue.reset() }.buttonStyle(.bordered)
        case .idle:
            EmptyView()
        }
    }
}
