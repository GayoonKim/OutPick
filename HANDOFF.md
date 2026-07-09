# OutPick Handoff

## 1. 최종 목표

- 현재 핵심 목표는 `post-deletion-audit-thumbnail` 설계 확정과 후속 구현 준비다.
- 이 작업은 포스트 삭제 요청이 영구 삭제(`purged`)된 뒤에도 운영자가 어떤 포스트가 삭제되었는지 식별할 수 있도록, 포스트에 한해서 감사용 저해상도 thumbnail snapshot을 남기는 것이다.
- 브랜드/시즌 삭제 완료 목록은 이미지 UI를 표시하지 않는 현재 정책을 유지한다.
- 포스트 삭제 완료 목록만 audit thumbnail을 표시한다.
- 원본 포스트 이미지와 기존 Storage asset은 purge 시 계속 삭제한다.
- audit thumbnail은 원본 보존이 아니라 운영 이력 식별용 제한 snapshot으로 별도 Storage prefix에 저장한다.
- 신규 포스트 삭제 요청부터 적용하고, 이미 purge된 기존 포스트 요청은 이미지 복구 대상이 아니다.
- 구현 전 보존 기간, thumbnail 크기/포맷, Storage 접근 방식, cleanup 방식, thumbnail 생성 실패 시 요청 생성 실패 여부를 확정해야 한다.
- 직전 핵심 작업 `admin-request-list-retention-unification`은 구현 마감과 후속 운영 QA 단계다.
- 해당 작업은 총 관리자 브랜드 요청 목록과 총 관리자/브랜드 owner/admin 삭제 요청 목록의 진행 중/완료 요청 표시 정책을 14일 최근 처리 이력 기준으로 통일한다.
- 2026-07-09 사용자 결정으로 완료된 요청 기본 노출 기간은 14일로 통일한다. 삭제 lifecycle의 7일 복구 가능 기간과 관리자 운영 목록의 14일 최근 처리 이력 노출 기간은 분리한다.
- 2026-07-09 추가 사용자 결정으로 브랜드 요청 화면은 `새 요청`, `처리 중`, `보류`, `완료` segment로 가고, 14일 이전 처리 이력 조회도 이번 작업에 포함한다.
- 2026-07-09 추가 사용자 결정으로 삭제 요청 `완료` 목록은 영구 삭제가 끝난 `purged`만 표시한다. 최근 14일 완료 목록을 기본 표시하고, `이전 완료 기록 보기` 버튼 후 14일 이전 완료 기록을 같은 화면 아래에 추가 표시한다. 이전 완료 기록은 스크롤 prefetch로 추가 로드한다.
- 2026-07-09 추가 사용자 결정으로 브랜드 요청 `보류`/`완료`도 최근 14일 목록을 기본 표시하고, 이전 기록 보기 버튼 후 14일 이전 기록을 같은 화면 아래에 추가 표시한다. 이전 기록은 스크롤 prefetch로 추가 로드한다.
- 구현, 로컬 검증, Functions 운영 배포를 완료했다.

## 2. 완료한 작업

### 새 핵심 작업 설계

- `docs/ai/tasks/post-deletion-audit-thumbnail/` task 디렉터리를 생성했다.
- `design.md`에 요구사항, 구현 디테일, 제약 조건, 완료 기준, 구현 가능성, 기술 스택, 사용자 흐름, 화면/API/데이터/아키텍처 설계를 정리했다.
- `plan.md`에 Phase 1~6 구현 계획을 정리했다.
- `decisions.md`에 포스트 audit thumbnail 방향, 별도 Storage prefix, 기존 purge 완료 포스트 backfill 제외, 구현 전 논의 필요 사항을 기록했다.
- `qa-checklist.md`에 서버/iOS/권한/Storage 수동 QA와 테스트 설계를 정리했다.
- `progress.md`에 2026-07-09 설계 시작 상태를 기록했다.
- `docs/ai/tasks/active.md`에 다음 핵심 작업으로 등록했다.
- `docs/ai/ENTRYPOINTS.md`에 작업별 진입점을 추가했다.

### 이전 핵심 작업 설계

- `docs/ai/tasks/admin-request-list-retention-unification/` task 디렉터리를 생성했다.
- `design.md`에 요구사항, 구현 디테일, 제약 조건, 완료 기준, 구현 가능성, 기술 스택, 사용자 흐름, 화면/API/데이터/아키텍처 설계를 정리했다.
- `plan.md`에 Phase 1~5 구현 계획을 정리했다.
- `decisions.md`에 14일 노출 기간, 삭제 요청 `failed` 처리 위치, 브랜드 요청 segment 확정안, 14일 이전 이력 조회 포함 결정을 기록했다.
- `qa-checklist.md`에 서버/iOS/권한/수동 QA와 테스트 설계를 정리했다.
- `progress.md`에 2026-07-09 설계 시작 상태를 기록했다.
- `docs/ai/tasks/active.md`에 다음 핵심 작업으로 등록했다.
- `docs/ai/ENTRYPOINTS.md`에 작업별 진입점을 추가했다.

### 코드 변경

- `functions/src/index.ts`
  - `listBrandRequestGroups`에 `processedScope = recent | history`와 14일 기준 `updatedAt` 필터를 추가했다.
  - `listLookbookDeletionRequests`에 `statusGroup = active | processed`, `processedScope = recent | history`를 추가했다.
  - `active` group은 `active/failed`, `processed` group은 영구 삭제가 끝난 `purged`만 조회한다.
  - 삭제 요청 응답 제목은 `targetDisplayName` fallback보다 `brandName`/`seasonTitle`/`postCaption` snapshot을 우선하도록 정규화한다.
- iOS 관리자 요청 목록:
  - 브랜드 요청 관리자 화면에 `완료` segment를 추가했다.
  - 브랜드 요청 `보류`/`완료`는 최근 14일 목록을 기본 표시하고, 이전 기록 보기 버튼 후 14일 이전 기록을 아래에 추가 표시한다.
  - 브랜드 요청 14일 이전 기록은 스크롤 prefetch로 다음 page를 불러온다.
  - 삭제 요청 목록에 `처리 중` / `완료` status group picker를 추가했다.
  - 삭제 요청 `완료`는 최근 14일 목록을 기본 표시하고, `이전 완료 기록 보기` 버튼 후 14일 이전 완료 기록을 아래에 추가 표시한다.
  - 삭제 요청 14일 이전 완료 기록은 스크롤 prefetch로 다음 page를 불러온다.
  - 삭제 요청 완료 목록 제목은 삭제 완료 후 원본 브랜드/시즌/포스트 문서가 없어도 요청 projection의 `brandName`/`seasonTitle`/`postCaption` snapshot을 fallback보다 우선 표시한다.
  - `postCaption`이 없는 포스트는 서버 snapshot의 `targetDisplayName = "포스트"`를 표시하고, `"삭제된 포스트"` fallback은 snapshot이 모두 없을 때만 사용한다.
  - `purged` 완료 목록은 이미지 UI를 표시하지 않는다. 완료 목록 표시를 위해 삭제된 원본 이미지나 별도 이미지 snapshot 파일을 보존하지 않는다.
  - 완료 브랜드 요청 row와 완료/실패 삭제 요청 row는 mutation action을 노출하지 않는다.
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

- `docs/ai/tasks/admin-request-list-retention-unification/design.md`
- `docs/ai/tasks/admin-request-list-retention-unification/plan.md`
- `docs/ai/tasks/admin-request-list-retention-unification/decisions.md`
- `docs/ai/tasks/admin-request-list-retention-unification/qa-checklist.md`
- `docs/ai/tasks/admin-request-list-retention-unification/progress.md`
- `docs/ai/ENTRYPOINTS.md`에 새 작업 진입점을 추가했다.
- `docs/ai/entrypoints/LOOKBOOK.md`, `docs/ai/entrypoints/FIREBASE.md`, `docs/ai/DATA_SCHEMA.md`에 구현된 query scope와 화면 구조를 반영했다.
- `docs/ai/tasks/active.md`에 새 작업을 현재 핵심 작업으로 추가했다.
- `docs/ai/tasks/active.md`에서 Phase C 완료를 반영했다.
- `docs/ai/entrypoints/LOOKBOOK.md`에 브랜드 상세 refresh, 관리자 콜백, `BrandDetailViewModel` 최신화 책임을 반영했다.
- `docs/ai/tasks/lookbook-admin-soft-delete-lifecycle/progress.md`에 Phase C 완료와 검증 결과를 반영했다. 이 파일은 `.git/info/exclude`의 `docs/ai/tasks/` 규칙 때문에 커밋에는 포함되지 않았다.

### 검증

- 새 작업 구현 후 Functions lint/build와 iOS build를 실행했다.
- `functions` `npm run lint` 통과.
- `functions` `npm run build` 통과.
- `xcodebuild -scheme OutPick -destination 'generic/platform=iOS Simulator' build` 통과.
- `firebase deploy --only functions --project outpick-664ae` 완료.
- iOS build 중 기존 Chat Swift 6 actor isolation 경고와 linker search path 경고가 있었으나 빌드는 성공했다.
- `git status --short` 확인 당시 설계 시작 전 working tree는 깨끗했다.
- `git diff --check` 통과.
- `xcodebuild -scheme OutPick -destination 'generic/platform=iOS Simulator' build` 통과.
- `xcodebuild -scheme OutPick -destination 'generic/platform=iOS Simulator' build-for-testing` 통과.
- 테스트 실행은 사용자 명시 요청이 없어 보류했다.

## 3. 아직 남은 작업

- 새 핵심 작업 `admin-request-list-retention-unification`은 구현/로컬 검증/Functions 운영 배포 완료 상태다.
- 새 핵심 작업 `post-deletion-audit-thumbnail`은 설계 문서화 완료, 구현 전 논의 대기 상태다.
- `post-deletion-audit-thumbnail` 구현 전 결정 필요 항목은 audit thumbnail 보존 기간, thumbnail 크기/포맷, Storage 접근 방식, cleanup 방식, thumbnail 생성 실패 시 요청 생성 실패 여부다.
- 남은 작업은 총 관리자/브랜드 owner/admin 수동 QA다.
- OUTSTANDING QA brand `qAVnr5qWjaFVc07Tq4HM`는 2026-07-09 수동 scheduler 실행으로 영구 삭제 완료했다. 삭제 요청 완료 표시 제목 계산 결과는 브랜드 `아웃스탠딩`, 시즌 `OUTSTANDING Vintage Reissue Collection Manufactured by TART OPTICAL CO`, 포스트 `포스트`다.
- 재시도 UX/API는 이번 핵심 작업 완료 후 별도 논의로 분리했다.
- Phase C 자체는 완료 상태다.
- 커밋 정리는 완료했다.
  - 커밋: `9e754fc 룩북 브랜드 상세 새로고침 정리`
  - Swift 앱 변경, 테스트 변경, 추적 중인 하네스 문서, `HANDOFF.md`를 같은 Phase C 보정 커밋으로 묶었다.
  - `docs/ai/tasks/lookbook-admin-soft-delete-lifecycle/progress.md`는 실제 파일은 갱신했지만 exclude 대상이라 커밋에는 포함하지 않았다.
- 제품/운영 논의로는 App Review Notes용 관리자 데모 계정/설명 준비 여부와 브랜드 룩북 콘텐츠 수집/표시 권리 범위 검토 여부가 남아 있다.

## 4. 수정한 파일 목록

- `docs/ai/tasks/post-deletion-audit-thumbnail/design.md`
  - 포스트 audit thumbnail 설계.
- `docs/ai/tasks/post-deletion-audit-thumbnail/plan.md`
  - Phase별 목표, 변경 범위, 완료 기준, 검증 방법.
- `docs/ai/tasks/post-deletion-audit-thumbnail/decisions.md`
  - 포스트만 audit thumbnail을 남기는 방향과 구현 전 결정사항.
- `docs/ai/tasks/post-deletion-audit-thumbnail/qa-checklist.md`
  - 서버/iOS/Storage 권한 QA와 테스트 설계.
- `docs/ai/tasks/post-deletion-audit-thumbnail/progress.md`
  - 설계 시작 상태.
- `docs/ai/tasks/admin-request-list-retention-unification/design.md`
  - 관리자 요청 목록 14일 표시 정책 통일 설계.
- `docs/ai/tasks/admin-request-list-retention-unification/plan.md`
  - Phase별 목표, 변경 범위, 완료 기준, 검증 방법.
- `docs/ai/tasks/admin-request-list-retention-unification/decisions.md`
  - 14일 노출 기간과 삭제 요청 status grouping 결정.
- `docs/ai/tasks/admin-request-list-retention-unification/qa-checklist.md`
  - 서버/iOS/권한/수동 QA와 테스트 설계.
- `docs/ai/tasks/admin-request-list-retention-unification/progress.md`
  - 설계 시작, 구현 완료, 검증 결과.
- `functions/src/index.ts`
  - 관리자 요청 목록 recent/history query scope 추가.
- `OutPick/DB/Firebase/CloudFunctions/CloudFunctionsManager.swift`
  - 브랜드 요청 group과 삭제 요청 목록 callable 파라미터에 processed scope/status group 추가.
- `OutPick/Features/Lookbook/Domains/Entities/BrandRequest.swift`
  - `ProcessedRequestScope`, `BrandRequestAdminStage.isProcessed` 추가.
- `OutPick/Features/Lookbook/Domains/Entities/LookbookDeletionRequest.swift`
  - `LookbookDeletionRequestStatusGroup` 추가.
- `OutPick/Features/Lookbook/Domains/UseCases/ListBrandRequestGroupsUseCase.swift`
- `OutPick/Features/Lookbook/Repositories/Protocols/BrandRequestRepositoryProtocol.swift`
- `OutPick/Features/Lookbook/Repositories/Implementations/CloudFunctionsBrandRequestRepository.swift`
- `OutPick/Features/Lookbook/Repositories/Protocols/LookbookDeletionRepositoryProtocol.swift`
- `OutPick/Features/Lookbook/Repositories/Implementations/CloudFunctionsLookbookDeletionRepository.swift`
  - scope/status group 파라미터 전달.
- `OutPick/Features/Lookbook/ViewModels/AdminBrandRequestGroupsViewModel.swift`
- `OutPick/Features/Lookbook/Views/Admin/AdminBrandRequestGroupsView.swift`
  - 브랜드 요청 `완료` segment와 이전 기록 버튼/스크롤 prefetch 추가.
- `OutPick/Features/Lookbook/ViewModels/AdminLookbookDeletionManagementViewModel.swift`
- `OutPick/Features/Lookbook/Views/Admin/AdminLookbookDeletionManagementView.swift`
  - 삭제 요청 status group UI와 이전 완료 기록 버튼/스크롤 prefetch 추가.
- `docs/ai/entrypoints/LOOKBOOK.md`
- `docs/ai/entrypoints/FIREBASE.md`
- `docs/ai/DATA_SCHEMA.md`
  - 관리자 요청 목록 14일/이전 scope 계약 반영.
- `docs/ai/ENTRYPOINTS.md`
  - 새 작업 진입점 추가.
- `docs/ai/tasks/active.md`
  - 새 핵심 작업 등록.
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
- 포스트 삭제 완료 목록에는 audit thumbnail을 표시한다.
- 브랜드/시즌 삭제 완료 목록에는 이미지 UI를 표시하지 않는다.
- 원본 포스트 이미지는 purge 시 계속 삭제하고, audit thumbnail은 별도 Storage prefix에 둔다.

이유:
- 포스트는 caption이 없을 수 있고 이미지가 사실상 식별자라, 완료 목록에서 텍스트만으로 어떤 포스트였는지 알기 어렵다.
- 원본 이미지를 보존하는 것은 영구 삭제 정책과 충돌할 수 있으므로, 운영 이력 식별용 저해상도 snapshot으로 제한한다.

트레이드오프:
- 삭제된 콘텐츠의 파생 이미지를 일정 기간 보존하므로 개인정보/콘텐츠 삭제 정책상 보존 기간과 접근 권한을 명확히 해야 한다.
- 서버에서 이미지 리사이즈와 Storage 저장을 처리해야 하므로 Functions 의존성과 실패 처리 정책이 추가된다.

보류한 대안:
- 포스트도 이미지 없이 텍스트 snapshot만 표시하는 방식은 caption 없는 포스트 식별성이 낮아 보류했다.
- 원본 이미지를 보존하는 방식은 삭제 완료 정책과 충돌 가능성이 커서 보류했다.

재검토 조건:
- audit thumbnail 보존도 정책상 부담이 크다고 판단되는 경우.
- 포스트에 안정적인 텍스트 식별자나 permalink가 생겨 이미지 없이도 충분히 식별 가능한 경우.

선택:
- 관리자 요청 목록의 최근 처리 이력 기본 노출 기간은 브랜드 요청과 삭제 요청 모두 14일로 통일한다.
- 브랜드 요청 화면은 `새 요청`, `처리 중`, `보류`, `완료` segment로 간다.
- 14일 이전 처리 이력 조회도 이번 작업 범위에 포함한다.
- 재시도 UX/API는 후속 논의로 분리한다.

이유:
- 기존 브랜드 요청 하네스가 이미 `completed`/`rejected` 처리 이력을 최근 14일 기준으로 기록하고 있다.
- 삭제 lifecycle의 7일 복구 가능 기간은 안전장치이고, 관리자 목록의 14일 노출 기간은 운영 UX 기준이다.
- 두 기간을 분리하면 purge 이후에도 최근 영구 삭제 완료 이력을 확인할 수 있다. 복구/취소 이력은 완료 목록에서 제외한다.

트레이드오프:
- 완료 목록에서 7일 이상 지난 purge 이력도 보이므로 삭제 복구 가능 여부와 혼동될 수 있다.
- UI 문구와 status badge로 `복구 가능 기간`과 `최근 처리 이력`을 구분해야 한다.

보류한 대안:
- 삭제 요청 완료 목록만 7일로 제한하는 방식은 브랜드 요청 정책과 맞지 않고, 삭제 안전장치와 운영 목록 UX를 섞게 되어 보류했다.

재검토 조건:
- 운영 목록 데이터가 많아져 14일 기본 조회나 이전 이력 조회가 느려지면 날짜 범위 필터나 검색을 추가한다.
- 운영 smoke QA에서 Firestore index 요구가 나오면 `firestore.indexes.json`을 보강한다.

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

- `post-deletion-audit-thumbnail`의 보존 기간, thumbnail 크기/포맷, Storage 접근 방식, cleanup 방식, thumbnail 생성 실패 시 요청 생성 실패 여부는 구현 전 사용자 확정이 필요하다.
- Firestore가 삭제 요청 `status in [...]`와 `brandID`/`targetType` 조합에 요구할 composite index는 dry-run 또는 실제 query로 재확인해야 한다. 확실하지 않음.
- `updatedAt` 누락 legacy 문서가 있는지는 재확인 필요.
- `docs/ai/tasks/lookbook-admin-soft-delete-lifecycle/progress.md`는 `.git/info/exclude`의 `docs/ai/tasks/` 규칙 때문에 `git status --short`에 표시되지 않는다. 실제 파일은 갱신했다.
- 테스트 실행은 하지 않았다. `build-for-testing`까지만 확인했다.
- App Review Notes용 관리자 데모 계정/설명 준비 필요 여부는 아직 결정되지 않았다.
- 브랜드 룩북 콘텐츠 수집/표시 권리 범위는 확실하지 않음. 출시/심사 전 사용자와 검토 필요.

## 7. 다음 턴에서 바로 실행해야 할 작업

1. `git status --short`로 현재 변경 범위를 확인한다.
2. `docs/ai/tasks/post-deletion-audit-thumbnail/design.md`와 `decisions.md`를 기준으로 구현 전 결정사항을 사용자와 확정한다.
3. 결정 필요 항목: 보존 기간, thumbnail 크기/포맷, Storage 접근 방식, cleanup 방식, thumbnail 생성 실패 시 요청 생성 실패 여부.
4. 총 관리자/브랜드 owner/admin 수동 QA에서 기존 관리자 요청 목록 보류/완료, 삭제 요청 처리 중/완료, 이전 기록 prefetch도 확인한다.
