# Phase 5 Socket Test Plan

## 목적과 위험도

이번 Phase는 Socket.IO 서버의 root entrypoint를 기능별 handler/service와 명시적 runtime dependency로 옮기는 동작 보존형 리팩터링이다. event 누락·중복, ACK key/error 변화, 인증 순서, state 공유, persist 이후 emit/push 순서와 shutdown 회귀를 자동 검증한다.

- 고위험: Firebase auth, room close/leave, text/lookbook/media persist, media reservation, graceful shutdown.
- 비동기 위험: callback ACK, fire-and-forget push, lazy room restore, middleware next, server close/timeout.
- 상태 위험: reconnect attempts, rate buckets, room projection, delivered image/video keys, shutting-down flag.

D40의 동시 finalize 병합, TTL/LRU와 Firestore transaction winner는 이 테스트 계획의 구현 대상이 아니다. D40 테스트 목록은 `qa-checklist.md`에 후속으로 유지한다.

## 테스트 전략

1. production event/route 목록과 ACK fixture를 test 상수로 고정한다.
2. handler는 fake socket/io와 service spy로 event 등록, ACK와 side-effect 순서를 검증한다.
3. clock, message ID, timer, process exit와 Firebase verify/profile lookup을 주입해 deterministic하게 검증한다.
4. 실제 Firebase Admin, Firestore, Storage와 FCM은 자동 unit test에서 사용하지 않는다.
5. local server와 승인된 Cloud Run smoke로 실제 Socket.IO transport/ADC/IAM을 보완한다.

## test runner

### `Socket/scripts/run-tests.mjs`

- `Socket/test/` 하위 모든 `*.test.js`를 재귀 수집한다.
- 경로를 정렬해 `node --test`에 전달한다.
- test가 0개면 non-zero로 종료한다.
- child process spawn 오류와 test non-zero exit를 그대로 실패로 반환한다.
- 새 npm dependency와 shell glob에 의존하지 않는다.

`package.json`:

```json
{
  "scripts": {
    "test": "node scripts/run-tests.mjs"
  }
}
```

runner 자체를 mock한 unit test보다 실제 `npm --prefix Socket test`가 재귀 발견과 0개가 아닌 실행을 증명하게 한다.

## 공통 test support

### `test/support/fakeSocket.js`

- `on`, `emit`, `join`, `leave` 호출 기록.
- `rooms`, `handshake`, `id`, 인증 사용자 field 설정.
- event별 등록 handler 조회와 호출 helper.

### `test/support/fakeIO.js`

- `use`, `on`, `to(roomID).emit` 호출 기록.
- adapter room/socket lookup fixture.
- middleware와 connection callback 실행 helper.

### `test/support/spies.js`

- callback ACK 기록.
- 호출 순서를 하나의 timeline에 기록하는 service/emit/push spy.
- deferred Promise로 middleware/service 비동기 완료 제어.

test support는 production source에서 import하지 않는다.

## 계약·구조 테스트

### `test/architecture/entrypoint.contract.test.js`

- `index.js`에 `socket.on`, `io.use`, `runTransaction`, `.collection(`, payload builder가 없다.
- `index.js`는 Firebase/runtime/application 생성, preload/listen/signal/error 연결만 갖는다.
- `firebaseAdmin.js` module top-level에 `initializeFirebaseAdmin()` 실행과 `admin.firestore()` export가 없다.
- `createSocketApplication` module import/create가 `listen`, `process.on`, `process.exit`을 호출하지 않는다.
- module top-level `new Map()`/`new Set()` state가 auth/handler 파일에 생기지 않는다.
- D40 표식인 in-flight Promise cache, TTL/LRU/winner 분기가 Phase 5 media source에 없다.

### `test/app/createSocketApplication.test.js`

- HTTP route가 `/`, `/readyz`, `/healthz` 정확히 3개 등록된다.
- Socket middleware가 reconnect → Firebase auth 순서로 정확히 2개 등록된다.
- connection registration이 한 번이다.
- connection 시 client event 11개와 disconnect 1개가 누락·중복 없이 등록된다.
- Socket.IO option `maxHttpBufferSize: 2MB`, compression threshold 1024가 동일하다.
- application 생성만으로 port가 열리지 않는다.

expected route/event 목록은 production export에서 가져오지 않고 test 상수로 둔다.

## runtime/auth 테스트

### `test/runtime/rateLimiter.test.js`

- window 안 limit까지 허용하고 다음 요청을 거부한다.
- window 경계 이후 오래된 timestamp를 제거한다.
- 서로 다른 key bucket이 독립적이다.
- 서로 다른 rate limiter instance가 state를 공유하지 않는다.
- deterministic clock만 사용한다.

### `test/runtime/messageIDGenerator.test.js`

- 주입한 millis/random으로 현재 `timestamp-hexSuffix` 형식을 만든다.
- text/lookbook/image/video에서 explicit ID가 있으면 generator를 호출하지 않는 계약은 각 handler test에서 확인한다.

### `test/auth/socketAuthMiddleware.test.js`

reconnect:

- auth/header/query/address client key 우선순위.
- moving window 안 최대 5회 허용, 6회 `max_connect_attempts_exceeded`.
- error data의 한글 message, `maxAttempts`, `retryAfterMs`.
- window 밖 attempt 제거.

Firebase auth:

- `auth.idToken`, `auth.token`, Bearer header 우선순위와 trim.
- token 없음은 `unauthenticated`/`missing_id_token`.
- decoded UID 없음은 `missing_token_uid`.
- verify 실패는 `invalid_id_token`.
- profile email 우선, token direct email, identities email fallback.
- `socket.userUID`, `userDocumentID`, `userEmail`, `userEmailSource` 설정.
- `next`가 성공/실패에서 정확히 한 번 호출된다.

fake token verifier와 fake user lookup을 사용한다.

## handler 테스트

### `test/handlers/connectionHandlers.test.js`

- connection 직후 `server:connect:ready` payload의 policy/serverTime/socketId.
- `room list`가 현재 registry key를 사용한다.
- `client:hello` ACK의 ok/attempt/policy/serverTime/key.
- `client:ping` ACK의 pong/serverTime.
- `set username` 기본 `Anonymous`와 `username set` emit.
- disconnect가 모든 room의 username을 제거하고 `user list`를 emit한다.

### `test/handlers/roomHandlers.test.js`

create/join/leave:

- invalid room ID의 기존 `message` 기반 ACK.
- create room의 registry 추가, join, username 중복 방지와 success ACK.
- join lazy load, access denial, not found `error` emit과 ACK.
- leave의 Socket.IO leave, registry 제거, `user list`, ACK 순서.

leave-or-close:

- invalid room, unauthenticated, internal error ACK.
- already deleted room의 `{ok:true, mode:"closed", alreadyDeleted:true}`.
- owner close 실패와 성공, `room:closed`, registry 삭제, 모든 socket leave, success ACK 순서.
- participant leave 실패와 성공, socket leave, registry/user list와 `{mode:"left"}`.

fake room registry, authorizer, lifecycle service와 adapter room fixture를 사용한다.

### `test/handlers/messageHandlers.test.js`

text:

- 빈 message, invalid room, access denial, UTF-8 4,000 bytes 초과, rate limit ACK.
- `roomID`/`roomName`, `msg`/`message`, nickname alias와 sender identity mapping.
- sentAt ISO와 replyPreview optional field normalization.
- explicit ID와 deterministic generated ID.
- persist 실패의 `seq_persist_error`이며 emit/push/success ACK가 없다.
- 성공 timeline이 persist → `chat message` emit → push 요청 → success ACK다.
- success ACK는 `ok`, `success`, `seq`, `messageID`를 유지한다.

lookbook share:

- 기존 payload/size/access/not-joined/shared-content/rate error ACK.
- persist 실패와 success timeline.
- `chat:lookbookShare`가 기존 handler에 정확히 한 번 위임된다.

sequence/push는 spy capability로 대체하고 실제 Firestore/FCM을 호출하지 않는다.

### `test/handlers/mediaHandlers.test.js`

preflight:

- invalid room/message/kind/count/path, unauthenticated/access/rate error ACK.
- existing message duplicate ACK.
- 동일 pending reservation refresh ACK.
- conflict ACK와 신규 pending reservation ACK.

image finalize:

- no images, 30개 초과, no valid attachment, rate/contract/reservation error.
- legacy image alias normalization과 thumbnail budget `thumbTrimmed`.
- delivered key hit + existing message duplicate ACK.
- persist 실패 시 key delete와 emit/push/success ACK 없음.
- 성공 시 `receiveImages` → push → ACK와 key 유지.

video finalize:

- invalid path count, reservation mismatch, duplicate와 persist error.
- attachment metadata mapping.
- 성공 시 `receiveVideo` → push → ACK와 key 유지.

공통:

- invalid media kind ACK.
- delivered state 50,001번째 add가 현재처럼 전체 clear된다.
- 동일 key 처리 중 Promise 병합이나 TTL/LRU 동작이 없음을 current-semantics test로 고정한다.

## media/service 테스트

### `test/media/mediaUploadService.test.js`

- image/video kind normalization.
- reservation TTL 24시간과 `rooms/{roomID}/messages/{messageID}` prefix.
- image count 1...30과 path count `count * 2`.
- video count 1과 path count 2.
- reservation not-found/not-pending/sender/kind/count/path/prefix/expired error.
- existing pending reservation refresh와 신규 reservation write field.
- existing message data 반환.

fake document/reference/snapshot과 deterministic clock/Timestamp factory를 사용한다.

`sequenceStore` transaction의 의미는 변경하지 않으므로 신규 winner 테스트를 추가하지 않는다. 기존 seq 반환 contract는 message/media handler spy로 보호한다.

## lifecycle 테스트

### `test/lifecycle/healthAndShutdown.test.js`

health:

- 정상 `/readyz`, `/healthz`는 200, `ok:true`, service/serverTime/uptime.
- shutdown 시작 후 두 route는 503, `ok:false`.
- `/` service metadata와 health path.

shutdown:

- 첫 signal만 상태를 전환하고 두 번째 signal은 no-op.
- io close 후 listening server close, 정상 exit 0.
- `ERR_SERVER_NOT_RUNNING`은 정상 exit 0.
- 다른 close error는 exit 1.
- 10초 내 종료되지 않으면 force exit 1.
- 정상 종료 후 force timer가 실행되지 않는다.

fake io/server/process exit, deterministic timer와 logger를 사용한다.

## 기존 service의 검증 경계

이번 Phase에서 동작을 변경하지 않는 다음 파일은 모든 내부 분기를 새로 전수 테스트하지 않는다.

- `roomCleanup.js`: room handler service spy와 승인된 smoke로 기존 삭제 순서를 보호한다.
- `sequenceStore.js`: 반환/실패를 handler spy로 보호하며 D40 전까지 signature를 바꾸지 않는다.
- `chatPushService.js`: clock 주입으로 달라지는 device freshness 경계만 필요하면 별도 작은 test를 추가한다.
- `sharedContentValidator.js`: 기존 lookbook handler characterization으로 보호한다.

리팩터링 중 해당 파일의 비시간 로직을 수정해야 하면 구현을 중단하고 테스트 범위를 다시 확정한다.

## 추가하지 않는 자동 테스트

- 실제 Firebase Admin/Firestore/Storage/FCM integration: emulator와 격리 fixture 기준선이 없어 Phase 5 범위를 넘는다.
- 실제 Firebase ID Token 생성·검증: fake verifier로 실패 분기를 고정하고 ADC/IAM은 smoke에서 확인한다.
- 실제 Cloud Run signal/traffic test: 배포는 별도 승인 대상이다.
- D40 concurrency/TTL/LRU/winner: 별도 후속 구현 전 수치와 ACK 계약 확정이 필요하다.
- iOS UI test: Socket wire 계약을 변경하지 않으며 실제 앱 송수신은 수동 QA로 확인한다.
- 성능/load test: 구조 리팩터링 완료 후 실제 지표에서 회귀가 발견될 때 추가한다.

## 수동 QA

### 로컬 필수 smoke

- ADC 확인 후 server start.
- `/`, `/readyz`, `/healthz` 응답.
- SIGTERM 또는 SIGINT graceful shutdown.
- 가능하면 test user token으로 Socket.IO connect와 ready/hello/ping.

### 승인된 staging/운영 배포 후 QA

- Firebase ID Token 정상/누락/만료 연결.
- background/foreground reconnect.
- room create/join/rejoin/leave.
- owner room close와 participant leave.
- text 송수신, reply preview와 FCM.
- lookbook share 송수신.
- image preflight/upload/finalize/duplicate.
- video preflight/upload/finalize/duplicate.
- Cloud Run readiness와 revision log.

운영 데이터 변경과 배포는 별도 사용자 승인을 받으며, 테스트 room/media fixture와 정리 절차를 먼저 기록한다.

## 실행 순서

각 Step 완료 시 관련 test를 먼저 실행하고, Step 5H에서 전체를 실행한다.

```bash
npm --prefix Socket run check
npm --prefix Socket test
```

정적 확인 후보:

```bash
rg -n "socket\.on|io\.use|runTransaction|\.collection\(" Socket/index.js
rg -n "initializeFirebaseAdmin\(\)|admin\.firestore\(\)" Socket/src/firebaseAdmin.js
rg -n "new Map\(|new Set\(" Socket/src/auth Socket/src/handlers
rg -n "inFlight|LRU|winner|expiresAt.*cache" Socket/src/media
```

로컬 health smoke는 임의 포트와 ADC 준비 여부를 확인한 뒤 수행한다. ADC가 없으면 자동 test/check까지만 완료하고 실제 Firebase start는 보류 사유를 기록한다.

## 테스트 실행 필요 여부

- 구현 중: Step별 관련 `node:test`와 syntax check를 실행한다. event/ACK/서버 상태 회귀 비용이 높아 실행이 필요하다.
- 구현 완료: 전체 `npm --prefix Socket run check`, `npm --prefix Socket test`를 필수로 실행한다.
- 운영 배포 전: 로컬 health/shutdown smoke와 배포 revision/rollback 기록이 필요하다.
- 구현 결과: `npm --prefix Socket run check`와 `npm --prefix Socket test`를 실행해 43개 테스트가 통과했다.
- ADC 기반 local start에서 Firestore room preload, `/readyz`·`/healthz` 200과 SIGINT graceful shutdown을 확인했다.
- Cloud Run smoke, iOS 실제 송수신 QA와 운영 배포는 별도 승인 대상으로 보류했다.
