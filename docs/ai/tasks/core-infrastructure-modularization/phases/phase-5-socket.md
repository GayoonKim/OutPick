# Phase 5 Socket Implementation Plan

## 상태와 목표

- D27~D39는 사용자 승인으로 확정됐다.
- 이 문서는 Phase 5 변경 파일, Step 5A~5H, rollback과 중단 조건 및 구현 결과를 기록한다.
- Step 5A~5H 구현과 자동 검증을 완료했다.
- D40 media dedupe 동작 강화는 Phase 5 구현 범위에서 제외한다.
- 운영 Cloud Run 배포는 구현·자동 검증 완료 후 별도 승인받는다.

`Socket/index.js`의 약 1,414줄 구현을 application/bootstrap, auth, connection, room, message, media와 lifecycle 경계로 옮긴다. 기존 Node 22 JavaScript ESM, Docker image와 Cloud Run service, HTTP route, Socket event/payload/ACK, Firebase/Storage path, persist→emit→push→ACK 순서를 유지한다.

## 구현 결과

- `Socket/index.js`를 1,414줄에서 41줄의 bootstrap/lifecycle 진입점으로 축소했다.
- `src/app/`에서 application과 production dependency graph를 조립하고 Firebase Admin 초기화를 명시적 bootstrap으로 전환했다.
- auth/connection/room/message/media handler와 room/media service, lifecycle/runtime/state owner를 분리했다.
- HTTP route 3개, middleware 2개, client event 11개와 disconnect 계약을 자동 테스트로 고정했다.
- `Socket/scripts/run-tests.mjs`와 `Socket/test/`를 추가했으며 `npm --prefix Socket run check`, 43개 `node:test`가 통과했다.
- D40 in-flight Promise, TTL/LRU, transaction winner 동작은 포함하지 않았고 기존 process-local delivered `Set` 의미를 유지했다.
- 최초 로컬 start에서 동결된 Socket.IO option 객체로 인한 runtime 오류를 발견해 application factory가 새 option 객체를 전달하도록 수정하고 회귀 테스트를 추가했다.
- ADC 기반 room preload, 임의 포트 `/readyz`·`/healthz` 200과 SIGINT graceful shutdown smoke가 통과했다.
- `package-lock.json`, Docker/build/deploy 설정은 변경하지 않았고 Cloud Run 배포와 iOS 실제 송수신 QA는 수행하지 않았다.

## 변경 유형과 위험도

- 유형: 동작 보존형 서버 구조 리팩터링, dependency/state owner 변경, test runner 추가.
- 고위험: Firebase ID Token 인증, room close/leave, text/lookbook/media persist와 emit/push, media reservation/finalize, graceful shutdown.
- 중위험: reconnect limit, room registry, rate limit, message payload normalization.
- 구조 위험: import 시 Firebase 자동 초기화, `index.js` 실행 부작용, event 누락·중복 등록, module top-level mutable state 재발.

## 이번 Phase의 명시적 비목표

- D40 in-flight Promise, TTL/LRU와 transaction winner 동작 구현.
- event 이름, payload, ACK optional key/error code 변경.
- Firebase/Firestore/Storage schema 또는 path 변경.
- FCM fanout 정책, room cleanup 순서와 sequence transaction 의미 변경.
- TypeScript 전환, 새 test framework/dependency, Redis 도입.
- Dockerfile base image, Cloud Run scaling/IAM/배포 설정 변경.
- iOS `RealtimeSocketService` 코드 변경.

## 목표 구조

```text
Socket/
├── index.js
├── package.json
├── README.md
├── scripts/
│   └── run-tests.mjs
├── src/
│   ├── app/
│   │   ├── createProductionDependencies.js
│   │   └── createSocketApplication.js
│   ├── auth/
│   │   ├── handshake.js
│   │   └── socketAuthMiddleware.js
│   ├── handlers/
│   │   ├── connectionHandlers.js
│   │   ├── roomHandlers.js
│   │   ├── messageHandlers.js
│   │   └── mediaHandlers.js
│   ├── lifecycle/
│   │   ├── healthRoutes.js
│   │   └── gracefulShutdown.js
│   ├── media/
│   │   ├── mediaDeliveryState.js
│   │   ├── mediaPayload.js
│   │   └── mediaUploadService.js
│   ├── messages/
│   │   ├── messagePayload.js
│   │   ├── preview.js
│   │   └── sequenceStore.js
│   ├── rooms/
│   │   ├── roomAccess.js
│   │   ├── roomCleanup.js
│   │   ├── roomLifecycleService.js
│   │   ├── roomRegistry.js
│   │   └── socketRoomAuthorizer.js
│   ├── runtime/
│   │   ├── messageIDGenerator.js
│   │   └── systemClock.js
│   └── 기존 lookbookShare, push, users, utils
└── test/
    ├── app/
    ├── architecture/
    ├── auth/
    ├── handlers/
    ├── lifecycle/
    ├── media/
    ├── runtime/
    └── support/
```

모든 폴더에 동일한 파일 세트를 강제하지 않는다. 위 파일은 현재 `index.js`의 독립 책임과 테스트 seam이 실제로 필요한 경계만 반영한다.

## 변경 파일

### 1. root, test runner와 운영 문서

| 파일 | 변경 | 책임 |
| --- | --- | --- |
| `Socket/index.js` | 축소 | Firebase/runtime 초기화, production dependency/application 생성, room bootstrap, listen과 signal 연결 |
| `Socket/package.json` | 수정 | dependency 없는 재귀 `node:test` runner 연결, check 범위 유지 |
| `Socket/scripts/run-tests.mjs` | 추가 | `test/` 하위 `*.test.js` 재귀 발견, 정렬 실행, 0개 test 방지 |
| `Socket/README.md` | 수정 | 새 로컬 check/test/start 순서와 source 진입점 기록 |

변경하지 않는 파일:

- `Socket/package-lock.json`: dependency를 추가하지 않으므로 의도적인 변경 대상이 아니다.
- `Socket/Dockerfile`, `.dockerignore`, `.gcloudignore`: 기존 image/build context를 유지한다.
- Firebase Admin JSON key: 읽기·수정·커밋 대상이 아니다.

### 2. application/bootstrap

| 파일 | 변경 | 책임 |
| --- | --- | --- |
| `src/app/createProductionDependencies.js` | 추가 | Firebase, clock/ID, state owner와 기존 Store/service를 한 번 조립 |
| `src/app/createSocketApplication.js` | 추가 | Express/HTTP/Socket.IO 생성, HTTP route·middleware·connection handler 등록, listen 전 application handle 반환 |
| `src/firebaseAdmin.js` | 수정 | import-time 초기화 제거, 명시적 `initializeFirebaseAdmin({env})`가 `{admin, db}` 반환 |
| `src/config.js` | 최소 수정 | 기존 상수/PORT 계약 유지, production 조립에 필요한 설정만 명시적으로 제공 |

경계 규칙:

- `firebaseAdmin.js` import만으로 `initializeApp` 또는 `firestore()`를 호출하지 않는다.
- production dependency graph는 `createProductionDependencies` 한 곳에서 만든다.
- `createSocketApplication`은 Firebase Admin을 직접 초기화하지 않고 준비된 capability만 받는다.
- application factory는 `listen`, `process.on`과 `process.exit`를 직접 호출하지 않는다.

### 3. runtime state와 deterministic primitive

| 파일 | 변경 | 책임 |
| --- | --- | --- |
| `src/runtime/systemClock.js` | 추가 | production 현재 millis/date/uptime 제공, test clock 주입 경계 |
| `src/runtime/messageIDGenerator.js` | 추가 | 현재 timestamp-random 형식의 message ID 생성, clock/random 주입 |
| `src/utils/rateLimit.js` | 수정 | module-global `Map` 제거, `createRateLimiter({clock})` instance가 bucket 소유 |
| `src/media/mediaDeliveryState.js` | 추가 | image/video delivered `Set`과 기존 50,000개 초과 전체 clear 의미를 그대로 소유 |

Phase 5에서는 `mediaDeliveryState`의 기존 `has/add/delete/clear` 의미를 변경하지 않는다. bounded TTL/LRU나 in-flight 상태를 추가하면 D40 범위 침범으로 중단한다.

### 4. auth와 connection

| 파일 | 변경 | 책임 |
| --- | --- | --- |
| `src/auth/handshake.js` | 추가 | client key, Firebase ID Token, decoded token email 추출 순수 함수 |
| `src/auth/socketAuthMiddleware.js` | 추가 | reconnect attempt middleware와 Firebase token/profile 인증 middleware factory |
| `src/handlers/connectionHandlers.js` | 추가 | ready, hello, ping, room list, username, disconnect event 등록 |

보존할 순서:

1. reconnect attempt 검사.
2. Firebase ID Token 검사/검증과 user profile lookup.
3. `socket.userUID`, document ID, email/source 설정.
4. connection 시 ready/room list emit 후 event handler 등록.

`connectAttempts`는 reconnect middleware factory instance가 소유하고 clock을 주입받는다. disconnect는 room registry의 현재 사용자 목록을 정리하고 기존 `user list` emit을 유지한다.

### 5. room

| 파일 | 변경 | 책임 |
| --- | --- | --- |
| `src/handlers/roomHandlers.js` | 추가 | create/join/leave/leave-or-close event, ACK와 Socket.IO room side effect |
| `src/rooms/socketRoomAuthorizer.js` | 추가 | room lazy load, Firestore access 확인과 누락된 socket membership 복구 capability |
| `src/rooms/roomLifecycleService.js` | 추가 | room document/owner 판단 후 close 또는 membership leave 작업 단위 결정 |
| `src/rooms/roomRegistry.js` | 유지·필요 시 최소 수정 | process-local room/user projection owner |
| `src/rooms/roomAccess.js` | 유지 | Firestore room/member access 판단 |
| `src/rooms/roomCleanup.js` | 유지 | Storage/user projection/subcollection/room 삭제와 participant leave |

handler는 Firestore `db`를 직접 받지 않는다. `roomLifecycleService`가 owner 판정과 cleanup capability 호출을 담당하고 handler는 `room:closed`, `user list`, leave와 ACK를 담당한다.

### 6. text와 lookbook share

| 파일 | 변경 | 책임 |
| --- | --- | --- |
| `src/handlers/messageHandlers.js` | 추가 | `chat message`, `chat:lookbookShare` 등록과 text handler 호출 |
| `src/messages/messagePayload.js` | 추가 | text/reply/sentAt payload normalization과 server message 생성 |
| `src/lookbookShare/lookbookShareHandler.js` | 수정 | clock/ID/rate limiter capability 주입, 기존 lookbook 계약 보존 |
| `src/messages/sequenceStore.js` | 유지 | 기존 seq 할당과 message/reservation transaction |
| `src/push/chatPushService.js` | 수정 | device freshness 계산에 clock 주입, FCM 정책은 유지 |

text와 lookbook share 모두 다음 순서를 유지한다.

1. validation/auth/room/access/rate 검사.
2. sequence 할당과 Firestore persist.
3. room에 `chat message` emit.
4. FCM fanout fire-and-forget.
5. success ACK.

`sequenceStore`가 `{seq, created}`를 반환하도록 바꾸거나 duplicate side effect를 억제하면 D40이므로 Phase 5에서 금지한다.

### 7. media

| 파일 | 변경 | 책임 |
| --- | --- | --- |
| `src/handlers/mediaHandlers.js` | 추가 | `chat:mediaPreflight`, `chat:mediaFinalize` 등록, image/video ACK와 emit/push 순서 |
| `src/media/mediaPayload.js` | 추가 | image/video normalization, server message, thumbnail budget와 CDN URL 파생 |
| `src/media/mediaUploadService.js` | 추가 | message/reservation ref, contract validation, existing message와 reservation 조회/검증/생성 |
| `src/media/mediaDeliveryState.js` | 추가 | 기존 image/video delivered key state |

보존 항목:

- reservation TTL 24시간과 storage prefix.
- image 최대 30개, image/video expected path count.
- pending refresh, duplicate/conflict ACK.
- sender/kind/count/path/prefix/expiry 검증.
- persist와 reservation 삭제 transaction.
- image `receiveImages`, video `receiveVideo`, push와 ACK 순서.
- delivered key 50,000개 초과 시 현재 전체 clear 동작.

### 8. health와 shutdown

| 파일 | 변경 | 책임 |
| --- | --- | --- |
| `src/lifecycle/healthRoutes.js` | 추가 | `/`, `/readyz`, `/healthz` 등록과 shutting-down 상태 기반 200/503 응답 |
| `src/lifecycle/gracefulShutdown.js` | 추가 | idempotent shutdown, io→HTTP close, 10초 force timeout과 exit code |

shutdown controller는 `process`, timer, logger를 주입받거나 좁은 callback dependency로 받아 실제 process 종료 없이 테스트한다. `index.js`만 SIGTERM/SIGINT와 server error를 controller에 연결한다.

## 기존 파일 재사용·제거 기준

계속 재사용:

- `src/rooms/roomAccess.js`
- `src/rooms/roomCleanup.js`
- `src/rooms/roomRegistry.js`
- `src/users/userLookup.js`
- `src/messages/preview.js`
- `src/messages/sequenceStore.js`
- `src/push/chatPushService.js`
- `src/lookbookShare/sharedContentValidator.js`
- `src/utils/strings.js`

이동 완료 후 `index.js`에서 제거할 구현:

- Express/Socket.IO route와 middleware/handler body.
- handshake/token/email helper.
- image/video payload helper와 media reservation query.
- `connectAttempts`, delivered image/video `Set`, `isShuttingDown` module state.
- room/message/media 직접 Firestore query.
- shutdown implementation.

임시 façade나 duplicate handler 등록은 Step 내부에서만 허용하고 각 Step 완료 전에 제거한다.

## 구현 순서

### Step 5A. characterization contract와 test runner

1. `scripts/run-tests.mjs`와 `package.json` test script를 추가한다.
2. HTTP route 3개, middleware 2개, client event 11개와 disconnect 1개의 expected fixture를 production source와 분리해 작성한다.
3. 현재 ACK key/error와 persist→emit→push→ACK 기준을 test 문서/fixture에 고정한다.
4. architecture contract에 entrypoint/runtime owner 목표를 먼저 기록하되 아직 이전하지 않은 위반은 단계별 expected 상태로 관리한다.

완료 기준:

- test runner가 `test/` 하위 test를 재귀 발견하고 0개면 실패한다.
- 현재 event/route inventory가 fixture와 일치한다.
- 새 npm dependency와 package-lock 변경이 없다.

Rollback: `package.json`, runner와 Step 5A test만 제거한다.

### Step 5B. explicit Firebase, runtime primitive와 state owner

1. `firebaseAdmin.js`의 import-time 초기화를 명시적 반환 factory로 바꾼다.
2. system clock과 message ID generator를 추가한다.
3. rate limiter를 instance factory로 바꾼다.
4. current-semantics media delivery state를 추가한다.
5. production dependency 조립 초안을 만들고 기존 `index.js`가 새 dependency를 사용하게 한다.

완료 기준:

- Firebase 초기화 owner가 bootstrap 한 곳이다.
- import만으로 Firebase app/db가 생성되지 않는다.
- rate/media state가 handler module top-level에 없다.
- 기존 server start 동작과 syntax check가 유지된다.

Rollback: `index.js` import를 기존 Firebase/rate/delivered state로 복귀하고 신규 runtime factory를 제거한다.

### Step 5C. auth, connection과 lifecycle 분리

1. handshake 순수 helper와 middleware factory를 이동한다.
2. connection/disconnect handler를 이동한다.
3. health route와 graceful shutdown controller를 이동한다.
4. current `index.js`가 새 registration/controller를 사용하게 한다.

완료 기준:

- middleware 순서와 auth error payload가 동일하다.
- ready/hello/ping/username/room list/disconnect 계약이 통과한다.
- readiness 200/503, 중복 shutdown, close 순서와 force timeout test가 통과한다.

Rollback: auth/connection/lifecycle registration을 기존 `index.js` body로 되돌리고 해당 신규 파일만 제거한다.

### Step 5D. room handler/service 분리

1. socket room authorizer를 추출한다.
2. room lifecycle service로 Firestore owner 판정과 cleanup 결정을 이동한다.
3. create/join/leave/leave-or-close handler를 등록한다.
4. 기존 room registry/access/cleanup contract를 유지한다.

완료 기준:

- room event 4개가 한 번씩 등록된다.
- invalid/not-found/not-joined/not-owner/internal error ACK가 동일하다.
- close와 participant leave의 Storage/Firestore/Socket side-effect 순서가 기존과 같다.
- handler가 `db`/`admin`을 직접 받지 않는다.

Rollback: room event 4개의 registration만 기존 구현으로 복귀한다. room data/schema rollback은 없다.

### Step 5E. text와 lookbook share 분리

1. text payload/reply/sentAt normalization을 추출한다.
2. text handler를 새 message registration에 연결한다.
3. 기존 lookbook handler에 clock/ID/rate capability를 주입하고 같은 registration에서 연결한다.
4. push service의 현재 시간 dependency만 clock으로 교체한다.

완료 기준:

- 두 event가 각각 한 번 등록된다.
- validation/access/rate/persist failure ACK와 success ACK가 동일하다.
- persist 실패 시 emit/push/success ACK가 없다.
- 성공 시 persist→emit→push 요청→ACK 순서가 동일하다.

Rollback: message event 2개의 registration/import만 기존 구현으로 되돌린다. Firestore 데이터 migration은 없다.

### Step 5F. media 분리

1. media payload/thumbnail budget helper를 이동한다.
2. preflight/reservation service를 이동한다.
3. current-semantics media delivery state를 image/video finalize에 연결한다.
4. preflight/finalize handler를 등록하고 기존 `index.js` body를 제거한다.

완료 기준:

- media event 2개가 각각 한 번 등록된다.
- preflight pending/duplicate/conflict와 finalize image/video ACK가 동일하다.
- reservation/persist/emit/push 순서와 delivered key delete/유지 경로가 동일하다.
- in-flight Promise, TTL/LRU와 transaction winner 분기가 없다.

Rollback: media event 2개와 helper/service import를 기존 구현으로 복귀한다. reservation/schema 변경은 없다.

### Step 5G. application factory와 index 축소

1. `createProductionDependencies`가 모든 factory를 한 번 조립한다.
2. `createSocketApplication`이 route/middleware/handler를 한 번 등록한다.
3. `index.js`를 Firebase/runtime/application 생성, room preload, listen, signal/error 연결만 남기도록 축소한다.
4. duplicate registration과 root helper/body를 제거한다.

완료 기준:

- application을 import/create해도 listen/process handler/Firebase 초기화가 암묵 실행되지 않는다.
- `index.js`에 `socket.on`, `io.use`, Firestore query, payload builder가 없다.
- HTTP 3개, middleware 2개, client event 11개와 disconnect 1개가 정확히 한 번 등록된다.
- room preload 실패 후에도 기존처럼 server를 시작한다.

Rollback: `index.js`를 직전 Step의 registration 조립 상태로 되돌리고 application factory 연결만 제거한다.

### Step 5H. 전체 검증과 하네스 최신화

1. `npm --prefix Socket run check`.
2. `npm --prefix Socket test`.
3. entrypoint/event/state/Firebase owner 정적 검색.
4. 로컬 `/`, `/readyz`, `/healthz` smoke와 graceful shutdown 확인.
5. `README`, `ENTRYPOINTS`, `CHAT`, `TESTS`, task progress/QA/HANDOFF를 실제 새 진입점으로 갱신한다.
6. 운영 배포 없이 결과를 보고하고 멈춘다.

## 순차 전환과 rollback 원칙

- 모든 Step이 같은 `index.js`와 production dependency graph를 건드리므로 병렬 구현하지 않는다.
- 한 event의 기존 handler와 신규 handler를 동시에 등록하지 않는다.
- Step별 contract test가 실패하면 다음 Step으로 가지 않는다.
- ACK key/error, Firebase path, sequence transaction 또는 side-effect 순서 차이가 발견되면 구조 정리로 간주하지 않고 구현을 중단한다.
- Phase 중 배포하지 않으므로 운영 revision rollback은 발생하지 않는다.
- schema/data migration이 없으므로 데이터 rollback은 없다.
- 운영 배포가 승인되면 배포 직전 revision과 rollback traffic 명령을 별도 기록한다.

## 구현 중단 조건

다음 중 하나가 필요해지면 임의로 확대하지 않고 사용자와 다시 논의한다.

- D40 in-flight/TTL/LRU/winner 의미를 도입해야만 handler 분리가 가능한 경우.
- iOS ACK parser 또는 retry/outbox 변경이 필요한 경우.
- Firestore collection/document, Storage prefix 또는 reservation schema 변경이 필요한 경우.
- 기존 room cleanup/sequence transaction 순서를 바꿔야 하는 경우.
- Firebase Emulator, Redis, 새 npm dependency나 별도 Cloud Run service가 필요한 경우.
- 기존 Firebase Admin JSON key를 사용·이동·커밋해야 하는 경우.
- 운영 배포 또는 운영 데이터 변경이 필요한 경우.

## 완료 기준

- `index.js`는 bootstrap/listen/signal 조립만 담당한다.
- Firebase Admin 초기화와 production dependency graph owner가 각각 한 곳이다.
- HTTP route 3개, auth middleware 2개, client event 11개와 disconnect가 누락·중복 없이 등록된다.
- handler는 필요한 좁은 service/state만 받으며 room/message/media handler가 `db`/`admin`을 직접 소유하지 않는다.
- reconnect, rate, room registry, media delivery와 shutdown state owner가 명확하다.
- clock과 message ID generator가 주입 가능하고 production wire 값 의미는 같다.
- 기존 event/payload/ACK, reservation, sequence/persist, emit/push와 shutdown 계약이 유지된다.
- D40 동작 변경이 Phase 5 코드에 포함되지 않는다.
- `npm --prefix Socket run check`와 `npm --prefix Socket test`가 통과한다.
- 관련 하네스가 실제 새 코드 진입점과 검증 위치를 가리킨다.
- Docker/Cloud Run 배포 경계는 유지되고 운영 배포는 수행하지 않는다.
