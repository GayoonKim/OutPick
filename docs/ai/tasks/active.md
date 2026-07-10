# Active Task

## 현재 상태

- 2026-07-10 ad hoc UX 보강으로, 입력 화면에서 키보드가 올라온 상태에 입력 영역 외부를 탭하면 키보드가 내려가도록 공통 helper와 주요 UIKit/SwiftUI 입력 화면 적용을 완료했다.
- 키보드 dismiss 공통 진입점은 `OutPick/Infra/Utility/Support/KeyboardDismissSupport.swift`이며, UIKit은 `installKeyboardDismissTapGesture()`, SwiftUI는 `outpickDismissKeyboardOnTap()`을 사용한다.
- 현재 다음 핵심 task는 `post-deletion-audit-thumbnail`이다.
- 목표는 포스트 삭제 요청이 영구 삭제(`purged`)된 뒤에도 운영자가 어떤 포스트가 삭제되었는지 식별할 수 있도록, 포스트에 한해서 감사용 저해상도 thumbnail snapshot을 남기는 것이다.
- 브랜드/시즌 삭제 완료 목록은 이미지 UI를 표시하지 않는 현재 정책을 유지한다.
- 포스트 삭제 완료 목록만 audit thumbnail을 표시한다.
- 원본 포스트 이미지와 기존 Storage asset은 purge 시 계속 삭제한다.
- audit thumbnail은 원본 보존이 아니라 운영 이력 식별용 제한 snapshot으로 별도 Storage prefix에 저장한다.
- 신규 포스트 삭제 요청부터 적용하고, 이미 purge된 기존 포스트 요청은 이미지 복구 대상이 아니다.
- 구현 전 `docs/ai/tasks/post-deletion-audit-thumbnail/` 하위 문서를 먼저 확인한다.
- 구현 전 논의 필요 항목은 audit thumbnail 보존 기간, thumbnail 크기/포맷, Storage 접근 방식, cleanup 방식, thumbnail 생성 실패 시 삭제 요청 생성 실패 여부다.
- 직전 핵심 task인 `admin-request-list-retention-unification`은 구현, 로컬 검증, Functions 운영 배포를 완료했다.
- `admin-request-list-retention-unification` 목표는 총 관리자 브랜드 요청 목록과 총 관리자/브랜드 owner/admin 삭제 요청 목록의 진행 중/완료 요청 표시 정책을 14일 최근 처리 이력 기준으로 통일하는 것이다.
- 2026-07-09 사용자 결정으로 완료된 요청 기본 노출 기간은 14일로 통일한다. 삭제 lifecycle의 7일 복구 가능 기간과 운영 목록의 14일 최근 처리 이력 노출 기간은 분리한다.
- 2026-07-09 추가 사용자 결정으로 브랜드 요청 화면은 `새 요청`, `처리 중`, `보류`, `완료` segment로 가고, 14일 이전 처리 이력 조회도 이번 작업에 포함한다.
- 2026-07-09 추가 사용자 결정으로 삭제 요청 `완료` 목록은 영구 삭제가 끝난 `purged`만 표시한다. 최근 14일 완료 목록을 기본 표시하고, `이전 완료 기록 보기` 버튼 후 14일 이전 완료 기록을 같은 화면 아래에 추가 표시한다. 이전 완료 기록은 스크롤 prefetch로 추가 로드한다.
- 2026-07-09 추가 사용자 결정으로 브랜드 요청 `보류`/`완료`도 최근 14일 목록을 기본 표시하고, 이전 기록 보기 버튼 후 14일 이전 기록을 같은 화면 아래에 추가 표시한다. 이전 기록은 스크롤 prefetch로 추가 로드한다.
- 2026-07-09 구현, 로컬 검증, Functions 운영 배포를 완료했다.
- 구현 전 설계 문서는 `docs/ai/tasks/admin-request-list-retention-unification/` 하위 문서를 먼저 확인한다.
- 직전 핵심 task인 `lookbook-admin-soft-delete-lifecycle`은 핵심 구현, 운영 배포, OUTSTANDING 통합 QA까지 완료했다.
- 후속 QA/보정은 Phase A 삭제 요청 목록 표시명 보정, Phase B 관리자 브랜드 관리 화면 메뉴 리팩토링, Phase C `BrandDetailView` pull-to-refresh 추가까지 완료했다.
- 2026-07-08 기준 Phase 1 추천안 확정, Phase 2 서버 soft delete 기반 구현/운영 배포, Phase 3 사용자 노출 차단 구현/로컬 검증, Phase 4 관리자 삭제/복구 UI 구현/로컬 빌드 검증, Phase 5 scheduled purge 구현/운영 배포, Phase 6 OUTSTANDING 통합 QA를 완료했다.
- 직전 핵심 task인 `admin-web-brand-season-management`는 Phase 2~7 구현, 운영 배포, 통합 수동 QA까지 완료 처리했다.
- 삭제 lifecycle의 확정 정책:
  - 브랜드 owner/admin은 브랜드 삭제 요청을 할 수 없다.
  - 브랜드 삭제 요청/취소와 브랜드 삭제 요청 상태 노출은 총 관리자에게만 제공한다.
  - 브랜드 `deletionRequested` 상태는 사용자 화면에서 즉시 숨긴다.
  - 브랜드 lifecycle은 `active -> deletionRequested -> purged`로 둔다.
  - 시즌 삭제 시 하위 포스트는 즉시 `deleted`로 바꾸지 않는다.
  - 시즌 `deleted` 상태로 시즌 탭/상세/하위 포스트 접근을 막고, 7일 후 scheduled function이 하위 컬렉션을 순회 삭제한다.
  - 복구 가능 기간은 7일이다.
  - 앱 관리자 UI에는 hard delete를 제공하지 않는다.
  - hard delete는 삭제 요청 취소/복구가 없으면 scheduled function이 7일 후 수행한다.
  - 브랜드 owner/admin에게 시즌/포스트 hard delete도 허용하지 않는다.
- 아래 핵심 작업은 완료/마감 처리했다.
  - `chat-legacy-identity-naming`
  - `chat-membership-model-transition` 핵심 구현 및 운영 배포
  - 운영 smoke QA 기반 legacy cleanup/index 배포 결정 및 실행
  - `chat-member-profile-cache-boundary` Phase 1~4
  - `grdb-schema-cleanup`
  - `chat-membership-model-transition` destructive 수동 QA
  - `Socket dependency audit` 보수 업데이트
  - `Storage rules/preview 권한 확인` read-only 운영 상태 점검
  - `Storage rules 최소 권한 설계/적용` 운영 배포와 핵심 chat upload QA
  - `chat-profile-snapshot-cache-refactor`
  - Realtime DEBUG 로그 정리
  - `admin-web-brand-season-management` Phase 2~7 구현, 운영 배포, 통합 수동 QA

## 완료한 핵심 작업

### 1. `chat-legacy-identity-naming`

- canonical user ID 기준 명명을 `userID`로 정리했다.
- `LocalChatUser.userID`, `RoomMember.userID` 등 Swift/API/GRDB 물리 schema를 canonical UID 의미로 맞췄다.
- legacy `userProfile`/`roomParticipant` runtime fallback은 제거했다.
- 최종 검증:
  - forbidden pattern 재검색 통과
  - `git diff --check` 통과
  - iOS generic simulator build 통과
  - `GRDBManagerMigrationTests` 통과

### 2. `chat-membership-model-transition`

- membership authoritative source를 `Rooms/{roomID}/members/{uid}`로 전환했다.
- 참여중 목록 source를 `users/{uid}/joinedRooms/{roomID}` projection + `Rooms` batch fetch + 클라이언트 정렬로 전환했다.
- Socket room access, push fanout, 방장 close cleanup, Firestore rules, Functions cleanup 경계를 새 membership 모델에 맞췄다.
- 운영 배포:
  - Socket Cloud Run `outpick-socket` revision `outpick-socket-00004-76z` 100% traffic 배포 완료
  - `firebase deploy --only firestore:rules --project outpick-664ae` 완료
  - `firebase deploy --only functions --project outpick-664ae` 완료
  - `firebase deploy --only firestore:indexes --project outpick-664ae --force` 완료
- 운영 legacy field count는 0으로 확인했다.

### 3. `chat-member-profile-cache-boundary`

- Phase 1:
  - `RoomProfileDisplayCache(roomID, userID)` GRDB schema/API/migration 추가
  - room당 20명 LRU eviction 구현
  - room cleanup과 orphan `LocalChatUser` prune 기준 반영
- Phase 2:
  - 메시지 저장 경로가 `LocalChatUser` + `RoomProfileDisplayCache`만 갱신하도록 전환
  - 메시지 경로의 local `RoomMember` write 제거
- Phase 3:
  - 설정 참여자 목록 source를 remote `Rooms/{roomID}/members` pagination으로 전환
  - 전체 members fetch + local `RoomMember` reconcile 제거
- Phase 4:
  - production 경계의 local membership replica API 제거
  - `RoomMember` table/model/migration은 migration chain 호환 흔적으로만 유지
  - `docs/ai/DATA_SCHEMA.md`, `docs/ai/entrypoints/CHAT.md` 갱신
- 최종 검증:
  - forbidden pattern 검색 통과
  - `git diff --check` 통과
  - iOS generic simulator build 통과
  - `GRDBManagerMigrationTests` 통과

## 작업 상태 목록

### 1. `post-deletion-audit-thumbnail` 설계 시작

- 목적:
  - 포스트 삭제 완료 목록에서 운영자가 어떤 포스트가 삭제되었는지 식별할 수 있게 한다.
  - 브랜드/시즌 완료 목록은 이미지 없이 텍스트 snapshot만 표시한다.
  - 포스트 완료 목록만 감사용 저해상도 thumbnail을 표시한다.
  - 원본 이미지 삭제 정책과 감사용 snapshot 보존 정책을 분리한다.
- 현재 상태:
  - 설계 문서, phase 계획, 결정 문서, QA 체크리스트를 생성했다.
  - 아직 구현은 시작하지 않았다.
- 먼저 확인할 문서:
  - `docs/ai/tasks/post-deletion-audit-thumbnail/design.md`
  - `docs/ai/tasks/post-deletion-audit-thumbnail/decisions.md`
  - `docs/ai/tasks/post-deletion-audit-thumbnail/plan.md`
  - `docs/ai/tasks/post-deletion-audit-thumbnail/progress.md`
  - `docs/ai/tasks/post-deletion-audit-thumbnail/qa-checklist.md`
  - `docs/ai/entrypoints/LOOKBOOK.md`
  - `docs/ai/entrypoints/FIREBASE.md`
  - `docs/ai/DATA_SCHEMA.md`
- 주요 진입점:
  - Functions: `functions/src/index.ts`의 포스트 삭제 요청 생성 경로, `listLookbookDeletionRequests`, `purgeExpiredLookbookDeletions`
  - iOS: `AdminLookbookDeletionManagementView.swift`, `AdminLookbookDeletionManagementViewModel.swift`, `LookbookDeletionRequest.swift`
  - Repository/Cloud Functions wrapper: `CloudFunctionsLookbookDeletionRepository.swift`, `CloudFunctionsManager.swift`
  - 권한/Storage: `firestore.rules`, Storage rules 위치 재확인 필요
- 확정 방향:
  - 포스트만 audit thumbnail을 남긴다.
  - 브랜드/시즌 완료 목록은 이미지 UI를 표시하지 않는다.
  - 원본 이미지는 purge 시 계속 삭제한다.
  - 기존 purge 완료 포스트는 image backfill 대상이 아니다.
- 구현 전 논의 필요:
  - 보존 기간: 30일, 90일, 180일 중 선택.
  - thumbnail 크기: 긴 변 160px, 200px, 240px 중 선택.
  - 포맷: JPEG 고정 또는 WebP 지원.
  - Storage 접근 방식: 관리자 권한 rules 또는 callable URL.
  - cleanup 방식: Storage lifecycle rule 또는 scheduled function.
  - thumbnail 생성 실패 시 삭제 요청 생성 실패 여부.
- 권장 검증:
  - Functions `npm run lint`, `npm run build`.
  - iOS generic simulator build.
  - Storage 권한/thumbnail 생성/삭제 후 보존 수동 QA.

### 2. `admin-request-list-retention-unification` 구현 완료

- 목적:
  - 관리자 콘솔 요청 목록에서 진행 중 요청과 최근 처리 완료 요청을 일관되게 보여준다.
  - 브랜드 요청 목록은 `새 요청`, `처리 중`, `보류`, `완료` 구조로 가고, `completed`/`rejected` 처리 이력은 최근 14일 기본 노출과 14일 이전 이력 조회를 모두 제공한다.
  - 삭제 요청 목록은 `처리 중(active/failed)`과 `완료(purged)`를 분리하고, 영구 삭제 완료 요청은 최근 14일 기본 노출과 14일 이전 이력 조회를 모두 제공한다.
  - 삭제 lifecycle의 7일 복구 기간은 유지하되, 관리자 운영 목록 노출 기간과 혼동하지 않는다.
- 현재 상태:
  - 설계 문서, phase 계획, 결정 문서, QA 체크리스트를 생성했다.
  - Functions/iOS 구현을 완료했다.
  - Functions 운영 배포를 완료했다.
- 먼저 확인할 문서:
  - `docs/ai/tasks/admin-request-list-retention-unification/design.md`
  - `docs/ai/tasks/admin-request-list-retention-unification/decisions.md`
  - `docs/ai/tasks/admin-request-list-retention-unification/plan.md`
  - `docs/ai/tasks/admin-request-list-retention-unification/progress.md`
  - `docs/ai/tasks/admin-request-list-retention-unification/qa-checklist.md`
  - `docs/ai/entrypoints/LOOKBOOK.md`
  - `docs/ai/entrypoints/FIREBASE.md`
  - `docs/ai/DATA_SCHEMA.md`
- 주요 진입점:
  - Functions: `functions/src/index.ts`의 `listBrandRequestGroups`, `listLookbookDeletionRequests`
  - 브랜드 요청 iOS: `AdminBrandRequestGroupsView.swift`, `AdminBrandRequestGroupsViewModel.swift`, `BrandRequest.swift`
  - 삭제 요청 iOS: `AdminLookbookDeletionManagementView.swift`, `AdminLookbookDeletionManagementViewModel.swift`, `LookbookDeletionRequest.swift`
  - Repository/UseCase: 브랜드 요청/삭제 요청 list 관련 protocol, CloudFunctions repository, CloudFunctionsManager wrapper
- 확정된 화면/범위:
  - 브랜드 요청 화면은 `새 요청`, `처리 중`, `보류`, `완료` segment로 간다.
  - 14일 이전 처리 이력 조회도 이번 작업에 포함한다.
  - 재시도 UX/API는 이번 핵심 작업 완료 후 별도 논의한다.
- 완료 범위:
  - `listBrandRequestGroups`는 `rejected/completed` group에서 `processedScope = recent | history`를 지원한다.
  - `listLookbookDeletionRequests`는 `statusGroup = active | processed`와 `processedScope = recent | history`를 지원한다.
  - 브랜드 요청 관리자 화면에 `완료` segment를 추가했다.
  - 브랜드 요청 `보류`/`완료`는 최근 14일 목록을 기본 표시하고, 이전 기록 보기 버튼 후 14일 이전 기록을 아래에 추가 표시한다.
  - 브랜드 요청 14일 이전 기록은 스크롤 prefetch로 다음 page를 불러온다.
  - 삭제 요청 목록에 `처리 중` / `완료` status group picker를 추가했다.
  - 삭제 요청 `완료`는 최근 14일 목록을 기본 표시하고, `이전 완료 기록 보기` 버튼 후 14일 이전 완료 기록을 아래에 추가 표시한다.
  - 삭제 요청 14일 이전 완료 기록은 스크롤 prefetch로 다음 page를 불러온다.
  - 삭제 요청 완료 목록 제목은 삭제 완료 후 원본 브랜드/시즌/포스트 문서가 없어도 요청 projection의 `brandName`/`seasonTitle`/`postCaption` snapshot을 fallback보다 우선 표시한다.
- 검증:
  - Functions `npm run lint` 통과.
  - Functions `npm run build` 통과.
  - iOS generic simulator build 통과.
- 권장 검증:
  - 총 관리자/브랜드 owner/admin 수동 QA.
  - 삭제 요청 processed query에서 Firestore index 요구가 나오면 `firestore.indexes.json` 보강.

### 2. `lookbook-admin-soft-delete-lifecycle` 완료

- 목적:
  - 브랜드/시즌/포스트 삭제 기능을 계정 탈취나 운영 실수에도 즉시 영구 삭제로 이어지지 않는 lifecycle로 설계한다.
  - 관리자 콘솔은 삭제 요청 목록 확인, 삭제 요청 취소, 삭제 상태 복구만 제공한다.
  - 실제 hard delete는 scheduled function이 7일 후 자동 처리한다.
- 현재 상태:
  - 핵심 구현, 운영 배포, OUTSTANDING 통합 QA까지 완료했다.
  - Phase 1 하네스/계약 정리 완료.
  - Phase 2 서버 soft delete 기반 구현 및 운영 배포 완료.
  - Phase 3 사용자 노출 차단 구현 및 로컬 검증 완료.
  - Phase 4 관리자 삭제/복구 UI 구현 및 로컬 빌드 검증 완료.
  - Phase 5 scheduled purge 구현 및 운영 배포 완료.
  - Phase 6 OUTSTANDING 통합 QA 완료.
  - 다음 수정 작업은 아래 문서와 진입점을 먼저 보고 범위를 좁힌 뒤 진행한다.
- 먼저 확인할 문서:
  - `docs/ai/tasks/lookbook-admin-soft-delete-lifecycle/design.md`
  - `docs/ai/tasks/lookbook-admin-soft-delete-lifecycle/decisions.md`
  - `docs/ai/tasks/lookbook-admin-soft-delete-lifecycle/plan.md`
  - `docs/ai/tasks/lookbook-admin-soft-delete-lifecycle/progress.md`
  - `docs/ai/tasks/lookbook-admin-soft-delete-lifecycle/qa-checklist.md`
  - `docs/ai/ENTRYPOINTS.md`
  - `docs/ai/entrypoints/LOOKBOOK.md`
  - `docs/ai/entrypoints/FIREBASE.md`
  - `docs/ai/DATA_SCHEMA.md`
- Phase 2 완료 범위:
  - `requestBrandDeletion`, `cancelBrandDeletion`, `softDeleteSeason`, `restoreSeason`, `softDeletePost`, `restorePost`, `listLookbookDeletionRequests` callable 추가.
  - `lookbookDeletionRequests` projection과 `lookbookDeletionAuditLogs` 감사 로그 기반 추가.
  - Firestore rules에서 projection/audit 직접 접근 차단, 시즌/포스트 직접 delete 차단.
  - `lookbookDeletionRequests` 목록 조회용 Firestore indexes 추가.
  - hard delete callable과 scheduled purge 본체는 추가하지 않음.
- Phase 2 검증:
  - Functions `npm run build` 통과.
  - Functions `npm run lint` 통과.
  - Firestore rules/indexes dry-run 통과.
- Phase 2 운영 배포:
  - `firebase deploy --only functions --project outpick-664ae --non-interactive` 완료.
  - `firebase deploy --only firestore:rules,firestore:indexes --project outpick-664ae --non-interactive` 완료.
  - Firestore indexes 배포 중 로컬 파일에 없는 운영 field override 1개 경고가 있었고, `--force`를 쓰지 않아 삭제하지 않았다.
- Phase 3 완료 범위:
  - 브랜드/시즌/포스트 도메인과 DTO에 `deletionStatus`를 반영했다.
  - 사용자 목록/탭/검색/좋아요 리스트에서는 삭제 상태 대상을 비노출한다.
  - 공유/딥링크/좋아요 상세 직접 진입에서는 부모 브랜드/시즌/포스트 상태를 확인하고 unavailable 상태를 표시한다.
  - 일반 사용자 unavailable 화면에는 삭제 요청 메모/사유를 노출하지 않는다.
  - `searchBrands` 응답 summary에 `deletionStatus`를 포함했지만, 앱은 Functions 배포 전에도 Firestore 단건 재조회로 검색 결과를 최종 검증한다.
- Phase 3 검증:
  - iOS generic simulator build 통과.
  - Functions `npm run lint` 통과.
  - Functions `npm run build` 통과.
- Phase 4 완료 범위:
  - 총 관리자 전용 브랜드 삭제 요청/취소 UI를 추가했다.
  - 브랜드 owner/admin에게 브랜드 삭제 요청/취소와 브랜드 `deletionRequested` 상태를 노출하지 않는다.
  - 브랜드 owner/admin은 선택 브랜드의 시즌/포스트 삭제와 복구만 할 수 있다.
  - 삭제 요청 목록, 복구 가능 기한, 삭제 사유 표시를 관리자 삭제 관리 화면에 추가했다.
  - hard delete 버튼은 추가하지 않았다.
- Phase 4 검증:
  - iOS generic simulator build 통과.
- Phase 5 확정 범위:
  - Firestore 문서만이 아니라 관련 Firebase Storage 파일까지 삭제한다.
  - 브랜드 purge는 `brands/{brandID}` 하위 Firestore 문서 전체, `brandNameIndex`, 관련 user state projection, `brands/{brandID}/` Storage prefix를 삭제한다.
  - 시즌 purge는 하위 posts/comments/replacements, 관련 user state projection, `brands/{brandID}/seasons/{seasonID}/` Storage prefix를 삭제한다.
  - 포스트 purge는 하위 comments/replacements, 관련 user state projection, `brands/{brandID}/seasons/{seasonID}/posts/{postID}/` Storage prefix를 삭제한다.
  - `Asia/Seoul` 기준 매일 04:00, 최대 20개 target/run으로 시작한다.
  - `failed` 요청은 `autoRetryEligible = true`, `retryAfter <= now`, `purgeAttemptCount < 3`일 때만 자동 재시도한다.
- Phase 5 완료 범위:
  - `functions/src/index.ts`의 `purgeExpiredLookbookDeletions`.
  - `firestore.indexes.json` purge 대상 조회 및 user state projection 정리용 인덱스.
  - Functions lint/build와 Firestore indexes dry-run 검증.
  - 2026-07-08 `firebase deploy --only functions,firestore:indexes --project outpick-664ae --non-interactive` 운영 배포 완료.
  - 새 scheduled function `purgeExpiredLookbookDeletions(asia-northeast3)` 생성 완료.
- Phase 6 완료 범위:
  - 사용자 수동 QA에서 권한/삭제/복구/비노출 흐름이 의도대로 동작함을 확인했다.
  - OUTSTANDING 테스트 브랜드 기준 post/season/brand purge QA를 완료했다.
  - 실패/재시도 QA에서 `failed`, `purgeAttemptCount`, `retryAfter`, `autoRetryEligible`, 3회 실패 후 자동 재시도 제외를 확인했다.
  - user state projection collection group field override 누락을 발견해 `firestore.indexes.json`에 보강하고 운영 배포했다.
- 다음 확인:
  - 삭제 lifecycle 자체는 완료 상태로 보고, 이후는 발견된 수정 사항을 별도 작은 변경으로 처리한다.
- 권장 검증:
  - Functions 변경 시 lint/build.
  - Firestore rules/indexes 변경 시 dry-run.
  - iOS 변경 시 generic simulator build.
  - 권한/상태 전이 unit test.
  - 총 관리자/브랜드 owner/admin/비관리자 수동 QA.

### 2. `admin-web-brand-season-management`

- 목적:
  - 브랜드/시즌 생성/import 기능을 일반 사용자 기능에서 분리하고, iOS 앱 내 관리자 계정 전용 Lookbook 관리 콘솔로 재배치한다.
  - 기존 시즌 import Cloud Tasks/Cloud Run worker 흐름은 가능한 재사용하고, 호출 주체와 운영 UI를 관리자 콘솔로 정리한다.
  - iOS 앱 내 운영자용 생성/import 진입점은 일반 사용자에게 비노출하고, 관리자 계정에서만 접근하게 한다.
  - 총 관리자와 브랜드별 관리자를 구분한다.
  - 총 관리자는 `brandAdmins/{uid}.isActive == true`, 브랜드별 관리자는 `brands/{brandID}/admins/{uid}.role in ["owner", "admin"]` 기준으로 판단한다.
  - 관리자 추가는 normalized email로 기존 `users.email`을 조회해 `brands/{brandID}/admins/{uid}` 문서에 추가한다.
  - 브랜드 요청 일일 제한은 `brandRequestDailyCounters/{uid}/brandRequestDays/{yyyyMMdd}`로 관리하고, TTL field는 `expiresAt`으로 둔다.
  - spam 누적 제한은 `brandRequestUserLimits/{uid}`에 기록한다.
  - 브랜드 요청 운영 단계는 `requested`, `processing`, `completed`, `rejected`로 둔다.
  - `spam`은 운영 단계가 아니라 `rejectionReason = spam`으로 처리한다.
  - 사용자 요청 목록은 기본 `active`와 이전 요청 `history` scope로 나눈다.
- 완료한 현재 phase:
  - Phase 2 브랜드 요청 데이터/API 기반 구현 및 운영 배포.
  - Phase 3 iOS 브랜드 검색/요청 UX 구현.
  - Phase 4 iOS 관리자 권한/진입점 정리 구현.
  - Phase 5A 관리자 브랜드 요청 group 큐 모델/API 구현.
  - Phase 5B iOS 관리자 요청 group 목록/상태 변경 구현.
  - Phase 6A 요청 group 완료 처리 + 브랜드 연결 구현.
  - Phase 6B iOS 관리자 추가/삭제, 브랜드 수정/로고 수정, import 관리 진입 정리 구현.
  - Phase 6H 통합 관리자 브랜드 관리 QA 수정 및 수동 QA 완료.
  - Phase 7 iOS 관리자 시즌 import 관리 QA 완료.
- Phase 6B 검증:
  - Functions `npm run lint` 통과.
  - Functions `npm run build` 통과.
  - `firebase deploy --only firestore:indexes --project outpick-664ae --dry-run --non-interactive` 통과.
  - XcodeBuildMCP `build_sim` 통과.
- Phase 6B 운영 배포:
  - 2026-07-06 Functions 배포 완료.
  - 2026-07-06 Firestore rules 배포 완료.
  - 2026-07-06 Firestore indexes 배포 완료.
- Phase 7 전 권한 모델 리팩토링:
  - 총 관리자는 `brandAdmins/{uid}.isActive == true` 기준으로 정리.
  - 브랜드 owner/admin은 `brands/{brandID}/admins/{uid}.role` 기준으로 정리.
  - `canCreateBrands`, `brandCreator`, `allowedBrandIDs`는 권한 판단 source에서 제외.
  - iOS 관리자 콘솔 노출을 총 관리자와 브랜드별 관리자 역할에 맞게 분리.
  - Functions lint/build, XcodeBuildMCP build 통과.
  - 2026-07-06 Functions 운영 배포 완료.
- Phase 6H/7 QA 수정 코드 진입점:
  - `OutPick/Features/Lookbook/Views/Admin/AdminBrandManagementView.swift`
  - `OutPick/Features/Lookbook/ViewModels/AdminBrandManagementViewModel.swift`
  - `OutPick/Features/Lookbook/Views/BrandDetail/BrandDetailView.swift`
  - `OutPick/Features/Lookbook/Views/BrandDetail/BrandDetailHeaderView.swift`
  - `OutPick/Features/Lookbook/Views/LookbookHome/BrandRowView.swift`
  - `OutPick/Features/Lookbook/Services/ImageLoading/BrandImageCache.swift`
  - `OutPick/Features/Lookbook/Services/ImageLoading/BrandImageCacheProtocol.swift`
  - `OutPickTests/AdminBrandManagementViewModelTests.swift`
- 먼저 확인할 문서:
  - `docs/ai/ENTRYPOINTS.md`
  - `docs/ai/entrypoints/LOOKBOOK.md`
  - `docs/ai/entrypoints/FIREBASE.md`
  - `docs/ai/DATA_SCHEMA.md`
  - `docs/ai/architecture/LOOKBOOK_IMPORT_WORKER.md`
  - `docs/ai/tasks/lookbook-import-worker/*`
  - `docs/ai/tasks/socket-cloud-run-deploy/design.md`
  - `docs/ai/tasks/socket-cloud-run-deploy/decisions.md`
- 다음 구현 전 확인:
  - App Review Notes용 관리자 데모 계정/설명 준비 여부.
  - 브랜드 룩북 콘텐츠 수집/표시 권리 범위 검토 필요 여부.
- 권장 검증:
  - 설계 하네스 완료 후 phase별로 별도 확정
  - Functions 변경 시 lint/build
  - Firestore/Storage rules 변경 시 dry-run
  - iOS 변경 시 generic simulator build
  - 관리자/비관리자 계정 수동 QA

## 다음 추천 순서

1. `lookbook-admin-soft-delete-lifecycle` 변경분을 기준으로 수정이 필요한 부분을 확인한다.
2. 수정 범위가 Swift 앱, Functions/Firestore, 문서 중 어디인지 나누고 해당 진입점 문서를 먼저 확인한다.
3. 수정이 확정되면 작은 단위로 구현, 검증, 하네스 문서 갱신을 반복한다.
