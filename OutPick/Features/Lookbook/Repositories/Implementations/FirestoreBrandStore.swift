//
//  FirestoreBrandStore.swift
//  OutPick
//
//  Created by 김가윤 on 1/13/26.
//

import Foundation
import FirebaseAuth
import FirebaseFirestore

/// Firestore 기반 BrandStoring 구현입니다.
struct FirestoreBrandStore: BrandStoringRepository {
    let db: Firestore

    init(db: Firestore = Firestore.firestore()) {
        self.db = db
    }

    func createBrand(
        name: String,
        isFeatured: Bool,
        websiteURL: String?,
        lookbookArchiveURL: String?
    ) async throws -> String {
        let docRef = db.collection("brands").document()
        let docID = docRef.documentID
        let normalizedName = normalizeBrandName(name)
        let currentUID = Auth.auth().currentUser?.uid

        let data: [String: Any] = [
            "name": normalizedDisplayName(name),
            "normalizedName": normalizedName,
            "websiteURL": websiteURL ?? NSNull(),
            "lookbookArchiveURL": lookbookArchiveURL ?? NSNull(),

            "logoPath": NSNull(),
            "logoThumbPath": NSNull(),
            "logoDetailPath": NSNull(),
            "logoOriginalPath": NSNull(),

            "isFeatured": isFeatured,
            "discoveryStatus": BrandDiscoveryStatus.idle.rawValue,
            "lastDiscoveryErrorMessage": NSNull(),
            "lastDiscoveryRequestedAt": NSNull(),
            "lastDiscoveryCompletedAt": NSNull(),
            "likeCount": 0,
            "viewCount": 0,
            "popularScore": 0.0,
            "createdBy": currentUID ?? NSNull(),
            "updatedBy": currentUID ?? NSNull(),
            "ownerUIDs": currentUID.map { [$0] } ?? [],
            "adminUIDs": [String](),
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp()
        ]

        try await docRef.setDataAsync(data, merge: false)
        return docID
    }

    func updateLogoPaths(
        docID: String,
        logoThumbPath: String?,
        logoDetailPath: String?
    ) async throws {
        var data: [String: Any] = [
            "updatedAt": FieldValue.serverTimestamp()
        ]
        if let logoThumbPath {
            data["logoPath"] = logoThumbPath
            data["logoThumbPath"] = logoThumbPath
        }
        if let logoDetailPath {
            data["logoDetailPath"] = logoDetailPath
        }

        try await db
            .collection("brands")
            .document(docID)
            .setDataAsync(data, merge: true)
    }

    func updateBrand(
        brandID: BrandID,
        name: String,
        websiteURL: String?,
        lookbookArchiveURL: String?,
        isFeatured: Bool?
    ) async throws -> Brand {
        let normalizedName = normalizeBrandName(name)
        var payload: [String: Any] = [
            "name": normalizedDisplayName(name),
            "normalizedName": normalizedName,
            "websiteURL": websiteURL ?? NSNull(),
            "lookbookArchiveURL": lookbookArchiveURL ?? NSNull(),
            "updatedAt": FieldValue.serverTimestamp()
        ]
        if let isFeatured {
            payload["isFeatured"] = isFeatured
        }
        try await db
            .collection("brands")
            .document(brandID.value)
            .setDataAsync(payload, merge: true)

        return Brand(
            id: brandID,
            name: normalizedDisplayName(name),
            websiteURL: websiteURL,
            lookbookArchiveURL: lookbookArchiveURL,
            logoThumbPath: nil,
            logoDetailPath: nil,
            logoOriginalPath: nil,
            isFeatured: isFeatured ?? false,
            discoveryStatus: .idle,
            lastDiscoveryErrorMessage: nil,
            lastDiscoveryRequestedAt: nil,
            lastDiscoveryCompletedAt: nil,
            metrics: BrandMetrics(likeCount: 0, viewCount: 0, popularScore: 0),
            updatedAt: Date()
        )
    }

    func addBrandManager(
        brandID: BrandID,
        email: String,
        role: BrandManagerRole
    ) async throws -> BrandManagerMutationReceipt {
        throw NSError(
            domain: "FirestoreBrandStore",
            code: -10,
            userInfo: [NSLocalizedDescriptionKey: "관리자 변경은 Cloud Functions에서만 지원합니다."]
        )
    }

    func removeBrandManager(
        brandID: BrandID,
        email: String,
        role: BrandManagerRole
    ) async throws -> BrandManagerMutationReceipt {
        throw NSError(
            domain: "FirestoreBrandStore",
            code: -11,
            userInfo: [NSLocalizedDescriptionKey: "관리자 변경은 Cloud Functions에서만 지원합니다."]
        )
    }
}

private extension FirestoreBrandStore {
    func normalizedDisplayName(_ rawValue: String) -> String {
        rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    func normalizeBrandName(_ rawValue: String) -> String {
        normalizedDisplayName(rawValue)
            .precomposedStringWithCompatibilityMapping
            .lowercased()
    }
}

// MARK: - Firestore async 브릿지 (setData completion -> async/await)

private extension DocumentReference {
    /// Firebase 버전에 따라 setData의 async 지원이 없을 수 있어 안전하게 브릿지합니다.
    func setDataAsync(_ documentData: [String: Any], merge: Bool) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.setData(documentData, merge: merge) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }
}
