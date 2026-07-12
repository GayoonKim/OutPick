# Lookbook Deletion Request List Simplification Plan

## Phase 1. 설계 확정과 하네스 교체

목표:

- 완료 삭제 요청 UI 제거와 `active/failed` 중심 목록 정책을 문서화한다.
- 폐기된 audit thumbnail 작업을 현재 핵심 작업에서 제거한다.

변경 범위:

- `docs/ai/tasks/lookbook-deletion-request-list-simplification/`
- `docs/ai/tasks/post-deletion-audit-thumbnail/` 제거
- `docs/ai/tasks/active.md`
- `docs/ai/ENTRYPOINTS.md`
- `docs/ai/entrypoints/LOOKBOOK.md`
- `docs/ai/entrypoints/FIREBASE.md`
- `HANDOFF.md`

완료 기준:

- 새 작업이 현재 핵심 task로 등록된다.
- 구현 범위, 제외 범위, 완료 기준, 테스트 계획이 문서화된다.
- Swift/Functions 코드는 수정하지 않는다.

검증 방법:

- 폐기 task 참조 검색
- `git diff --check`
- `git status --short`

논의 필요 사항:

- 없음. 구현과 운영 배포는 사용자 승인 후 진행한다.

## Phase 2. Functions 목록 계약 단순화

목표:

- 삭제 요청 목록 API를 `active/failed` 전용 계약으로 단순화한다.

예상 변경 범위:

- `functions/src/index.ts`
- `docs/ai/entrypoints/FIREBASE.md`
- `docs/ai/DATA_SCHEMA.md`

완료 기준:

- `listLookbookDeletionRequests`가 항상 `active/failed`만 조회한다.
- 삭제 요청 전용 `status/statusGroup/processedScope/recentProcessedDays` 입력 파싱과 완료 query가 제거된다.
- 권한별 brand scope와 target type은 유지된다.
- `limit + 1` query로 실제 다음 page가 있을 때만 `nextCursor`를 반환한다.
- 기존 `lookbookDeletionRequests` composite index는 `active/failed` 조회와 purge에 필요하므로 변경하지 않는다.

검증 방법:

- `functions` `npm run lint`
- `functions` `npm run build`
- total admin 전역 query와 brand-scoped query 계약 확인
- cursor 첫 page/중간 page/마지막 page 계약 확인

논의 필요 사항:

- Functions 운영 배포는 사용자 명시 승인 후 진행한다.

## Phase 3. Functions failed purge 즉시 재시도와 lease

목표:

- 총 관리자가 failed purge를 즉시 background 재시도할 수 있게 한다.
- scheduled/manual purge 동시 실행을 lease로 막는다.

예상 변경 범위:

- `functions/src/index.ts`
- `docs/ai/entrypoints/FIREBASE.md`
- `docs/ai/DATA_SCHEMA.md`
- Functions test 파일 후보

완료 기준:

- 총 관리자 전용 `retryFailedLookbookDeletionPurge` callable이 추가된다.
- callable은 manual retry token을 transaction으로 기록하고 purge 완료를 기다리지 않고 응답한다.
- `onLookbookDeletionManualRetryQueued` Firestore trigger가 새 queued token만 감지해 purge를 즉시 시작한다.
- callable 중복 요청은 새 token을 만들지 않고 duplicate receipt를 반환한다.
- scheduled/manual 경로가 공통 15분 lease claim/finalize helper를 사용한다.
- 유효 lease가 있으면 중복 purge를 시작하지 않는다.
- finalize는 자신의 lease token과 문서 token이 같을 때만 반영된다.
- trigger 실패/timeout 시 scheduler fallback이 가능하다.
- 재시도 요청과 성공/실패가 감사 로그에 남는다.
- 목록 응답에 failed retry 상태 metadata가 포함된다.

검증 방법:

- Functions `npm run lint`
- Functions `npm run build`
- lease claim 경쟁, 만료 lease, stale token finalize 자동 테스트
- 권한/상태/precondition 테스트
- trigger 중복 전달 idempotency 테스트

논의 필요 사항:

- Functions 운영 배포는 사용자 명시 승인 후 진행한다.

## Phase 4. iOS Domain/Repository/ViewModel 단순화

목표:

- 삭제 완료/history 상태와 API 파라미터를 iOS 경계에서 제거한다.
- 처리 대상 scroll prefetch와 failed 재시도 상태/action을 ViewModel에 반영한다.

예상 변경 범위:

- `OutPick/Features/Lookbook/Domains/Entities/LookbookDeletionRequest.swift`
- `OutPick/Features/Lookbook/Repositories/Protocols/LookbookDeletionRepositoryProtocol.swift`
- `OutPick/Features/Lookbook/Repositories/Implementations/CloudFunctionsLookbookDeletionRepository.swift`
- `OutPick/DB/Firebase/CloudFunctions/CloudFunctionsManager.swift`
- `OutPick/Features/Lookbook/ViewModels/AdminLookbookDeletionManagementViewModel.swift`
- `OutPick/Features/Lookbook/Views/Admin/AdminLookbookDeletionManagementView.swift`
- `OutPickTests/AdminLookbookDeletionManagementViewModelTests.swift` 후보

완료 기준:

- `LookbookDeletionRequestStatusGroup`이 제거된다.
- 삭제 repository에서 `statusGroup/processedScope`가 제거된다.
- ViewModel의 완료/history 상태와 history cursor/prefetch 동작이 제거된다.
- 처리 대상용 `nextCursor`, 추가 로딩 상태, scroll prefetch 동작이 추가된다.
- page append는 `requestID` 기준 중복을 제거한다.
- 목록 reload는 권한 범위의 처리 대상 첫 page와 cursor를 갱신한다.
- 목록 entity/repository가 failed retry metadata와 총 관리자 재시도 mutation을 지원한다.
- 브랜드 요청의 `ProcessedRequestScope`는 유지된다.
- status group 타입 제거 후 빌드 가능하도록 처리 중/완료 picker와 완료/history UI도 이 phase에서 함께 제거한다.

검증 방법:

- fake repository 기반 ViewModel unit test 작성 후보
- Swift compile/build-for-testing

논의 필요 사항:

- 없음.

## Phase 5. iOS 삭제 요청 화면 단순화

목표:

- 총 관리자와 브랜드 owner/admin 화면에서 처리 가능한 삭제 요청만 보여준다.

예상 변경 범위:

- `OutPick/Features/Lookbook/Views/Admin/AdminLookbookDeletionManagementView.swift`
- `docs/ai/entrypoints/LOOKBOOK.md`

완료 기준:

- Phase 4에서 제거된 처리 중/완료 picker와 완료/history UI가 다시 나타나지 않는다.
- 총 관리자 브랜드별 grouping이 유지된다.
- 브랜드 scoped 목록과 복구 action이 유지된다.
- `active/failed` 포스트 이미지를 기존 경로로 식별할 수 있다.
- 전체 목록 하단 sentinel에서 다음 처리 대상 page를 자동 prefetch한다.
- 총 관리자 failed row에 `삭제 다시 시도` action과 `삭제 처리 중` 상태가 표시된다.
- 브랜드 owner/admin 실행 중 문구는 `삭제를 다시 처리하고 있습니다.`로 표시된다.
- 브랜드 owner/admin 최종 실패 문구는 `관리자 확인이 필요합니다.`로 표시된다.
- 빈 상태와 설명 문구가 처리 대상 중심으로 바뀐다.

검증 방법:

- iOS generic simulator build
- 총 관리자 전역 화면 수동 QA
- 브랜드 owner/admin scoped 화면 수동 QA

논의 필요 사항:

- 없음.

## Phase 6. 통합 검증, 배포, 하네스 최신화

목표:

- 서버와 iOS 계약을 함께 검증하고 운영 하네스를 최신화한다.

예상 변경 범위:

- `docs/ai/tasks/lookbook-deletion-request-list-simplification/progress.md`
- `docs/ai/tasks/lookbook-deletion-request-list-simplification/qa-checklist.md`
- `docs/ai/ENTRYPOINTS.md`
- `docs/ai/entrypoints/LOOKBOOK.md`
- `docs/ai/entrypoints/FIREBASE.md`
- `docs/ai/DATA_SCHEMA.md`
- `HANDOFF.md`

완료 기준:

- Functions lint/build와 iOS build가 통과한다.
- total admin과 brand owner/admin 권한별 목록을 확인한다.
- `active/failed` 표시, 포스트 이미지 식별, 복구 action을 확인한다.
- 50개 이후 요청 scroll prefetch와 중복 제거를 확인한다.
- total admin 즉시 retry, background 실행, lease 동시성, scheduler fallback을 확인한다.
- 브랜드 owner/admin 실행 중/최종 실패 문구를 확인한다.
- `purged/cancelled/restored`가 앱 목록에 나타나지 않음을 확인한다.
- 사용자 승인 후 Functions 운영 배포 결과를 기록한다.

검증 방법:

- `npm run lint`
- `npm run build`
- `xcodebuild -scheme OutPick -destination 'generic/platform=iOS Simulator' build`
- 필요 시 선택된 unit test
- 수동 smoke QA
