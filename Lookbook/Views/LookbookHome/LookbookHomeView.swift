//
//  LookbookHomeView.swift
//  OutPick
//
//  Created by 김가윤 on 12/18/25.
//

import SwiftUI
import FirebaseFirestore
import FirebaseStorage

struct LookbookHomeView: View {

    @StateObject private var viewModel = LookbookHomeViewModel()

    var body: some View {
        NavigationView {
            Group {
                switch viewModel.state {
                case .idle, .loading:
                    ProgressView("브랜드 불러오는 중...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                case .loaded:
                    List {
                        Section(header: Text("Brands")) {
                            ForEach(viewModel.brands) { brand in
                                BrandRowView(brand: brand)
                            }
                        }

                        if viewModel.canLoadMore {
                            Section {
                                Button {
                                    Task { await viewModel.loadMore() }
                                } label: {
                                    HStack {
                                        Spacer()
                                        if viewModel.isPaging {
                                            ProgressView()
                                        } else {
                                            Text("더 불러오기")
                                        }
                                        Spacer()
                                    }
                                }
                                .disabled(viewModel.isPaging)
                            }
                        }
                    }

                case .failed(let message):
                    VStack(spacing: 12) {
                        Text("불러오기에 실패했어요")
                            .font(.headline)
                        Text(message)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)

                        Button("다시 시도") {
                            Task { await viewModel.refresh() }
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Lookbook")
            .task {
                await viewModel.refresh()
            }
        }
    }
}

// MARK: - Row

private struct BrandRowView: View {

    let brand: Brand

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            BrandLogoView(logoPath: brand.logoPath)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(brand.name)
                        .font(.headline)

                    if brand.isFeatured {
                        Text("FEATURED")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.15))
                            .cornerRadius(6)
                    }

                    Spacer()
                }

                HStack(spacing: 10) {
                    Text("❤️ \(brand.metrics.likeCount)")
                    Text("👀 \(brand.metrics.viewCount)")
                    Text("🔥 \(brand.metrics.popularScore)")
                }
                .font(.caption)
                .foregroundColor(.secondary)

                // logoPath는 디버그용으로만 표시 (필요 없으면 삭제 가능)
                if let logoPath = brand.logoPath, !logoPath.isEmpty {
                    Text("logoPath: \(logoPath)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Logo

private struct BrandLogoView: View {

    let logoPath: String?

    @State private var url: URL? = nil
    @State private var isLoading: Bool = false

    private let size: CGFloat = 44

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.secondary.opacity(0.12))

            if let url {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    ProgressView()
                }
                .clipped()
            } else {
                Image(systemName: "photo")
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .task(id: logoPath) {
            await loadURLIfNeeded()
        }
    }

    private func loadURLIfNeeded() async {
        guard let logoPath, !logoPath.isEmpty else {
            url = nil
            return
        }

        // 이미 가져온 URL이 있으면 재요청하지 않음
        if url != nil { return }
        if isLoading { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let ref = Storage.storage().reference(withPath: logoPath)
            let fetched = try await ref.downloadURLAsync()
            url = fetched
        } catch {
            // 실패 시엔 기본 플레이스홀더 유지
            url = nil
        }
    }
}

// MARK: - ViewModel

@MainActor
private final class LookbookHomeViewModel: ObservableObject {

    enum State: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    @Published var state: State = .idle
    @Published var brands: [Brand] = []
    @Published var isPaging: Bool = false

    private let repo: BrandRepositoryProtocol
    private var last: DocumentSnapshot? = nil

    // 페이지 크기(임시)
    private let limit: Int = 20

    init(repo: BrandRepositoryProtocol = FirestoreBrandRepository()) {
        self.repo = repo
    }

    var canLoadMore: Bool {
        // 마지막 스냅샷이 nil이면(첫 로드 전) 버튼을 숨김
        // 마지막 페이지 여부는 서버에서 알 수 없어서, 일단 "받아온 개수가 limit와 같으면 더 있을 수 있다"로 처리
        return last != nil && brands.count % limit == 0
    }

    func refresh() async {
        state = .loading
        last = nil

        do {
            let page = try await repo.fetchBrands(sort: .latest, limit: limit, after: nil)
            brands = page.items
            last = page.last
            state = .loaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func loadMore() async {
        guard !isPaging else { return }
        guard let last else { return }

        isPaging = true
        defer { isPaging = false }

        do {
            let page = try await repo.fetchBrands(sort: .latest, limit: limit, after: last)
            brands.append(contentsOf: page.items)
            self.last = page.last
        } catch {
            // 페이징 실패는 전체 화면 에러로 바꾸지 않고, 로그/표시만 간단히 처리
            state = .failed(error.localizedDescription)
        }
    }
}

// MARK: - Firebase Storage async 호환 (downloadURL completion -> async/await)

private extension StorageReference {
    /// Firebase 버전에 따라 downloadURL의 async 지원이 없을 수 있어, 안전하게 브릿지합니다.
    func downloadURLAsync() async throws -> URL {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            self.downloadURL { url, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let url else {
                    continuation.resume(throwing: NSError(domain: "LookbookHomeView", code: -10, userInfo: [
                        NSLocalizedDescriptionKey: "다운로드 URL을 받지 못했습니다."
                    ]))
                    return
                }
                continuation.resume(returning: url)
            }
        }
    }
}

#Preview {
    LookbookHomeView()
}
