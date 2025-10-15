//
//  StorageService.swift
//  Bovanta:Sport
//
//  Created on 2025-10-14
//

import SwiftUI
import Combine

/// Lightweight, versioned, Codable storage over UserDefaults.
/// - Atomic (per key) writes
/// - ISO8601 dates
/// - Per-key migrations (data → data), chainable
/// - Change notifications via Combine
///
/// Keys convention: "storage.<domain>" (e.g., storage.teams, storage.matches)
public final class StorageService: ObservableObject {
    // MARK: - Singleton
    public static let shared = StorageService()
    private init() {}

    // MARK: - Types

    /// Canonical keys known to the app. You can add more as needed.
    public enum Key: String, CaseIterable, Hashable, Sendable {
        case teams   = "storage.teams"
        case matches = "storage.matches"
        case settings = "storage.settings"
    }

    /// A versioned payload wrapper saved into UserDefaults.
    private struct VersionedBox<T: Codable>: Codable {
        let version: Int
        let payload: T
    }

    /// Migration closure transforms raw Data of an older version into a newer version.
    public typealias Migration = (_ old: Data) throws -> Data

    // MARK: - Storage / Codec

    private let defaults: UserDefaults = .standard
    private let queue = DispatchQueue(label: "storage.service.queue", qos: .userInitiated)

    private lazy var encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.withoutEscapingSlashes]
        return e
    }()

    private lazy var decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    // MARK: - Migrations

    /// Registry: key → [fromVersion: (toVersion, transform)]
    /// Supports chained upgrades: 1→2, 2→3, … up to targetVersion
    private var migrations: [Key: [Int: (to: Int, transform: Migration)]] = [:]

    /// Register a migration for a key.
    /// Example:
    /// StorageService.shared.register(.teams, from: 1, to: 2) { data in ... return newData }
    public func register(_ key: Key, from: Int, to: Int, transform: @escaping Migration) {
        precondition(to > from, "Migration 'to' must be greater than 'from'")
        var map = migrations[key] ?? [:]
        map[from] = (to, transform)
        migrations[key] = map
    }

    // MARK: - Publishers

    /// Emits a key whenever its value changes (save/clear).
    public let didChange = PassthroughSubject<Key, Never>()

    // MARK: - Public API

    /// Save a codable value for a key with semantic version.
    /// - Parameters:
    ///   - value: Codable payload to save
    ///   - key: Storage key
    ///   - version: Schema/version number for this payload
    public func save<T: Codable>(_ value: T, for key: Key, version: Int) {
        queue.sync {
            do {
                let boxed = VersionedBox(version: version, payload: value)
                let data = try encoder.encode(boxed)
                defaults.set(data, forKey: key.rawValue)
                DispatchQueue.main.async { self.didChange.send(key) }
            } catch {
                assertionFailure("StorageService save failed for \(key.rawValue): \(error)")
            }
        }
    }

    /// Load a codable value for a key. If no value is present, returns the provided default.
    /// - Parameters:
    ///   - type: Expected Codable type
    ///   - key: Storage key
    ///   - defaultValue: Value returned if nothing is stored or decode fails
    ///   - targetVersion: The current schema version your app expects
    ///   - allowMigrations: If true, apply registered migrations up to targetVersion
    /// - Returns: Decoded value, or defaultValue on failure
    public func load<T: Codable>(_ type: T.Type,
                                 for key: Key,
                                 default defaultValue: T,
                                 targetVersion: Int,
                                 allowMigrations: Bool = true) -> T {
        queue.sync {
            guard let raw = defaults.data(forKey: key.rawValue) else { return defaultValue }

            // Try to decode the versioned box first.
            if let box = try? decoder.decode(VersionedBox<T>.self, from: raw) {
                // If version matches target → return
                if box.version == targetVersion { return box.payload }

                // If version differs and migrations are allowed → attempt upgrade chain
                if allowMigrations, let upgraded: T = migrateIfNeeded(T.self, key: key, fromData: raw, currentVersion: box.version, targetVersion: targetVersion) {
                    return upgraded
                }

                // Fallback: return payload even if version differs (caller may re-save)
                return box.payload
            }

            // Legacy fallback: maybe it was saved as plain T without VersionedBox
            if let legacy = try? decoder.decode(T.self, from: raw) {
                // Wrap and re-save as current version to normalize storage
                self.save(legacy, for: key, version: targetVersion)
                return legacy
            }

            // Decode failed → return default
            return defaultValue
        }
    }

    /// Remove a value for the given key.
    public func clear(_ key: Key) {
        queue.sync {
            defaults.removeObject(forKey: key.rawValue)
            DispatchQueue.main.async { self.didChange.send(key) }
        }
    }

    /// Remove all keys with "storage." prefix (hard reset).
    public func clearAll() {
        queue.sync {
            for (k, _) in defaults.dictionaryRepresentation() where k.hasPrefix("storage.") {
                defaults.removeObject(forKey: k)
            }
            // Emit for each known key
            Key.allCases.forEach { k in
                DispatchQueue.main.async { self.didChange.send(k) }
            }
        }
    }

    // MARK: - Debug / Utilities

    /// Returns a human-readable JSON string for quick inspection (if decodable).
    public func debugJSONString(for key: Key) -> String? {
        guard let data = defaults.data(forKey: key.rawValue) else { return nil }
        do {
            let obj = try JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)
            let pretty = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .withoutEscapingSlashes])
            return String(data: pretty, encoding: .utf8)
        } catch {
            return nil
        }
    }

    // MARK: - Private: Migration engine

    /// Attempt to migrate raw versioned payload Data up to `targetVersion`, decoding as `T` at the end.
    private func migrateIfNeeded<T: Codable>(_ type: T.Type,
                                             key: Key,
                                             fromData data: Data,
                                             currentVersion: Int,
                                             targetVersion: Int) -> T? {
        guard targetVersion > currentVersion else {
            // If target < current, just try decode as-is (downgrade not supported)
            return try? decoder.decode(VersionedBox<T>.self, from: data).payload
        }

        var working = data
        var ver = currentVersion
        guard var chain = migrations[key], !chain.isEmpty else {
            // No migrations registered — try decode in case structure is backward-compatible
            return try? decoder.decode(VersionedBox<T>.self, from: data).payload
        }

        // Walk migration chain: ver → next.to → … → targetVersion
        while ver < targetVersion {
            guard let step = chain[ver] else {
                // Missing step: stop and try decode; if fails, abort
                return try? decoder.decode(VersionedBox<T>.self, from: working).payload
            }
            do {
                working = try step.transform(working)
                ver = step.to
            } catch {
                assertionFailure("Migration failed for key \(key.rawValue) at v\(ver)→v\(step.to): \(error)")
                return try? decoder.decode(VersionedBox<T>.self, from: working).payload
            }
        }

        // Now at targetVersion; decode and re-save normalized box
        do {
            let box = try decoder.decode(VersionedBox<T>.self, from: working)
            // If decoded box version is already target → persist and return
            if box.version == targetVersion {
                save(box.payload, for: key, version: targetVersion)
                return box.payload
            } else {
                // Box may still be a legacy/plain T inside; attempt plain decode of T
                if let payload = try? decoder.decode(T.self, from: working) {
                    save(payload, for: key, version: targetVersion)
                    return payload
                }
                return box.payload
            }
        } catch {
            // As a last resort, try plain T decode
            if let payload = try? decoder.decode(T.self, from: working) {
                save(payload, for: key, version: targetVersion)
                return payload
            }
            return nil
        }
    }
}

// MARK: - Convenience overloads for raw string keys (compat with early repos)

public extension StorageService {
    func save<T: Codable>(_ value: T, forKey key: String, version: Int) {
        guard let k = StorageService.Key(rawValue: key) else {
            // Save under arbitrary key without versioning box (legacy compatibility)
            queue.sync {
                if let data = try? encoder.encode(value) {
                    defaults.set(data, forKey: key)
                }
            }
            return
        }
        save(value, for: k, version: version)
    }

    func load<T: Codable>(_ type: T.Type,
                          forKey key: String,
                          default def: T,
                          targetVersion: Int,
                          allowMigrations: Bool = true) -> T {
        if let k = StorageService.Key(rawValue: key) {
            return load(T.self, for: k, default: def, targetVersion: targetVersion, allowMigrations: allowMigrations)
        }
        // Arbitrary key fallback (no version box expected)
        return queue.sync {
            guard let raw = defaults.data(forKey: key),
                  let decoded = try? decoder.decode(T.self, from: raw) else { return def }
            return decoded
        }
    }

    func clear(_ rawKey: String) {
        queue.sync {
            defaults.removeObject(forKey: rawKey)
        }
    }
}
