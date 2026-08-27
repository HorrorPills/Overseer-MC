//
//  VersionManifestService.swift
//  Overseer
//
//  Thin client for Mojang's real, public version-manifest API — the
//  same one the official launcher uses to discover new releases and
//  snapshots. Verified live against the real endpoints while building
//  this (2026-08): the version-naming scheme changed this year to
//  `YY.drop-snapshot.build` (e.g. "26.3-snapshot-9"), which is real,
//  not a placeholder — see the project memory note on this if it comes
//  up again. Structure confirmed by fetching the real manifest:
//
//    GET https://launchermeta.mojang.com/mc/game/version_manifest_v2.json
//      -> { latest: { release, snapshot }, versions: [{ id, type, url, sha1, ... }] }
//
//    GET <a version's own `url`>
//      -> { downloads: { server: { url, sha1, size } }, ... }
//
//  This file only ever reads from Mojang's CDN — no credentials, no
//  write access. The SFTP upload/replace step lives in MCSFTPClient /
//  AutoUpdaterCoordinator instead.
//

import Foundation

struct MojangVersionManifest: Decodable, Sendable {
    struct Latest: Decodable, Sendable {
        var release: String
        var snapshot: String
    }
    struct VersionEntry: Decodable, Sendable {
        var id: String
        var type: String
        var url: String
        var sha1: String
    }
    var latest: Latest
    var versions: [VersionEntry]
}

struct MojangVersionDetail: Decodable, Sendable {
    struct Downloads: Decodable, Sendable {
        struct ServerDownload: Decodable, Sendable {
            var url: String
            var sha1: String
            var size: Int
        }
        var server: ServerDownload?
    }
    var downloads: Downloads
}

enum VersionManifestError: Error, LocalizedError {
    case versionNotFound(String)
    case noServerDownload(String)
    case invalidURL
    case badResponse

    var errorDescription: String? {
        switch self {
        case .versionNotFound(let id): "Version \"\(id)\" wasn't listed in Mojang's manifest."
        case .noServerDownload(let id): "Version \"\(id)\" has no server.jar download listed."
        case .invalidURL: "Mojang returned a malformed download URL."
        case .badResponse: "Mojang's version API returned an unexpected response."
        }
    }
}

actor VersionManifestService {
    static let shared = VersionManifestService()

    private static let manifestURL = URL(string: "https://launchermeta.mojang.com/mc/game/version_manifest_v2.json")!

    /// A dedicated session with a generous timeout for the server.jar
    /// download itself (~60MB as of 26.3-snapshot-9) — the default
    /// 60-second request timeout is comfortable for the small JSON
    /// manifest calls but too tight to risk on a large binary over a
    /// potentially slow connection.
    private let downloadSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300
        return URLSession(configuration: config)
    }()

    func fetchManifest() async throws -> MojangVersionManifest {
        let (data, response) = try await URLSession.shared.data(from: Self.manifestURL)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw VersionManifestError.badResponse
        }
        return try JSONDecoder().decode(MojangVersionManifest.self, from: data)
    }

    /// Fetches one version's own detail manifest (the `url` field on a
    /// `VersionEntry` from `fetchManifest()`), which is where the
    /// server.jar download link actually lives.
    func fetchVersionDetail(url: String) async throws -> MojangVersionDetail {
        guard let detailURL = URL(string: url) else { throw VersionManifestError.invalidURL }
        let (data, response) = try await URLSession.shared.data(from: detailURL)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw VersionManifestError.badResponse
        }
        return try JSONDecoder().decode(MojangVersionDetail.self, from: data)
    }

    /// Resolves a version ID (as reported by `fetchManifest()`) to its
    /// server.jar download info in one call — fetches the manifest
    /// itself, so prefer `fetchVersionDetail(url:)` directly when the
    /// caller already has the manifest (and thus the entry's `url`) in
    /// hand, to avoid a redundant manifest fetch.
    func serverDownload(forVersion versionID: String) async throws -> MojangVersionDetail.Downloads.ServerDownload {
        let manifest = try await fetchManifest()
        guard let entry = manifest.versions.first(where: { $0.id == versionID }) else {
            throw VersionManifestError.versionNotFound(versionID)
        }
        let detail = try await fetchVersionDetail(url: entry.url)
        guard let server = detail.downloads.server else {
            throw VersionManifestError.noServerDownload(versionID)
        }
        return server
    }

    func downloadServerJar(from urlString: String) async throws -> Data {
        guard let jarURL = URL(string: urlString) else { throw VersionManifestError.invalidURL }
        let (data, response) = try await downloadSession.data(from: jarURL)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw VersionManifestError.badResponse
        }
        return data
    }
}
