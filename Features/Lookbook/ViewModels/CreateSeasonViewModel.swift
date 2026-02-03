//
//  CreateSeasonViewModel.swift
//  OutPick
//
//  Created by 김가윤 on 1/9/26.
//

//
//  CreateSeasonViewModel.swift
//  OutPick
//
//  Created by 김가윤 on 1/9/26.
//

//
//  CreateSeasonViewModel.swift
//  OutPick
//
//  Created by 김가윤 on 1/9/26.
//

//
//  CreateSeasonViewModel.swift
//  OutPick
//
//  Created by 김가윤 on 1/9/26.
//

import Foundation

@MainActor
final class CreateSeasonViewModel: ObservableObject {

    // MARK: - 입력
    @Published var yearText: String = ""
    @Published var term: SeasonTerm = .fw
    @Published var descriptionText: String = ""
    @Published var coverImageData: Data? = nil

    @Published var query: String = ""

    // MARK: - 결과
    @Published private(set) var isSearching: Bool = false
    @Published private(set) var conceptSuggestions: [TagConcept] = []
    @Published private(set) var tagSuggestions: [Tag] = []

    // MARK: - 선택
    @Published private(set) var selectedConcepts: [TagConcept] = []
    @Published private(set) var selectedTags: [Tag] = []

    // MARK: - 저장 상태
    @Published private(set) var isSaving: Bool = false
    @Published var errorMessage: String? = nil

    // MARK: - 검색 제어
    // 디바운스 + 이전 검색 취소용 Task
    private var searchTask: Task<Void, Never>?

    // 추천 항목 탭으로 query를 프로그램적으로 변경할 때, onChange로 인한 재검색을 1회 억제합니다.
    private var shouldSkipNextSearch: Bool = false

    // 디바운스 시간(초)
    private let debounceNanoseconds: UInt64 = 250_000_000 // 0.25s

    // MARK: - Dependencies
    private let brandID: BrandID
    private let seasonRepository: SeasonRepositoryProtocol
    private let tagRepository: TagRepositoryProtocol
    private let tagAliasRepository: TagAliasRepositoryProtocol
    private let tagConceptRepository: TagConceptRepositoryProtocol

    init(
        brandID: BrandID,
        seasonRepository: SeasonRepositoryProtocol,
        tagRepository: TagRepositoryProtocol,
        tagAliasRepository: TagAliasRepositoryProtocol,
        tagConceptRepository: TagConceptRepositoryProtocol
    ) {
        self.brandID = brandID
        self.seasonRepository = seasonRepository
        self.tagRepository = tagRepository
        self.tagAliasRepository = tagAliasRepository
        self.tagConceptRepository = tagConceptRepository
    }

    // MARK: - UI 정리
    func dismissSearchUI() {
        // 진행 중 검색 중단 + 추천 목록/상태만 정리(검색창 텍스트는 유지)
        searchTask?.cancel()
        searchTask = nil
        isSearching = false
        conceptSuggestions = []
        tagSuggestions = []
    }

    /// - 타이핑: 디바운스(0.25s) 후 검색 실행
    /// - 새 입력: 이전 검색 Task 취소
    /// - 추천 탭으로 query 변경: 1회는 재검색 스킵
    func onQueryChanged() {
        // ✅ 추천 탭으로 query가 바뀐 경우: 이번 1회는 재검색 스킵
        if shouldSkipNextSearch {
            shouldSkipNextSearch = false
            return
        }

        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)

        // 입력이 비면 즉시 정리 + 진행 중 검색 취소
        guard !q.isEmpty else {
            dismissSearchUI()
            return
        }

        // ✅ 이전 검색 취소
        searchTask?.cancel()

        // “검색 중...”을 입력 즉시 표시(원하면 디바운스 이후로 옮길 수 있음)
        isSearching = true

        // ✅ 디바운스 + 검색
        searchTask = Task { [weak self] in
            guard let self else { return }

            do {
                try await Task.sleep(nanoseconds: debounceNanoseconds)
                try Task.checkCancellation()

                // 디바운스 후에도 query가 그대로인지 확인(스테일 결과 방지)
                let latest = await MainActor.run {
                    self.query.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                guard latest == q else { return }

                // 1) aliases 먼저 조회 → concept 추천
                let aliases = try await self.tagAliasRepository.searchAliases(prefix: q, limit: 10)
                try Task.checkCancellation()

                let conceptIDs = Array(Set(aliases.map { $0.conceptId }))
                let concepts = try await self.tagConceptRepository.fetchConcepts(conceptIDs: conceptIDs)
                try Task.checkCancellation()

                // 2) tags 검색(병렬)
                async let tagsTask: [Tag] = self.tagRepository.searchTags(prefix: q, limit: 10)
                let tags = try await tagsTask
                try Task.checkCancellation()

                // 반영 직전에 query가 그대로인지 재확인
                let latest2 = await MainActor.run {
                    self.query.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                guard latest2 == q else { return }

                await MainActor.run {
                    self.conceptSuggestions = concepts.sorted { $0.displayName < $1.displayName }
                    self.tagSuggestions = tags
                    self.isSearching = false
                }

            } catch is CancellationError {
                await MainActor.run {
                    self.isSearching = false
                }
            } catch {
                await MainActor.run {
                    self.conceptSuggestions = []
                    self.tagSuggestions = []
                    self.isSearching = false
                }
            }
        }
    }

    // MARK: - 선택/해제

    func addConcept(_ concept: TagConcept) {
        guard !selectedConcepts.contains(where: { $0.id == concept.id }) else { return }
        selectedConcepts.append(concept)

        // ✅ 추천 탭: 텍스트만 채우고 재검색은 1회 스킵
        dismissSearchUI()
        shouldSkipNextSearch = true
        query = concept.displayName
    }

    func removeConcept(conceptID: String) {
        selectedConcepts.removeAll(where: { $0.id == conceptID })
    }

    func addTag(_ tag: Tag) {
        guard !selectedTags.contains(where: { $0.id.value == tag.id.value }) else { return }
        selectedTags.append(tag)

        // ✅ 추천 탭: 텍스트만 채우고 재검색은 1회 스킵
        dismissSearchUI()
        shouldSkipNextSearch = true
        query = tag.name
    }

    func removeTag(tagID: TagID) {
        selectedTags.removeAll(where: { $0.id.value == tagID.value })
    }

    // MARK: - 저장
    func save() async -> Season? {
        guard let year = Int(yearText.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            errorMessage = "연도를 숫자로 입력해주세요."
            return nil
        }

        // 저장 중에는 검색 작업을 중단(불필요한 상태 변경 방지)
        dismissSearchUI()

        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            let conceptIDs = selectedConcepts.map { $0.id }
            let conceptIDsOrNil: [String]? = conceptIDs.isEmpty ? nil : conceptIDs

            let season = try await seasonRepository.createSeason(
                brandID: brandID,
                year: year,
                term: term,
                description: descriptionText,
                coverImageData: coverImageData,
                tagIDs: selectedTags.map { $0.id },
                tagConceptIDs: conceptIDsOrNil
            )
            return season
        } catch {
            errorMessage = "시즌 저장 실패: \(error.localizedDescription)"
            return nil
        }
    }
}

