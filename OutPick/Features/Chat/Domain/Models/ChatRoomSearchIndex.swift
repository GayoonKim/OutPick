//
//  ChatRoomSearchIndex.swift
//  OutPick
//
//  Created by Codex on 6/30/26.
//

import Foundation

enum ChatRoomSearchIndex {
    static let currentVersion: Int = 1

    struct IndexedFields {
        let normalizedText: String
        let searchChars: [String]
        let searchNgrams2: [String]
        let version: Int
    }

    static func buildIndexedFields(roomName: String, roomDescription: String) -> IndexedFields {
        let normalized = normalize([roomName, roomDescription].joined(separator: " "))
        return IndexedFields(
            normalizedText: normalized,
            searchChars: uniqueCharacters(in: normalized),
            searchNgrams2: uniqueNGrams(in: normalized, n: 2),
            version: currentVersion
        )
    }

    static func contains(room: ChatRoom, keyword: String) -> Bool {
        let indexedText = [room.roomName, room.roomDescription].joined(separator: " ")
        return contains(indexedText, keyword: keyword)
    }

    static func contains(_ rawText: String?, keyword: String) -> Bool {
        let normalizedText = normalize(rawText)
        let normalizedKeyword = normalize(keyword)
        guard !normalizedKeyword.isEmpty else { return false }
        return normalizedText.contains(normalizedKeyword)
    }

    static func queryToken(for keyword: String) -> (field: String, token: String)? {
        let normalizedKeyword = normalize(keyword)
        guard !normalizedKeyword.isEmpty else { return nil }

        let chars = Array(normalizedKeyword)
        if chars.count == 1 {
            return ("roomSearchChars", String(chars[0]))
        }

        return ("roomSearchNgrams2", String(chars.prefix(2)))
    }

    static func normalize(_ rawText: String?) -> String {
        guard let rawText else { return "" }
        let folded = rawText
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()

        let collapsedWhitespace = folded.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        )

        return collapsedWhitespace.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func uniqueCharacters(in normalizedText: String) -> [String] {
        guard !normalizedText.isEmpty else { return [] }
        var seen = Set<String>()
        var result: [String] = []
        result.reserveCapacity(normalizedText.count)

        for ch in normalizedText where !ch.isWhitespace {
            let value = String(ch)
            if seen.insert(value).inserted {
                result.append(value)
            }
        }
        return result
    }

    private static func uniqueNGrams(in normalizedText: String, n: Int) -> [String] {
        guard n > 0 else { return [] }
        let chars = Array(normalizedText)
        guard chars.count >= n else { return [] }

        var seen = Set<String>()
        var result: [String] = []
        result.reserveCapacity(max(0, chars.count - n + 1))

        for idx in 0...(chars.count - n) {
            let gram = String(chars[idx..<(idx + n)])
            if seen.insert(gram).inserted {
                result.append(gram)
            }
        }
        return result
    }
}
