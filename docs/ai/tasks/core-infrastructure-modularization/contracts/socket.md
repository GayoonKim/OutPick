# Socket Contract Inventory

## 현재 경계

- 진입점: `Socket/index.js`.
- 배포 단위: 기존 단일 Cloud Run service와 Docker image를 유지한다.
- 현재 이미 분리된 요소: config, Firebase Admin, room access/cleanup/registry, sequence store, push service, lookbook share, message preview, user lookup.
- process-local state: connect attempts, image/video delivered key, rooms, shutdown 상태.

## HTTP 계약

| route | 정상 응답 | 종료 중 | 목표 owner |
| --- | --- | --- | --- |
| `/readyz` | 현재 health JSON과 200 | 503 | app/lifecycle |
| `/healthz` | 현재 health JSON과 200 | 503 | app/lifecycle |
| `/` | service metadata | 기존 동작 유지 | app/bootstrap |

## connection middleware 계약과 순서

1. reconnect attempt/rate 정책을 검사한다.
2. Firebase ID token을 `socket.handshake.auth` 또는 header에서 읽는다.
3. token을 검증하고 `socket.userUID`, user document/email 정보를 설정한다.
4. 인증된 socket에 connection handler를 등록한다.

연결 거절 계약:

- reconnect 초과: `connect_error`, `max_connect_attempts_exceeded`.
- token 없음: `unauthenticated` + `missing_id_token`.
- token UID 없음: `unauthenticated` + `missing_token_uid`.
- 잘못된 token: `unauthenticated` + `invalid_id_token`.

## server → client event

| event | payload 핵심 | 발생 조건 |
| --- | --- | --- |
| `server:connect:ready` | `policy`, `serverTime`, `socketId` | 인증 연결 완료 |
| `room list` | process-local room ID 목록 | 연결 완료 |
| `username set` | 기존 username payload | username 설정 |
| `joined room` | `roomID` | join 성공 |
| `user list` | room user 목록 | leave/disconnect/membership 변경 |
| `room:closed` | room close 정보 | owner의 room close 성공 |
| `chat message` | persisted server message | text/lookbook share 성공 |
| `receiveImages` | persisted image server message | image finalize 성공 |
| `receiveVideo` | persisted video server message | video finalize 성공 |
| `error` | 기존 문자열/오류 payload | legacy join 등 실패 |

## client → server event와 ACK

| event | 입력 핵심 | success ACK | 주요 error 계약 | 목표 handler |
| --- | --- | --- | --- | --- |
| `client:hello` | `attempt?` | `ok`, `attempt`, `policy`, `serverTime`, `key` | 기존 handshake error | connection |
| `client:ping` | 없음 | `pong`, `serverTime` | 기존 callback 동작 | connection |
| `set username` | username | 별도 ACK 없음, `username set` emit | 기존 동작 | connection |
| `create room` | `roomID` | `ok:true`, `roomID` | `invalid_room_id` | room |
| `join room` | `roomID` | 기존 success ACK | access/not-found error + `error` emit | room |
| `leave room` | `roomID` | 기존 success ACK | 기존 error shape | room |
| `room:leave-or-close` | room/user payload | `ok:true`, `mode:left|closed`, `alreadyDeleted?` | 기존 code/message | room lifecycle |
| `chat message` | text message payload | `ok:true`, `success:true`, `seq`, `messageID` | validation/auth/access/rate/persist error | message |
| `chat:lookbookShare` | lookbook share payload | message와 같은 success shape | schema/size/access/rate error | message/share |
| `chat:mediaPreflight` | room/message/kind/count | pending 또는 duplicate ACK | validation/access/rate/reservation error | media |
| `chat:mediaFinalize` | image/video uploaded payload | `ok:true`, `messageID`, image는 `thumbTrimmed?`; duplicate는 seq 포함 | validation/access/rate/reservation/persist error | media |

ACK의 정확한 optional key와 error code는 Phase 5 변경 직전 `Socket/index.js`를 snapshot하여 test fixture로 고정한다. 리팩터링에서 이름이나 의미를 정리한다는 이유로 변경하지 않는다.

## iOS 소비 계약

`RealtimeSocketService.swift`는 다음 계약을 사용한다.

- emit: `client:hello`, `set username`, `create room`, `join room`, `leave room`, `room:leave-or-close`, `chat message`, `chat:lookbookShare`, media preflight/finalize.
- listen: `server:connect:ready`, `room:closed`, `chat message`, `receiveImages`, `receiveVideo`.
- 이벤트 이름뿐 아니라 ACK callback 호출 여부와 timing도 iOS retry/outbox 흐름의 계약이다.

## 보존해야 할 side-effect 순서

### text와 lookbook share

1. payload/auth/room/access/size/rate 검증.
2. sequence 할당과 Firestore persist.
3. room에 `chat message` emit.
4. FCM fanout을 fire-and-forget으로 요청.
5. client ACK.

persist 실패 시 emit/FCM/success ACK를 수행하지 않는다.

### media preflight/finalize

- preflight는 validation/access/rate 검사 후 Firestore reservation을 만들고 duplicate/pending 의미를 유지한다.
- finalize는 delivered-key와 reservation으로 idempotency를 확인한다.
- sequence/persist와 reservation 삭제는 현재와 같은 transaction 경계를 유지한다.
- persist 성공 후 image는 `receiveImages`, video는 `receiveVideo`를 emit하고 push 후 ACK한다.

현재 delivered `Set`은 이미 persist된 duplicate를 빠르게 확인하는 process-local hint이며, 처리 중인 동일 요청을 기다리게 하지는 않는다. Firestore transaction은 message/seq 중복 생성을 막지만 transaction 이후 emit/push의 요청별 중복 실행 가능성은 별도 D40 개선 대상이다. Phase 5 모듈화는 이 의미를 변경하지 않는다.

D40 후속 목표는 같은 instance에서 in-flight Promise를 공유하고, Firestore transaction이 새 message 생성 winner인지 반환하게 하여 winner만 emit/push하도록 만드는 것이다. 완료 결과는 bounded TTL/LRU cache에 두되 Firestore message/reservation을 instance 간 최종 권위로 유지한다. 상세 결정은 [Phase 5 Socket 결정](../decisions/phase-5-socket.md)을 따른다.

### room close

Storage prefix와 사용자 projection, subcollection, room document 정리 순서를 보존한다. 성공 후 `room:closed`를 emit하고 socket room/process-local 상태를 정리한다.

## runtime state 목표

- `createSocketRuntimeState()`가 process-local map/set과 shutdown 상태를 한 번 생성한다.
- middleware/handler factory가 필요한 state와 service만 주입받는다.
- module top-level에서 독자적인 map/set을 추가하지 않는다.
- Cloud Run instance 간 공유 상태로 오해하지 않도록 Firestore idempotency와 process-local dedupe 역할을 분리한다.

## 목표 source 구조

- `index.js`: dependency 생성, server start, signal/shutdown 조립.
- `src/app/`: HTTP/Socket.IO server 생성과 handler 등록.
- `src/auth/`: reconnect와 Firebase auth middleware.
- `src/handlers/`: connection, room, message, media handler.
- `src/media/`: payload normalization, reservation/finalize service.
- `src/lifecycle/`: health와 graceful shutdown.

## Phase 5 회귀 기준

- Node `node:test`로 event 등록, ACK success/error, 인증 거절, persist→emit→push→ACK 순서를 검증한다.
- `npm --prefix Socket run check`와 새 test 명령을 통과한다.
- readyz/healthz와 graceful shutdown을 로컬로 검증한다.
- Docker/Cloud Run 배포는 별도 사용자 승인 전 수행하지 않는다.
