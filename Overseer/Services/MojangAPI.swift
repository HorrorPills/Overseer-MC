//
//  MojangAPI.swift
//  Overseer
//
//  Identity enrichment: GS4/SLP only ever give us usernames. This
//  resolves the Mojang UUID (kept around for a stable player identity
//  across name changes — not currently required for anything else) and
//  fetches/caches a 3D head render for the avatar shown throughout the
//  UI.
//
//  Avatars are fetched directly by username against mc-heads.net,
//  falling back to minotar.net — both resolve the UUID server-side, so
//  no round trip through Mojang's API is needed for the image itself.
//  (This used to go through crafatar.com by UUID; crafatar has been
//  down — HTTP 521 — so avatars silently never rendered. Fetching by
//  username directly also sidesteps needing that UUID lookup to
//  succeed first.)
//
//  Mojang's API and the avatar services are all unauthenticated and
//  rate-limited, so lookups are de-duplicated per username via
//  `inFlight` and results are cached (UUIDs indefinitely; avatars on
//  disk with a TTL) so we don't hammer any of them on every redraw.
//

import Foundation
#if canImport(AppKit)
import AppKit
#endif

actor MojangAPI {
    static let shared = MojangAPI()

    private struct ProfileResponse: Decodable {
        var id: String
        var name: String
    }

    private var uuidCache: [String: String] = [:]
    private var inFlightUUIDLookups: Set<String> = []
    private var usernameCache: [String: String] = [:]
    private let avatarCache = AvatarCache()
    private let session: URLSession

    private init(session: URLSession = .shared) {
        self.session = session
    }

    /// Fire-and-forget enrichment kicked off from PollingCoordinator when
    /// a new session opens. Deliberately pinned to @MainActor (rather
    /// than the MojangAPI actor's own isolation) since `player` is a
    /// SwiftData model that must only be touched from the main actor;
    /// the network round trip inside still happens off-main via the
    /// `await` hop onto the MojangAPI actor.
    @MainActor
    func enrichIfNeeded(player: Player) {
        guard player.uuid == nil else { return }
        let username = player.username
        Task {
            guard let uuid = await MojangAPI.shared.resolveUUID(for: username) else { return }
            player.uuid = uuid
        }
    }

    /// Resolves a Mojang UUID for `username`, or nil if the lookup fails
    /// (unknown username, rate limited, offline). Results are cached for
    /// the lifetime of the app.
    func resolveUUID(for username: String) async -> String? {
        if let cached = uuidCache[username] { return cached }
        guard !inFlightUUIDLookups.contains(username) else {
            // Another caller is already resolving this username; avoid a
            // duplicate request by polling the cache briefly.
            while inFlightUUIDLookups.contains(username) {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            return uuidCache[username]
        }

        inFlightUUIDLookups.insert(username)
        defer { inFlightUUIDLookups.remove(username) }

        guard let url = URL(string: "https://api.mojang.com/users/profiles/minecraft/\(username)") else {
            return nil
        }
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return nil // 204/404 = no such username; 429 = rate limited
            }
            let profile = try JSONDecoder().decode(ProfileResponse.self, from: data)
            uuidCache[username] = profile.id
            return profile.id
        } catch {
            return nil
        }
    }

    /// Fetches (and disk-caches) a 3D head render for `username`,
    /// including the overlay/hat layer. Tries each provider in order,
    /// falling through on any failure (network error, non-200, empty
    /// body) so one dead service doesn't blank out every avatar in the
    /// app the way crafatar's outage did.
    func avatarImageData(username: String) async -> Data? {
        if let cached = await avatarCache.cachedData(for: username) { return cached }

        for url in avatarURLs(for: username) {
            do {
                let (data, response) = try await session.data(from: url)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200, !data.isEmpty else {
                    continue
                }
                await avatarCache.store(data, for: username)
                return data
            } catch {
                continue
            }
        }
        return nil
    }

    /// Reverse of `resolveUUID` — the direction the Inventory Analyzer
    /// needs, since a `.dat` file's identity is only ever the UUID
    /// (the filename), for a player who isn't already a known `Player`
    /// (e.g. left before this app started tracking). Mojang's session
    /// server wants the UUID undashed.
    func resolveUsername(for uuid: String) async -> String? {
        let undashed = uuid.replacingOccurrences(of: "-", with: "")
        if let cached = usernameCache[undashed] { return cached }
        guard let url = URL(string: "https://sessionserver.mojang.com/session/minecraft/profile/\(undashed)") else {
            return nil
        }
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            let profile = try JSONDecoder().decode(ProfileResponse.self, from: data)
            usernameCache[undashed] = profile.name
            return profile.name
        } catch {
            return nil
        }
    }

    private func avatarURLs(for username: String) -> [URL] {
        let encoded = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? username
        return [
            "https://mc-heads.net/avatar/\(encoded)/100",
            "https://minotar.net/avatar/\(encoded)/100"
        ].compactMap(URL.init(string:))
    }
}

/// Simple disk-backed cache for avatar PNGs under Application Support,
/// keyed by username. Avoids re-fetching (and hitting the rate limit
/// of) whichever avatar provider succeeded, across app launches.
actor AvatarCache {
    private let directory: URL
    private let ttl: TimeInterval = 60 * 60 * 24 * 7 // 1 week

    init(fileManager: FileManager = .default) {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        directory = base.appendingPathComponent("Overseer/AvatarCache", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func fileURL(for username: String) -> URL {
        directory.appendingPathComponent("\(username.lowercased()).png")
    }

    func cachedData(for username: String) -> Data? {
        let url = fileURL(for: username)
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modified = attributes[.modificationDate] as? Date,
              Date().timeIntervalSince(modified) < ttl else {
            return nil
        }
        return try? Data(contentsOf: url)
    }

    func store(_ data: Data, for username: String) {
        try? data.write(to: fileURL(for: username), options: .atomic)
    }
}
