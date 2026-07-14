# Socket Module Design

## 목표

Socket/index.js를 server bootstrap으로 축소하고 auth, connection, room, message, media, lifecycle handler와 service를 분리한다.

## 목표 흐름

~~~text
Socket/index.js
  → runtime dependency 생성
  → middleware와 handler 등록
  → HTTP/Socket server 시작과 종료
~~~

## 추가 분리 후보

- app/createSocketServer.js
- auth/socketAuthMiddleware.js
- handlers/connectionHandlers.js
- handlers/roomHandlers.js
- handlers/messageHandlers.js
- handlers/mediaHandlers.js
- media/mediaUploadService.js
- media/messagePayloadNormalizer.js
- lifecycle/shutdown.js

## 현재 재사용할 패턴

Socket/index.js는 이미 아래 factory를 dependency injection 형태로 사용한다.

- createUserLookup
- createRoomRegistry
- createRoomAccess
- createRoomCleanup
- createSequenceStore
- createChatPushService
- createLookbookShareHandler

새 handler/service도 같은 factory/injection 패턴을 사용해 index.js module global 의존을 줄인다.

## runtime state

아래 process-local mutable state는 handler 파일마다 복제하지 않는다.

- connectAttempts.
- delivered image keys.
- delivered video keys.
- room registry.
- shutdown state.

명시적인 runtime state 또는 각 capability owner가 한 번 생성하고 필요한 handler에 주입한다.

Phase 5에서는 현재 delivered-key 동작을 보존하며 state owner만 명시화한다. 동시 media finalize 요청을 실제로 병합하는 in-flight Promise, TTL/LRU 완료 캐시와 Firestore transaction winner 기반 단일 emit/push는 [D40 후속 강화](../decisions/phase-5-socket.md#d40-media-dedupe는-in-flight-병합-bounded-완료-캐시와-단일-side-effect-방식으로-후속-강화한다)에서 별도로 구현한다.

## 보존 계약

- Socket event 이름.
- payload와 ACK 형식.
- Firebase ID Token handshake.
- room join/leave 순서.
- message sequence 할당과 persist 순서.
- media preflight/finalize idempotency.
- FCM fanout 시점.
- readyz/healthz 응답.
- Cloud Run PORT와 graceful shutdown.

## 테스트 방향

- handler factory에 fake socket/io/db/service를 주입한다.
- event registration과 ACK를 Node built-in test로 검증하는 방식을 추천한다.
- 실제 Socket.IO transport, Cloud Run TLS, Firebase Admin은 smoke QA로 보완한다.
- 사용자 승인으로 Phase 5에서 Socket/package.json에 `node:test` 기반 test 명령을 추가한다.
- D40 후속 단계에서는 deterministic clock으로 TTL/LRU를 검증하고, 같은 instance의 Promise 병합과 서로 다른 instance의 transaction winner를 fake로 검증한다.

## 완료 기준

- index.js는 dependency 생성, handler 등록, start/shutdown 조립만 담당한다.
- handler가 fake dependency로 검증 가능하다.
- process-local state owner가 명확하다.
- event/ACK/auth/persist/fanout 계약이 유지된다.
- syntax check와 승인된 자동 테스트 및 smoke QA가 통과한다.

구체적인 변경 파일과 Step 5A~5H는 [Phase 5 구현 계획](../phases/phase-5-socket.md), test file과 fake/spy·수동 QA는 [Phase 5 테스트 계획](../phases/phase-5-socket-tests.md)을 따른다.
