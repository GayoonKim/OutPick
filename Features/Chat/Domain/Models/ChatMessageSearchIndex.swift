//
//  ChatMessageSearchIndex.swift
//  OutPick
//
//  Created by Codex on 2/25/26.
//

import Foundation

enum ChatMessageSearchIndex {
    static let currentVersion: Int = 1

    struct IndexedFields {
        let normalizedText: String
        let searchChars: [String]
        let searchNgrams2: [String]
        let version: Int
    }

    static func buildIndexedFields(from rawText: String?) -> IndexedFields {
        let normalized = normalize(rawText)
        let chars = uniqueCharacters(in: normalized)
        let ngrams2 = uniqueNGrams(in: normalized, n: 2)
        return IndexedFields(
            normalizedText: normalized,
            searchChars: chars,
            searchNgrams2: ngrams2,
            version: currentVersion
        )
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
            return ("searchChars", String(chars[0]))
        }

        let twoGram = String(chars.prefix(2))
        return ("searchNgrams2", twoGram)
    }

    private static func uniqueCharacters(in normalizedText: String) -> [String] {
        guard !normalizedText.isEmpty else { return [] }
        var seen = Set<String>()
        var result: [String] = []
        result.reserveCapacity(normalizedText.count)

        for ch in normalizedText where !ch.isWhitespace {
            let s = String(ch)
            if seen.insert(s).inserted {
                result.append(s)
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

