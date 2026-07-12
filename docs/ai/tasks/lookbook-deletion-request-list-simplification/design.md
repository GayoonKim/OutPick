# Lookbook Deletion Request List Simplification Design

## 목표

브랜드/시즌/포스트 삭제 요청 화면을 복구 또는 운영 대응이 가능한 요청에 집중하도록 단순화한다.

현재 앱은 삭제 요청을 `처리 중(active/failed)`과 `완료(purged)`로 나누고, 완료 요청의 최근 14일 및 이전 이력까지 조회한다. 영구 삭제가 완료된 `purged` 요청은 앱에서 더 이상 복구하거나 변경할 수 없으므로 앱 UI에서 제거하고 서버 감사 기록으로만 유지한다.

핵심 목표는 다음과 같다.

1. 총 관리자와 브랜드 owner/admin 삭제 요청 화면에는 `active`와 `failed`만 표시한다.
2. 총 관리자 전역 목록의 기존 브랜드별 접기/펼치기 구조는 유지한다.
3. 복구 가능 기간에는 원본 썸네일을 이용해 포스트를 이미지로 식별한다.
4. `purged`, `cancelled`, `restored` 요청은 앱 목록에 표시하지 않는다.
5. 삭제 요청 전용 `processed`/history 조회 계약과 클라이언트 상태를 제거한다.
6. `purged` projection과 감사 로그는 서버 운영 이력으로 유지한다.
7. purge 이후 별도 audit thumbnail은 생성하거나 보존하지 않는다.

## 요구사항 정리

- 총 관리자 전역 삭제 요청 목록은 권한 범위 전체의 `active/failed` 요청을 브랜드별로 묶어 표시한다.
- 브랜드 owner/admin 삭제 요청 목록은 선택된 권한 브랜드의 시즌/포스트 `active/failed` 요청만 표시한다.
- 브랜드 삭제 요청과 복구 UI는 기존대로 총 관리자에게만 제공한다.
- `active` 포스트 요청에는 원본이 purge되기 전이므로 기존 `postImageThumbPath` 또는 `targetImagePath`를 이용해 식별 이미지를 표시한다.
- `failed` 요청은 실제 영구 삭제가 끝나지 않은 운영 대응 대상이므로 목록에서 숨기지 않는다.
- `purged`, `cancelled`, `restored`는 앱 목록에서 제외한다.
- 처리 중/완료 segmented picker, 최근 14일 완료 목록, 이전 완료 기록 버튼과 pagination을 제거한다.
- 브랜드 등록 요청 화면의 `새 요청/처리 중/보류/완료` 구조와 `ProcessedRequestScope`는 이번 작업 범위에서 변경하지 않는다.
- 삭제 요청 projection과 `lookbookDeletionAuditLogs`의 기록 정책은 유지한다.

## 구현 디테일 정리

### 서버 조회 계약

- `listLookbookDeletionRequests`는 삭제 관리 앱이 실제로 사용하는 `status in [active, failed]`만 조회한다.
- 삭제 요청 조회 입력에서 다음 필드를 제거한다.
  - `status`
  - `statusGroup`
  - `processedScope`
  - `recentProcessedDays`
- `targetType`, `brandID`, `limit`, cursor 계약은 유지한다.
- 앱 미배포 상태이므로 구버전 호환 분기를 유지하지 않고 Functions와 iOS 계약을 같은 작업에서 정리한다.
- `limit + 1`개를 조회해 실제 다음 page가 있을 때만 `nextCursor`를 반환한다.
- 기존 `lookbookDeletionRequests` composite index는 `active/failed` 조회에도 필요하므로 유지한다.

### 실패 요청 즉시 재시도

- 총 관리자 전용 callable `retryFailedLookbookDeletionPurge`를 추가한다.
- callable은 장시간 cascade purge를 직접 기다리지 않고, transaction으로 manual retry token과 실행 metadata를 기록한 뒤 즉시 응답한다.
- Firestore update trigger `onLookbookDeletionManualRetryQueued`는 `before.manualRetryToken != after.manualRetryToken && after.manualRetryState == queued`일 때만 기존 idempotent purge helper를 즉시 실행한다.
- 기존 scheduled purge와 manual trigger는 같은 lease claim helper를 사용한다.
- manual trigger가 실행되지 않거나 timeout되면 기존 scheduler가 fallback으로 처리할 수 있도록 `autoRetryEligible = true`, `retryAfter = now`를 함께 기록한다.

추가 metadata 후보:

```text
manualRetryState: queued | running | failed | null
manualRetryToken
manualRetryCount
manualRetryRequestedAt
manualRetryRequestedBy
purgeLeaseToken
purgeLeaseUntil
purgeExecutionSource: scheduled | manual
```

callable 허용 조건:

- 총 관리자만 호출할 수 있다.
- `status == failed` 요청만 재시도할 수 있다.
- `queued` manual retry 또는 유효한 request lease가 있으면 새 token을 만들지 않고 `duplicate = true` receipt를 반환한다. lease가 만료된 stale `running`은 새 retry를 허용한다.
- 기존 requestID를 재사용하고 새 삭제 요청 문서를 만들지 않는다.
- 새 재시도 cycle을 위해 `purgeAttemptCount = 0`으로 초기화하고 누적 수동 재시도 횟수는 `manualRetryCount`에 남긴다.
- 재시도 요청과 실행 결과를 `lookbookDeletionAuditLogs`에 기록한다.

### 동시 실행 방지

- 실행 직전 Firestore transaction으로 lease를 claim한다.
- `purgeLeaseUntil > now`인 유효 lease가 있으면 다른 scheduled/manual 실행은 purge를 시작하지 않는다.
- lease 유효 기간은 Functions 최대 실행 시간 540초보다 긴 15분으로 둔다.
- purge 성공/실패 결과 반영 시 실행자가 가진 `purgeLeaseToken`과 문서 token이 같은지 확인한다.
- Functions timeout 또는 비정상 종료로 lease가 남아도 15분 후 scheduler/manual 실행이 다시 claim할 수 있다.
- scheduled와 manual 경로 모두 같은 claim/finalize helper를 사용한다.

### iOS 도메인/Repository

- `LookbookDeletionRequestStatusGroup`을 제거한다.
- `LookbookDeletionRequestStatus`는 저장된 상태와 서버 데이터 계약을 표현하므로 `active/cancelled/restored/purged/failed` 값을 유지한다.
- `LookbookDeletionRepositoryProtocol.listDeletionRequests`에서 `statusGroup`과 `processedScope`를 제거한다.
- `CloudFunctionsLookbookDeletionRepository`와 `CloudFunctionsManager`도 단순화된 입력만 전달한다.
- 브랜드 요청에서 사용하는 `ProcessedRequestScope`는 유지한다.
- 목록 응답과 iOS entity에 `autoRetryEligible`, `retryAfter`, `purgeAttemptCount`, `purgeErrorMessage`, `manualRetryState`, `manualRetryCount`, 서버 계산값 `purgeInProgress`를 추가한다.
- lease token 자체는 서버 동시성 제어 정보이므로 iOS 응답에 노출하지 않는다.
- Repository에 총 관리자 전용 failed purge 재시도 mutation 계약을 추가한다.

### ViewModel

다음 완료/history 전용 상태와 동작을 제거한다.

- `historicalDeletionRequests`
- `selectedRequestStatusGroup`
- `isHistoricalDeletionRequestsVisible`
- history 로딩/pagination 상태와 cursor
- 완료 group 선택, 이전 완료 기록 열기, history prefetch 메서드

`reloadDeletionRequests`는 항상 현재 권한 범위의 `active/failed` 첫 page를 가져온다.

처리 대상 pagination 상태와 동작을 추가한다.

- `deletionRequestsNextCursor`
- `isLoadingMoreDeletionRequests`
- 목록 하단 sentinel에서 호출하는 `loadMoreDeletionRequestsIfNeeded`
- page append 시 `requestID` 기준 중복 제거
- 새로고침/brand scope 변경 시 cursor 초기화

failed 재시도 mutation 상태를 관리하고 중복 탭을 막는다.

### View

- `requestStatusGroupPicker`를 제거한다.
- `historicalDeletionRequestsSection`과 history prefetch 연결을 제거한다.
- 삭제 요청 목록 제목과 빈 상태 문구를 처리 가능한 요청 중심으로 바꾼다.
- 총 관리자 전역 화면의 브랜드별 grouping과 target별 하위 섹션은 유지한다.
- 브랜드 scoped 화면의 기존 row와 복구 action은 유지한다.
- 개별 요청 row나 펼친 target row가 아니라 전체 목록 아래의 공통 sentinel로 scroll prefetch를 트리거한다.
- 총 관리자 `failed` row는 `삭제 다시 시도` action을 제공하고 queued/running 또는 `purgeInProgress` 동안 `삭제 처리 중`으로 비활성화한다.
- 브랜드 owner/admin은 `autoRetryEligible`, queued/running 또는 `purgeInProgress`이면 `삭제를 다시 처리하고 있습니다.`를 본다.
- 브랜드 owner/admin은 자동/수동 재시도 대상이 아니고 실행 중도 아닌 최종 failed 상태에서 `관리자 확인이 필요합니다.`를 본다.

## 제약 조건 정리

- 기존 7일 복구 가능 기간과 scheduled purge lifecycle은 변경하지 않는다.
- `active/failed` 요청에 대한 권한 검증, 복구 action, 이미지 표시를 깨뜨리지 않는다.
- 브랜드 등록 요청의 보류/완료 이력은 변경하지 않는다.
- `purged` projection과 감사 로그를 삭제하거나 데이터 마이그레이션하지 않는다.
- purge 이후 원본 또는 파생 이미지를 완료 목록 표시 목적으로 보존하지 않는다.
- Functions 계약 변경은 lint/build와 운영 배포가 필요하다.
- 앱 미배포 상태이므로 구버전 API 호환은 제약 조건이 아니다.
- 구현 전 사용자가 코드 수정과 운영 배포를 각각 승인해야 한다.
- manual purge는 callable 응답 안에서 완료를 기다리지 않고 background trigger가 즉시 시작한다.

## 완료 기준 정리

- 총 관리자 전역 삭제 요청 목록에 `active/failed` 요청만 브랜드별로 표시된다.
- 브랜드 owner/admin 삭제 요청 목록에 권한 브랜드의 시즌/포스트 `active/failed` 요청만 표시된다.
- 처리 중/완료 picker와 완료/history UI가 제거된다.
- 포스트 `active` 요청은 기존 원본 썸네일로 식별할 수 있다.
- `purged`, `cancelled`, `restored` 요청은 앱 목록에 표시되지 않는다.
- 삭제 요청 API와 iOS Repository에서 `statusGroup`/`processedScope` 계약이 제거된다.
- scroll prefetch로 50개 이후의 `active/failed` 요청도 누락 없이 추가 표시된다.
- 서버는 실제 다음 page가 있을 때만 `nextCursor`를 반환한다.
- 총 관리자가 failed purge를 즉시 background 재시도할 수 있다.
- scheduled/manual 동시 실행에서 하나의 worker만 lease를 획득한다.
- trigger 실패나 timeout 이후 scheduler fallback이 가능하다.
- 브랜드 owner/admin에는 실행 중 `삭제를 다시 처리하고 있습니다.`, 최종 실패 `관리자 확인이 필요합니다.`가 표시된다.
- `purged` projection과 감사 로그는 서버에 그대로 남는다.
- `post-deletion-audit-thumbnail` 작업과 관련 참조가 제거된다.
- 관련 ENTRYPOINTS, LOOKBOOK, FIREBASE, DATA_SCHEMA, HANDOFF 문서가 구현 결과와 일치한다.

## 구현 가능성 검증

확인한 진입점:

- `functions/src/index.ts`
  - `listLookbookDeletionRequests`
- `OutPick/Features/Lookbook/Views/Admin/AdminLookbookDeletionManagementView.swift`
- `OutPick/Features/Lookbook/ViewModels/AdminLookbookDeletionManagementViewModel.swift`
- `OutPick/Features/Lookbook/Domains/Entities/LookbookDeletionRequest.swift`
- `OutPick/Features/Lookbook/Repositories/Protocols/LookbookDeletionRepositoryProtocol.swift`
- `OutPick/Features/Lookbook/Repositories/Implementations/CloudFunctionsLookbookDeletionRepository.swift`
- `OutPick/DB/Firebase/CloudFunctions/CloudFunctionsManager.swift`
- `firestore.indexes.json`

가능성 판단:

- 현재 서버의 기본 분기가 이미 `active/failed` query를 사용하므로 완료 분기와 입력 파라미터를 제거하는 방식으로 단순화할 수 있다.
- 총 관리자 전역 브랜드 grouping은 View의 순수 표시 로직이므로 status picker/history만 제거하고 유지할 수 있다.
- 완료/history 상태가 ViewModel에 분리되어 있어 삭제 범위를 특정할 수 있다.
- 포스트 복구 가능 기간에는 원본 Storage asset이 purge되지 않으므로 기존 이미지 표시 경로를 유지할 수 있다.
- 현재 purge helper가 없는 문서와 Storage 삭제를 허용하는 idempotent 구조이므로 scheduled/manual 경로에서 공유할 수 있다.
- 기존 Firestore update trigger 패턴이 있어 manual retry token 기반 background 실행을 같은 Functions 프로젝트 안에서 구성할 수 있다.

## 기술 스택 선정

- iOS: 기존 SwiftUI + MVVM-C + Repository + DI 구조 유지.
- 서버: 기존 Firebase callable `listLookbookDeletionRequests` 단순화.
- 데이터: 기존 `lookbookDeletionRequests`와 `lookbookDeletionAuditLogs` 유지.
- 이미지: 기존 원본 thumb path만 복구 가능 기간에 사용하며 신규 이미지 파생본은 만들지 않는다.
- 테스트: ViewModel fake repository 기반 unit test와 Functions query 계약 검증, 화면은 수동 QA 우선.
- 동시성 테스트: lease claim/finalize와 trigger 중복 전달은 순수 helper 또는 Firestore emulator 기반 자동 테스트를 우선한다.

## 사용자 흐름 점검

### 총 관리자

1. 총 관리자 콘솔에서 삭제 요청 목록에 진입한다.
2. `active/failed` 요청이 브랜드별로 표시된다.
3. 브랜드 row를 펼치면 브랜드/시즌/포스트 요청을 확인한다.
4. 포스트는 이미지로 식별한다.
5. 복구 가능한 요청은 복구하고, 실패 요청은 상태를 확인한다.
6. failed 요청에서 `삭제 다시 시도`를 누르면 background purge가 즉시 시작된다.
7. queued/running 동안 `삭제 처리 중`으로 표시된다.
8. purge가 완료된 요청은 다음 조회부터 목록에서 사라진다.

### 브랜드 owner/admin

1. 권한 브랜드의 삭제 관리 화면에 진입한다.
2. 시즌/포스트 `active/failed` 요청만 확인한다.
3. 포스트는 이미지로 식별하고 복구할 수 있다.
4. 브랜드 target 요청은 기존 권한 정책대로 보이지 않는다.
5. failed 요청이 실행 중이면 `삭제를 다시 처리하고 있습니다.`, 최종 실패면 `관리자 확인이 필요합니다.`를 본다.

## 화면 설계

- 별도의 status segment를 두지 않는다.
- 화면 제목은 `삭제 요청 목록`을 유지한다.
- 보조 문구는 `복구 가능하거나 처리가 필요한 삭제 요청을 확인합니다.`로 정리한다.
- 총 관리자 전역 목록:
  - 브랜드별 접기/펼치기 유지.
  - 펼친 영역에서 브랜드/시즌/포스트 target별 요청 표시.
- 브랜드 scoped 목록:
  - 기존 row 목록 유지.
- 목록 pagination:
  - 전체 목록 아래 sentinel이 보이면 다음 cursor page를 자동으로 불러온다.
  - 브랜드 접힘 여부와 무관하게 동작한다.
- failed row:
  - 총 관리자: `삭제 다시 시도` 또는 `삭제 처리 중`.
  - 브랜드 owner/admin 자동 재시도 예정/실행 중: `삭제를 다시 처리하고 있습니다.`
  - 브랜드 owner/admin 최종 실패: `관리자 확인이 필요합니다.`
- 빈 상태:
  - `처리할 삭제 요청이 없습니다.`

## API 설계

### `listLookbookDeletionRequests` 입력

```text
targetType?: brand | season | post
brandID?: string
limit?: number
cursorUpdatedAt?: ISO timestamp
cursorRequestID?: string
```

서버 내부 고정 조건:

```text
status in [active, failed]
```

응답 page와 cursor 구조는 유지한다.

### `retryFailedLookbookDeletionPurge` 입력

```text
requestID: string
```

응답:

```text
requestID
manualRetryToken
manualRetryState: queued
duplicate: boolean
```

이미 queued 또는 lease 실행 중인 중복 요청이면 `manualRetryToken`은 기존 값 또는 `null`일 수 있다.

callable은 purge 완료를 기다리지 않는다. manual retry token 저장이 성공하면 응답하고, Firestore trigger가 즉시 실행을 이어받는다.

## 데이터 설계

- Firestore schema 변경은 없다.
- `lookbookDeletionRequests/{requestID}`의 모든 lifecycle 상태는 유지한다.
- `lookbookDeletionAuditLogs/{logID}`도 유지한다.
- 이번 작업은 앱 조회 범위와 API 입력 계약을 줄이는 작업이며 기존 운영 이력을 삭제하는 작업이 아니다.
- 완료 projection과 감사 로그의 장기 보존 기간은 별도 운영 정책 논의 대상이며 이번 구현의 blocker는 아니다.
- manual retry/lease metadata는 `lookbookDeletionRequests/{requestID}`에 저장한다.

## 코드 아키텍처 설계

- View는 picker/history UI를 제거하고 브랜드 grouping과 row 렌더링에 집중한다.
- ViewModel은 현재 처리 대상 목록과 mutation 상태만 관리한다.
- Repository는 삭제 요청 목록 callable 구현을 숨기는 기존 경계를 유지한다.
- Functions가 권한별 brand scope와 `active/failed` query를 강제한다.
- Functions callable은 재시도 권한과 입력을 검증하고 background trigger가 purge 실행을 담당한다.
- scheduled/manual purge는 공통 lease claim/finalize와 idempotent target purge helper를 사용한다.
- Coordinator, Container, CompositionRoot, DI 조립 변경은 예상하지 않는다.

## 정책 리스크 점검

- P1 Privacy/Data: purge 이후 이미지 파생본을 만들지 않아 콘텐츠 보존 범위가 줄어든다.
- P1 UGC/Safety: `failed` 요청을 숨기면 실제 삭제가 완료되지 않은 콘텐츠가 운영상 방치될 수 있으므로 반드시 처리 대상 목록에 유지한다.
- P2 Technical Reviewability: 총 관리자와 브랜드 owner/admin 권한별 빈 상태와 요청 표시가 달라 수동 QA 계정이 필요하다.
- P0 Data Integrity: scheduled/manual purge 중복 실행은 partial cascade와 상태 덮어쓰기 위험이 있어 lease token 검증이 필수다.
- 이 작업은 새로운 개인정보 수집, 권한 요청, 외부 전송을 추가하지 않는다.
- 최신 Apple 조항 번호 확인이 구현 방향을 바꾸는 사안은 현재 확인되지 않았다.

## 구현 전 결정사항 점검

확정:

- 완료 목록 제거는 총 관리자와 브랜드 owner/admin 모두에 적용한다.
- `active/failed`만 앱에서 표시한다.
- 총 관리자 브랜드 grouping은 유지한다.
- 삭제 요청 전용 `processed` API 계약은 제거한다.
- 앱 미배포 상태이므로 구버전 호환은 고려하지 않는다.
- audit thumbnail 작업은 폐기한다.
- 브랜드 등록 요청의 보류/완료 이력은 유지한다.
- 처리 대상 다음 page는 목록 하단 sentinel 기반 scroll prefetch로 불러온다.
- 제거된 완료 조회 입력은 모든 iOS/Repository/Functions 경계에서 삭제하며 별도 deprecated-field 거부 로직은 추가하지 않는다.
- failed purge는 총 관리자 전용 callable과 Firestore trigger로 즉시 background 재시도한다.
- scheduled/manual purge는 15분 lease로 동시 실행을 막고 scheduler를 fallback으로 유지한다.
- 브랜드 owner/admin 실행 중 문구는 `삭제를 다시 처리하고 있습니다.`, 최종 실패 문구는 `관리자 확인이 필요합니다.`로 한다.

후속 논의이며 이번 작업 blocker 아님:

- 완료 projection과 감사 로그의 보존 기간.
