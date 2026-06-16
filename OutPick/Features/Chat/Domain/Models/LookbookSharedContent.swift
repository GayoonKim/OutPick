//
//  LookbookSharedContent.swift
//  OutPick
//
//  Created by Codex on 6/16/26.
//

import Foundation

struct LookbookSharedContent: Codable, Hashable, Sendable {
    enum ContentType: String, Codable, Hashable, Sendable {
        case brand
        case season
        case post

        init?(legacyRawValue rawValue: String?) {
            guard let rawValue else { return nil }
            let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            self.init(rawValue: normalized)
        }
    }

    let schemaVersion: Int
    let contentType: ContentType
    let brandID: String
    let seasonID: String?
    let postID: String?
    let titleSnapshot: String
    let subtitleSnapshot: String?
    let thumbnailPathSnapshot: String?

    init(
        schemaVersion: Int,
        contentType: ContentType,
        brandID: String,
        seasonID: String? = nil,
        postID: String? = nil,
        titleSnapshot: String,
        subtitleSnapshot: String? = nil,
        thumbnailPathSnapshot: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.contentType = contentType
        self.brandID = brandID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.seasonID = Self.trimmedNonEmpty(seasonID)
        self.postID = Self.trimmedNonEmpty(postID)
        self.titleSnapshot = titleSnapshot.trimmingCharacters(in: .whitespacesAndNewlines)
        self.subtitleSnapshot = Self.trimmedNonEmpty(subtitleSnapshot)
        self.thumbnailPathSnapshot = Self.trimmedNonEmpty(thumbnailPathSnapshot)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        let contentType = try container.decode(ContentType.self, forKey: .contentType)
        let brandID = try container.decode(String.self, forKey: .brandID)
        let seasonID = try container.decodeIfPresent(String.self, forKey: .seasonID)
        let postID = try container.decodeIfPresent(String.self, forKey: .postID)
        let titleSnapshot = try container.decode(String.self, forKey: .titleSnapshot)
        let subtitleSnapshot = try container.decodeIfPresent(String.self, forKey: .subtitleSnapshot)
        let thumbnailPathSnapshot = try container.decodeIfPresent(String.self, forKey: .thumbnailPathSnapshot)

        let content = LookbookSharedContent(
            schemaVersion: schemaVersion,
            contentType: contentType,
            brandID: brandID,
            seasonID: seasonID,
            postID: postID,
            titleSnapshot: titleSnapshot,
            subtitleSnapshot: subtitleSnapshot,
            thumbnailPathSnapshot: thumbnailPathSnapshot
        )

        guard content.isValid else {
            throw DecodingError.dataCorruptedError(
                forKey: .titleSnapshot,
                in: container,
                debugDescription: "Invalid lookbook shared content"
            )
        }

        self = content
    }

    var isValid: Bool {
        guard schemaVersion == 1,
              !brandID.isEmpty,
              !titleSnapshot.isEmpty else {
            return false
        }

        switch contentType {
        case .brand:
            return true
        case .season:
            return seasonID?.isEmpty == false
        case .post:
            return seasonID?.isEmpty == false && postID?.isEmpty == false
        }
    }

    func toDict() -> [String: Any] {
        var dict: [String: Any] = [
            "schemaVersion": schemaVersion,
            "contentType": contentType.rawValue,
            "brandID": brandID,
            "titleSnapshot": titleSnapshot
        ]
        if let seasonID {
            dict["seasonID"] = seasonID
        }
        if let postID {
            dict["postID"] = postID
        }
        if let subtitleSnapshot {
            dict["subtitleSnapshot"] = subtitleSnapshot
        }
        if let thumbnailPathSnapshot {
            dict["thumbnailPathSnapshot"] = thumbnailPathSnapshot
        }
        return dict
    }

    static func from(_ value: Any?) -> LookbookSharedContent? {
        if let dict = value as? [String: Any] {
            return fromDict(dict)
        }

        if let dict = value as? NSDictionary {
            return fromDict(dict as? [String: Any] ?? [:])
        }

        if let data = value as? Data {
            return try? JSONDecoder().decode(LookbookSharedContent.self, from: data)
        }

        if let string = value as? String,
           let data = string.data(using: .utf8) {
            return try? JSONDecoder().decode(LookbookSharedContent.self, from: data)
        }

        return nil
    }

    private static func fromDict(_ dict: [String: Any]) -> LookbookSharedContent? {
        guard let schemaVersion = intValue(dict["schemaVersion"]),
              let contentType = ContentType(legacyRawValue: stringValue(dict["contentType"])),
              let brandID = stringValue(dict["brandID"]),
              let titleSnapshot = stringValue(dict["titleSnapshot"]) else {
            return nil
        }

        let content = LookbookSharedContent(
            schemaVersion: schemaVersion,
            contentType: contentType,
            brandID: brandID,
            seasonID: stringValue(dict["seasonID"]),
            postID: stringValue(dict["postID"]),
            titleSnapshot: titleSnapshot,
            subtitleSnapshot: stringValue(dict["subtitleSnapshot"]),
            thumbnailPathSnapshot: stringValue(dict["thumbnailPathSnapshot"])
        )

        return content.isValid ? content : nil
    }

    private static func trimmedNonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func stringValue(_ value: Any?) -> String? {
        switch value {
        case let string as String:
            return trimmedNonEmpty(string)
        case let string as NSString:
            return trimmedNonEmpty(String(string))
        case let number as NSNumber:
            return number.stringValue
        default:
            return nil
        }
    }

    private static func intValue(_ value: Any?) -> Int? {
        switch value {
        case let number as NSNumber:
            return number.intValue
        case let int as Int:
            return int
        case let int64 as Int64:
            return Int(int64)
        case let double as Double:
            return Int(double)
        case let string as String:
            return Int(string)
        default:
            return nil
        }
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case contentType
        case brandID
        case seasonID
        case postID
        case titleSnapshot
        case subtitleSnapshot
        case thumbnailPathSnapshot
    }
}
