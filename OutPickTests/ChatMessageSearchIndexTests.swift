import Foundation
import CryptoKit
import Testing
@testable import OutPick

struct ChatMessageSearchIndexTests {
    @Test func sharedV2FixturesMatchExpectedNormalizationTokensAndContains() throws {
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: resource("normalization-v2.json")))
        #expect(fixture.version == 2)
        #expect(fixture.fixtures.count == 25)
        for row in fixture.fixtures {
            let result = ChatMessageSearchIndex.buildIndexedFields(from: row.raw)
            #expect(result.version == 2, "\(row.id)")
            #expect(Array(result.normalizedText.utf8) == Array(row.normalized.utf8), "\(row.id)")
            #expect(result.searchChars == row.searchChars, "\(row.id)")
            #expect(result.searchNgrams2 == row.searchNgrams2, "\(row.id)")
            let token = ChatMessageSearchIndex.queryToken(for: row.raw ?? "")
            #expect(token?.field == row.queryToken?.field, "\(row.id)")
            #expect(token?.token == row.queryToken?.token, "\(row.id)")
            for sample in row.containsCases {
                #expect(ChatMessageSearchIndex.contains(row.raw, keyword: sample.keyword) == sample.matches, "\(row.id): \(sample.keyword)")
            }
        }
        let count = ["ㅋㅋ", "ㅋㅋㅋㅋㅋ", "뭐야 ㅋㅋ", "ㅋ"].filter { ChatMessageSearchIndex.contains($0, keyword: "ㅋㅋ") }.count
        #expect(count == 3)
    }

    @Test func pinnedUnicodeCorpusAndLocaleIndependenceHold() throws {
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: resource("unicode/manifest.json")))
        #expect(manifest.unicodeVersion == "15.1.0")
        for (name, hash) in manifest.files {
            let data = try Data(contentsOf: resource("unicode/\(name)"))
            let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            #expect(actual == hash, "\(name)")
        }
        var expectedFold: [UInt32: String] = [:]
        for line in try text("CaseFolding.txt").components(separatedBy: "\n") {
            let columns = line.components(separatedBy: "#")[0].components(separatedBy: ";").map { $0.trimmingCharacters(in: .whitespaces) }
            guard columns.count >= 3, ["C", "F"].contains(columns[1]) else { continue }
            let key = try #require(UInt32(columns[0], radix: 16))
            let mapped = try decode(columns[2])
            expectedFold[key] = mapped
            #expect(ChatMessageSearchIndex.normalize(try decode(columns[0])) == ChatMessageSearchIndex.normalize(mapped), "\(columns[0])")
        }
        #expect(expectedFold.count == 1530)
        #expect(ChatSearchUnicodeData.caseFolding == expectedFold)
        var marks = Set<UInt32>()
        for line in try text("UnicodeData.txt").components(separatedBy: "\n") {
            let c = line.components(separatedBy: ";")
            if c.count > 2, ["Mn", "Me"].contains(c[2]) { marks.insert(try #require(UInt32(c[0], radix: 16))) }
        }
        var removed = Set<UInt32>()
        for line in try text("PropList.txt").components(separatedBy: "\n") {
            let c = line.components(separatedBy: "#")[0].components(separatedBy: ";").map { $0.trimmingCharacters(in: .whitespaces) }
            guard c.count > 1, c[1] == "Diacritic" else { continue }
            let bounds = c[0].components(separatedBy: "..").compactMap { UInt32($0, radix: 16) }
            let lower = try #require(bounds.first)
            let upper = try #require(bounds.last)
            for code in lower...upper where marks.contains(code) { removed.insert(code) }
        }
        #expect(removed.count == 707)
        #expect(ChatSearchUnicodeData.removedDiacritics == removed)
        var count = 0
        for line in try text("NormalizationTest.txt").components(separatedBy: "\n") {
            guard let first = line.first, "0123456789ABCDEF".contains(first) else { continue }
            let c = try line.components(separatedBy: ";").prefix(5).map(decode)
            #expect(c.count == 5)
            guard c.count == 5 else { continue }
            count += 1
            for s in c.prefix(3) {
                #expect(Array(ChatMessageSearchIndex.canonicalCompose(s).utf8) == Array(c[1].utf8), "\(line)")
                #expect(Array(s.decomposedStringWithCanonicalMapping.utf8) == Array(c[2].utf8), "\(line)")
                #expect(ChatMessageSearchIndex.normalize(s) == ChatMessageSearchIndex.normalize(c[0]), "\(line)")
                let normalized = ChatMessageSearchIndex.normalize(s)
                #expect(Array(ChatMessageSearchIndex.normalize(normalized).utf8) == Array(normalized.utf8), "\(line)")
            }
            for s in c.suffix(2) {
                #expect(Array(ChatMessageSearchIndex.canonicalCompose(s).utf8) == Array(c[3].utf8), "\(line)")
                #expect(Array(s.decomposedStringWithCanonicalMapping.utf8) == Array(c[4].utf8), "\(line)")
            }
        }
        #expect(count > 19000)
        // locale 입력을 받지 않는 고정 매핑이며 지역별 I 처리와 구별되는 기대값이다.
        #expect(ChatMessageSearchIndex.normalize("Iİı CAFÉ Σς Straße") == "iiı cafe σσ strasse")
    }

    @Test func everyLiteralMatchHasCandidateTokenAndNormalizationIsIdempotent() throws {
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: resource("normalization-v2.json")))
        #expect(!fixture.fixtures.isEmpty)
        for row in fixture.fixtures {
            let fields = ChatMessageSearchIndex.buildIndexedFields(from: row.raw)
            #expect(ChatMessageSearchIndex.normalize(fields.normalizedText) == fields.normalizedText)
            for sample in row.containsCases where sample.matches {
                let token = try #require(ChatMessageSearchIndex.queryToken(for: sample.keyword))
                let tokens = token.field == "searchChars" ? fields.searchChars : fields.searchNgrams2
                #expect(tokens.contains(token.token), "\(row.id)")
            }
        }
        let spaces: [UInt32] = [9,10,11,12,13,32,133,160,5760,8192,8193,8194,8195,8196,8197,8198,8199,8200,8201,8202,8232,8233,8239,8287,12288]
        for cp in spaces {
            let scalar = try #require(UnicodeScalar(cp))
            #expect(ChatMessageSearchIndex.normalize("A\(scalar)B") == "a b")
        }
        #expect(ChatMessageSearchIndex.normalize("A\u{FEFF}B") == "a\u{FEFF}b")
    }

    @Test func sessionContractSeparatesScopeCountAndLifetime() throws {
        let identity = ChatSearchSessionIdentity(sessionID: UUID(), accountID: "a", accountEpoch: UUID(), roomID: "r", generation: 1)
        let scope = try ChatSearchScope(identity: identity, keyword: " CAFÉ ", upperSeq: 100, source: .serverIndex)
        #expect(scope.normalizedQuery == "cafe")
        #expect(scope.upperSeq == 100)
        #expect(throws: ChatSearchFailure.invalidRequest) { try ChatSearchScope(identity: identity, keyword: " ", upperSeq: 100, source: .serverIndex) }
        #expect(throws: ChatSearchFailure.invalidRequest) { try ChatSearchScope(identity: identity, keyword: "a", upperSeq: -1, source: .localOffline) }
        #expect(ChatSearchCountState.unknown != .completed(totalCount: 0))
        #expect(ChatSearchCountState.scanning(knownCount: 0) != .completed(totalCount: 0))
        let nextLogin = ChatSearchSessionIdentity(sessionID: identity.sessionID, accountID: "a", accountEpoch: UUID(), roomID: "r", generation: 1)
        #expect(identity != nextLogin)
    }
}

private final class ChatSearchFixtureBundleMarker {}
private func resource(_ path: String) throws -> URL {
    let base = try #require(Bundle(for: ChatSearchFixtureBundleMarker.self).resourceURL)
    return base.appendingPathComponent("chat-search").appendingPathComponent(path)
}
private func text(_ name: String) throws -> String { try String(contentsOf: resource("unicode/\(name)"), encoding: .utf8) }
private func decode(_ hex: String) throws -> String {
    let scalars = try hex.split(whereSeparator: \.isWhitespace).map { token -> UnicodeScalar in
        let code = try #require(UInt32(token, radix: 16))
        return try #require(UnicodeScalar(code))
    }
    return String(String.UnicodeScalarView(scalars))
}
private struct Fixture: Decodable {
    let version: Int
    let fixtures: [Row]
    struct Row: Decodable {
        let id: String
        let raw: String?
        let normalized: String
        let searchChars: [String]
        let searchNgrams2: [String]
        let queryToken: Token?
        let containsCases: [Contains]
    }
    struct Token: Decodable { let field: String; let token: String }
    struct Contains: Decodable { let keyword: String; let matches: Bool }
}
private struct Manifest: Decodable { let unicodeVersion: String; let files: [String: String] }
