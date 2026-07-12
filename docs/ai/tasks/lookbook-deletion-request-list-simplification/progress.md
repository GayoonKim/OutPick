# Lookbook Deletion Request List Simplification Progress

## 최종 상태

- 상태: 완료
- 2026-07-13 Phase 2~6 구현, 자동 검증, Functions 운영 배포를 완료했다.
- 사용자가 총 관리자와 브랜드 owner/admin 삭제 요청 목록 화면을 직접 확인하고 작업 마감을 승인했다.
- 실제 lease 경쟁과 scheduler fallback을 운영 데이터로 강제 재현하는 destructive QA는 필수 완료 기준에서 제외하고 후속 운영 회귀 QA로 남긴다.

## 2026-07-12 설계 시작

- 사용자 결정으로 다음 핵심 작업을 `lookbook-deletion-request-list-simplification`으로 등록했다.
- 배경:
  - `purged` 완료 요청은 앱에서 더 이상 복구하거나 변경할 action이 없다.
  - 포스트는 제목이 없지만 복구 가능한 `active/failed` 기간에는 원본 썸네일로 식별할 수 있다.
  - 완료 요청을 앱에서 제거하면 purge 이후 별도 audit thumbnail을 보존할 필요가 없다.
- 확정 방향:
  - 총 관리자와 브랜드 owner/admin 모두 삭제 요청 화면에서 `active/failed`만 본다.
  - 총 관리자 전역 브랜드별 grouping은 유지한다.
  - 처리 중/완료 picker와 완료/history UI를 제거한다.
  - 삭제 요청 전용 `processed` API 계약을 제거한다.
  - 앱 미배포 상태이므로 구버전 API 호환은 고려하지 않는다.
  - `purged` projection과 감사 로그는 서버 운영 이력으로 유지한다.
  - 브랜드 등록 요청의 보류/완료 이력은 유지한다.
  - `post-deletion-audit-thumbnail` 작업은 폐기한다.
  - 처리 대상 다음 page는 목록 하단 sentinel 기반 scroll prefetch로 불러온다.
  - 제거된 완료 조회 입력은 iOS/Repository/Functions 경계에서 모두 삭제하고 별도 deprecated-field 거부 로직은 추가하지 않는다.
  - failed purge는 총 관리자 전용 callable이 manual retry token을 기록하고 Firestore trigger가 즉시 background 실행한다.
  - scheduled/manual purge는 공통 15분 lease로 동시 실행을 막고 scheduler fallback을 유지한다.
  - 브랜드 owner/admin 실행 중 문구는 `삭제를 다시 처리하고 있습니다.`, 최종 실패 문구는 `관리자 확인이 필요합니다.`로 확정했다.
- 현재 상태:
  - 설계, 결정, phase 계획, QA 체크리스트 문서화 완료.
  - Phase 2 Functions 목록 계약 단순화 구현 완료.
  - Phase 3 failed purge 즉시 retry/trigger/lease 구현과 자동 테스트 완료.
  - Phase 4 iOS Domain/Repository/ViewModel 단순화와 빌드 가능한 범위의 완료/history UI 제거를 완료했다.
  - Phase 5 iOS 화면 단순화를 완료했다.
  - 2026-07-13 Functions 운영 배포를 완료했다.

## 2026-07-12 Phase 2 Functions 목록 계약 단순화

- `listLookbookDeletionRequests`에서 삭제 요청 전용 `status`, `statusGroup`, `processedScope`, `recentProcessedDays` 입력 파싱과 완료 query 분기를 제거했다.
- 서버 query를 `status in [active, failed]`로 고정했다.
- `targetType`, `brandID`, `limit`, cursor와 권한 검증은 유지했다.
- `limit + 1`개를 조회하고 첫 `limit`개만 반환해 실제 다음 page가 있을 때만 `nextCursor`를 반환하도록 바꿨다.
- 삭제 요청 전용 status/status group type과 parser helper를 제거했다.
- 브랜드 요청용 `ProcessedRequestScope`와 최근 처리 기간 상수는 유지했다.
- 기존 `lookbookDeletionRequests` composite index는 `active/failed` 조회와 purge에도 필요하므로 변경하지 않았다.
- 검증:
  - `functions` `npm run lint` 통과.
  - `functions` `npm run build` 통과.
  - 운영 smoke query는 Functions 미배포 상태라 보류했다.
- Functions 운영 배포는 수행하지 않았다.

## 2026-07-12 Phase 3 failed purge 즉시 retry/trigger/lease

- 총 관리자 전용 callable `retryFailedLookbookDeletionPurge`를 추가했다.
  - `failed` 기존 requestID만 허용한다.
  - 새 manual retry token, `queued`, `autoRetryEligible = true`, `retryAfter = now`를 transaction으로 기록한다.
  - 새 request를 만들지 않고 `purgeAttemptCount`는 새 cycle 기준 0으로 초기화하며 `manualRetryCount`는 누적한다.
  - queued 또는 유효 request lease 중복 요청은 duplicate receipt를 반환한다.
- Firestore update trigger `onLookbookDeletionManualRetryQueued`를 추가했다.
  - token이 바뀌고 새 상태가 queued일 때만 실행한다.
  - callable 응답과 분리된 background purge를 즉시 시작한다.
  - trigger 오류는 request/audit에 기록하고 scheduler fallback을 유지한다.
- scheduled/manual 공통 purge lease를 구현했다.
  - `lookbookDeletionPurgeLeases/{brandID}` 브랜드 단위로 15분 lease를 claim한다.
  - 같은 브랜드의 브랜드/시즌/포스트 purge를 직렬화한다.
  - request와 lease 문서 token이 모두 실행 token과 같을 때만 finalize한다.
  - 만료 lease는 다시 claim할 수 있다.
- 기존 scheduled purge도 공통 claim/run 경로로 전환했다.
- 목록 응답에 `autoRetryEligible`, `retryAfter`, `purgeAttemptCount`, 총 관리자용 정제 오류, `manualRetryState`, `manualRetryCount`, `purgeInProgress`를 추가했다.
  - lease token은 응답에 포함하지 않는다.
  - 브랜드 owner/admin에는 purge 오류 원문을 반환하지 않는다.
- 순수 lease helper와 Node 테스트를 추가했다.
  - lease 만료 경계.
  - 새 queued token trigger 조건.
  - stale finalize token 차단.
  - queued/유효 lease duplicate 판정.
- 검증:
  - `functions` `npm test` 5개 통과.
  - `functions` `npm run lint` 통과.
  - `functions` `npm run build` 통과.
- 운영 배포와 destructive smoke QA는 수행하지 않았다.

## 2026-07-13 Phase 4 iOS Domain/Repository/ViewModel 단순화

- `LookbookDeletionRequestStatusGroup`과 삭제 요청 전용 `statusGroup/processedScope` iOS 입력을 제거했다.
- 삭제 요청 entity에 자동 재시도, 시도 횟수, 정제 오류, manual retry 상태/횟수, purge 실행 여부 metadata를 추가했다.
- repository와 `CloudFunctionsManager`에 `retryFailedLookbookDeletionPurge` callable receipt 매핑을 추가했다.
- ViewModel의 완료/history 목록, cursor, group 선택, history prefetch 상태를 제거했다.
- 처리 대상 첫 page cursor와 추가 로딩 상태를 추가하고 page append를 `requestID` 기준으로 중복 제거한다.
- 총 관리자 failed retry mutation을 추가하고 기존 단일 mutation key로 중복 실행을 차단한다.
- status group 타입 제거 후에도 빌드 가능하도록 Phase 5 예정 범위 중 picker와 완료/history UI 제거를 함께 반영했다.
- fake repository 기반 ViewModel 테스트 4개를 추가했다.
  - 첫 page 교체와 next cursor 저장.
  - 다음 page append, requestID 중복 제거, 마지막 cursor 종료.
  - 동시 next page 요청의 repository 중복 호출 차단.
  - total admin + failed 상태 retry 권한 경계.
- 검증:
  - generic iOS Simulator build 통과.
  - build-for-testing 통과.
  - 선택 단위 테스트 4개 통과.
  - `git diff --check` 통과.
- Phase 5에는 목록 하단 sentinel UI 연결, retry 버튼/실행 상태, 브랜드 owner/admin 문구를 반영한다.

## 2026-07-13 Phase 5 iOS 삭제 요청 화면 단순화

- 전체 삭제 요청 목록 아래에 공통 pagination sentinel을 연결했다.
  - next cursor가 있을 때만 나타난다.
  - 로딩 중에는 하단 진행 표시를 보여주고 나머지는 1pt 투명 감지 영역을 사용한다.
  - sentinel `onAppear`가 ViewModel의 중복 방지된 다음 page 로드를 호출한다.
- 총 관리자 failed row UX를 추가했다.
  - queued/running 또는 유효 purge lease 중에는 상태를 `삭제 처리 중`으로 표시한다.
  - 실행 중이 아닌 failed 요청에는 `삭제 다시 시도` action을 제공한다.
- 브랜드 owner/admin failed row UX를 추가했다.
  - 자동 재시도 대상, queued/running 또는 purge 실행 중이면 `삭제를 다시 처리하고 있습니다.`를 표시한다.
  - 그 외 최종 실패에는 `관리자 확인이 필요합니다.`를 표시한다.
- 목록 보조 문구와 빈 상태를 처리 대상 중심으로 변경했다.
- retry 표시 상태 조합을 domain 계산 속성으로 두고 단위 테스트를 추가했다.
- 검증:
  - generic iOS Simulator build 통과.
  - ViewModel/domain 선택 테스트 5개 통과.
  - `git diff --check` 통과.
- 실제 Firebase 데이터와 권한 계정별 수동 QA는 Phase 6에 남아 있다.

## 2026-07-13 Phase 6 통합 검증과 운영 배포

- 배포 전 Functions 검증:
  - `npm test` lease/trigger helper 5개 통과.
  - `npm run lint` 통과.
  - `npm run build` 통과.
- iOS 검증:
  - `AdminLookbookDeletionManagementViewModelTests` 선택 테스트 5개 통과.
  - generic iOS Simulator build 통과.
  - 기존 linker search path 경고는 남지만 빌드는 성공했다.
- `firebase deploy --only functions --project outpick-664ae` 운영 배포 완료.
  - `retryFailedLookbookDeletionPurge` callable 생성 성공.
  - `onLookbookDeletionManualRetryQueued` Firestore update trigger 생성 성공.
  - `listLookbookDeletionRequests`, `purgeExpiredLookbookDeletions` 업데이트 성공.
  - 기존 Functions 삭제 요청은 발생하지 않았다.
- 배포 후 `firebase functions:list`에서 위 네 함수의 v2/asia-northeast3/Node.js 24 등록을 확인했다.
- 배포된 `listLookbookDeletionRequests`에 비로그인 POST를 보내 `401 UNAUTHENTICATED`와 `로그인이 필요합니다.` 응답을 확인했다.
- 정적 불변 조건 재확인:
  - `purged` projection과 `lookbookDeletionAuditLogs` 기록 경로 유지.
  - audit thumbnail 생성/Storage prefix 미추가.
  - 기존 purge Storage 삭제 정책 유지.
- 보류된 운영 QA:
  - 총 관리자/브랜드 owner/admin 로그인 계정별 실제 목록 조회.
  - 안전한 failed 요청을 이용한 manual retry → trigger → lease → 성공/재실패.
  - 50개 초과 실제 목록의 sentinel pagination.
  - 실제 데이터를 만드는 destructive smoke QA는 별도 테스트 대상과 승인 없이 수행하지 않았다.
- 사용자 수동 확인:
  - 총 관리자와 브랜드 owner/admin 삭제 요청 목록 UI 확인 완료.
  - 중복 섹션 제목 제거 상태 확인 완료.
  - 2026-07-13 사용자 승인으로 핵심 작업을 완료 마감했다.
