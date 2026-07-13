//
//  CloudFunctionsBrandStore.swift
//  OutPick
//
//  Created by Codex on 4/16/26.
//

import Foundation

/// Cloud Functions를 통해 브랜드 문서를 생성/수정하는 BrandStoring 구현입니다.
/// - Note: 브랜드 문서 직접 쓰기는 Firestore Rules에서 차단하고, 서버 권한 검증을 통과한 요청만 반영합니다.
struct CloudFunctionsBrandStore: BrandStoringRepository {
    private let transport: any CloudFunctionsTransporting

    init(transport: any CloudFunctionsTransporting = FirebaseCloudFunctionsTransport()) {
        self.transport = transport
    }

    func createBrand(
        name: String,
        englishName: String?,
        isFeatured: Bool,
        websiteURL: String?,
        lookbookArchiveURL: String?
    ) async throws -> String {
        var data: [String: Any] = ["name": name, "isFeatured": isFeatured]
        if let englishName { data["englishName"] = englishName }
        if let websiteURL { data["websiteURL"] = websiteURL }
        if let lookbookArchiveURL { data["lookbookArchiveURL"] = lookbookArchiveURL }
        let response = try await transport.call("createBrand", data: data)
        return try CloudFunctionResponseDecoder(dictionary: response).string("brandID")
    }

    func updateBrand(
        brandID: BrandID,
        name: String,
        englishName: String?,
        websiteURL: String?,
        lookbookArchiveURL: String?,
        isFeatured: Bool?
    ) async throws -> Brand {
        var data: [String: Any] = [
            "brandID": brandID.value,
            "name": name,
            "englishName": englishName ?? NSNull(),
            "websiteURL": websiteURL ?? "",
            "lookbookArchiveURL": lookbookArchiveURL ?? ""
        ]
        if let isFeatured { data["isFeatured"] = isFeatured }
        let response = try await transport.call("updateBrand", data: data)
        let brand = try CloudFunctionResponseDecoder(dictionary: response)
            .nestedDictionary("brand")
        return try BrandCloudFunctionsMapper.brand(brand)
    }

    func updateLogoPaths(
        docID: String,
        logoThumbPath: String?,
        logoDetailPath: String?
    ) async throws {
        var data: [String: Any] = ["brandID": docID]
        if let logoThumbPath { data["logoThumbPath"] = logoThumbPath }
        if let logoDetailPath { data["logoDetailPath"] = logoDetailPath }
        _ = try await transport.call("updateBrandLogoPaths", data: data)
    }

    func addBrandManager(
        brandID: BrandID,
        email: String,
        role: BrandManagerRole
    ) async throws -> BrandManagerMutationReceipt {
        let response = try await transport.call(
            "addBrandManager",
            data: ["brandID": brandID.value, "email": email, "role": role.rawValue]
        )
        return try BrandCloudFunctionsMapper.managerReceipt(response, fallbackRemoved: false)
    }

    func removeBrandManager(
        brandID: BrandID,
        email: String,
        role: BrandManagerRole
    ) async throws -> BrandManagerMutationReceipt {
        let response = try await transport.call(
            "removeBrandManager",
            data: ["brandID": brandID.value, "email": email, "role": role.rawValue]
        )
        return try BrandCloudFunctionsMapper.managerReceipt(response, fallbackRemoved: true)
    }
}
