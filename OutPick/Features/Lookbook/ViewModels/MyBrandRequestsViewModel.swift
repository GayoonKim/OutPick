import Foundation

@MainActor
final class MyBrandRequestsViewModel: ObservableObject {
    enum Phase: Equatable {
        case idle, loading, ready
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var requests: [BrandRequest] = []
    @Published private(set) var scope: BrandRequestListScope
    @Published private(set) var navigationError: String?
    @Published private(set) var openingRequestID: String?

    private let listUseCase: any ListMyBrandRequestsUseCaseProtocol
    private let loadBrandUseCase: any LoadPublicBrandUseCaseProtocol
    private let pageLimit: Int
    private let prefetchThreshold: Int
    private var nextCursor: BrandRequestPage.Cursor?
    private var isLoading = false
    private var generation = 0
    private var navigationGeneration = 0
    private var loadTask: Task<Void, Never>?

    init(scope: BrandRequestListScope = .active,
         listUseCase: any ListMyBrandRequestsUseCaseProtocol,
         loadBrandUseCase: any LoadPublicBrandUseCaseProtocol,
         pageLimit: Int = 20, prefetchThreshold: Int = 5) {
        self.scope = scope
        self.listUseCase = listUseCase
        self.loadBrandUseCase = loadBrandUseCase
        self.pageLimit = pageLimit
        self.prefetchThreshold = prefetchThreshold
    }

    var canLoadNextPage: Bool { nextCursor != nil && !isLoading }

    func loadInitial() async {
        guard phase == .idle else { return }
        await reload()
    }

    func reload() async {
        cancelPendingNavigation()
        generation += 1
        loadTask?.cancel()
        nextCursor = nil
        phase = .loading
        await load(cursor: nil, generation: generation)
    }

    func selectScope(_ nextScope: BrandRequestListScope) async {
        guard scope != nextScope else { return }
        scope = nextScope
        requests = []
        navigationError = nil
        await reload()
    }

    func loadNextPageIfNeeded(current request: BrandRequest) async {
        guard let cursor = nextCursor, !isLoading,
              let index = requests.firstIndex(where: { $0.id == request.id }),
              index >= max(requests.count - prefetchThreshold, 0) else { return }
        await load(cursor: cursor, generation: generation)
    }

    func retry() async {
        guard !isLoading else { return }
        if let cursor = nextCursor {
            await load(cursor: cursor, generation: generation)
        } else {
            await reload()
        }
    }

    private func load(cursor: BrandRequestPage.Cursor?, generation: Int) async {
        let requestedScope = scope
        isLoading = true
        let task = Task { [weak self, listUseCase, pageLimit] in
            do {
                var currentCursor = cursor
                var consumedCursors = cursor.map { [$0] } ?? []
                while true {
                    let page = try await listUseCase.execute(scope: requestedScope, limit: pageLimit, cursor: currentCursor)
                    guard let self, !Task.isCancelled, self.generation == generation,
                          self.scope == requestedScope else { return }
                    guard page.scope == requestedScope,
                          page.nextCursor.map({ !consumedCursors.contains($0) }) ?? true else {
                        throw CloudFunctionsClientError.invalidResponse
                    }
                    if currentCursor == nil {
                        self.requests = page.requests
                    } else {
                        var seen = Set(self.requests.map(\.id))
                        self.requests.append(contentsOf: page.requests.filter { seen.insert($0.id).inserted })
                    }
                    self.nextCursor = page.nextCursor
                    guard page.requests.isEmpty, let next = page.nextCursor else {
                        self.phase = .ready
                        self.isLoading = false
                        return
                    }
                    consumedCursors.append(next)
                    currentCursor = next
                }
            } catch {
                guard let self, !Task.isCancelled, self.generation == generation,
                      self.scope == requestedScope else { return }
                self.phase = .failed((error as? BrandRequestFailure)?.errorDescription
                    ?? "요청 내역을 확인하지 못했어요. 다시 시도해 주세요.")
                self.isLoading = false
            }
        }
        loadTask = task
        await task.value
    }

    func cancelPendingNavigation() {
        navigationGeneration += 1
        openingRequestID = nil
    }

    func openCompletedBrand(_ request: BrandRequest, using coordinator: any BrandRequestRouting) async {
        guard request.status == .added, let id = request.resolvedBrandID,
              openingRequestID == nil else { return }
        let requestedGeneration = generation
        let requestedNavigationGeneration = navigationGeneration
        openingRequestID = request.id
        navigationError = nil
        defer {
            if requestedNavigationGeneration == navigationGeneration { openingRequestID = nil }
        }
        do {
            let brand = try await loadBrandUseCase.execute(brandID: id)
            guard !Task.isCancelled, requestedGeneration == generation,
                  requestedNavigationGeneration == navigationGeneration else { return }
            coordinator.pushBrandDetail(brand: brand)
        } catch {
            guard !Task.isCancelled, requestedGeneration == generation,
                  requestedNavigationGeneration == navigationGeneration else { return }
            navigationError = error.localizedDescription
        }
    }
}
