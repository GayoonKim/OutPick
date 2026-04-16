//
//  CloudFunctionsManager.swift
//  OutPick
//
//  Created by 김가윤 on 12/4/25.
//

import Foundation
import FirebaseFunctions

struct KakaoFirebaseAuthBridgeResponse {
    let firebaseCustomToken: String
    let identityKey: String
    let providerUserID: String
    let email: String?
}

struct BrandAdminCapabilitiesResponse {
    let canCreateBrands: Bool
    let allowedBrandIDs: [String]
    let roles: [String]
}

enum CloudFunctionsManagerError: LocalizedError {
    case invalidResponse
    case missingField(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Cloud Functions 응답 형식이 올바르지 않습니다."
        case .missingField(let field):
            return "Cloud Functions 응답에 \(field) 값이 없습니다."
        }
    }
}

final class CloudFunctionsManager {
    static let shared = CloudFunctionsManager()
    private static let region = "asia-northeast3"

    private lazy var regionalFunctions = Functions.functions(region: Self.region)
    private lazy var defaultFunctions = Functions.functions()

    private init() {}

    func callHelloUser(name: String, completion: @escaping (Result<String, Error>) -> Void) {
        let data: [String: Any] = ["name": name]

        regionalFunctions.httpsCallable("helloUser").call(data) { result, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            if let dict = result?.data as? [String: Any],
               let text = dict["result"] as? String {
                completion(.success(text))
            } else {
                // 응답 포맷이 예상과 다를 경우
                let parseError = NSError(
                    domain: "CloudFunctions",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "응답 파싱 실패"]
                )
                completion(.failure(parseError))
            }
        }
    }

    func exchangeKakaoToken(accessToken: String) async throws -> KakaoFirebaseAuthBridgeResponse {
        let response = try await callFunction(
            "exchangeKakaoToken",
            data: ["accessToken": accessToken]
        )

        let firebaseCustomToken = try stringValue(response, key: "firebaseCustomToken")
        let identityKey = try stringValue(response, key: "identityKey")
        let providerUserID = try stringValue(response, key: "providerUserID")
        let email = optionalStringValue(response, key: "email")

        return KakaoFirebaseAuthBridgeResponse(
            firebaseCustomToken: firebaseCustomToken,
            identityKey: identityKey,
            providerUserID: providerUserID,
            email: email
        )
    }

    func createBrand(
        brandID: String,
        name: String,
        logoThumbPath: String?,
        logoDetailPath: String?,
        isFeatured: Bool
    ) async throws -> String {
        var data: [String: Any] = [
            "brandID": brandID,
            "name": name,
            "isFeatured": isFeatured
        ]
        if let logoThumbPath {
            data["logoThumbPath"] = logoThumbPath
        }
        if let logoDetailPath {
            data["logoDetailPath"] = logoDetailPath
        }

        let response = try await callFunction("createBrand", data: data)
        return try stringValue(response, key: "brandID")
    }

    func getBrandAdminCapabilities() async throws -> BrandAdminCapabilitiesResponse {
        let response: [String: Any]
        do {
            response = try await callFunction("getBrandAdminCapabilities", data: [:])
        } catch {
            let nsError = error as NSError
            print(
                """
                [CloudFunctionsManager] getBrandAdminCapabilities failed \
                region=\(Self.region) domain=\(nsError.domain) code=\(nsError.code) \
                description=\(nsError.localizedDescription). Retrying default region.
                """
            )
            response = try await callFunction(
                "getBrandAdminCapabilities",
                data: [:],
                functions: defaultFunctions
            )
        }

        return BrandAdminCapabilitiesResponse(
            canCreateBrands: response["canCreateBrands"] as? Bool ?? false,
            allowedBrandIDs: stringArrayValue(response, key: "allowedBrandIDs"),
            roles: stringArrayValue(response, key: "roles")
        )
    }

    func updateBrandLogoDetailPath(
        brandID: String,
        logoDetailPath: String
    ) async throws -> String {
        let response = try await callFunction(
            "updateBrandLogoDetailPath",
            data: [
                "brandID": brandID,
                "logoDetailPath": logoDetailPath
            ]
        )
        return try stringValue(response, key: "brandID")
    }

    private func callFunction(
        _ name: String,
        data: [String: Any],
        functions: Functions? = nil
    ) async throws -> [String: Any] {
        let functionsClient = functions ?? regionalFunctions

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[String: Any], Error>) in
            functionsClient.httpsCallable(name).call(data) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let dictionary = result?.data as? [String: Any] else {
                    continuation.resume(throwing: CloudFunctionsManagerError.invalidResponse)
                    return
                }

                continuation.resume(returning: dictionary)
            }
        }
    }

    private func stringValue(_ dictionary: [String: Any], key: String) throws -> String {
        guard let value = dictionary[key] as? String, !value.isEmpty else {
            throw CloudFunctionsManagerError.missingField(key)
        }
        return value
    }

    private func optionalStringValue(_ dictionary: [String: Any], key: String) -> String? {
        guard let value = dictionary[key], !(value is NSNull) else {
            return nil
        }
        guard let string = value as? String else {
            return nil
        }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func stringArrayValue(_ dictionary: [String: Any], key: String) -> [String] {
        guard let values = dictionary[key] as? [String] else {
            return []
        }
        return values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
