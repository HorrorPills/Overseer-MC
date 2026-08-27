//
//  MCSFTPClient.swift
//  Overseer
//
//  Thin wrapper around Citadel (github.com/orlandos-nl/Citadel) — the
//  project's first external dependency, added specifically because
//  hand-rolling SSH's key exchange/cipher/auth handshake would be
//  reckless. This file is the only place that imports Citadel/NIO
//  directly; everything downstream (SFTPSyncCoordinator) only sees the
//  plain Sendable types below.
//
//  Host key verification uses `.acceptAnything()` — equivalent to
//  `ssh -o StrictHostKeyChecking=no`, the same trust model used to
//  explore this server's layout by hand before writing this file.
//  Citadel 0.12.1 has no built-in trust-on-first-use/pinning helper;
//  pinning the host key would need capturing and storing its
//  fingerprint separately, which is more than this single-server admin
//  tool's threat model calls for today.
//
//  One connection is opened per sync pass and closed at the end,
//  rather than kept alive between 15-minute sync cycles — simpler, and
//  more resilient to the host dropping an idle connection.
//

import Foundation
import Citadel
import NIO

struct SFTPRemoteFile: Sendable, Identifiable {
    var id: String { name }
    var name: String
    var size: UInt64
    var modificationDate: Date?
    var isDirectory: Bool

    /// POSIX file-type bits live in the top nibble of the mode
    /// (S_IFMT = 0o170000); a directory is S_IFDIR = 0o040000.
    static func isDirectory(permissions: UInt32?) -> Bool {
        guard let permissions else { return false }
        return (permissions & 0o170000) == 0o040000
    }
}

enum MCSFTPError: Error, Equatable {
    case notConnected
    case connectionFailed(String)
}

actor MCSFTPClient {
    // `SSHClient` (unlike `SFTPClient`, which Citadel does mark
    // `Sendable`) isn't itself Sendable in Citadel 0.12.1. In practice
    // this actor's methods are only ever called serially, one `await`
    // at a time, by SFTPSyncCoordinator — there's no actual concurrent
    // access for the compiler to be protecting against here, so
    // `nonisolated(unsafe)` (same reasoning as AppNapPreventer's token)
    // is the pragmatic fix rather than fighting the type system over a
    // dependency's Sendability gap.
    private nonisolated(unsafe) var sshClient: SSHClient?
    private var sftpClient: SFTPClient?

    func connect(host: String, port: Int, username: String, password: String) async throws {
        let client = try await SSHClient.connect(
            host: host,
            port: port,
            authenticationMethod: .passwordBased(username: username, password: password),
            hostKeyValidator: .acceptAnything(),
            reconnect: .never
        )
        self.sshClient = client
        self.sftpClient = try await client.openSFTP()
    }

    func disconnect() async {
        try? await sftpClient?.close()
        try? await sshClient?.close()
        sftpClient = nil
        sshClient = nil
    }

    /// Directory listing, with the `.`/`..` entries SFTP always includes
    /// filtered out — every caller wants "real" entries only.
    func listDirectory(atPath path: String) async throws -> [SFTPRemoteFile] {
        guard let sftpClient else { throw MCSFTPError.notConnected }
        let names = try await sftpClient.listDirectory(atPath: path)
        return names
            .flatMap(\.components)
            .filter { $0.filename != "." && $0.filename != ".." }
            .map { component in
                SFTPRemoteFile(
                    name: component.filename,
                    size: component.attributes.size ?? 0,
                    modificationDate: component.attributes.accessModificationTime?.modificationTime,
                    isDirectory: SFTPRemoteFile.isDirectory(permissions: component.attributes.permissions)
                )
            }
    }

    /// Downloads one file's full contents. Uses `readAll()` (chunked,
    /// size-aware reads under the hood), never a single `read()` call —
    /// SFTP servers cap how much a single READ request returns
    /// regardless of the requested length, so a naive one-shot read
    /// would silently truncate anything larger than one packet.
    func downloadFile(atPath path: String) async throws -> Data {
        guard let sftpClient else { throw MCSFTPError.notConnected }
        return try await sftpClient.withFile(filePath: path, flags: .read) { file in
            let buffer = try await file.readAll()
            return Data(buffer.readableBytesView)
        }
    }

    /// Writes `data` to `path`, creating it if needed and truncating any
    /// existing content — used by the Auto Updater to stage the new
    /// server.jar under a temporary name (see `AutoUpdaterCoordinator`,
    /// which uploads to a `.new` path and only swaps it into place with
    /// `rename(atPath:to:)` after the upload has fully succeeded, so a
    /// dropped connection mid-transfer never leaves a half-written
    /// server.jar on disk).
    func uploadFile(_ data: Data, atPath path: String) async throws {
        guard let sftpClient else { throw MCSFTPError.notConnected }
        var mutableBuffer = ByteBuffer()
        mutableBuffer.writeBytes(data)
        let buffer = mutableBuffer // captured as `let` — the closure below is @Sendable
        try await sftpClient.withFile(filePath: path, flags: [.read, .write, .create, .truncate]) { file in
            try await file.write(buffer, at: 0)
        }
    }

    func deleteFile(atPath path: String) async throws {
        guard let sftpClient else { throw MCSFTPError.notConnected }
        try await sftpClient.remove(at: path)
    }

    func renameFile(atPath oldPath: String, to newPath: String) async throws {
        guard let sftpClient else { throw MCSFTPError.notConnected }
        try await sftpClient.rename(at: oldPath, to: newPath)
    }
}
