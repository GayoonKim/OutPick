//
//  ChatMessageSearchIndex.swift
//  OutPick
//
//  Created by Codex on 2/25/26.
//

import Foundation

enum ChatMessageSearchIndex {
    static let currentVersion: Int = 2
    private static let whitespace: Set<UInt32> = [
        9, 10, 11, 12, 13, 32, 133, 160, 5760,
        8192, 8193, 8194, 8195, 8196, 8197, 8198, 8199, 8200, 8201, 8202,
        8232, 8233, 8239, 8287, 12288
    ]

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
        let folded = rawText.decomposedStringWithCanonicalMapping.unicodeScalars
            .map { ChatSearchUnicodeData.caseFolding[$0.value] ?? String($0) }.joined()
        let stripped = folded.decomposedStringWithCanonicalMapping.unicodeScalars
            .filter { !ChatSearchUnicodeData.removedDiacritics.contains($0.value) }
        let composed = canonicalCompose(String(String.UnicodeScalarView(stripped)))
        var result = ""
        var pendingSpace = false
        for scalar in composed.unicodeScalars {
            if whitespace.contains(scalar.value) {
                pendingSpace = !result.isEmpty
            } else {
                if pendingSpace { result.append(" ") }
                result.unicodeScalars.append(scalar)
                pendingSpace = false
            }
        }
        return result
    }

    /// 일부 한글 자모 조합에서 Foundation의 직접 NFC 변환이 재조합을 생략하므로 분해를 먼저 보장한다.
    static func canonicalCompose(_ text: String) -> String {
        text.decomposedStringWithCanonicalMapping.precomposedStringWithCanonicalMapping
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

        let chars = Array(normalizedKeyword.unicodeScalars)
        if chars.count == 1 {
            return ("searchChars", String(chars[0]))
        }

        let twoGram = chars.prefix(2).map(String.init).joined()
        return ("searchNgrams2", twoGram)
    }

    private static func uniqueCharacters(in normalizedText: String) -> [String] {
        guard !normalizedText.isEmpty else { return [] }
        var seen = Set<String>()
        var result: [String] = []
        result.reserveCapacity(normalizedText.count)

        for ch in normalizedText.unicodeScalars where ch.value != 32 {
            let s = String(ch)
            if seen.insert(s).inserted {
                result.append(s)
            }
        }
        return result
    }

    private static func uniqueNGrams(in normalizedText: String, n: Int) -> [String] {
        guard n > 0 else { return [] }
        let chars = Array(normalizedText.unicodeScalars)
        guard chars.count >= n else { return [] }

        var seen = Set<String>()
        var result: [String] = []
        result.reserveCapacity(max(0, chars.count - n + 1))

        for idx in 0...(chars.count - n) {
            let gram = chars[idx..<(idx + n)].map(String.init).joined()
            if seen.insert(gram).inserted {
                result.append(gram)
            }
        }
        return result
    }
}
