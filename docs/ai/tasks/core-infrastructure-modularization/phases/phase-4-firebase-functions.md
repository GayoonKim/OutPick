# Phase 4 Firebase Functions Implementation Plan

## 상태와 목표

- D20~D26과 추가 논의 A안 3개를 사용자 승인으로 확정했다.
- Step 4A~4I 구현과 자동 검증을 완료했다.
- 운영 배포와 emulator/운영 smoke는 별도 사용자 승인을 받는다.

`functions/src/index.ts`의 7,809줄 구현을 기능 하위 도메인과 작업 단위 service로 이동한다. 기존 default codebase, 49개 export 이름, payload/response, `HttpsError`, runtime metadata와 부작용 순서를 유지하고 `index.ts`는 명시적 flat export만 남긴다.

## 추가 확정 결정

### P4-A. 필요한 책임만 파일로 분리한다

- 모든 feature에 같은 파일 세트를 강제하지 않는다.
- `functions.ts`는 trigger 등록, auth/payload 검증, service 호출과 response/error 변환만 소유한다.
- 독립적인 변경 이유가 있을 때만 `service`, `validator`, `mapper`, `policy`, query/storage helper를 추가한다.
- 단순 feature는 `functions.ts` 하나를 허용한다.

### P4-B. 복잡한 service에만 dependency seam을 둔다

- Auth, Chat cleanup, Lookbook import/deletion처럼 네트워크·Auth·Firestore·Tasks·Storage 실패 순서가 중요한 service에 dependency object를 주입한다.
- Brand/Engagement/Comment/Safety 전체에 repository/interface를 강제하지 않는다.
- 해당 영역은 순수 validator/mapper/policy characterization과 export metadata contract로 보호한다.

### P4-C. clean/test discovery는 Node script로 관리한다

- `functions/scripts/clean-lib.mjs`가 build 전 `lib/`를 삭제한다.
- `functions/scripts/run-tests.mjs`가 `lib/`를 재귀 탐색해 모든 `*.test.js`를 Node test runner에 전달한다.
- test file이 0개면 실패시킨다.
- shell glob, `find`, 새 npm dependency에 의존하지 않는다.

## 목표 구조

```text
functions/
├── scripts/
│   ├── clean-lib.mjs
│   └── run-tests.mjs
└── src/
    ├── core/
    ├── shared/
    ├── auth/
    ├── brand/admin/
    ├── brand/requests/
    ├── lookbook/deletion/
    ├── lookbook/engagement/
    ├── lookbook/comments/
    ├── lookbook/safety/
    ├── lookbook/import/
    ├── chat/cleanup/
    ├── index.contract.test.ts
    ├── architecture.contract.test.ts
    └── index.ts
```

## 변경 파일

### 1. build/test orchestration

| 파일 | 변경 | 책임 |
| --- | --- | --- |
| `functions/package.json` | 수정 | clean build와 재귀 test runner 연결 |
| `functions/scripts/clean-lib.mjs` | 추가 | dependency 없이 `lib/` 제거 |
| `functions/scripts/run-tests.mjs` | 추가 | compiled test 재귀 발견, 0개 방지, Node test 실행 |

`package-lock.json`은 dependency를 추가하지 않으므로 의도적인 변경 대상이 아니다.

### 2. core와 shared

| 파일 | 책임 |
| --- | --- |
| `src/core/firebase.ts` | Admin app 존재 여부를 확인한 단일 초기화, `db`, Auth, Storage bucket 접근 |
| `src/core/runtime.ts` | `setGlobalOptions({maxInstances: 10})`, `FUNCTIONS_REGION`, 공통 runtime 상수의 단일 owner |
| `src/core/callable.ts` | payload, required/optional string·boolean·document ID·auth UID primitive 검증 |
| `src/core/errors.ts` | unknown error message와 공통 error code 판별 |
| `src/core/concurrency.ts` | deletion/import가 공유하는 bounded concurrency 실행 primitive |
| `src/shared/brandAuthorization.ts` | total admin, owner/write access, capability와 공통 브랜드 권한 정책 |

경계 규칙:

- `firebase.ts` 이외 파일은 `initializeApp`을 호출하지 않는다.
- `runtime.ts` 이외 파일은 `setGlobalOptions`를 호출하지 않는다.
- 모든 `functions.ts`는 `core/runtime.js`에 명시적으로 의존한다.
- feature는 다른 feature 디렉터리를 직접 import하지 않는다.
- 동일한 도메인 의미만 `shared`로 올리고 feature-local mapper/query는 승격하지 않는다.

### 3. Auth와 Chat cleanup

| 파일 | 책임 |
| --- | --- |
| `src/auth/functions.ts` | `exchangeKakaoToken` 등록과 request/response 경계 |
| `src/auth/kakaoService.ts` | Kakao HTTP 요청과 Firebase custom token 생성, fetch/Auth dependency seam |
| `src/chat/cleanup/functions.ts` | `onRoomClosed`, `cleanupExpiredChatMediaUploads` 등록 |
| `src/chat/cleanup/cleanupService.ts` | room close와 만료 media 문서/Storage cleanup, Firestore·Storage dependency seam |

Kakao endpoint/header/error, Chat trigger path, `0 4 * * *`, `Asia/Seoul`, cleanup limit 100과 삭제 순서를 유지한다.

### 4. Brand admin/requests

| 파일 | 책임 |
| --- | --- |
| `src/brand/admin/functions.ts` | capability/create/update/manager/logo callable 6개 등록 |
| `src/brand/admin/adminService.ts` | brand transaction, manager Auth lookup과 name index write orchestration |
| `src/brand/admin/brandValidation.ts` | brand name, email, URL, role, logo path와 patch 검증 |
| `src/brand/requests/functions.ts` | request/list/group/stage/resolve/search callable 10개 등록 |
| `src/brand/requests/requestService.ts` | daily counter, dedupe, pagination query, group mutation transaction |
| `src/brand/requests/requestPolicy.ts` | status/stage/scope/retention/limit/date 정책 |
| `src/brand/requests/requestMappers.ts` | public/admin/group/search response mapping |

daily limit 5, user history 14일, admin recent 기본 14일/최대 30일, cursor와 group resolution 의미를 유지한다.

### 5. Lookbook engagement/comments/safety

| 파일 | 책임 |
| --- | --- |
| `src/lookbook/engagement/functions.ts` | brand/post/season/comment engagement callable 4개 등록 |
| `src/lookbook/engagement/engagementService.ts` | user state와 metric transaction |
| `src/lookbook/engagement/engagementPolicy.ts` | metric 기본값·state document ID·response 계산 |
| `src/lookbook/comments/functions.ts` | create comment/reply/delete callable 3개 등록 |
| `src/lookbook/comments/commentService.ts` | comment/reply transaction과 delete projection 처리 |
| `src/lookbook/comments/commentPolicy.ts` | message/reason와 comment path/ID 정책 |
| `src/lookbook/safety/functions.ts` | report/block/hidden IDs callable 3개 등록 |
| `src/lookbook/safety/safetyService.ts` | report idempotency, block write와 hidden ID 조회 |
| `src/lookbook/safety/safetyPolicy.ts` | report document ID, spam limit와 안전 입력 정책 |

metric 증감, idempotency, reply preview/delete 처리, report/block authorization과 response key를 변경하지 않는다.

### 6. Lookbook import

| 파일 | 책임 |
| --- | --- |
| `src/lookbook/import/functions.ts` | callable 6개, trigger 1개, scheduler 1개 등록 |
| `src/lookbook/import/importService.ts` | import job 생성, candidate batch와 asset retry 상태 전이 |
| `src/lookbook/import/taskService.ts` | Tasks config, deterministic ID, OIDC와 enqueue idempotency |
| `src/lookbook/import/diagnosticService.ts` | worker diagnostic 호출, candidate 교체, retention cleanup |
| `src/lookbook/import/importValidation.ts` | URL, candidate/job payload, status와 diagnostic type 검증 |
| `src/lookbook/import/seasonCandidateDiscovery.ts` | 기존 discovery orchestration 이동 |
| `src/lookbook/import/seasonCandidateParser.ts` | 기존 parser 이동 |

이동 export:

- callable: `requestSeasonImport`, `requestSeasonAssetRetry`, `requestSeasonCandidateImportJobs`, `runLookbookExtractionDiagnostic`, `getLatestLookbookExtractionDiagnostic`, `discoverSeasonCandidates`
- trigger/scheduler: `onSeasonImportQueued`, `cleanupExpiredLookbookExtractionDiagnostics`

queue/location/endpoint/env/OIDC/audience/task ID, timeout/memory와 상태 전이 순서를 유지한다.

### 7. Lookbook deletion

| 파일 | 책임 |
| --- | --- |
| `src/lookbook/deletion/functions.ts` | callable 10개, manual trigger와 scheduler 등록 |
| `src/lookbook/deletion/softDeleteService.ts` | brand/season/post soft delete·restore·batch operation |
| `src/lookbook/deletion/deletionMappers.ts` | display snapshot, request/audit/response mapping |
| `src/lookbook/deletion/deletionQuery.ts` | active/failed pagination과 display fallback query |
| `src/lookbook/deletion/purgeService.ts` | claim, target purge, finalize와 related request 처리 |
| `src/lookbook/deletion/storageCleanup.ts` | safe Storage path 수집과 bounded delete |
| `src/lookbook/deletion/purgeDrain.ts` | 기존 drain 이동 |
| `src/lookbook/deletion/purgeLease.ts` | 기존 lease 이동 |
| `src/lookbook/deletion/purgeDrain.test.ts` | 기존 test 이동 |
| `src/lookbook/deletion/purgeLease.test.ts` | 기존 test 이동 |

7일 retention, batch 20/동시성 3, purge page 20, 서로 다른 브랜드 최대 3개, 7분 budget, 15분 lease, retry/finalize와 Storage/Firestore 삭제 순서를 유지한다.

### 8. root entrypoint와 계약 테스트

| 파일 | 변경 | 책임 |
| --- | --- | --- |
| `src/index.ts` | 축소 | 기존 49개 이름을 wildcard 없이 명시적으로 re-export |
| `src/index.contract.test.ts` | 추가 | export 이름과 `__endpoint` runtime/trigger/schedule metadata |
| `src/architecture.contract.test.ts` | 추가 | initialize/global option owner, feature import와 root 구현 잔여 검사 |

`firebase.json`, Firestore rules/indexes, worker HTTP API, iOS/Socket 코드는 변경 대상이 아니다.

### 9. 이동 후 root에서 제거할 파일

- `src/lookbookDeletionPurgeDrain.ts`
- `src/lookbookDeletionPurgeDrain.test.ts`
- `src/lookbookDeletionPurgeLease.ts`
- `src/lookbookDeletionPurgeLease.test.ts`
- `src/lookbookSeasonCandidateDiscovery.ts`
- `src/lookbookSeasonCandidateParser.ts`

## 구현 순서

### Step 4A. 계약 characterization과 test runner

1. 49개 export/metadata expected fixture를 현재 inventory와 선언에서 작성한다.
2. clean/test scripts와 package scripts를 반영한다.
3. 기존 root test가 recursive runner에서도 실행되는지 확인한다.

완료 기준: stale `lib` 없이 기존 test가 발견되고 metadata 차이가 명확히 실패한다.

Rollback: package/scripts 변경만 되돌린다.

### Step 4B. core/shared

1. Firebase/runtime/callable/error/concurrency primitive를 이동한다.
2. 공유 brand authorization을 이동한다.
3. `index.ts`의 function body는 유지한 채 새 core/shared를 사용한다.

완료 기준: initialize/global option owner가 하나이고 49개 metadata contract가 통과한다.

Rollback: root import를 기존 local helper로 복귀하고 신규 core/shared만 제거한다.

### Step 4C. Auth와 Chat cleanup

wrapper/service를 이전하고 `index.ts`가 해당 3개 이름을 새 module에서 re-export한다.

완료 기준: export/metadata와 Auth/cleanup failure test가 통과하고 root 구현은 제거된다.

### Step 4D. Brand admin/requests

admin validation/service, request policy/mapper/service와 wrapper를 이전한다.

완료 기준: Brand 16개 callable export와 policy/mapper tests가 통과한다.

### Step 4E. Engagement/comments/safety

metric transaction, comment mutation과 safety operation을 각각 이전한다.

완료 기준: 10개 callable export와 순수 policy characterization이 통과한다.

### Step 4F. Import

1. candidate discovery/parser를 이동한다.
2. Tasks, import 상태 전이와 diagnostic service를 이전한다.
3. 8개 export metadata와 env/queue/endpoint를 대조한다.

완료 기준: task idempotency, diagnostic/import policy, candidate 동작과 metadata가 통과한다.

### Step 4G. Deletion

1. drain/lease와 test를 이동한다.
2. soft delete/restore/list mapper/query를 이전한다.
3. Storage cleanup과 purge service를 이전한다.
4. callable/trigger/scheduler wrapper를 마지막에 전환한다.

완료 기준: drain/lease와 신규 deletion tests, 12개 export metadata가 통과한다.

### Step 4H. index 축소와 정적 경계 검사

1. `index.ts`를 49개 명시적 re-export만 갖는 entrypoint로 축소한다.
2. implementation과 wildcard/default export가 없는지 검사한다.
3. 이동 대상 root 파일 6개와 잔여 import를 제거한다.

완료 기준: root에 handler body가 없고 `Object.keys(index)`가 정확히 49개다.

### Step 4I. 전체 검증과 하네스 최신화

1. `npm test`.
2. `npm run lint`.
3. `npm run build`.
4. source/export/runtime/static owner 검색.
5. `ENTRYPOINTS`, `FIREBASE`, `TESTS`, task progress/QA/HANDOFF 갱신.
6. 운영 배포 없이 멈추고 결과를 보고한다.

## 순차 전환과 rollback

- Step 4C~4G는 한 module씩 re-export를 바꾸고 즉시 test/lint/build 가능한 단위로 완료한다.
- 새 module과 root의 같은 export를 동시에 내보내지 않는다.
- 계약 test가 실패하면 다음 module로 가지 않고 해당 module의 re-export와 이동만 복귀한다.
- schema, Storage path, queue, scheduler와 배포 revision을 변경하지 않으므로 데이터 rollback은 없다.
- Phase 중 배포하지 않으므로 운영 rollback은 필요하지 않다.
- 전체 배포 승인 시에만 배포 전 현재 revision과 rollback revision을 별도 기록한다.

## 완료 기준

- `index.ts`가 기존 49개 이름의 명시적 flat export만 제공한다.
- callable 43개, Firestore trigger 3개, scheduler 3개와 runtime metadata가 동일하다.
- Admin 초기화와 global option owner가 각각 한 곳이다.
- feature 간 직접 import와 circular dependency가 없다.
- 복잡한 service만 dependency seam을 가진다.
- stale `lib`가 제거되고 하위 test가 모두 발견된다.
- 기존 deletion tests와 신규 contract/policy/service tests가 통과한다.
- `npm test`, `npm run lint`, `npm run build`가 통과한다.
- 배포, Firebase schema, iOS/Socket 코드는 변경하지 않는다.

## 구현 결과

- `index.ts`는 65줄의 49개 명시적 flat re-export만 유지한다.
- Admin 초기화/global option owner는 `core/firebase.ts`, `core/runtime.ts` 각 한 곳이다.
- 기능 module과 이동된 purge/import helper, clean/recursive runner를 반영했다.
- 실제 파일은 P4-A에 따라 단순 책임을 같은 feature `functions.ts`에 유지하고 독립 변경·테스트 이유가 있는 Auth/Chat service, purge drain/lease, import discovery/parser를 분리했다.
- `npm test` 51개, `npm run lint`, `npm run build`와 architecture contract가 통과했다.
- 운영 배포, schema/rules/indexes, iOS/Socket 변경은 수행하지 않았다.

## 구현 중 중단 조건

- payload/response, `HttpsError`, runtime metadata 또는 side-effect 순서를 바꿔야 한다.
- 새 Firestore index/rule/schema, Storage path, queue 또는 worker endpoint가 필요하다.
- 승인한 A안보다 넓은 Firebase repository/interface 계층이 필요하다.
- feature policy를 `shared`로 추가 승격해야 circular import를 피할 수 있다.
- 49개 중 dead function 제거 또는 새 export 추가가 필요하다.

중단 조건이 발생하면 구현을 멈추고 선택지·영향·추천안을 사용자에게 보고한다.
