//
//  RCONClient.swift
//  Overseer
//
//  Source RCON protocol client, TCP, entirely independent of the GS4 /
//  Server List Ping engine (its own connection, its own actor, its own
//  reconnect policy). Reference: https://developer.valvesoftware.com/wiki/Source_RCON_Protocol
//
//  Wire format per packet (all integers little-endian, unlike GS4/SLP
//  which are big-endian):
//    Length     Int32   size of everything below, NOT including itself
//    Request ID Int32   echoed back by the server; -1 = auth failure
//    Type       Int32   3 = SERVERDATA_AUTH, 2 = SERVERDATA_AUTH_RESPONSE
//                        or SERVERDATA_EXECCOMMAND (same wire value —
//                        disambiguated by which we're expecting), 0 =
//                        SERVERDATA_RESPONSE_VALUE
//    Payload    ASCII   null-terminated
//    Pad        1 byte  empty null-terminated string
//
//  Large command output (e.g. `/whitelist list` on a big server) comes
//  back split across multiple RESPONSE_VALUE packets. The protocol has
//  no explicit "final packet" flag, so we use the standard client
//  trick: immediately after the real command, send a second, empty
//  EXECCOMMAND as a marker. Every RESPONSE_VALUE packet up to and
//  including the one whose request ID matches the marker belongs to
//  the real command; concatenating their payloads reassembles the full
//  (possibly fragmented) response.
//

import Foundation
import Network

actor RCONClient {

    enum RCONError: Error, LocalizedError, Equatable {
        case invalidPort
        case connectionFailed(String)
        case authenticationFailed
        case timeout
        case connectionClosed
        case malformedPacket

        var errorDescription: String? {
            switch self {
            case .invalidPort: return "Invalid RCON port."
            case .connectionFailed(let reason): return "RCON connection failed: \(reason)"
            case .authenticationFailed: return "RCON authentication failed — check the password."
            case .timeout: return "RCON command timed out."
            case .connectionClosed: return "RCON connection closed unexpectedly."
            case .malformedPacket: return "Received a malformed RCON packet."
            }
        }
    }

    struct Configuration: Sendable, Equatable {
        var host: String
        var port: UInt16
        var password: String
        var timeout: TimeInterval

        static let `default` = Configuration(
            host: "",
            port: 25575,
            password: "",
            timeout: 8
        )
    }

    private static let authPacketType: Int32 = 3
    private static let authResponsePacketType: Int32 = 2 // shares a wire value with execCommand
    private static let execCommandPacketType: Int32 = 2
    private static let responseValuePacketType: Int32 = 0

    private var configuration: Configuration
    private var connection: NWConnection?
    private var reader: RCONPacketReader?
    private var nextRequestID: Int32 = 100
    private let socketQueue = DispatchQueue(label: "com.mcservermonitor.rcon")

    // Reconnect backoff, tracked independently of the GS4/SLP engine's.
    private var reconnectDelay: TimeInterval = 1
    private let maxReconnectDelay: TimeInterval = 60
    private var nextAllowedConnectAttempt: Date = .distantPast

    // Manual FIFO mutex: actor reentrancy alone doesn't serialize calls
    // across suspension points, and two `execute()` calls interleaving
    // their sends/reads on the same socket would scramble responses.
    private var locked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    /// Minimum gap enforced between the end of one command and the start
    /// of the next, on top of the FIFO ordering above — ordering alone
    /// only prevents responses from scrambling, it doesn't stop several
    /// schedulers landing on the same tick (tick-poll, position
    /// tracking, entity cleanup can all fire close together) from
    /// hammering the socket back-to-back with zero breathing room. Cheap
    /// insurance against exactly the class of low-level Network.framework
    /// read hiccup (ENODATA) this file's `execute()` now also recovers
    /// from automatically.
    private static let minimumCommandSpacing: TimeInterval = 0.15
    private var lastCommandFinishedAt: Date?

    /// How many callers are currently queued up behind the in-flight
    /// command (not counting that command itself) — surfaced in the UI
    /// so queuing is visible rather than just theoretical.
    var queuedCommandCount: Int { waiters.count }

    private(set) var isConnected = false

    init(configuration: Configuration = .default) {
        self.configuration = configuration
    }

    func updateConfiguration(_ configuration: Configuration) {
        self.configuration = configuration
        disconnect() // force re-auth against the new target on next command
    }

    func disconnect() {
        connection?.cancel()
        connection = nil
        reader = nil
        isConnected = false
    }

    /// Sends one Vanilla command and returns its (possibly reassembled)
    /// text response. Commands are strictly queued FIFO; concurrent
    /// callers each wait their turn rather than racing the socket.
    @discardableResult
    func execute(_ command: String) async throws -> String {
        await acquireLock()
        defer { releaseLock() }
        await enforceMinimumSpacing()
        defer { lastCommandFinishedAt = .now }
        do {
            return try await withTimeout(configuration.timeout) {
                try await self.performExecute(command)
            }
        } catch {
            // `ensureConnected()` only resets/reconnects when the initial
            // connect+auth itself fails — a failure here means something
            // went wrong *after* that (a timeout, a dropped socket, a
            // stray low-level read error like the ENODATA class of
            // Network.framework hiccup) while `connection`/`reader` were
            // already considered live. Left alone, `isConnected` and
            // `connection.isUsable` both keep reporting "fine" on a
            // socket that's actually dead, so every subsequent command
            // silently repeats the same failure forever — this was the
            // real cause of RCON getting stuck "Disconnected" until the
            // app was relaunched. Tearing the connection down here forces
            // the next call to reconnect+re-auth from scratch instead of
            // reusing a zombie connection.
            disconnect()
            throw error
        }
    }

    // MARK: - FIFO queue

    private func acquireLock() async {
        if !locked {
            locked = true
            return
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            waiters.append(continuation)
        }
    }

    private func enforceMinimumSpacing() async {
        guard let last = lastCommandFinishedAt else { return }
        let remaining = Self.minimumCommandSpacing - Date.now.timeIntervalSince(last)
        guard remaining > 0 else { return }
        try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
    }

    private func releaseLock() {
        if waiters.isEmpty {
            locked = false
        } else {
            waiters.removeFirst().resume() // hand the lock straight to the next waiter
        }
    }

    // MARK: - Execution

    private func performExecute(_ command: String) async throws -> String {
        try await ensureConnected()
        guard let connection, let reader else { throw RCONError.notReady }

        let commandID = allocateRequestID()
        let markerID = allocateRequestID()

        try await send(RCONPacket(requestID: commandID, type: Self.execCommandPacketType, payload: command).encoded(), on: connection)
        try await send(RCONPacket(requestID: markerID, type: Self.execCommandPacketType, payload: "").encoded(), on: connection)

        var accumulated = ""
        // Bounded so a protocol confusion can't spin forever; a single
        // command realistically never spans more than a few dozen
        // fragments even for the chattiest vanilla output.
        for _ in 0..<256 {
            let packet = try await reader.nextPacket()
            if packet.requestID == markerID {
                break
            }
            if packet.requestID == commandID {
                accumulated += packet.payload
            }
            // Packets with any other request ID are stale/unexpected —
            // ignored rather than treated as fatal, since a prior timed
            // -out command's late reply could still be in flight.
        }
        return accumulated
    }

    private func allocateRequestID() -> Int32 {
        nextRequestID += 1
        if nextRequestID == Int32.max { nextRequestID = 100 } // never collide with -1 (auth failure sentinel)
        return nextRequestID
    }

    // MARK: - Connection lifecycle

    private func ensureConnected() async throws {
        if isConnected, let connection, connection.isUsable {
            return
        }
        disconnect()
        guard Date() >= nextAllowedConnectAttempt else {
            throw RCONError.connectionFailed("Backing off after a recent failure; retry shortly.")
        }
        do {
            try await connectAndAuthenticate()
            reconnectDelay = 1
            isConnected = true
        } catch {
            nextAllowedConnectAttempt = Date().addingTimeInterval(reconnectDelay)
            reconnectDelay = min(reconnectDelay * 2, maxReconnectDelay)
            isConnected = false
            throw error
        }
    }

    private func connectAndAuthenticate() async throws {
        guard let port = NWEndpoint.Port(rawValue: configuration.port) else {
            throw RCONError.invalidPort
        }
        let newConnection = NWConnection(host: NWEndpoint.Host(configuration.host), port: port, using: .tcp)
        try await waitUntilReady(newConnection)

        let newReader = RCONPacketReader(connection: newConnection)
        let authID = allocateRequestID()
        try await send(RCONPacket(requestID: authID, type: Self.authPacketType, payload: configuration.password).encoded(), on: newConnection)

        // The server sends an empty RESPONSE_VALUE packet before the
        // real AUTH_RESPONSE; skip anything that isn't the auth reply.
        var authenticated = false
        for _ in 0..<8 {
            let packet = try await newReader.nextPacket()
            if packet.type == Self.authResponsePacketType {
                guard packet.requestID != -1 else { throw RCONError.authenticationFailed }
                authenticated = true
                break
            }
        }
        guard authenticated else { throw RCONError.authenticationFailed }

        connection = newConnection
        reader = newReader
    }

    private func waitUntilReady(_ connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.stateUpdateHandler = nil
                    continuation.resume()
                case .failed(let error):
                    connection.stateUpdateHandler = nil
                    continuation.resume(throwing: RCONError.connectionFailed(error.localizedDescription))
                case .cancelled:
                    connection.stateUpdateHandler = nil
                    continuation.resume(throwing: RCONError.connectionClosed)
                default:
                    break
                }
            }
            connection.start(queue: socketQueue)
        }
    }

    private func send(_ data: Data, on connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: RCONError.connectionFailed(error.localizedDescription))
                } else {
                    continuation.resume()
                }
            })
        }
    }
}

private extension RCONClient.RCONError {
    static let notReady = RCONClient.RCONError.connectionFailed("Not connected.")
}

private extension NWConnection {
    /// Best-effort "is this still worth trying to send on" check. We
    /// track `isConnected` ourselves for the authoritative state; this
    /// just avoids reusing a connection Network.framework has already
    /// torn down from under us.
    var isUsable: Bool {
        switch state {
        case .ready: return true
        default: return false
        }
    }
}

// MARK: - Packet model

struct RCONPacket: Equatable {
    var requestID: Int32
    var type: Int32
    var payload: String

    func encoded() -> Data {
        var payloadBytes = Array(payload.utf8)
        payloadBytes.append(0x00) // terminates the payload string
        var body: [UInt8] = []
        body += requestID.littleEndianBytes
        body += type.littleEndianBytes
        body += payloadBytes
        body += [0x00] // empty terminated "pad" string
        let length = Int32(body.count)
        return Data(length.littleEndianBytes + body)
    }
}

/// Pure, testable decode step: attempts to slice one length-prefixed
/// RCON packet off the front of `buffer`, consuming its bytes and
/// returning it — or returns nil (buffer untouched) if more bytes are
/// needed. Kept free of any networking so it's directly unit-testable
/// against synthetic byte buffers, mirroring GS4Protocol/
/// ServerListPingProtocol's parser/networking split.
enum RCONPacketDecoder {
    static func decodeNext(from buffer: inout Data) throws -> RCONPacket? {
        guard buffer.count >= 4 else { return nil }
        let lengthBytes = [UInt8](buffer.prefix(4))
        let length = Int(Int32(littleEndianBytes: lengthBytes))
        // Minimum valid packet: reqID(4) + type(4) + empty payload's null
        // terminator(1) + pad(1) = 10.
        guard length >= 10 else { throw RCONClient.RCONError.malformedPacket }
        let total = 4 + length
        guard buffer.count >= total else { return nil }

        let body = buffer.subdata(in: 4..<total)
        buffer.removeSubrange(0..<total)

        let requestID = Int32(littleEndianBytes: [UInt8](body.prefix(4)))
        let type = Int32(littleEndianBytes: [UInt8](body[body.startIndex + 4..<body.startIndex + 8]))
        let payloadAndPad = body.suffix(from: body.startIndex + 8)
        // Payload is null-terminated, followed by the empty pad string's
        // own null terminator — strip both trailing zero bytes.
        let payloadBytes = payloadAndPad.reversed().drop { $0 == 0 }.reversed()
        let payload = String(decoding: Array(payloadBytes), as: UTF8.self)

        return RCONPacket(requestID: requestID, type: type, payload: payload)
    }
}

/// Buffers raw TCP bytes and slices out length-prefixed RCON packets.
/// An actor (rather than a plain class, like the analogous reader in
/// ServerQueryEngine) specifically because `RCONClient` holds this one
/// as long-lived state across calls instead of creating it fresh per
/// call — Swift 6's region isolation checker wants a stored reference
/// crossing `await` points to be provably isolated, which an actor
/// gives us for free.
private actor RCONPacketReader {
    private let connection: NWConnection
    private var buffer = Data()

    init(connection: NWConnection) {
        self.connection = connection
    }

    func nextPacket() async throws -> RCONPacket {
        while true {
            if let packet = try RCONPacketDecoder.decodeNext(from: &buffer) {
                return packet
            }
            let chunk = try await receiveChunk()
            buffer.append(chunk)
        }
    }

    private func receiveChunk() async throws -> Data {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, isComplete, error in
                if let error {
                    continuation.resume(throwing: RCONClient.RCONError.connectionFailed(error.localizedDescription))
                    return
                }
                if let data, !data.isEmpty {
                    continuation.resume(returning: data)
                } else if isComplete {
                    continuation.resume(throwing: RCONClient.RCONError.connectionClosed)
                } else {
                    continuation.resume(returning: Data())
                }
            }
        }
    }
}

// MARK: - Little-endian Int32 helpers (RCON is LE; GS4/SLP elsewhere in
// this module are BE, so these are deliberately distinct extensions).

extension Int32 {
    var littleEndianBytes: [UInt8] {
        let le = self.littleEndian
        return withUnsafeBytes(of: le, Array.init)
    }

    init(littleEndianBytes bytes: [UInt8]) {
        precondition(bytes.count == 4)
        let value = bytes.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }
        self = Int32(littleEndian: value)
    }
}

/// Races `operation` against a timer and throws `.timeout` if the timer
/// wins. Mirrors `ServerQueryEngine`'s helper but kept local — the RCON
/// engine is deliberately independent of the GS4/SLP engine.
private func withTimeout<T: Sendable>(
    _ seconds: TimeInterval,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw RCONClient.RCONError.timeout
        }
        guard let result = try await group.next() else {
            throw RCONClient.RCONError.timeout
        }
        group.cancelAll()
        return result
    }
}
