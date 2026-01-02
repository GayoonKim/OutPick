//
//  LookbookHomeViewModel.swift
//  OutPick
//
//  Created by 김가윤 on 12/18/25.
//

import Foundation
import FirebaseFirestore

@MainActor
final class LookbookHomeViewModel: ObservableObject {

    enum Phase: Equatable {
        case idle
        case loading
        case ready
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var brands: [Brand] = []

    /// DI
    private let repo: BrandRepositoryProtocol
    let imageLoader: any ImageLoading

    /// 페이지네이션 기준(마지막 문서)
    private var lastBrandDocument: DocumentSnapshot? = nil

    /// 중복 로드 방지
    private var didPreload = false
    private var isPreloading = false
    private var isLoadingNext = false

    /// 최초 로딩 시 가져올 브랜드 수
    private let initialBrandLimit: Int
    /// 첫 화면용 로고 프리패치 개수
    private let prefetchLogoCount: Int
    /// 프리패치 동시성
    private let prefetchConcurrency: Int
    /// 썸네일 다운로드 최대 바이트(목록 전용)
    private let thumbMaxBytes: Int

    init(
        repo: BrandRepositoryProtocol = FirestoreBrandRepository(),
        imageLoader: any ImageLoading = BrandLogoImageStore(),
        initialBrandLimit: Int = 20,
        prefetchLogoCount: Int = 12,
        prefetchConcurrency: Int = 6,
        thumbMaxBytes: Int = 1 * 1024 * 1024
    ) {
        self.repo = repo
        self.imageLoader = imageLoader
        self.initialBrandLimit = initialBrandLimit
        self.prefetchLogoCount = prefetchLogoCount
        self.prefetchConcurrency = prefetchConcurrency
        self.thumbMaxBytes = thumbMaxBytes
    }

    /// 앱 시작 시 또는 룩북 탭 진입 전에 한 번 호출
    func preloadIfNeeded() async {
        guard !didPreload, !isPreloading else { return }
        isPreloading = true
        defer { isPreloading = false }
        
        phase = .loading

        do {
            // 1) 브랜드 fetch (아직 publish 하지 않음)
            let page = try await repo.fetchBrands(sort: .latest, limit: initialBrandLimit, after: nil)

            // 2) 첫 화면용 N개 thumbPath만 모아서 prefetch
            let prefetchTargets = makePrefetchTargets(from: page.items, count: prefetchLogoCount)
            await imageLoader.prefetch(items: prefetchTargets, concurrency: prefetchConcurrency)

            // 3) prefetch 완료 후에야 publish → 화면 표시
            self.brands = page.items
            self.lastBrandDocument = page.last
            self.phase = .ready
            
            didPreload = true
        } catch {
            self.phase = .failed(error.localizedDescription)
        }
    }

    func retry() async {
        didPreload = false
        lastBrandDocument = nil
        brands = []
        phase = .idle
        await preloadIfNeeded()
    }

    /// 스크롤 바닥에서 다음 페이지 로드
    func loadNextPageIfNeeded(current brand: Brand) async {
        guard phase == .ready else { return }
        guard let last = brands.last, last.id == brand.id else { return }
        guard !isLoadingNext else { return }
        guard let after = lastBrandDocument else { return }

        isLoadingNext = true
        defer { isLoadingNext = false }

        do {
            let page = try await repo.fetchBrands(sort: .latest, limit: initialBrandLimit, after: after)

            // 다음 페이지도 첫 몇 개만 가볍게 프리패치
            let prefetchTargets = makePrefetchTargets(from: page.items, count: min(prefetchLogoCount, 8))
            await imageLoader.prefetch(items: prefetchTargets, concurrency: prefetchConcurrency)

            self.brands.append(contentsOf: page.items)
            self.lastBrandDocument = page.last
        } catch {
            // 페이지네이션 실패는 치명적이지 않으니 조용히 무시
        }
    }

    private func makePrefetchTargets(
        from brands: [Brand],
        count: Int
    ) -> [(path: String, cacheKey: String, maxBytes: Int)] {

        let slice = brands.prefix(max(count, 0))

        return slice.compactMap { brand in
            // 목록에서는 썸네일 우선, 없으면 기존 logoPath로 폴백
            let resolved = brand.logoThumbPath ?? brand.logoOriginalPath
            guard let path = resolved, !path.isEmpty else { return nil }

            // 캐시 키는 용도를 포함
            let key = "brandLogoThumb|\(path)"
            return (path: path, cacheKey: key, maxBytes: thumbMaxBytes)
        }
    }
}

