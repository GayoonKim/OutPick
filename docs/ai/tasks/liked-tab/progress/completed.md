# Liked Tab Completed Progress

## 목적

좋아요 탭 작업의 완료 상세, 변경 파일, 검증 이력을 보존한다.

현재 상태는 `../progress.md`, phase 지도는 `../plan.md`, 결정 상세는 `../decisions/liked-tab.md`를 본다.

## 완료한 작업

좋아요 브랜드 1차 구현:

- 하단 탭에 `좋아요` 탭을 추가하고 `룩북` 탭과 `내 정보` 탭 사이에 배치했다.
- `LookbookCompositionRoot`, `LookbookContainer`, `LookbookCoordinator` 흐름으로 좋아요 탭 root를 조립했다.
- `LoadLikedBrandsUseCase`를 추가해 `brandStates` 페이지 조회 후 최신 `Brand` 문서를 다시 조회하도록 했다.
- `BrandUserStateRepositoryProtocol`과 `FirestoreBrandUserStateRepository`에 좋아요한 브랜드 목록 페이지 조회 계약/구현을 추가했다.
- 좋아요 탭에서 브랜드 상세로 이동할 때 `BrandAdminSessionStore` 환경 객체를 destination에 명시 주입해 환경 객체 누락 크래시를 방지했다.

시즌 좋아요 도메인/Repository/Functions/rules:

- `SeasonUserState`, `SeasonEngagementResult`, 관련 DTO/Repository protocol/Firestore 구현/Cloud Functions Repository를 추가했다.
- `setSeasonEngagement` callable Function을 추가했다.
- `users/{uid}/seasonStates` 조회와 rules 접근 흐름을 추가했다.
- materializer에서 시즌 문서에 필요한 좋아요 관련 필드가 채워지도록 연결했다.

시즌 상세 연결:

- `SeasonDetailViewModel`에 시즌 좋아요 상태 로드/토글 흐름을 연결했다.
- `SeasonDetailHeaderCardView`, `SeasonDetailView`에서 좋아요 UI와 액션을 연결했다.
- `SeasonDetailViewModelTests`를 추가했다.

좋아요 화면 일반화:

- `LikedBrandsView`/`LikedBrandsViewModel`을 `LikedView`/`LikedViewModel`로 리네이밍했다.
- `Views/LikedBrands` 폴더를 `Views/Liked` 구조로 이동했다.
- 브랜드 전용 카드와 시즌 카드 구성을 좋아요 화면 내부 섹션으로 연결했다.
- `LoadLikedSeasonsUseCase`를 추가해 좋아요한 시즌 상태 페이지를 읽고 시즌 문서를 합성한다.
- `LikedViewModelTests`, `LoadLikedSeasonsUseCaseTests`를 추가했다.

좋아요 포스트 목록 연결:

- `PostUserStateRepositoryProtocol`과 `FirestorePostUserStateRepository`에 좋아요한 포스트 목록 페이지 조회 계약/구현을 추가했다.
- `LoadLikedPostsUseCase`를 추가해 좋아요한 포스트 state 페이지와 최신 `LookbookPost` 문서를 합성한다.
- `LikedViewModel`에 `postSection`, 포스트 pagination, 포스트 store seeding, 포스트 invalidation 반영을 연결했다.
- `LikedView`에 좋아요 포스트 2열 grid를 연결하고, 셀 탭 시 기존 `PostDetailView`로 push한다.
- 브랜드/시즌/포스트 카드 모두 오른쪽 상단 메뉴에서 좋아요 취소를 제공한다.
- 좋아요 취소는 로컬 목록에서 먼저 제거하고, 서버 실패 시 기존 위치로 복구한다.
- `LookbookPostInteractionState`가 `LookbookPost?`를 보존하고 `allPostStateInvalidationStream()`을 제공하도록 보강해, 포스트 좋아요 후 pull-to-refresh 없이 좋아요 탭에 즉시 반영되도록 했다.

하네스 실전 검증 중 확인/완료:

- Phase 1 현재 상태 재확인을 완료했다.
- 실제 working tree 기준 좋아요 탭 리네이밍/섹션별 상태 분리 변경은 이미 clean 상태로 확인됐다.
- `LikedViewModel`은 이미 `brandSection`, `seasonSection` 독립 상태를 갖고 있으며 부분 실패 테스트도 존재한다.
- `AsyncLoadGate`를 추가하고 `LikedViewModel`의 `didLoadInitial`/`isLoadingInitial` 직접 상태를 대체했다.
- 테스트/QA 경계 기준을 공식 하네스와 로컬 test-design workflow에 반영했다.

배포:

- `npm run lint` 통과.
- `npm run build` 통과.
- Firestore rules는 첫 배포 시도에서 배포 완료됐다.
- Functions 전체 배포는 원격에만 남아 있는 `updateBrandLogoDetailPath(asia-northeast3)` 삭제 확인 때문에 non-interactive 모드에서 중단됐다.
- 운영 함수 삭제는 수행하지 않았다.
- 이후 변경 대상만 지정해 `setSeasonEngagement`, `createSeasonContentFromImportJobs`, `onSeasonImportParsed` 배포를 완료했다.

## 변경 파일 목록

2026-06-02 task 문서 재점검에서 실제 코드 기준 확인한 주요 변경/관련 파일:

```text
OutPick/Features/Lookbook/ViewModels/LikedViewModel.swift
OutPick/Features/Lookbook/Views/Liked/LikedView.swift
OutPick/Features/Lookbook/Views/Liked/LikedBrandCardView.swift
OutPick/Features/Lookbook/Views/Liked/LikedSeasonCardView.swift
OutPick/Features/Lookbook/Views/Liked/LikedPostCardView.swift
OutPick/Features/Lookbook/Domains/UseCases/LoadLikedBrandsUseCase.swift
OutPick/Features/Lookbook/Domains/UseCases/LoadLikedSeasonsUseCase.swift
OutPick/Features/Lookbook/Domains/UseCases/LoadLikedPostsUseCase.swift
OutPick/Features/Lookbook/Repositories/Protocols/BrandUserStateRepositoryProtocol.swift
OutPick/Features/Lookbook/Repositories/Protocols/SeasonUserStateRepositoryProtocol.swift
OutPick/Features/Lookbook/Repositories/Protocols/PostUserStateRepositoryProtocol.swift
OutPick/Features/Lookbook/Repositories/Implementations/FirestoreBrandUserStateRepository.swift
OutPick/Features/Lookbook/Repositories/Implementations/FirestoreSeasonUserStateRepository.swift
OutPick/Features/Lookbook/Repositories/Implementations/FirestorePostUserStateRepository.swift
OutPick/Features/Lookbook/Domains/Stores/LookbookInteractionStore.swift
OutPick/Features/Lookbook/Domains/Stores/PostInteractionManaging.swift
OutPickTests/LikedViewModelTests.swift
OutPickTests/LoadLikedPostsUseCaseTests.swift
OutPickTests/LookbookInteractionStoreTests.swift
```

주요 파일 의미:

- `OutPick/Features/Lookbook/ViewModels/AsyncLoadGate.swift`: 화면 private async load 중복 실행 방지 helper.
- `OutPick/Features/Lookbook/ViewModels/LikedViewModel.swift`: 브랜드/시즌/포스트 좋아요 목록 상태, 초기 로드, 재진입 refresh, pagination, invalidation 반영, 좋아요 취소 optimistic remove/restore를 관리한다.
- `OutPick/Features/Lookbook/Views/Liked/LikedView.swift`: `좋아요 브랜드`, `좋아요 시즌`, `좋아요 포스트` 섹션을 렌더링한다.
- `OutPick/Features/Lookbook/Views/Liked/LikedPostCardView.swift`: 좋아요 포스트 2열 grid 카드 UI.
- `OutPick/Features/Lookbook/Domains/UseCases/LoadLikedPostsUseCase.swift`: 좋아요한 포스트 state와 최신 post 문서 합성.
- `OutPickTests/LikedViewModelTests.swift`: 브랜드/시즌/포스트 목록, refresh, invalidation, 포스트 좋아요 즉시 반영 관련 테스트.
- `OutPickTests/LoadLikedSeasonsUseCaseTests.swift`: 좋아요한 시즌 상태와 시즌 문서 합성 테스트.
- `OutPickTests/LoadLikedPostsUseCaseTests.swift`: 좋아요한 포스트 상태와 포스트 문서 합성 테스트.

## 검증 이력

- 이전에 `xcodebuild test -scheme OutPick -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:OutPickTests/LikedViewModelTests -only-testing:OutPickTests/LoadLikedSeasonsUseCaseTests` 통과 이력이 있다.
- `git diff --check` 통과 이력이 있다.
- 2026-06-02 `xcodebuild test -scheme OutPick -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:OutPickTests/LikedViewModelTests` 통과.
- 2026-06-02 `xcodebuild test -scheme OutPick -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:OutPickTests/LookbookInteractionStoreTests -only-testing:OutPickTests/LikedViewModelTests` 통과.
- 2026-06-02 `xcodebuild test -scheme OutPick -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:OutPickTests/SeasonDetailViewModelTests -only-testing:OutPickTests/PostDetailScreenViewModelTests -only-testing:OutPickTests/LookbookDebugFailureInjectionStoreTests -only-testing:OutPickTests/LoadLikedPostsUseCaseTests` 통과.
- 2026-06-02 `git diff --check` 통과.
- 2026-06-02 `xcodebuild -scheme OutPick -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /private/tmp/OutPickDerivedData build` 통과.
- 2026-06-02 iPhone 17 시뮬레이터에 앱 설치/실행 성공. 로그인 화면 표시 확인.
- 2026-06-02 포스트 좋아요 로컬 반영 수정 후 `LookbookInteractionStoreTests`, `LikedViewModelTests`, `SeasonDetailViewModelTests`, `PostDetailScreenViewModelTests`, `LookbookDebugFailureInjectionStoreTests`, `LoadLikedPostsUseCaseTests` targeted test 통과.
- 2026-06-02 사용자가 포스트 좋아요 즉시 표시/좋아요 취소 즉시 제거 수동 QA 성공을 보고했다.

## 남은 QA

- 브랜드/시즌/포스트 pagination 끝까지 스크롤.
- 섹션별 빈 상태, 실패 상태, 로딩 상태 시각 QA.
