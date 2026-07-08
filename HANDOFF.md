# OutPick Handoff

## 1. 최종 목표

- 현재 핵심 목표는 `lookbook-admin-soft-delete-lifecycle` 완료 이후 발견된 후속 QA/보정 사항을 작은 단위로 정리하고 마감하는 것이다.
- 2026-07-09 기준 후속 Phase A 삭제 요청 목록 표시명 보정, Phase B 관리자 브랜드 관리 화면 메뉴 리팩토링, Phase C `BrandDetailView` pull-to-refresh 추가까지 완료했다.
- Phase C의 핵심 성공 기준은 브랜드 상세 화면이 서버 최신 브랜드 정보, 로고 path/`updatedAt`, 브랜드 interaction state, 시즌 목록을 같은 refresh 흐름에서 다시 가져오고, 관리자 화면에서 돌아온 브랜드 수정도 동일한 ViewModel 상태로 반영하는 것이다.

## 2. 완료한 작업

### 코드 변경

- `BrandDetailViewModel`이 브랜드 상세 상태의 owner가 되도록 정리했다.
  - 초기 진입 `Brand`를 seed해 빠른 첫 표시를 유지한다.
  - `BrandRepositoryProtocol.fetchBrand(brandID:)`로 브랜드 단건 최신 정보를 가져온다.
  - `SeasonRepositoryProtocol.fetchAllSeasons(brandID:)`로 시즌 목록을 함께 갱신한다.
  - 최신 브랜드 기준으로 브랜드 interaction/user state를 다시 seed한다.
  - 브랜드가 사용자 비노출 상태가 되면 `brand = nil`, `seasons = []`, 접근 불가 메시지로 전환한다.
- `BrandDetailView`는 local `@State Brand` 대신 `viewModel.brand`를 표시하도록 바꿨다.
  - 관리자 화면 진입은 최신 `viewModel.brand`를 `initialBrand`로 전달한다.
  - 관리자 화면 수정 콜백은 `viewModel.applyUpdatedBrand(_:)`로 반영한다.
  - pull-to-refresh는 `refreshContents(brandID:)`를 호출하고, indicator가 너무 빨리 사라지지 않도록 최소 0.6초 표시한다.
- `LookbookContainer`에서 `BrandDetailViewModel` 생성 시 `brandRepository`를 주입한다.
- `BrandDetailViewModelTests`를 추가했다.
  - refresh가 브랜드 단건과 시즌 목록을 함께 갱신하는지 검증한다.
  - 브랜드 unavailable 에러 시 표시 상태를 비우고 안내 메시지를 남기는지 검증한다.
- 기존 테스트 helper의 `Brand`, `Season`, `LookbookPost` 생성자에 `deletionStatus: .active`를 보강해 현재 도메인 생성자와 맞췄다.

### 문서 변경

- `docs/ai/tasks/active.md`에서 Phase C 완료를 반영했다.
- `docs/ai/entrypoints/LOOKBOOK.md`에 브랜드 상세 refresh, 관리자 콜백, `BrandDetailViewModel` 최신화 책임을 반영했다.
- `docs/ai/tasks/lookbook-admin-soft-delete-lifecycle/progress.md`에 Phase C 완료와 검증 결과를 반영했다. 이 파일은 `.git/info/exclude`의 `docs/ai/tasks/` 규칙 때문에 커밋에는 포함되지 않았다.

### 검증

- `git diff --check` 통과.
- `xcodebuild -scheme OutPick -destination 'generic/platform=iOS Simulator' build` 통과.
- `xcodebuild -scheme OutPick -destination 'generic/platform=iOS Simulator' build-for-testing` 통과.
- 테스트 실행은 사용자 명시 요청이 없어 보류했다.

## 3. 아직 남은 작업

- Phase C 자체는 완료 상태다.
- 커밋 정리는 완료했다.
  - 커밋: `9e754fc 룩북 브랜드 상세 새로고침 정리`
  - Swift 앱 변경, 테스트 변경, 추적 중인 하네스 문서, `HANDOFF.md`를 같은 Phase C 보정 커밋으로 묶었다.
  - `docs/ai/tasks/lookbook-admin-soft-delete-lifecycle/progress.md`는 실제 파일은 갱신했지만 exclude 대상이라 커밋에는 포함하지 않았다.
- 제품/운영 논의로는 App Review Notes용 관리자 데모 계정/설명 준비 여부와 브랜드 룩북 콘텐츠 수집/표시 권리 범위 검토 여부가 남아 있다.

## 4. 수정한 파일 목록

- `OutPick/Features/Lookbook/ViewModels/BrandDetailViewModel.swift`
  - 브랜드 상세 최신화 상태 owner, 브랜드 단건 refresh, unavailable 처리, 관리자 수정 반영 API 추가.
- `OutPick/Features/Lookbook/Views/BrandDetail/BrandDetailView.swift`
  - `viewModel.brand` 기반 렌더링, refreshable 추가, 최소 0.6초 indicator 표시, unavailable view 추가.
- `OutPick/Features/Lookbook/LookbookContainer.swift`
  - `BrandDetailViewModel`에 `brandRepository` 주입.
- `OutPickTests/BrandDetailViewModelTests.swift`
  - Phase C refresh 동작 회귀 테스트 추가.
- `OutPickTests/AdminBrandManagementViewModelTests.swift`
- `OutPickTests/BrandEngagementInteractionUseCaseTests.swift`
- `OutPickTests/LikedViewModelTests.swift`
- `OutPickTests/LoadLikedPostsUseCaseTests.swift`
- `OutPickTests/LoadLikedSeasonsUseCaseTests.swift`
- `OutPickTests/LookbookChatShareUseCaseTests.swift`
- `OutPickTests/LookbookInteractionStoreTests.swift`
- `OutPickTests/PostDetailScreenViewModelTests.swift`
- `OutPickTests/SeasonDetailViewModelTests.swift`
  - 도메인 생성자 변경에 맞춰 테스트 fixture에 `deletionStatus: .active` 추가.
- `docs/ai/entrypoints/LOOKBOOK.md`
  - 브랜드 상세 화면/VM 진입점과 refresh 계약 갱신.
- `docs/ai/tasks/active.md`
  - 후속 Phase C 완료 상태 반영.
- `docs/ai/tasks/lookbook-admin-soft-delete-lifecycle/progress.md`
  - Phase C 완료와 검증 결과 반영. `.git/info/exclude` 대상이라 커밋에는 미포함.
- `HANDOFF.md`
  - 현재 Phase C 완료 상태 기준으로 7개 항목 최신화.

## 5. 중요한 아키텍처 결정

선택:
- 브랜드 상세 화면의 표시 상태는 `BrandDetailViewModel.brand`로 모으고, View의 local `@State Brand`는 제거했다.

이유:
- 기존에는 브랜드 정보, 로고 정보, 시즌 정보 최신화가 View local state, 관리자 콜백, 시즌 repository 호출로 나뉘어 있었다.
- refresh와 관리자 수정 반영을 같은 ViewModel 경계로 모으면 화면 표시 source가 하나가 되고, stale brand/로고 path 문제가 줄어든다.
- 기존 MVVM-C + Repository + DI 흐름을 유지하면서 `BrandRepositoryProtocol`만 ViewModel에 주입하므로 변경 범위가 작다.

트레이드오프:
- 브랜드 단건과 시즌 목록 refresh가 같은 화면 refresh에서 함께 수행되므로 네트워크 호출이 1개 늘어난다.
- 대신 사용자가 pull-to-refresh를 기대하는 정보 범위인 브랜드 본문, 로고, interaction, 시즌 목록이 한 번에 최신화된다.

보류한 대안:
- 브랜드 상세에 별도 brand detail use case를 새로 추가하는 방식은 현재 중복 추상화가 될 가능성이 있어 보류했다.
- 실시간 listener로 브랜드/시즌 변경을 즉시 반영하는 방식은 Phase C 범위를 넘어가고 listener lifecycle 검증 비용이 커서 보류했다.

재검토 조건:
- 브랜드 상세에서 refresh 외에도 여러 화면이 동일한 브랜드 최신화 orchestration을 재사용하게 되면 `LoadBrandDetailUseCase` 같은 use case 추출을 재검토한다.
- 관리자 수정 직후 여러 화면 간 동기화 요구가 커지면 홈/상세 공용 brand store 또는 invalidation bus를 재검토한다.

## 6. 다시 확인해야 할 불확실한 부분

- `docs/ai/tasks/lookbook-admin-soft-delete-lifecycle/progress.md`는 `.git/info/exclude`의 `docs/ai/tasks/` 규칙 때문에 `git status --short`에 표시되지 않는다. 실제 파일은 갱신했다.
- 테스트 실행은 하지 않았다. `build-for-testing`까지만 확인했다.
- App Review Notes용 관리자 데모 계정/설명 준비 필요 여부는 아직 결정되지 않았다.
- 브랜드 룩북 콘텐츠 수집/표시 권리 범위는 확실하지 않음. 출시/심사 전 사용자와 검토 필요.

## 7. 다음 턴에서 바로 실행해야 할 작업

1. `git status --short`로 working tree가 깨끗한지 확인한다.
2. 다음 작업이 새 기능/큰 수정이면 `docs/ai/tasks/active.md`와 관련 entrypoint 문서를 먼저 확인한다.
3. App Review Notes용 관리자 데모 계정/설명 준비 여부와 브랜드 룩북 콘텐츠 수집/표시 권리 범위 검토 필요 여부를 사용자와 논의한다.
