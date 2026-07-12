# Lookbook Deletion Request List Simplification QA Checklist

## 설계/범위

- [x] 총 관리자와 브랜드 owner/admin 모두 `active/failed`만 표시하는 정책이 확정됐다.
- [x] 총 관리자 전역 브랜드 grouping 유지가 확정됐다.
- [x] 브랜드 등록 요청 UI는 변경하지 않는다고 분리됐다.
- [x] audit thumbnail 작업 폐기가 확정됐다.
- [x] 앱 미배포 상태라 구버전 API 호환이 필요하지 않다고 확인했다.
- [x] 처리 대상 pagination은 목록 하단 sentinel scroll prefetch로 확정됐다.
- [x] failed purge는 총 관리자 전용 즉시 background retry로 확정됐다.
- [x] scheduled/manual purge는 15분 lease로 동시 실행을 막기로 확정됐다.
- [x] 브랜드 owner/admin 실행 중/최종 실패 문구가 확정됐다.

## Functions/API

- [x] 배포된 목록 callable이 비로그인 요청을 `UNAUTHENTICATED`로 거부한다.

- [x] `listLookbookDeletionRequests` 입력에서 `status`가 제거됐다.
- [x] `statusGroup`이 제거됐다.
- [x] `processedScope`와 `recentProcessedDays`가 제거됐다.
- [x] 서버 query가 `status in [active, failed]`로 고정됐다.
- [x] 총 관리자 전역 조회가 동작한다.
- [x] 브랜드 owner/admin 조회는 `brandID`가 필수다.
- [x] 권한 없는 브랜드 조회가 거부된다.
- [x] target type 필터와 cursor pagination이 유지된다.
- [x] `limit + 1` query가 실제 다음 page가 있을 때만 `nextCursor`를 반환한다.
- [x] 기존 `lookbookDeletionRequests` composite index가 유지됐다.
- [x] Functions lint/build가 통과했다.

## Functions failed purge 재시도/lease

- [x] 총 관리자 전용 `retryFailedLookbookDeletionPurge` callable이 추가됐다.
- [x] 총 관리자가 아니면 재시도가 거부된다.
- [x] `failed`가 아닌 요청은 재시도가 거부된다.
- [x] 기존 requestID를 재사용하고 새 삭제 요청을 만들지 않는다.
- [x] callable은 manual retry token을 기록한 뒤 purge 완료를 기다리지 않고 응답한다.
- [x] `onLookbookDeletionManualRetryQueued` trigger는 token 변경 + queued 상태에서만 purge를 시작한다.
- [x] queued 또는 유효 lease 중복 callable은 새 token 없이 duplicate receipt를 반환한다.
- [x] manual retry 등록 시 `autoRetryEligible = true`, `retryAfter = now`가 기록된다.
- [x] 새 retry cycle의 `purgeAttemptCount`는 0으로 초기화된다.
- [x] 누적 수동 재시도 횟수는 `manualRetryCount`에 기록된다.
- [x] scheduled/manual 경로가 같은 lease claim helper를 사용한다.
- [x] 유효한 lease가 있으면 두 번째 worker가 purge를 시작하지 않는다.
- [x] lease 유효 기간은 15분이다.
- [x] 만료된 lease는 다시 claim할 수 있다.
- [x] stale lease token은 성공/실패 상태를 덮어쓸 수 없다.
- [x] trigger 중복 전달 판정이 같은 token update를 무시한다.
- [x] trigger 실패/timeout 뒤 scheduler fallback metadata가 유지된다.
- [x] 수동 재시도 요청과 purge 결과가 감사 로그에 남도록 구현됐다.
- [x] 목록 응답에 retry UI용 metadata와 서버 계산 `purgeInProgress`가 포함된다.
- [x] lease token은 iOS 응답에 노출되지 않는다.
- [x] lease 순수 helper Node 테스트 5개가 통과했다.
- [ ] Firestore emulator 또는 운영 smoke QA로 실제 동시 claim 한 건만 실행되는지 확인했다.
- [ ] 같은 브랜드의 상하위 purge 직렬화와 scheduler fallback을 실제 데이터로 확인했다.

## iOS Domain/Repository/ViewModel

- [x] `LookbookDeletionRequestStatusGroup`이 제거됐다.
- [x] 삭제 repository 계약에서 `statusGroup/processedScope`가 제거됐다.
- [x] 브랜드 요청의 `ProcessedRequestScope`는 유지됐다.
- [x] ViewModel의 완료/history 상태와 cursor가 제거됐다.
- [x] ViewModel의 완료 group 선택과 history prefetch 동작이 제거됐다.
- [x] 처리 대상 `nextCursor`와 추가 로딩 상태가 추가됐다.
- [x] 목록 하단 sentinel이 다음 page를 한 번만 요청한다.
- [x] page append가 `requestID` 기준 중복을 제거한다.
- [x] 새로고침과 brand scope 변경이 처리 대상 cursor를 초기화한다.
- [x] 총 관리자 failed retry mutation 중 중복 탭이 차단된다.
- [x] 초기 로드와 새로고침이 처리 대상 목록을 정상적으로 가져온다.
- [x] 복구 mutation 뒤 목록이 갱신된다.
- [x] non-total-admin에서 brand target이 노출되지 않는다.

## iOS 화면

- [x] 처리 중/완료 segmented picker가 표시되지 않는다.
- [x] 최근 14일 완료 목록이 표시되지 않는다.
- [x] 이전 완료 기록 버튼과 섹션이 표시되지 않는다.
- [x] 총 관리자 전역 목록이 브랜드별로 묶인다.
- [x] 브랜드 row 접기/펼치기가 동작한다.
- [x] 펼친 영역에서 브랜드/시즌/포스트 요청이 target별로 표시된다.
- [x] 브랜드 owner/admin은 권한 브랜드의 시즌/포스트 요청만 본다.
- [x] 포스트 `active/failed` row에서 이미지로 대상을 식별할 수 있다.
- [x] `active` 요청의 복구 action이 유지된다.
- [x] `failed` 요청이 목록에서 숨겨지지 않는다.
- [x] 총 관리자 failed row에 `삭제 다시 시도`가 표시된다.
- [x] 총 관리자 queued/running row는 `삭제 처리 중`으로 표시되고 action이 비활성화된다.
- [x] 브랜드 owner/admin auto retry 예정 또는 queued/running/실행 중 row에 `삭제를 다시 처리하고 있습니다.`가 표시된다.
- [x] 브랜드 owner/admin 최종 failed row에 `관리자 확인이 필요합니다.`가 표시된다.
- [x] 브랜드 owner/admin에게 retry action이 표시되지 않는다.
- [x] 빈 상태 문구가 `처리할 삭제 요청이 없습니다.`로 표시된다.

## 데이터/감사

- [x] `purged` projection을 삭제하는 migration이 추가되지 않았다.
- [x] `lookbookDeletionAuditLogs` 기록 정책이 유지됐다.
- [x] audit thumbnail Storage prefix 또는 파생 이미지 생성 코드가 추가되지 않았다.
- [x] purge 시 기존 원본 Storage 삭제 정책이 유지됐다.

## 자동 테스트 설계

테스트 대상:

- `AdminLookbookDeletionManagementViewModel`
- `LookbookDeletionRepositoryProtocol` fake/spy
- `listLookbookDeletionRequests` query 입력 계약

필요한 테스트:

- 초기 로드가 별도 완료 scope 없이 목록 repository를 한 번 호출한다.
- 목록 하단 prefetch가 cursor page를 append하고 requestID 중복을 제거한다.
- 동시에 여러 prefetch가 들어와도 repository 호출이 한 번만 진행된다.
- total admin 전역 모드는 `brandID = nil`로 조회한다.
- brand-scoped 모드는 해당 `brandID`로 조회한다.
- non-total-admin은 응답에 섞인 brand target을 화면 상태에서 제거한다.
- 복구 성공 후 처리 대상 목록을 다시 불러온다.
- repository 실패 시 빈 목록과 오류 메시지를 남긴다.
- total admin failed retry가 repository mutation을 호출하고 상태를 갱신한다.
- brand owner/admin은 retry mutation을 호출할 수 없다.
- scheduled/manual 동시 claim에서 한 worker만 성공한다.
- 만료 lease는 재획득되고 유효 lease는 거부된다.
- stale lease token finalize는 무시된다.

수동 QA 항목:

- 총 관리자 전역 브랜드 grouping과 접기/펼치기.
- 포스트 이미지 표시와 복구 대상 식별.
- 처리 대상 50개 이후 scroll prefetch.
- 총 관리자 retry tap 후 queued/running/성공/재실패 표시.
- 브랜드 owner/admin 실행 중/최종 실패 문구.
- 브랜드 owner/admin 권한별 노출.
- 로딩/빈 상태/오류 문구.
- 완료 picker/history UI 제거 상태.

보류할 테스트와 이유:

- SwiftUI snapshot test는 현재 UI 인프라 대비 단순 제거 작업이라 수동 QA를 우선한다.
- Firebase emulator integration test는 준비 상태를 재확인하되, lease/중복 실행처럼 재현이 어려운 핵심 경계는 순수 helper unit test 또는 emulator test 중 가능한 방식으로 반드시 자동 검증한다.

테스트 실행 여부:

- 구현 단계에서 삭제 신뢰 기능의 회귀 비용이 크므로 Functions lint/build와 iOS build는 우선 수행한다.
- unit test를 작성하면 사용자 명시 요청이 없더라도 build-for-testing까지 수행하고, 실제 test 실행 여부는 구현 보고에서 명시한다.

## 문서/배포

- [x] 폐기된 `post-deletion-audit-thumbnail` 구현 task 문서가 제거되고 역사적 결정만 남았다.
- [x] `docs/ai/ENTRYPOINTS.md`가 최신이다.
- [x] `docs/ai/entrypoints/LOOKBOOK.md`가 최신이다.
- [x] `docs/ai/entrypoints/FIREBASE.md`가 최신이다.
- [x] `docs/ai/DATA_SCHEMA.md`가 최신이다.
- [x] `HANDOFF.md`가 최신이다.
- [x] Functions 배포는 사용자 승인 후 실행했다.
