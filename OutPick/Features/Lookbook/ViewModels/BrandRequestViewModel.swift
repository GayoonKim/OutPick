//
//  BrandRequestViewModel.swift
//  OutPick
//
//  Created by Codex on 7/6/26.
//

import Foundation

@MainActor
final class BrandRequestViewModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case submitting
        case submitted(BrandRequestSubmissionReceipt)
        case failed(String)
    }

    @Published var brandName: String
    @Published var englishBrandName: String = ""
    @Published private(set) var phase: Phase = .idle

    private let submitUseCase: any SubmitBrandRequestUseCaseProtocol

    init(
        initialBrandName: String,
        submitUseCase: any SubmitBrandRequestUseCaseProtocol
    ) {
        self.brandName = initialBrandName
        self.submitUseCase = submitUseCase
    }

    var trimmedBrandName: String {
        brandName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedEnglishBrandName: String {
        englishBrandName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var canSubmit: Bool {
        trimmedBrandName.isEmpty == false && phase != .submitting
    }

    func submit() async -> BrandRequestSubmissionReceipt? {
        guard canSubmit else { return nil }
        phase = .submitting

        do {
            let receipt = try await submitUseCase.execute(
                brandName: trimmedBrandName,
                englishBrandName: trimmedEnglishBrandName.isEmpty ? nil : trimmedEnglishBrandName
            )
            phase = .submitted(receipt)
            return receipt
        } catch {
            phase = .failed(Self.message(for: error))
            return nil
        }
    }

    private static func message(for error: Error) -> String {
        let nsError = error as NSError
        switch nsError.code {
        case 8:
            return "오늘 요청 가능 횟수를 모두 사용했어요."
        case 7:
            return "브랜드 요청이 제한된 계정이에요."
        default:
            return error.localizedDescription
        }
    }
}
