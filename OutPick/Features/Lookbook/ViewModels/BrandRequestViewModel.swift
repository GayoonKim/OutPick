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
    @Published var websiteURL: String = ""
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var navigationError: String?
    @Published private(set) var isOpeningBrand = false

    private let submitUseCase: any SubmitBrandRequestUseCaseProtocol
    private let initialBrandName: String
    private let loadBrandUseCase: any LoadPublicBrandUseCaseProtocol

    init(
        initialBrandName: String,
        submitUseCase: any SubmitBrandRequestUseCaseProtocol,
        loadBrandUseCase: any LoadPublicBrandUseCaseProtocol
    ) {
        self.brandName = initialBrandName
        self.initialBrandName = initialBrandName
        self.submitUseCase = submitUseCase
        self.loadBrandUseCase = loadBrandUseCase
    }

    var trimmedBrandName: String {
        brandName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedEnglishBrandName: String {
        englishBrandName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var canSubmit: Bool {
        BrandRequestInput.isValid(brandName: trimmedBrandName, websiteURL: trimmedWebsiteURL,
                                 englishBrandName: trimmedEnglishBrandName.isEmpty ? nil : trimmedEnglishBrandName)
            && phase != .submitting && receipt == nil
    }

    var receipt: BrandRequestSubmissionReceipt? {
        if case .submitted(let receipt) = phase { return receipt }
        return nil
    }

    var submissionErrorMessage: String? {
        if case .failed(let message) = phase { return message }
        return nil
    }

    func dismissSubmissionError() {
        guard case .failed = phase else { return }
        phase = .idle
    }

    func openCompletedBrand(using coordinator: any BrandRequestRouting) async {
        guard let id = receipt?.destinationBrandID, !isOpeningBrand else { return }
        isOpeningBrand = true
        navigationError = nil
        defer { isOpeningBrand = false }
        do {
            let brand = try await loadBrandUseCase.execute(brandID: id)
            guard !Task.isCancelled else { return }
            coordinator.pushBrandDetail(brand: brand)
        } catch {
            navigationError = error.localizedDescription
        }
    }

    var trimmedWebsiteURL: String { websiteURL.trimmingCharacters(in: .whitespacesAndNewlines) }

    var hasDraftChanges: Bool {
        trimmedBrandName != initialBrandName.trimmingCharacters(in: .whitespacesAndNewlines) ||
        trimmedEnglishBrandName.isEmpty == false || trimmedWebsiteURL.isEmpty == false
    }

    var disablesInteractivePop: Bool {
        phase == .submitting || (receipt == nil && hasDraftChanges)
    }

    func submit() async -> BrandRequestSubmissionReceipt? {
        guard canSubmit else { return nil }
        phase = .submitting

        do {
            let receipt = try await submitUseCase.execute(
                brandName: trimmedBrandName,
                websiteURL: trimmedWebsiteURL,
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
        (error as? BrandRequestFailure)?.errorDescription
            ?? "접수 결과를 확인하지 못했어요. 요청 내역을 확인해 주세요."
    }
}
