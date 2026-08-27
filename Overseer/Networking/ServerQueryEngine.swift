//
//  ServerQueryEngine.swift
//  Overseer
//
//  Thread-safe actor that owns all live socket I/O against the target
//  Minecraft server, using Network.framework (`NWConnection`) directly
//  rather than URLSession/BSD sockets, so we get first-class async/await
//  and clean cancellation.
//
//  Two independent protocols run per poll:
//   - GS4 Query (UDP)         -> authoritative, un-sampled player list,
//                                 MOTD, map, max slots.
//   - Server List Ping (TCP)  -> network latency (ping) + a JSON status
//                                 payload used as a cross-check/fallback
//                                 and for the server favicon.
//
//  Both are wrapped in a per-call timeout and run concurrently; either
//  may fail independently (e.g. query disabled but SLP open) without
//  taking down the whole poll. Everything here is pure networking —
//  persistence and session-boundary logic live in PollingCoordinator.
//

import Foundation
import Network

actor ServerQueryEngine {

    enum QueryError: Error, LocalizedError, Equatable {
        case invalidPort
        case connectionFailed(String)
        case timeout
        case connectionClosed

        var errorDescription: String? {
            switch self {
            case .invalidPort: return "Invalid port number."
            case .connectionFailed(let reason): return "Connection failed: \(reason)"
            case .timeout: return "Timed out waiting for a response."
            case .connectionClosed: return "Connection closed unexpectedly."
            }
        }
    }

    struct Configuration: Sendable, Equatable {
        /// Primary target — defaults to the raw IP so polling doesn't
        /// depend on DNS at all.
        var host: String
        /// Optional hostname to retry with if `host` is unreachable
        /// (e.g. the IP changes but the domain doesn't). Set to nil to
        /// disable the fallback entirely.
        var fallbackHost: String?
        var port: UInt16
        var timeout: TimeInterval

        static let `default` = Configuration(
            host: "",
            fallbackHost: nil,
            port: 25565,
            timeout: 5
        )
    }

    struct PollResult: Sendable {
        var timestamp: Date
        var fullStat: GS4FullStat?
        var slpStatus: SLPStatus?
        var pingMs: Int?
        var gs4ErrorDescription: String?
        var slpErrorDescription: String?
        var resolvedHost: String

        var isOnline: Bool { fullStat != nil || slpStatus != nil }
    }

    private var configuration: Configuration
    private let socketQueue = DispatchQueue(label: "com.mcservermonitor.query-engine")

    init(configuration: Configuration = .default) {
        self.configuration = configuration
    }

    func updateConfiguration(_ configuration: Configuration) {
        self.configuration = configuration
    }

    func currentConfiguration() -> Configuration { configuration }

    // MARK: - Public poll entry point

    /// Runs one full poll cycle: GS4 full stat + SLP ping, concurrently,
    /// each independently time-boxed to `configuration.timeout`. Falls
    /// back to `fallbackHost` only if BOTH protocols fail against the
    /// primary host.
    func poll() async -> PollResult {
        let timestamp = Date()
        let primary = await pollOnce(host: configuration.host, timestamp: timestamp)
        if primary.isOnline { return primary }
        guard let fallbackHost = configuration.fallbackHost, fallbackHost != configuration.host else {
            return primary
        }
        return await pollOnce(host: fallbackHost, timestamp: timestamp)
    }

    private func pollOnce(host: String, timestamp: Date) async -> PollResult {
        async let gs4: Result<GS4FullStat, Error> = attempt { try await self.fetchFullStat(host: host) }
        async let slp: Result<(SLPStatus, Int), Error> = attempt { try await self.fetchServerListPing(host: host) }

        let gs4Result = await gs4
        let slpResult = await slp

        var result = PollResult(timestamp: timestamp, resolvedHost: host)
        switch gs4Result {
        case .success(let stat): result.fullStat = stat
        case .failure(let error): result.gs4ErrorDescription = String(describing: error)
        }
        switch slpResult {
        case .success(let (status, ping)):
            result.slpStatus = status
            result.pingMs = ping
        case .failure(let error):
            result.slpErrorDescription = String(describing: error)
        }
        return result
    }

    private func attempt<T: Sendable>(_ body: @escaping @Sendable () async throws -> T) async -> Result<T, Error> {
        do { return .success(try await body()) } catch { return .failure(error) }
    }

    // MARK: - GS4 Query (UDP)

    private func fetchFullStat(host: String) async throws -> GS4FullStat {
        try await withTimeout(configuration.timeout) {
            let connection = try await self.makeConnection(host: host, using: .udp)
            defer { connection.cancel() }
            try await self.waitUntilReady(connection)

            // Masked session ID: top nibble of each byte must be zero
            // per the GS4 spec so all server implementations accept it.
            let sessionID: Int32 = 0x0F0F0F0F

            try await self.send(GS4Protocol.handshakeRequest(sessionID: sessionID), on: connection)
            let handshakeResponse = try await self.receiveDatagram(on: connection)
            let token = try GS4Protocol.parseHandshakeResponse(handshakeResponse)

            try await self.send(GS4Protocol.fullStatRequest(sessionID: sessionID, token: token), on: connection)
            let statResponse = try await self.receiveDatagram(on: connection)
            return try GS4Protocol.parseFullStatResponse(statResponse)
        }
    }

    // MARK: - Server List Ping (TCP)

    private func fetchServerListPing(host: String) async throws -> (SLPStatus, Int) {
        try await withTimeout(configuration.timeout) {
            let connection = await self.makeTCPConnection(host: host)
            defer { connection.cancel() }
            try await self.waitUntilReady(connection)

            let port = await self.configuration.port
            try await self.send(ServerListPingProtocol.handshakePacket(host: host, port: port), on: connection)
            try await self.send(ServerListPingProtocol.statusRequestPacket(), on: connection)

            let reader = TCPPacketReader(connection: connection)
            let statusBody = try await reader.nextPacket()
            let status = try ServerListPingProtocol.parseStatusResponse(statusBody)

            let payload = Int64(Date().timeIntervalSince1970 * 1000)
            let start = DispatchTime.now()
            try await self.send(ServerListPingProtocol.pingPacket(payload: payload), on: connection)
            let pongBody = try await reader.nextPacket()
            try ServerListPingProtocol.validatePong(pongBody, expectedPayload: payload)
            let elapsedNanos = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
            let pingMs = Int(elapsedNanos / 1_000_000)

            return (status, pingMs)
        }
    }

    // MARK: - NWConnection plumbing

    private func makeConnection(host: String, using parameters: NWParameters) throws -> NWConnection {
        guard let port = NWEndpoint.Port(rawValue: configuration.port) else {
            throw QueryError.invalidPort
        }
        return NWConnection(host: NWEndpoint.Host(host), port: port, using: parameters)
    }

    private func makeTCPConnection(host: String) -> NWConnection {
        let params = NWParameters.tcp
        params.serviceClass = .responsiveData
        guard let port = NWEndpoint.Port(rawValue: configuration.port) else {
            // Constructing with an invalid port is a programmer error at
            // this point (validated in makeConnection for UDP); mirror
            // the same guard for TCP for symmetry/safety.
            return NWConnection(host: NWEndpoint.Host(host), port: 1, using: params)
        }
        return NWConnection(host: NWEndpoint.Host(host), port: port, using: params)
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
                    continuation.resume(throwing: QueryError.connectionFailed(error.localizedDescription))
                case .cancelled:
                    connection.stateUpdateHandler = nil
                    continuation.resume(throwing: QueryError.connectionClosed)
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
                    continuation.resume(throwing: QueryError.connectionFailed(error.localizedDescription))
                } else {
                    continuation.resume()
                }
            })
        }
    }

    /// UDP datagrams arrive whole from Network.framework, so a single
    /// `receiveMessage` call is sufficient (no stream reassembly needed,
    /// unlike the TCP path below).
    private func receiveDatagram(on connection: NWConnection) async throws -> Data {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            connection.receiveMessage { data, _, _, error in
                if let error {
                    continuation.resume(throwing: QueryError.connectionFailed(error.localizedDescription))
                    return
                }
                guard let data, !data.isEmpty else {
                    continuation.resume(throwing: QueryError.connectionClosed)
                    return
                }
                continuation.resume(returning: data)
            }
        }
    }
}

/// Buffers raw TCP bytes and slices out VarInt-length-prefixed packets,
/// since a single `receive` call has no guaranteed relationship to
/// packet boundaries over a TCP stream (unlike the UDP datagram path).
/// Deliberately a plain class, not actor-isolated: it's only ever used
/// sequentially within a single `ServerQueryEngine` call.
private final class TCPPacketReader {
    private let connection: NWConnection
    private var buffer = Data()

    init(connection: NWConnection) {
        self.connection = connection
    }

    func nextPacket() async throws -> Data {
        while true {
            if let body = try decodeBufferedPacket() {
                return body
            }
            let chunk = try await receiveChunk()
            buffer.append(chunk)
        }
    }

    private func decodeBufferedPacket() throws -> Data? {
        let bytes = [UInt8](buffer)
        var offset = 0
        let length: Int32
        do {
            length = try VarInt.decode(bytes, offset: &offset)
        } catch VarIntError.truncated {
            return nil // need more bytes for the length prefix itself
        }
        let total = offset + Int(length)
        guard buffer.count >= total else { return nil } // need more bytes for the body
        let body = buffer.subdata(in: offset..<total)
        buffer.removeSubrange(0..<total)
        return body
    }

    private func receiveChunk() async throws -> Data {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, isComplete, error in
                if let error {
                    continuation.resume(throwing: ServerQueryEngine.QueryError.connectionFailed(error.localizedDescription))
                    return
                }
                if let data, !data.isEmpty {
                    continuation.resume(returning: data)
                } else if isComplete {
                    continuation.resume(throwing: ServerQueryEngine.QueryError.connectionClosed)
                } else {
                    continuation.resume(returning: Data())
                }
            }
        }
    }
}

/// Races `operation` against a timer and throws `.timeout` if the timer
/// wins, cancelling whichever task loses.
private func withTimeout<T: Sendable>(
    _ seconds: TimeInterval,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw ServerQueryEngine.QueryError.timeout
        }
        guard let result = try await group.next() else {
            throw ServerQueryEngine.QueryError.timeout
        }
        group.cancelAll()
        return result
    }
}
