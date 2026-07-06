//
//  MyBrandRequestsViewModel.swift
//  OutPick
//
//  Created by Codex on 7/6/26.
//

import Foundation

@MainActor
final class MyBrandRequestsViewModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case loading
        case ready
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var requests: [BrandRequest] = []
    @Published var scope: BrandRequestListScope

    private let listUseCase: any ListMyBrandRequestsUseCaseProtocol
    private let pageLimit: Int
    private let prefetchThreshold: Int
    private var nextCursor: BrandRequestPage.Cursor?
    private var isLoading = false

    init(
        scope: BrandRequestListScope = .active,
        listUseCase: any ListMyBrandRequestsUseCaseProtocol,
        pageLimit: Int = 20,
        prefetchThreshold: Int = 5
    ) {
        self.scope = scope
        self.listUseCase = listUseCase
        self.pageLimit = pageLimit
        self.prefetchThreshold = prefetchThreshold
    }

    var canLoadNextPage: Bool {
        nextCursor != nil && isLoading == false
    }

    func loadInitial() async {
        guard phase == .idle else { return }
        await reload()
    }

    func reload() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        phase = .loading
        nextCursor = nil

        do {
            let page = try await listUseCase.execute(
                scope: scope,
                limit: pageLimit,
                cursor: nil
            )
            requests = page.requests
            nextCursor = page.nextCursor
            phase = .ready
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func selectScope(_ nextScope: BrandRequestListScope) async {
        guard scope != nextScope else { return }
        scope = nextScope
        await reload()
    }

    func loadNextPageIfNeeded(current request: BrandRequest) async {
        guard let nextCursor else { return }
        guard shouldPrefetch(afterSeeing: request) else { return }
        guard !isLoading else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let page = try await listUseCase.execute(
                scope: scope,
                limit: pageLimit,
                cursor: nextCursor
            )
            requests.append(contentsOf: page.requests)
            self.nextCursor = page.nextCursor
            phase = .ready
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func shouldPrefetch(afterSeeing request: BrandRequest) -> Bool {
        guard let index = requests.firstIndex(where: { $0.id == request.id }) else {
            return false
        }
        return index >= max(requests.count - prefetchThreshold, 0)
    }
}
