//
//  PinAwareInteractionCache.swift
//  OutPick
//
//  Created by Codex on 5/11/26.
//

import Foundation

struct PinAwareInteractionCache<Key: Hashable, Value> {
    private struct Entry {
        var value: Value
        var lastAccessedAt: Date
    }

    private var entries: [Key: Entry] = [:]
    private var pinnedKeys: Set<Key> = []
    private let maxCount: Int
    private let retentionInterval: TimeInterval

    init(
        maxCount: Int,
        retentionInterval: TimeInterval
    ) {
        self.maxCount = max(1, maxCount)
        self.retentionInterval = max(60, retentionInterval)
    }

    var valuesByKey: [Key: Value] {
        entries.mapValues(\.value)
    }

    mutating func value(for key: Key, now: Date = Date()) -> Value? {
        guard var entry = entries[key] else { return nil }
        entry.lastAccessedAt = now
        entries[key] = entry
        return entry.value
    }

    mutating func set(_ value: Value, for key: Key, now: Date = Date()) {
        entries[key] = Entry(
            value: value,
            lastAccessedAt: now
        )
        evictIfNeeded(now: now)
    }

    mutating func update(
        for key: Key,
        now: Date = Date(),
        _ transform: (inout Value) -> Void
    ) {
        guard var entry = entries[key] else { return }
        transform(&entry.value)
        entry.lastAccessedAt = now
        entries[key] = entry
        evictIfNeeded(now: now)
    }

    mutating func pin(_ keys: Set<Key>, now: Date = Date()) {
        pinnedKeys.formUnion(keys)

        for key in keys {
            guard var entry = entries[key] else { continue }
            entry.lastAccessedAt = now
            entries[key] = entry
        }
    }

    mutating func unpin(_ keys: Set<Key>, now: Date = Date()) {
        pinnedKeys.subtract(keys)
        evictIfNeeded(now: now)
    }

    mutating func evictIfNeeded(now: Date = Date()) {
        let cutoff = now.addingTimeInterval(-retentionInterval)
        let expiredKeys = entries
            .filter { pinnedKeys.contains($0.key) == false && $0.value.lastAccessedAt < cutoff }
            .map(\.key)

        for key in expiredKeys {
            entries.removeValue(forKey: key)
        }

        guard entries.count > maxCount else { return }
        let removalCount = entries.count - maxCount
        let removableKeys = entries
            .filter { pinnedKeys.contains($0.key) == false }
            .sorted { $0.value.lastAccessedAt < $1.value.lastAccessedAt }
            .prefix(removalCount)
            .map(\.key)

        for key in removableKeys {
            entries.removeValue(forKey: key)
        }
    }
}
