//
//  SubmitBrandRequestUseCase.swift
//  OutPick
//
//  Created by Codex on 7/6/26.
//

import Foundation

protocol SubmitBrandRequestUseCaseProtocol {
    func execute(
        brandName: String,
        websiteURL: String,
        englishBrandName: String?
    ) async throws -> BrandRequestSubmissionReceipt
}

struct SubmitBrandRequestUseCase: SubmitBrandRequestUseCaseProtocol {
    private let repository: BrandRequestRepositoryProtocol

    init(repository: BrandRequestRepositoryProtocol) {
        self.repository = repository
    }

    func execute(
        brandName: String,
        websiteURL: String,
        englishBrandName: String?
    ) async throws -> BrandRequestSubmissionReceipt {
        guard BrandRequestInput.isValid(brandName: brandName, websiteURL: websiteURL,
                                       englishBrandName: englishBrandName) else {
            throw BrandRequestInput.invalidInput
        }
        return try await repository.submitBrandRequest(
            brandName: brandName,
            websiteURL: websiteURL,
            englishBrandName: englishBrandName
        )
    }
}

enum BrandRequestInput: LocalizedError {
    case invalidInput

    var errorDescription: String? { "브랜드명과 올바른 공식 URL을 입력해주세요." }

    static func isValid(brandName: String, websiteURL: String, englishBrandName: String?) -> Bool {
        func validName(_ value: String) -> Bool {
            guard value.utf16.count <= 80 else { return false }
            let normalized = value.precomposedStringWithCompatibilityMapping
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .lowercased()
            return !normalized.isEmpty && normalized.unicodeScalars.count <= 80
        }
        guard validName(brandName), englishBrandName.map(validName) ?? true else { return false }
        let raw = websiteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, raw.unicodeScalars.count <= 2048,
              raw.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else { return false }
        let withScheme = raw.contains("://") ? raw : "https://" + raw
        guard let url = URLComponents(string: withScheme),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil, url.url != nil else { return false }
        return true
    }
}
