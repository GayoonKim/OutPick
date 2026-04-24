//
//  CreateSeasonFromURLViewModel.swift
//  OutPick
//
//  Created by Codex on 4/23/26.
//

import Foundation
import FirebaseFunctions

@MainActor
final class CreateSeasonFromURLViewModel: ObservableObject {
    @Published var seasonURLText: String = ""
    @Published private(set) var isSaving: Bool = false
    @Published var errorMessage: String?

    private let brandID: BrandID
    private let seasonImportRepository: SeasonImportRequestingRepository

    init(
        brandID: BrandID,
        seasonImportRepository: SeasonImportRequestingRepository
    ) {
        self.brandID = brandID
        self.seasonImportRepository = seasonImportRepository
    }

    func requestImport() async -> SeasonImportRequestReceipt? {
        errorMessage = nil

        let normalizedSeasonURL: String
        do {
            normalizedSeasonURL = try makeNormalizedSeasonURL(from: seasonURLText)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }

        isSaving = true
        defer { isSaving = false }

        do {
            return try await seasonImportRepository.requestSeasonImport(
                brandID: brandID,
                seasonURL: normalizedSeasonURL,
                sourceCandidateID: nil
            )
        } catch {
            print(
                "[CreateSeasonFromURLViewModel] requestSeasonImport failed " +
                "brandID=\(brandID.value) error=\(error.localizedDescription)"
            )
            errorMessage = friendlyErrorMessage(for: error)
            return nil
        }
    }
}

private extension CreateSeasonFromURLViewModel {
    func makeNormalizedSeasonURL(from rawValue: String) throws -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw NSError(
                domain: "CreateSeasonFromURLViewModel",
                code: -30,
                userInfo: [NSLocalizedDescriptionKey: "시즌 URL을 입력해주세요."]
            )
        }

        // 한국어 주석: 사용자가 스킴 없이 붙여넣는 경우를 고려해 https를 기본값으로 보정합니다.
        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"

        guard var components = URLComponents(string: candidate) else {
            throw NSError(
                domain: "CreateSeasonFromURLViewModel",
                code: -31,
                userInfo: [NSLocalizedDescriptionKey: "시즌 URL 형식이 올바르지 않습니다."]
            )
        }

        guard let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme) else {
            throw NSError(
                domain: "CreateSeasonFromURLViewModel",
                code: -32,
                userInfo: [NSLocalizedDescriptionKey: "시즌 URL은 http 또는 https만 지원합니다."]
            )
        }

        guard let host = components.host, !host.isEmpty else {
            throw NSError(
                domain: "CreateSeasonFromURLViewModel",
                code: -33,
                userInfo: [NSLocalizedDescriptionKey: "시즌 URL에 도메인이 필요합니다."]
            )
        }

        components.scheme = scheme
        components.host = host.lowercased()

        guard let normalized = components.string else {
            throw NSError(
                domain: "CreateSeasonFromURLViewModel",
                code: -34,
                userInfo: [NSLocalizedDescriptionKey: "시즌 URL을 정규화하지 못했습니다."]
            )
        }

        return normalized
    }

    func friendlyErrorMessage(for error: Error) -> String {
        let nsError = error as NSError
        print("Functions error domain=\(nsError.domain) code=\(nsError.code) userInfo=\(nsError.userInfo)")

        if nsError.domain == FunctionsErrorDomain,
           let code = FunctionsErrorCode(rawValue: nsError.code) {
            switch code {
            case .permissionDenied:
                return "이 브랜드에 시즌 URL import를 요청할 권한이 없습니다."
            case .notFound:
                return "브랜드 문서 또는 시즌 URL import 서버 API를 찾지 못했습니다. 방금 추가한 기능이라면 requestSeasonImport Functions 배포 여부를 먼저 확인해주세요."
            case .invalidArgument:
                return "시즌 URL 값이 올바르지 않습니다."
            case .unauthenticated:
                return "로그인이 필요합니다."
            default:
                break
            }
        }

        return "시즌 URL import 요청 생성 실패: \(error.localizedDescription)"
    }
}
