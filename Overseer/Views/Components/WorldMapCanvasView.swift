//
//  WorldMapCanvasView.swift
//  Overseer
//
//  Two layers in one Canvas, sharing one world-coordinate -> pixel
//  transform (so a breadcrumb always lands on the biome tile it's
//  actually standing on): a flat-colored biome tile per generated
//  chunk (see WorldMapEngine/BiomeColorPalette), and each player's
//  breadcrumb trail as a dot per recorded position (older ones fainter
//  and smaller, the most recent bold and ringed) connected by a thin
//  line — the dots, not the line, are the primary way to trace a path
//  visually, since a bare line reads as one continuous smear once a
//  player has doubled back on themselves a few times.
//
//  Rendering is viewport-culled by region (`RegionChunkGrid`, ~1024
//  chunks each): only regions whose 512x512-block bounding box
//  actually intersects what's currently on screen get their chunks
//  iterated. A fully-explored server can easily have 100k+ chunks
//  cached total — iterating all of them on every frame during a drag
//  or pinch gesture (which fires many times a second) is what made
//  panning/zooming feel laggy before this was added; culling to the
//  handful of regions actually visible turns that into a non-issue.
//
//  Pan (click-drag) and zoom (pinch) are self-contained state here —
//  WorldMapView only ever asks for a *reframe* (center on spawn, fit
//  everything) via `frameAction`, never touches scale/center directly.
//

import SwiftUI

enum WorldMapFrameAction: Equatable {
    case spawn
    case fitAll
}

struct WorldMapCanvasView: View {
    var regions: [RegionChunkGrid]
    var breadcrumbsByPlayer: [String: [PlayerPositionSample]]
    var playerColors: [Color]
    /// Set when a player's row is clicked in the Breadcrumb Log table —
    /// their trail is drawn bold and full-opacity, everyone else's fades
    /// well into the background, so a specific path is easy to trace
    /// even with several players' trails overlapping on screen.
    var highlightedUsername: String?
    @Binding var frameAction: WorldMapFrameAction?

    /// Points per in-game block — larger means more zoomed in.
    @State private var scale: CGFloat = 0.2
    /// World (x, z) shown at the center of the canvas.
    @State private var center: CGPoint = .zero
    @State private var hasFramedOnce = false

    @GestureState private var dragTranslation: CGSize = .zero
    @GestureState private var magnifyAmount: CGFloat = 1

    @State private var hoverLocation: CGPoint?

    private static let minScale: CGFloat = 0.002
    private static let maxScale: CGFloat = 24
    private static let padding: CGFloat = 16
    /// Spawn-adjacent radius (blocks) preferred for the default/"Center
    /// on Spawn" framing — wide enough to comfortably cover a base
    /// without pulling in a remote outpost hundreds of chunks away.
    private static let spawnRadius = 3000.0

    private var sortedPlayers: [(username: String, color: Color, samples: [PlayerPositionSample])] {
        breadcrumbsByPlayer.keys.sorted().enumerated().map { index, username in
            (username, playerColors[index % playerColors.count], breadcrumbsByPlayer[username]!.sorted { $0.timestamp < $1.timestamp })
        }
    }

    var body: some View {
        GeometryReader { geo in
            let liveScale = clampedScale(scale * magnifyAmount)
            let liveCenter = CGPoint(
                x: center.x - dragTranslation.width / liveScale,
                y: center.y - dragTranslation.height / liveScale
            )

            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    draw(context: context, size: size, scale: liveScale, center: liveCenter)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 1)
                        .updating($dragTranslation) { value, state, _ in state = value.translation }
                        .onEnded { value in
                            center.x -= value.translation.width / liveScale
                            center.y -= value.translation.height / liveScale
                        }
                )
                .simultaneousGesture(
                    MagnificationGesture()
                        .updating($magnifyAmount) { value, state, _ in state = value }
                        .onEnded { value in
                            scale = clampedScale(scale * value)
                        }
                )
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location): hoverLocation = location
                    case .ended: hoverLocation = nil
                    }
                }

                if let hoverLocation, let readout = coordinateReadout(at: hoverLocation, size: geo.size, scale: liveScale, center: liveCenter) {
                    hoverBadge(readout)
                        .position(x: min(max(hoverLocation.x + 70, 60), geo.size.width - 60), y: max(hoverLocation.y - 24, 16))
                }

                zoomControls
                    .padding(10)
            }
            .background(.quaternary.opacity(0.15), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .onAppear { frameIfNeeded(canvasSize: geo.size) }
            .onChange(of: regions.count) { _, _ in frameIfNeeded(canvasSize: geo.size) }
            .onChange(of: frameAction) { _, action in
                guard let action else { return }
                apply(action, canvasSize: geo.size)
                frameAction = nil
            }
        }
        .accessibilityLabel("World map with biome terrain and player breadcrumb trails — drag to pan, pinch to zoom")
    }

    // MARK: - Drawing

    private func draw(context: GraphicsContext, size: CGSize, scale: CGFloat, center: CGPoint) {
        func project(x: Double, z: Double) -> CGPoint {
            CGPoint(
                x: size.width / 2 + (CGFloat(x) - center.x) * scale,
                y: size.height / 2 + (CGFloat(z) - center.y) * scale
            )
        }

        // Viewport in world-block coordinates, padded by one region so
        // tiles don't visibly pop in right at the edge.
        let viewMinX = Double(center.x) - Double(size.width / 2 + 512) / Double(scale)
        let viewMaxX = Double(center.x) + Double(size.width / 2 + 512) / Double(scale)
        let viewMinZ = Double(center.y) - Double(size.height / 2 + 512) / Double(scale)
        let viewMaxZ = Double(center.y) + Double(size.height / 2 + 512) / Double(scale)

        let chunkPixelSize = max(16 * scale, 1)
        for region in regions {
            let bounds = region.blockBounds
            guard Double(bounds.maxX) >= viewMinX, Double(bounds.minX) <= viewMaxX,
                  Double(bounds.maxZ) >= viewMinZ, Double(bounds.minZ) <= viewMaxZ
            else { continue }

            for (chunk, biome) in region.chunks {
                let origin = project(x: Double(chunk.x * 16), z: Double(chunk.z * 16))
                guard origin.x > -chunkPixelSize, origin.x < size.width, origin.y > -chunkPixelSize, origin.y < size.height else { continue }
                let rect = CGRect(x: origin.x, y: origin.y, width: chunkPixelSize, height: chunkPixelSize)
                context.fill(Path(rect), with: .color(BiomeColorPalette.color(for: biome)))
            }
        }

        // When a player is highlighted, every other trail fades well
        // into the background instead of disappearing outright — still
        // visible for context, just clearly secondary — and the
        // highlighted trail itself is drawn last so it's never
        // underneath another player's line at an overlap.
        let isFiltering = highlightedUsername != nil
        let others = isFiltering ? sortedPlayers.filter { $0.username != highlightedUsername } : sortedPlayers
        let highlighted = sortedPlayers.first { $0.username == highlightedUsername }

        for player in others {
            drawTrail(player, context: context, size: size, project: project, dimmed: isFiltering)
        }
        if let highlighted {
            drawTrail(highlighted, context: context, size: size, project: project, dimmed: false)
        }

        // Spawn marker (0, 0) — a fixed landmark that stays meaningful
        // no matter how far the camera has panned.
        let spawnPoint = project(x: 0, z: 0)
        if spawnPoint.x > -20, spawnPoint.x < size.width + 20, spawnPoint.y > -20, spawnPoint.y < size.height + 20 {
            var cross = Path()
            cross.move(to: CGPoint(x: spawnPoint.x - 6, y: spawnPoint.y))
            cross.addLine(to: CGPoint(x: spawnPoint.x + 6, y: spawnPoint.y))
            cross.move(to: CGPoint(x: spawnPoint.x, y: spawnPoint.y - 6))
            cross.addLine(to: CGPoint(x: spawnPoint.x, y: spawnPoint.y + 6))
            context.stroke(cross, with: .color(.white), lineWidth: 2)
            context.stroke(cross, with: .color(.black.opacity(0.6)), lineWidth: 1)
        }
    }

    /// One player's line + recency-graded dots. `dimmed` scales every
    /// opacity down hard (used for every player *except* the one
    /// currently highlighted in the Breadcrumb Log table) without
    /// changing anything else about how the trail is drawn.
    private func drawTrail(
        _ player: (username: String, color: Color, samples: [PlayerPositionSample]),
        context: GraphicsContext,
        size: CGSize,
        project: (Double, Double) -> CGPoint,
        dimmed: Bool
    ) {
        guard let first = player.samples.first else { return }
        let fade: Double = dimmed ? 0.12 : 1.0

        var path = Path()
        path.move(to: project(first.x, first.z))
        for sample in player.samples.dropFirst() {
            path.addLine(to: project(sample.x, sample.z))
        }
        context.stroke(path, with: .color(player.color.opacity(0.35 * fade)), style: StrokeStyle(lineWidth: dimmed ? 1 : 1.5, lineCap: .round, lineJoin: .round))

        // A dot per recorded position, not just the line — fading in
        // from pale/small (oldest) to bold/large (most recent) so the
        // sequence of stops is readable at a glance instead of one
        // continuous, hard-to-trace smear.
        let count = player.samples.count
        for (index, sample) in player.samples.enumerated() {
            let point = project(sample.x, sample.z)
            guard point.x > -20, point.x < size.width + 20, point.y > -20, point.y < size.height + 20 else { continue }
            let recency = count > 1 ? Double(index) / Double(count - 1) : 1
            let isLast = index == count - 1
            let radius: CGFloat = isLast ? 5 : 2 + 2 * recency
            let opacity = (isLast ? 1.0 : 0.35 + 0.5 * recency) * fade
            let dot = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
            context.fill(Path(ellipseIn: dot), with: .color(player.color.opacity(opacity)))
            if isLast {
                context.stroke(Path(ellipseIn: dot), with: .color(.white.opacity(0.9 * fade)), lineWidth: 1.5)
            }
        }
    }

    // MARK: - Hover readout

    private func coordinateReadout(at location: CGPoint, size: CGSize, scale: CGFloat, center: CGPoint) -> String? {
        let worldX = Double(center.x + (location.x - size.width / 2) / scale)
        let worldZ = Double(center.y + (location.y - size.height / 2) / scale)

        // Snap to the nearest breadcrumb within ~10pt so hovering near a
        // trail shows exactly who was there and when, not just raw
        // coordinates under the cursor.
        var nearest: (username: String, sample: PlayerPositionSample, distance: CGFloat)?
        for player in sortedPlayers {
            for sample in player.samples {
                let point = CGPoint(
                    x: size.width / 2 + (CGFloat(sample.x) - center.x) * scale,
                    y: size.height / 2 + (CGFloat(sample.z) - center.y) * scale
                )
                let distance = hypot(point.x - location.x, point.y - location.y)
                guard distance <= 10 else { continue }
                if nearest == nil || distance < nearest!.distance {
                    nearest = (player.username, sample, distance)
                }
            }
        }

        if let nearest {
            return "\(nearest.username) — \(Int(nearest.sample.x)), \(Int(nearest.sample.z))\n\(nearest.sample.timestamp.formatted(.relative(presentation: .named)))"
        }
        return "X: \(Int(worldX.rounded()))  Z: \(Int(worldZ.rounded()))"
    }

    private func hoverBadge(_ text: String) -> some View {
        Text(text)
            .font(.caption2.monospaced())
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .fixedSize()
            .allowsHitTesting(false)
    }

    // MARK: - Zoom controls (mouse-only fallback for pinch-to-zoom)

    private var zoomControls: some View {
        VStack(spacing: 0) {
            Button {
                scale = clampedScale(scale * 1.5)
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .padding(6)
            Divider().frame(width: 20)
            Button {
                scale = clampedScale(scale / 1.5)
            } label: {
                Image(systemName: "minus")
            }
            .buttonStyle(.borderless)
            .padding(6)
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .frame(width: 28)
    }

    // MARK: - Framing

    private func clampedScale(_ value: CGFloat) -> CGFloat {
        min(max(value, Self.minScale), Self.maxScale)
    }

    private func frameIfNeeded(canvasSize: CGSize) {
        guard !hasFramedOnce, !regions.isEmpty || !breadcrumbsByPlayer.isEmpty else { return }
        hasFramedOnce = true
        apply(.spawn, canvasSize: canvasSize)
    }

    private func apply(_ action: WorldMapFrameAction, canvasSize: CGSize) {
        let bounds: (minX: Double, maxX: Double, minZ: Double, maxZ: Double)?
        switch action {
        case .spawn:
            bounds = worldBounds(preferringSpawnRadius: true)
        case .fitAll:
            bounds = worldBounds(preferringSpawnRadius: false)
        }
        guard let bounds else {
            center = .zero
            return
        }

        let spanX = max(bounds.maxX - bounds.minX, 64)
        let spanZ = max(bounds.maxZ - bounds.minZ, 64)
        let usableWidth = max(canvasSize.width - Self.padding * 2, 1)
        let usableHeight = max(canvasSize.height - Self.padding * 2, 1)
        scale = clampedScale(min(usableWidth / CGFloat(spanX), usableHeight / CGFloat(spanZ)))
        center = CGPoint(x: (bounds.minX + bounds.maxX) / 2, y: (bounds.minZ + bounds.maxZ) / 2)
    }

    /// When `preferringSpawnRadius` is true and any chunk/breadcrumb
    /// falls within `spawnRadius` blocks of (0,0), only that
    /// spawn-adjacent subset is used — a single remote outpost far from
    /// spawn otherwise dominates a naive fit-everything bounding box,
    /// squashing the actually-relevant area into a handful of pixels.
    private func worldBounds(preferringSpawnRadius: Bool) -> (minX: Double, maxX: Double, minZ: Double, maxZ: Double)? {
        var minX = Double.greatestFiniteMagnitude, maxX = -Double.greatestFiniteMagnitude
        var minZ = Double.greatestFiniteMagnitude, maxZ = -Double.greatestFiniteMagnitude
        var found = false

        func consider(_ x: Double, _ z: Double) {
            guard !preferringSpawnRadius || (abs(x) <= Self.spawnRadius && abs(z) <= Self.spawnRadius) else { return }
            found = true
            minX = min(minX, x); maxX = max(maxX, x)
            minZ = min(minZ, z); maxZ = max(maxZ, z)
        }

        for region in regions {
            for chunk in region.chunks.keys {
                consider(Double(chunk.x * 16), Double(chunk.z * 16))
                consider(Double(chunk.x * 16 + 16), Double(chunk.z * 16 + 16))
            }
        }
        for samples in breadcrumbsByPlayer.values {
            for sample in samples { consider(sample.x, sample.z) }
        }

        if !found && preferringSpawnRadius {
            return worldBounds(preferringSpawnRadius: false) // nothing near spawn -> fall back to fitting everything
        }
        guard found else { return nil }
        return (minX, maxX, minZ, maxZ)
    }
}
