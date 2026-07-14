# Phase 4 Firebase Functions Test Plan

## 목적과 위험도

이번 Phase는 7,809줄 root entrypoint를 여러 module로 옮기는 동작 보존형 서버 리팩터링이다. export 누락, runtime metadata 변경, 초기화 중복, 테스트 미발견과 transaction/Tasks/Storage 부작용 순서 회귀를 우선 검증한다.

- 고위험: deletion purge, import Tasks/diagnostic, Auth token exchange, Chat Storage cleanup.
- 중위험: Brand request transaction, engagement/comment/safety transaction.
- 구조 위험: 49개 export, trigger path/schedule, global runtime, Admin initialization, circular import, stale `lib`.

## 테스트 전략

1. root export와 `__endpoint` metadata는 contract test로 전수 검증한다.
2. pure validator/mapper/policy는 Node unit test로 characterization한다.
3. 외부 실패 순서가 중요한 Auth/Chat/import/deletion service만 dependency fake를 사용한다.
4. Firebase Emulator는 새 인프라 범위가 크므로 필수 완료 기준에서 제외한다.
5. 운영 배포와 실제 데이터 변경 smoke는 별도 승인 후 수행한다.

## test runner 검증

### `functions/scripts/clean-lib.mjs`

- `fs.rm(..., {recursive: true, force: true})`로 `lib`만 제거한다.
- source, node_modules와 다른 build directory를 건드리지 않는다.

### `functions/scripts/run-tests.mjs`

- `lib/` 하위 모든 `*.test.js`를 재귀 수집한다.
- 정렬된 경로를 `node --test`에 전달한다.
- test 0개, spawn 실패와 non-zero exit를 실패로 반환한다.
- 하위 feature test가 실행 로그에 나타나는지 확인한다.

별도 script unit test보다 실제 `npm test`가 stale file 제거와 하위 test 발견을 함께 증명하게 한다.

## 계약 테스트

### `src/index.contract.test.ts`

- `Object.keys(index)`가 정확히 49개다.
- callable 43개, Firestore trigger 3개, scheduler 3개 이름이 기준선과 같다.
- 각 export의 `__endpoint`에서 region, timeoutSeconds, memory와 maxInstances를 비교한다.
- Firestore trigger path/event type, schedule/timezone을 비교한다.
- helper/service/default export가 root에서 노출되지 않는다.

expected fixture는 test의 명시적 상수로 둔다. production module에서 목록을 가져오면 같은 실수를 공유하므로 금지한다.

### `src/architecture.contract.test.ts`

`functions/src` 정적 검사:

- `initializeApp` owner는 `core/firebase.ts` 하나다.
- `setGlobalOptions` owner는 `core/runtime.ts` 하나다.
- `onInit`으로 registration/global option을 초기화하지 않는다.
- `index.ts`에는 query/transaction/batch/Storage/Tasks와 handler body가 없다.
- wildcard/default export가 없다.
- feature가 다른 feature를 직접 import하지 않는다.
- root에 기존 이동 대상 helper가 남지 않는다.

순환 import는 lint/build와 필요 시 dependency 없는 상대 import graph 검사로 확인한다.

## core/shared 테스트

### `src/core/callable.test.ts`

- null/array/primitive payload 거부.
- required string trim, empty/max length/type 오류.
- optional string undefined/null/empty/max length.
- boolean type과 auth UID 없음의 `unauthenticated`.
- document ID trim/empty/slash/list 검증.
- 오류 code/message가 기존 계약과 같다.

### `src/shared/brandAuthorization.test.ts`

- total admin, brand owner/admin role과 write access 판단.
- 누락/잘못된 roles가 권한을 부여하지 않는다.
- capability response boolean 조합.

Firestore read 전체는 fake repository로 감싸지 않고 데이터 기반 순수 권한 판단을 검증한다.

## feature 테스트

### Auth

`src/auth/kakaoService.test.ts`

- token info → me endpoint 요청 순서/header.
- Kakao ID 없음, HTTP 오류, malformed JSON.
- email optional 처리와 custom token claim.
- fetch/Auth token 생성 실패의 기존 error mapping.
- fake fetch와 fake token creator를 사용한다.

### Chat cleanup

`src/chat/cleanup/cleanupService.test.ts`

- room closed가 아닌 update는 no-op.
- close 시 Storage path와 문서 cleanup 순서.
- 만료 media query limit 100과 image/video path.
- Storage not-found 허용과 실제 실패 전파 정책.
- repeated cleanup idempotency.
- Firestore query/delete와 Storage delete fake를 사용한다.

### Brand admin/requests

`src/brand/admin/brandValidation.test.ts`

- canonical/normalized name, email, URL, role, logo path와 patch semantics.

`src/brand/requests/requestPolicy.test.ts`

- daily KST key, limit 5, status/admin stage 변환.
- user active/history, admin recent/history boundary.
- cursor/limit bound와 rejection reason.

`src/brand/requests/requestMappers.test.ts`

- public/admin/group/search summary optional field와 Timestamp ISO mapping.
- 내부 권한/감사 field가 사용자 response에 노출되지 않는다.

전체 Firestore transaction fake는 추가하지 않는다. policy/mapper, root contract와 승인 후 smoke로 검증한다.

### Engagement/comments/safety

`src/lookbook/engagement/engagementPolicy.test.ts`

- 누락/숫자 metric의 0 fallback.
- brand/season/post/comment state document ID.
- like/save/metric response 계산과 음수 방지 의미.

`src/lookbook/comments/commentPolicy.test.ts`

- comment/reply message trim/limit.
- document path/ID와 delete reason optional semantics.
- reply preview 삭제 대상 판단.

`src/lookbook/safety/safetyPolicy.test.ts`

- deterministic report document ID.
- reason/detail/source와 자기 자신 차단 거부.
- spam limit patch와 hidden IDs 중복 제거.

전체 Firestore SDK fake가 필요해지면 구현을 중단하고 seam 범위를 재논의한다.

### Lookbook import

`src/lookbook/import/taskService.test.ts`

- env 기본 location/queue/endpoint와 override.
- deterministic import/asset retry task ID.
- payload, schedule, OIDC service account/audience.
- `ALREADY_EXISTS`를 idempotent 성공으로 처리.
- Tasks create 실패 전파.

`src/lookbook/import/importValidation.test.ts`

- URL/document ID/candidate list/status/diagnostic type.
- candidate max count와 import 중복 차단 상태.

`src/lookbook/import/diagnosticService.test.ts`

- worker response mapping과 malformed/failed response.
- candidate replacement 순서와 최대 저장 수.
- retention 90일과 cleanup limit 100.

`src/lookbook/import/seasonCandidateDiscovery.test.ts`

- 기존 discovery/parser 대표 fixture, pagination/load-more와 중복 제거.
- 이동 중 동작을 변경하지 않는다.

Tasks/worker/fetch/Firestore write는 좁은 dependency fake를 사용한다.

### Lookbook deletion

이동·유지:

- `src/lookbook/deletion/purgeDrain.test.ts`
- `src/lookbook/deletion/purgeLease.test.ts`

기존 20개 초과 page, 브랜드 동시성/순서, 부모 우선, 실패 후 계속, 7분 cutoff, lease/manual duplicate/finalize ownership을 유지한다.

`src/lookbook/deletion/deletionMappers.test.ts`

- display fallback/snapshot, target path/ID, request/audit patch.
- active/failed summary, sanitized error와 batch partial result.

`src/lookbook/deletion/storageCleanup.test.ts`

- 허용 bucket path만 수집하고 외부/빈/중복 path를 제거한다.
- brand/season/post/comment/replacement subresource path.
- bounded delete와 not-found/실패 정책.

`src/lookbook/deletion/purgeService.test.ts`

- claim 성공/skip, success finalize, failure retryAfter.
- target purge → related request update → finalize 순서.
- 중간 실패 시 완료 상태를 쓰지 않는다.
- fake query/batch/storage dependency를 사용한다.

## 추가하지 않는 테스트

- 43개 callable wrapper 전수 실행: emulator 없이 SDK 결합과 fixture 비용이 크므로 metadata와 pure/service test, 대표 smoke로 나눈다.
- Firebase Emulator integration: 현재 emulator/fixture 기준선이 없고 구조 이동 범위를 넘는다.
- 운영 Firestore/Storage destructive test: 배포와 운영 데이터 변경은 별도 승인 대상이다.
- 성능/cold-start benchmark: 실제 회귀가 관찰될 때 추가한다.
- UI/iOS test: wire contract는 바꾸지 않고 iOS callable 38개 계약은 Phase 2에서 고정했다.

## 수동 smoke QA

emulator 또는 승인된 staging 환경이 마련되면:

- unauthenticated callable과 invalid payload.
- Kakao token exchange.
- Brand capability/create 또는 update, request list/stage.
- engagement, comment create/delete, report/block.
- import request/Tasks enqueue/queued trigger/diagnostic.
- deletion soft delete/restore/list와 별도 fixture purge.
- room close cleanup과 scheduler 대표 fixture.

운영 배포 후 smoke는 데이터 변경 범위와 정리 절차를 별도 승인받는다.

## 실행 순서

각 module Step과 Phase 최종에서 실행한다.

```bash
cd functions
npm test
npm run lint
npm run build
```

정적 확인:

```bash
rg -n "initializeApp\(" functions/src
rg -n "setGlobalOptions\(" functions/src
rg -n "onInit\(" functions/src
rg -n "export \*|export default" functions/src/index.ts
rg -n "runTransaction|\.batch\(|CloudTasksClient|storage\(\)" functions/src/index.ts
find functions/lib -name '*.test.js' -type f | sort
git diff --check
```

## 실행 결과와 완료 기준

- 구현 후 `npm test` 51개, `npm run lint`, `npm run build`가 통과했다.
- `index.contract.test.ts`와 `architecture.contract.test.ts`, 하위 기능 테스트가 재귀 runner에서 발견됐다.
- 운영 배포는 사용자 별도 승인 전 실행하지 않는다.
- runner가 하위 test를 모두 발견하고 0개를 성공 처리하지 않아야 한다.
- 49개 export/runtime metadata와 초기화 owner/import 방향이 검증돼야 한다.
- 기존 deletion tests와 신규 고위험 service/policy tests가 통과해야 한다.
- `npm test`, `npm run lint`, `npm run build`, `git diff --check`가 통과해야 한다.
- 보류한 smoke/배포는 이유와 승인 조건을 progress에 남긴다.
