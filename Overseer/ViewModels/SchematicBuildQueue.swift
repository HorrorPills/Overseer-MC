//
//  SchematicBuildQueue.swift
//  Overseer
//
//  Drives a precomputed list of /setblock and /fill commands (see
//  Schematic/RCONCommandPlanner.swift) through RCONAutomationCoordinator
//  at a configurable rate, with pause/resume/cancel and observable
//  progress for SchematicBuilderView. Every dispatched command still
//  goes through `coordinator.sendConsoleCommand`, so it shows up in the
//  RCON Console log and is subject to the same vanilla guard rail as
//  everything else in the app — this class adds pacing and cancellation
//  on top, nothing else.
//

import Foundation
import Observation

@MainActor
@Observable
final class SchematicBuildQueue {
    enum State: Equatable {
        case idle
        case running
        case paused
        case completed
        case cancelled
    }

    private(set) var state: State = .idle
    private(set) var totalCommands = 0
    private(set) var completedCommands = 0
    private(set) var startedAt: Date?

    var progress: Double {
        totalCommands > 0 ? Double(completedCommands) / Double(totalCommands) : 0
    }

    var remainingCommands: Int {
        max(0, totalCommands - completedCommands)
    }

    var elapsed: TimeInterval {
        guard let startedAt else { return 0 }
        return Date.now.timeIntervalSince(startedAt)
    }

    private let coordinator: RCONAutomationCoordinator
    private var commands: [String] = []
    private var commandDelayNanoseconds: UInt64 = 0
    private var buildTask: Task<Void, Never>?
    private var pauseRequested = false

    init(coordinator: RCONAutomationCoordinator) {
        self.coordinator = coordinator
    }

    func start(commands: [String], commandsPerSecond: Double) {
        guard state != .running else { return }
        self.commands = commands
        totalCommands = commands.count
        completedCommands = 0
        pauseRequested = false
        commandDelayNanoseconds = commandsPerSecond > 0 ? UInt64(1_000_000_000 / commandsPerSecond) : 0
        state = .running
        startedAt = .now
        runFrom(index: 0)
    }

    /// Takes effect once the in-flight command finishes — there's no
    /// clean way to interrupt an RCON call already in progress.
    func pause() {
        guard state == .running else { return }
        pauseRequested = true
    }

    func resume() {
        guard state == .paused else { return }
        pauseRequested = false
        state = .running
        runFrom(index: completedCommands)
    }

    func cancel() {
        buildTask?.cancel()
        buildTask = nil
        state = .cancelled
    }

    /// Clears everything back to `.idle` so the same queue instance can
    /// drive another build (e.g. after a completed/cancelled run).
    func reset() {
        cancel()
        state = .idle
        commands = []
        totalCommands = 0
        completedCommands = 0
        startedAt = nil
    }

    private func runFrom(index: Int) {
        buildTask = Task { [weak self] in
            await self?.run(startingAt: index)
        }
    }

    private func run(startingAt startIndex: Int) async {
        for index in startIndex..<commands.count {
            if Task.isCancelled { return }
            if pauseRequested {
                state = .paused
                return
            }
            await coordinator.sendConsoleCommand(commands[index])
            completedCommands = index + 1
            if commandDelayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: commandDelayNanoseconds)
            }
        }
        if !Task.isCancelled && !pauseRequested {
            state = .completed
        }
    }
}
