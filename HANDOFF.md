# OutPick Handoff

## 1. 최종 목표

- `lookbook-deletion-request-list-simplification`은 2026-07-13 Phase 2~6 구현, Functions 운영 배포, 사용자 수동 QA를 완료하고 마감했다.
- `lookbook-deletion-purge-drain`은 2026-07-13 Phase 1~3 설계, 구현, 운영 배포, destructive smoke QA를 완료했다.
- 목표는 매일 04:00 purge 스케줄은 유지하면서 한 실행의 전체 20개 고정 상한을 제거하고, 시간 예산 안에서 eligible 요청을 페이지 반복 조회와 bounded concurrency로 계속 소진하는 것이다.
- 같은 브랜드 purge는 기존 15분 lease로 직렬화하고 서로 다른 브랜드만 제한적으로 병렬 처리한다.
- 페이지 크기 20개, 동시 브랜드 3개, 실행 후 7분 신규 claim 중단으로 확정·구현했다.
- active/failed 독립 cursor, failed `retryAfter <= now` query, `brand -> season -> post` pass, 브랜드별 순차 queue를 구현했다.
- 신규 Firestore index READY 확인 후 Functions 운영 배포를 완료했고 스케줄은 `Asia/Seoul` 매일 04:00, timeout 540초, memory 1024Mi를 유지한다.
- QA 요청 31개로 20개 초과 pagination, 시즌 cascade, eligible/future failed, Storage 삭제를 확인했고 별도 유효 manual lease fixture로 scheduled skip을 확인했다. 모든 QA 잔여물은 정리했다.
- 장기 결정과 재검토 조건은 `docs/ai/adr/ADR-018-룩북-영구-삭제는-일일-bounded-drain과-브랜드-lease로-처리한다.md`에 기록했다.
- 총 관리자와 브랜드 owner/admin 삭제 요청 화면에는 복구 가능한 `active`와 운영 대응이 필요한 `failed`만 표시한다.
- 총 관리자 전역 목록의 기존 브랜드별 접기/펼치기 구조와 복구 가능 포스트의 원본 썸네일 표시는 유지한다.
- 처리 중/완료 picker, `purged` 완료 목록, 최근 14일/이전 완료 기록 UI와 history pagination을 제거한다.
- 삭제 요청 전용 `status/statusGroup/processedScope/recentProcessedDays` API 입력도 Functions와 iOS에서 함께 제거한다.
- 앱은 아직 배포되지 않아 구버전 API 호환 분기를 유지하지 않는다.
- `purged` projection과 `lookbookDeletionAuditLogs`는 서버 운영 이력으로 유지한다.
- purge 이후 별도 audit thumbnail은 만들지 않으며 기존 `post-deletion-audit-thumbnail` 작업은 폐기했다.
- 브랜드 등록 요청의 `새 요청/처리 중/보류/완료` UI와 이전 이력 조회는 변경하지 않는다.
- 처리 대상 pagination은 전체 목록 하단 sentinel scroll prefetch로 구현하고 서버는 `limit + 1` query로 정확한 `nextCursor`를 반환한다.
- 총 관리자는 failed row에서 manual retry를 요청할 수 있고, callable이 token을 기록하면 Firestore trigger가 background purge를 즉시 시작한다.
- scheduled/manual purge는 공통 15분 lease로 동시 실행을 막고 scheduler fallback을 유지한다.
- 브랜드 owner/admin 실행 중 문구는 `삭제를 다시 처리하고 있습니다.`, 최종 실패 문구는 `관리자 확인이 필요합니다.`로 한다.
- 2026-07-12 Phase 2에서 `listLookbookDeletionRequests`의 완료/history 입력과 query를 제거하고 `active/failed` 고정 query 및 `limit + 1` 기반 정확한 cursor를 구현했다.
- Phase 2 목록 계약은 2026-07-13 Phase 3 함수들과 함께 운영 배포했다.
- 2026-07-12 Phase 3에서 총 관리자 failed retry callable, 새 queued token Firestore trigger, 브랜드 단위 scheduled/manual 공통 15분 lease를 구현했다.
- request와 lease token이 모두 실행 token과 일치할 때만 finalize하며 trigger 실패/timeout은 scheduler가 fallback한다.
- Phase 3 lease helper Node 테스트 5개, Functions lint/build가 통과했다.
- 2026-07-13 Phase 4에서 iOS 삭제 요청 status group/processed scope와 완료/history 상태를 제거하고 active/failed cursor pagination, requestID 중복 제거, retry metadata/총 관리자 mutation 경계를 구현했다.
- status group 타입 제거와 빌드 가능성을 맞추기 위해 picker 및 완료/history UI 제거도 Phase 4에 포함했다.
- Phase 4 generic simulator build, build-for-testing, ViewModel 선택 테스트 4개가 통과했다.
- 2026-07-13 Phase 5에서 목록 하단 공통 sentinel, 총 관리자 failed retry action/실행 상태, 브랜드 owner/admin 실행 중/최종 실패 문구를 화면에 연결했다.
- retry 표시 상태 조합 테스트를 추가해 Phase 5 기준 선택 테스트 5개와 generic simulator build가 통과했다.
- 2026-07-13 Phase 6에서 Functions 테스트/lint/build, iOS 선택 테스트 5개, generic simulator build를 재검증하고 Functions 전체 운영 배포를 완료했다.
- 배포 후 새 callable/trigger와 목록/scheduler 함수 등록을 확인했고, 비로그인 목록 호출이 `UNAUTHENTICATED`로 거부되는 것도 확인했다.
- 사용자가 총 관리자와 브랜드 owner/admin 삭제 요청 목록 화면을 직접 확인했다. 실제 lease 경쟁/scheduler fallback destructive 재현은 후속 운영 회귀 QA로 분리했다.
- 직전 핵심 작업 `admin-request-list-retention-unification`은 구현 마감과 후속 운영 QA 단계다.
- 해당 작업은 총 관리자 브랜드 요청 목록과 총 관리자/브랜드 owner/admin 삭제 요청 목록의 진행 중/완료 요청 표시 정책을 14일 최근 처리 이력 기준으로 통일한다.
- 2026-07-09 사용자 결정으로 완료된 요청 기본 노출 기간은 14일로 통일한다. 삭제 lifecycle의 7일 복구 가능 기간과 관리자 운영 목록의 14일 최근 처리 이력 노출 기간은 분리한다.
- 2026-07-09 추가 사용자 결정으로 브랜드 요청 화면은 `새 요청`, `처리 중`, `보류`, `완료` segment로 가고, 14일 이전 처리 이력 조회도 이번 작업에 포함한다.
- 2026-07-09 추가 사용자 결정으로 삭제 요청 `완료` 목록은 영구 삭제가 끝난 `purged`만 표시한다. 최근 14일 완료 목록을 기본 표시하고, `이전 완료 기록 보기` 버튼 후 14일 이전 완료 기록을 같은 화면 아래에 추가 표시한다. 이전 완료 기록은 스크롤 prefetch로 추가 로드한다.
- 2026-07-09 추가 사용자 결정으로 브랜드 요청 `보류`/`완료`도 최근 14일 목록을 기본 표시하고, 이전 기록 보기 버튼 후 14일 이전 기록을 같은 화면 아래에 추가 표시한다. 이전 기록은 스크롤 prefetch로 추가 로드한다.
- 구현, 로컬 검증, Functions 운영 배포를 완료했다.

## 2. 완료한 작업

### `lookbook-deletion-purge-drain` Phase 1~3 완료

- 2026-07-13 `design.md`, `decisions.md`, `plan.md`, `progress.md`, `qa-checklist.md` 기준 Phase 1 정책을 확정했다.
- `functions/src/lookbookDeletionPurgeDrain.ts`와 테스트를 추가하고 `functions/src/index.ts`, `functions/package.json`, `firestore.indexes.json`을 변경했다.
- Functions 테스트 11개, lint, build, Firestore index dry-run이 통과했다.
- 신규 index 두 개가 READY인 것을 확인한 뒤 Firestore indexes와 Functions 운영 배포를 완료했다.
- QA run `qa-purge-drain-20260713T075809Z`에서 브랜드 5개, 요청 31개, Storage marker 31개로 통합 검증했다.
- 1차 실행은 `pageCount 4 / loaded 25 / success 25 / failure 0`, 2차 future retry 실행은 `loaded 1 / success 1`이었다.
- 시즌 purge가 하위 포스트 요청 5개를 `purged`로 닫았고 최종 요청 31개, purge 감사 26개, Storage 삭제를 확인했다.
- 유효 manual source lease 실행은 `skipped 1 / hasRemainingCandidates true`, lease 제거 후 실행은 `success 1`이었다.
- QA 브랜드/request/audit/lease/Storage 잔여물과 전역 eligible 요청은 최종 0건이었다.

### 입력 화면 키보드 dismiss UX 보강

- 2026-07-10 ad hoc UX 보강으로 입력 화면에서 키보드가 올라온 상태에 입력 영역 외부를 탭하면 키보드가 내려가도록 처리했다.
- 공통 helper `OutPick/Infra/Utility/Support/KeyboardDismissSupport.swift`를 추가했다.
  - UIKit 화면은 `installKeyboardDismissTapGesture()`를 적용한다.
  - SwiftUI 화면은 `outpickDismissKeyboardOnTap()` modifier를 적용한다.
  - `UITextField`/`UITextView` 내부 탭은 무시해 커서 이동과 입력 포커스를 방해하지 않는다.
  - `cancelsTouchesInView = false`와 simultaneous gesture 허용으로 버튼/셀/스크롤 탭 흐름을 유지한다.
- UIKit 적용 화면:
  - 채팅방, 채팅방 생성, 채팅방 편집, 채팅방 검색, 프로필 2단계.
- SwiftUI 적용 화면:
  - 룩북 홈 검색, 브랜드 요청, 브랜드 생성, 시즌 생성, 시즌 URL 등록, 브랜드 관리, 브랜드 요청 보류 메모, 삭제 관리, 댓글/답글 입력, 댓글 신고 상세 입력.
- 사용자 수동 확인으로 의도한 대로 동작함을 확인했다.
- 검증:
  - `git diff --check` 통과.
  - `xcodebuild -scheme OutPick -destination 'generic/platform=iOS Simulator' build` 통과.
  - 기존 linker search path 경고는 남아 있으나 빌드는 성공했다.

### 새 핵심 작업 설계

- `docs/ai/tasks/lookbook-deletion-request-list-simplification/` task 디렉터리를 생성했다.
- `design.md`에 요구사항, 구현 디테일, 제약 조건, 완료 기준, 구현 가능성, 기술 스택, 사용자 흐름, 화면/API/데이터/아키텍처 설계를 정리했다.
- `plan.md`에 Phase 1~5 구현 계획을 정리했다.
- `decisions.md`에 `active/failed` 전용 목록, 브랜드 grouping 유지, scroll prefetch, 삭제 요청 processed API 제거, 즉시 background retry, lease, 감사 기록 유지 결정을 기록했다.
- `qa-checklist.md`에 Functions/iOS/권한/이미지 식별 수동 QA와 테스트 설계를 정리했다.
- `progress.md`에 2026-07-12 설계 시작 상태를 기록했다.
- 폐기된 `docs/ai/tasks/post-deletion-audit-thumbnail/` task 문서와 하네스 참조를 제거했다.
- `docs/ai/tasks/active.md`, `docs/ai/ENTRYPOINTS.md`, 관련 entrypoint 문서를 새 핵심 작업 기준으로 갱신했다.

### `lookbook-deletion-request-list-simplification` Phase 2

- `functions/src/index.ts`의 `listLookbookDeletionRequests`를 `active/failed` 전용 계약으로 단순화했다.
- 삭제 요청 전용 `status`, `statusGroup`, `processedScope`, `recentProcessedDays` 파싱과 완료 query를 제거했다.
- 삭제 요청 전용 status/status group type과 parser helper를 제거했다.
- `targetType`, `brandID`, `limit`, cursor와 권한 검증은 유지했다.
- `limit + 1` query로 실제 다음 page가 있을 때만 `nextCursor`를 반환한다.
- 기존 `firestore.indexes.json`은 active/failed 목록과 purge에도 필요하므로 변경하지 않았다.
- 관련 FIREBASE/LOOKBOOK/DATA_SCHEMA/task 문서를 갱신했다.
- `functions` `npm run lint`, `npm run build`가 통과했다.
- Functions 운영 배포는 수행하지 않았다.

### `lookbook-deletion-request-list-simplification` Phase 3

- 총 관리자 전용 `retryFailedLookbookDeletionPurge` callable을 추가했다.
- `onLookbookDeletionManualRetryQueued` Firestore trigger가 새 queued token을 감지해 background purge를 즉시 시작한다.
- scheduled/manual purge 모두 `lookbookDeletionPurgeLeases/{brandID}` 브랜드 단위 15분 lease를 claim한다.
- 같은 브랜드의 브랜드/시즌/포스트 purge를 직렬화해 계층 Storage prefix 충돌을 막는다.
- request와 lease token이 모두 실행 token과 같을 때만 성공/실패를 finalize한다.
- manual trigger 실패/timeout 시 `autoRetryEligible`, `retryAfter` 기반 scheduler fallback을 유지한다.
- 목록 summary에 retry metadata와 서버 계산 `purgeInProgress`를 추가했다.
- raw lease token은 iOS 응답에 포함하지 않고 purge 오류 상세는 총 관리자에게만 정제해 반환한다.
- `functions/src/lookbookDeletionPurgeLease.ts`와 Node test를 추가했다.
- `npm test` 5개, `npm run lint`, `npm run build`가 통과했다.
- Functions 운영 배포와 destructive smoke QA는 수행하지 않았다.

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

- `lookbook-deletion-purge-drain` Phase 1~3은 완료했다.
- 합성 QA로 실제 대규모 브랜드의 최악 처리 시간과 7분 cutoff 종료는 재현하지 않았으므로 운영 로그에서 관찰한다.
- 키보드 dismiss UX 보강은 구현/빌드 검증/사용자 수동 QA 완료 상태다.
- 새 핵심 작업 `admin-request-list-retention-unification`은 구현/로컬 검증/Functions 운영 배포 완료 상태다.
- 새 핵심 작업 `lookbook-deletion-request-list-simplification`은 설계 문서화와 Phase 2~3 Functions 구현/로컬 검증 완료 상태다.
- iOS에서는 status group/history 상태와 완료 UI를 제거하되 총 관리자 브랜드 grouping, scroll prefetch, 포스트 이미지, 복구 action, failed retry 상태/action을 구현해야 한다.
- 완료 projection/감사 로그 보존 기간은 후속 논의이며 이번 구현 blocker는 아니다.
- 남은 작업은 총 관리자/브랜드 owner/admin 수동 QA다.
- OUTSTANDING QA brand `qAVnr5qWjaFVc07Tq4HM`는 2026-07-09 수동 scheduler 실행으로 영구 삭제 완료했다. 삭제 요청 완료 표시 제목 계산 결과는 브랜드 `아웃스탠딩`, 시즌 `OUTSTANDING Vintage Reissue Collection Manufactured by TART OPTICAL CO`, 포스트 `포스트`다.
- 삭제 요청 failed 재시도 UX/API는 현재 핵심 작업 Phase 3~5에 편입했다. 브랜드 요청 재시도 정책은 별도 논의다.
- Phase C 자체는 완료 상태다.
- 커밋 정리는 완료했다.
  - 커밋: `9e754fc 룩북 브랜드 상세 새로고침 정리`
  - Swift 앱 변경, 테스트 변경, 추적 중인 하네스 문서, `HANDOFF.md`를 같은 Phase C 보정 커밋으로 묶었다.
  - `docs/ai/tasks/lookbook-admin-soft-delete-lifecycle/progress.md`는 실제 파일은 갱신했지만 exclude 대상이라 커밋에는 포함하지 않았다.
- 제품/운영 논의로는 App Review Notes용 관리자 데모 계정/설명 준비 여부와 브랜드 룩북 콘텐츠 수집/표시 권리 범위 검토 여부가 남아 있다.

## 4. 수정한 파일 목록

- `docs/ai/tasks/lookbook-deletion-purge-drain/design.md`
  - 일일 스케줄 유지와 전체 20개 상한 제거를 전제로 한 bounded drain 설계.
- `docs/ai/tasks/lookbook-deletion-purge-drain/decisions.md`
  - 확정 결정과 구현 전 수치 확정 항목 구분.
- `docs/ai/tasks/lookbook-deletion-purge-drain/plan.md`
  - 정책 수치 확정, Functions 구현, 통합 QA/배포의 Phase 1~3 계획.
- `docs/ai/tasks/lookbook-deletion-purge-drain/progress.md`
  - 핵심 작업 등록 상태와 미구현 상태 기록.
- `docs/ai/tasks/lookbook-deletion-purge-drain/qa-checklist.md`
  - 20개 초과 drain, 동시성, 실패 격리, 시간 예산, lease 회귀 검증 범위.
- `functions/src/lookbookDeletionPurgeDrain.ts`
  - 브랜드별 bounded worker, page 반복, 시간 예산, 결과 집계 순수 helper.
- `functions/src/lookbookDeletionPurgeDrain.test.ts`
  - 20개 초과, 동시 브랜드 3개, 같은 브랜드 순차, 부모 우선, 실패/skip, 시간 예산 테스트.
- `functions/src/index.ts`
  - active/failed 독립 cursor query와 `brand -> season -> post` scheduled drain 연결.
- `functions/package.json`
  - 빌드된 모든 Functions test 실행.
- `firestore.indexes.json`
  - active/failed purge drain query용 복합 index 추가.
- `docs/ai/entrypoints/FIREBASE.md`, `docs/ai/DATA_SCHEMA.md`, `docs/ai/entrypoints/TESTS.md`
  - drain query, worker, index, 테스트와 운영 QA 진입점 반영.
- `docs/ai/tasks/active.md`
  - 현재 핵심 작업 포인터를 `lookbook-deletion-purge-drain`으로 변경.
- `docs/ai/ENTRYPOINTS.md`
  - 새 task 문서와 Functions 서버 진입점 추가.
- `HANDOFF.md`
  - 새 목표, 확정 결정, 남은 논의와 다음 실행 순서 반영.
- `docs/ai/tasks/lookbook-deletion-request-list-simplification/design.md`
  - 처리 가능한 삭제 요청만 앱에 표시하는 요구사항과 서버/iOS 설계.
- `docs/ai/tasks/lookbook-deletion-request-list-simplification/plan.md`
  - Phase별 목표, 변경 범위, 완료 기준, 검증 방법.
- `docs/ai/tasks/lookbook-deletion-request-list-simplification/decisions.md`
  - `active/failed` 전용 목록, scroll prefetch, 완료/history API 제거, 즉시 background retry, 15분 lease, 감사 기록 유지 결정.
- `docs/ai/tasks/lookbook-deletion-request-list-simplification/qa-checklist.md`
  - Functions/iOS/권한/이미지 식별 QA와 테스트 설계.
- `docs/ai/tasks/lookbook-deletion-request-list-simplification/progress.md`
  - Phase 2~6 구현, 검증, 운영 배포 결과와 보류된 수동 QA.
- `docs/ai/tasks/post-deletion-audit-thumbnail/`
  - 완료 목록 제거 결정으로 작업 전체를 폐기하고 문서를 삭제했다.
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
  - 기존 관리자 요청 목록 recent/history query 이력.
  - 현재 핵심 task Phase 2에서 삭제 요청 목록을 `active/failed` 전용 + 정확한 cursor로 단순화.
  - Phase 3에서 총 관리자 manual retry callable, Firestore trigger, 브랜드 단위 15분 lease와 scheduler fallback 추가.
- `functions/src/lookbookDeletionPurgeLease.ts`
  - lease 만료, trigger token, stale finalize, duplicate retry, 화면 상태 정규화 순수 정책 helper.
- `functions/src/lookbookDeletionPurgeLease.test.ts`
  - purge lease 순수 정책 Node 테스트.
- `functions/package.json`
  - Functions lease test 실행용 `npm test` script 추가.
- `docs/ai/entrypoints/TESTS.md`
  - Functions purge lease 테스트 진입점과 실행 명령 추가.
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
- `OutPick/Infra/Utility/Support/KeyboardDismissSupport.swift`
  - UIKit/SwiftUI 공통 키보드 dismiss tap helper 추가.
- `OutPick/Features/Chat/Controllers/ChatViewController.swift`
- `OutPick/Features/Chat/Controllers/RoomCreateViewController.swift`
- `OutPick/Features/Chat/Controllers/RoomEditViewController.swift`
- `OutPick/Features/Chat/Controllers/RoomSearchViewController.swift`
- `OutPick/Features/Profile/Views/SecondProfileViewController.swift`
  - UIKit 입력 화면에 `installKeyboardDismissTapGesture()` 적용.
- `OutPick/Features/Lookbook/Views/LookbookHome/LookbookHomeView.swift`
- `OutPick/Features/Lookbook/Views/BrandRequest/BrandRequestView.swift`
- `OutPick/Features/Lookbook/Views/CreateBrand/brand/CreateBrandView.swift`
- `OutPick/Features/Lookbook/Views/CreateBrand/season/CreateSeasonView.swift`
- `OutPick/Features/Lookbook/Views/CreateBrand/season/CreateSeasonFromURLView.swift`
- `OutPick/Features/Lookbook/Views/Admin/AdminBrandManagementView.swift`
- `OutPick/Features/Lookbook/Views/Admin/AdminBrandRequestGroupsView.swift`
- `OutPick/Features/Lookbook/Views/Admin/AdminLookbookDeletionManagementView.swift`
- `OutPick/Features/Lookbook/Views/PostDetail/CommentReportSheetView.swift`
- `OutPick/Features/Lookbook/Views/PostDetail/PostCommentsSheetView.swift`
- `OutPick/Features/Lookbook/Views/PostDetail/PostCommentRepliesSheetView.swift`
  - SwiftUI 입력 화면에 `outpickDismissKeyboardOnTap()` 적용.
- `docs/ai/ENTRYPOINTS.md`
- `docs/ai/entrypoints/APP.md`
- `docs/ai/entrypoints/CHAT.md`
- `docs/ai/entrypoints/LOOKBOOK.md`
- `docs/ai/entrypoints/PROFILE.md`
  - 키보드 dismiss 공통 helper와 화면별 진입점 문서화.

## 5. 중요한 아키텍처 결정

선택:
- `purgeExpiredLookbookDeletions`는 매일 04:00 실행을 유지한다.
- 한 실행의 전체 20개 고정 상한은 제거하고 페이지 반복 조회 + bounded concurrency로 시간 예산 안에서 큐를 소진한다.
- 기존 scheduled/manual 공통 브랜드 lease와 요청 단위 purge helper를 재사용한다.
- active/failed query는 독립 cursor를 사용하고 failed eligibility는 `retryAfter <= now`를 Firestore에서 직접 필터링한다.
- 부모 target 우선순위는 `brand -> season -> post`, 같은 target type은 `purgeAfter -> requestID`다.
- page는 브랜드별 queue로 묶고 서로 다른 브랜드만 최대 3개 병렬 처리한다.
- 실행 후 7분부터 신규 claim을 중단하고 이미 시작한 purge는 완료를 기다린다.

이유:
- 초기 사용자 규모에서는 15분 스케줄이 필요하지 않지만, 21번째 요청을 무조건 다음 날로 미루는 고정 상한도 불필요하다.
- 요청별 삭제량이 달라 무제한 병렬화는 timeout과 Firestore/Storage 부하 위험이 있다.

트레이드오프:
- 하루 1회이므로 정확히 7일이 되는 순간이 아니라 다음 04:00에 삭제된다.
- 시간 예산 안에 backlog를 다 처리하지 못하면 나머지는 다음 날까지 대기한다.

보류한 대안:
- 15분 스케줄은 운영 backlog가 확인될 때 재검토한다.
- Cloud Tasks나 별도 Cloud Run worker는 현재 규모에 비해 복잡도가 커서 도입하지 않는다.

재검토 조건:
- 잔여 backlog가 반복되거나 삭제 완료 지연 요구가 생기면 스케줄 주기, 동시성, 별도 queue 도입을 재검토한다.

선택:
- 앱 삭제 요청 목록에는 총 관리자와 브랜드 owner/admin 모두 `active/failed`만 표시한다.
- 총 관리자 전역 브랜드 grouping과 복구 가능 포스트의 원본 썸네일은 유지한다.
- `purged/cancelled/restored` 완료 UI와 삭제 요청 전용 processed/history API 계약은 제거한다.
- `purged` projection과 감사 로그는 서버 운영 이력으로 유지하고, purge 이후 별도 audit thumbnail은 만들지 않는다.
- 처리 대상 pagination은 목록 하단 sentinel scroll prefetch로 구현한다.
- failed purge는 총 관리자 callable이 token을 기록하고 Firestore trigger가 즉시 background 실행한다.
- scheduled/manual purge는 15분 lease로 동시 실행을 막고 scheduler fallback을 유지한다.

이유:
- `active`는 복구 가능하고 `failed`는 운영 대응이 필요하지만, 종료된 요청에는 앱에서 실행할 action이 없다.
- 포스트는 제목이 없어 이미지 식별이 필요하지만 7일 복구 기간에는 원본 Storage asset이 남아 별도 파생 이미지가 필요하지 않다.
- 앱 미배포 상태라 구버전 호환 분기를 유지할 필요가 없다.
- failed 상태에서 새 삭제 요청을 만들 수 없고 partial purge 가능성 때문에 일반 복구도 안전하지 않아 전용 retry가 필요하다.

트레이드오프:
- 앱에서 완료 이력을 조회할 수 없지만 일상 운영 화면이 처리 대상에 집중된다.
- 완료 처리 분석은 앱 UI가 아니라 서버 projection과 감사 로그를 이용해야 한다.
- immediate purge는 background trigger로 시작되므로 앱은 완료를 동기 대기하지 않고 상태를 다시 조회해야 한다.
- lease metadata와 동시성 테스트가 추가돼 구현 범위가 커지지만 destructive action 중복 실행 위험을 줄인다.

보류한 대안:
- 완료 목록과 audit thumbnail을 유지하는 방식은 action 없는 UI, 이미지 보존 정책, Functions/Storage 복잡도가 추가돼 폐기했다.
- 완료 projection과 감사 로그 자체를 삭제하는 방식은 운영 추적을 잃으므로 선택하지 않았다.
- callable이 cascade purge 완료까지 기다리는 방식은 앱/Functions timeout 위험 때문에 선택하지 않았다.
- scheduled purge만 다시 예약하는 방식은 최대 하루 지연돼 즉시 운영 대응 요구에 맞지 않아 선택하지 않았다.

재검토 조건:
- 운영자가 앱 안에서 완료 이력을 조회해야 하는 구체적인 업무 요구가 생기면 metadata 전용 운영 화면을 별도 검토한다.

선택:
- 관리자 요청 목록의 최근 처리 이력 기본 노출 기간은 브랜드 요청과 삭제 요청 모두 14일로 통일한다.
- 브랜드 요청 화면은 `새 요청`, `처리 중`, `보류`, `완료` segment로 간다.
- 14일 이전 처리 이력 조회도 이번 작업 범위에 포함한다.
- 당시 재시도 UX/API는 후속 논의로 분리했다. 삭제 요청 failed retry는 현재 핵심 task에서 즉시 background retry로 편입했으며, 브랜드 요청 재시도 논의만 별도로 남는다.

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

- 실제 대규모 브랜드의 최악 처리 시간과 7분 cutoff 운영 종료는 합성 QA로 재현하지 않았다. 운영 로그에서 관찰이 필요하다.
- 현재 `firestore.indexes.json`의 삭제 요청 composite index는 `active/failed` 목록과 purge query에도 필요하므로 이번 작업에서 제거하지 않는다.
- Firestore의 고정 `status in [active, failed]`와 `brandID`/`targetType` 조합은 실제 총 관리자/브랜드 관리자 인증 호출로 재확인해야 한다. 비로그인 권한 거부까지만 운영 확인했다. 확실하지 않음.
- Firestore trigger와 scheduler lease 경쟁, trigger timeout 후 scheduler fallback은 자동 테스트와 운영 전 smoke QA가 필요하다.
- `updatedAt` 누락 legacy 문서가 있는지는 재확인 필요.
- `docs/ai/tasks/lookbook-admin-soft-delete-lifecycle/progress.md`는 `.git/info/exclude`의 `docs/ai/tasks/` 규칙 때문에 `git status --short`에 표시되지 않는다. 실제 파일은 갱신했다.
- 현재 작업의 Functions 테스트 5개와 iOS 선택 테스트 5개는 실행해 통과했다.
- App Review Notes용 관리자 데모 계정/설명 준비 필요 여부는 아직 결정되지 않았다.
- 브랜드 룩북 콘텐츠 수집/표시 권리 범위는 확실하지 않음. 출시/심사 전 사용자와 검토 필요.

## 7. 다음 턴에서 바로 실행해야 할 작업

1. `lookbook-deletion-purge-drain`은 완료 상태로 유지하고 운영 backlog/elapsed/cutoff 로그를 관찰한다.
2. 다음 핵심 작업을 사용자와 선택한다.
