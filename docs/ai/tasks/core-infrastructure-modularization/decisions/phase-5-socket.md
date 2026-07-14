# Phase 5 Socket Decisions

## 상태

2026-07-14 사용자 승인으로 N14~N26을 D27~D39로 확정했다. media dedupe 강화 방향은 D40 후속 결정으로 기록하되, Phase 5 모듈화에서는 기존 event/payload/ACK와 idempotency 동작을 보존했다. 변경 파일과 Step 5A~5H는 [Phase 5 구현 계획](../phases/phase-5-socket.md), 자동·수동 검증은 [Phase 5 테스트 계획](../phases/phase-5-socket-tests.md)에 기록했다. Step 5A~5H 구현과 자동 검증을 완료했으며 Cloud Run 배포는 수행하지 않았다.

## D27. Node 22 JavaScript ESM을 유지한다

- Phase 5에서는 TypeScript 전환이나 새 runtime framework를 도입하지 않는다.
- 현재 `package.json`의 ESM 경계와 Cloud Run Node 22 실행 경계를 유지한다.
- 구조 리팩터링과 언어·빌드 체계 변경을 분리한다.

## D28. index.js는 bootstrap과 lifecycle 조립만 담당한다

- `index.js`는 설정 확인, dependency 생성, application 생성, listen, signal/shutdown 조립만 담당한다.
- event handler body, Firestore query, media normalization, room 정책과 rate-limit 구현을 두지 않는다.
- 소스 파일 수가 늘어도 기존 Docker image 하나와 Cloud Run service 하나로 배포한다.

## D29. createSocketApplication factory를 application 조립 경계로 둔다

- Express, HTTP server와 Socket.IO server 생성, HTTP route와 middleware/handler 등록을 application factory에서 조립한다.
- factory는 listen을 직접 시작하지 않고 생성된 application/server handle을 반환한다.
- test는 실제 PORT를 열지 않고 registration과 lifecycle dependency를 검증할 수 있어야 한다.

## D30. Firebase Admin 초기화는 명시적인 bootstrap dependency로 만든다

- Firebase Admin import 자체가 초기화 부작용을 일으키지 않게 한다.
- bootstrap이 Firebase dependency를 한 번 생성해 application/service에 주입한다.
- handler가 Admin singleton을 새로 초기화하거나 넓은 Admin 객체 전체를 직접 받지 않는다.

## D31. 기능별 register*Handlers factory를 사용한다

- connection, room, message, media, disconnect/lifecycle 경계로 event 등록 책임을 나눈다.
- handler factory는 자신이 등록하는 event와 필요한 dependency만 안다.
- 함수 하나당 파일 하나를 강제하지 않고 같은 변경 이유와 dependency를 공유하는 handler를 묶는다.

## D32. handler는 좁은 service에 의존하고 service가 db/admin 세부사항을 소유한다

- handler는 payload/auth/ACK 변환과 service 호출을 담당한다.
- Firestore transaction, Storage 삭제, push fanout 같은 작업 단위 부작용은 service가 소유한다.
- 모든 helper에 interface/factory를 강제하지 않고 실패 순서와 비동기 경합을 검증해야 하는 경계에 dependency seam을 둔다.

## D33. process-local mutable state의 owner를 분명히 한다

- socket application runtime은 connection/shutdown 상태를 소유한다.
- room registry는 room/user projection을 소유한다.
- rate limiter는 자신의 key/window state를 소유한다.
- media dedupe state는 media capability가 소유하며 module top-level `Map`/`Set`을 handler마다 추가하지 않는다.
- process-local state를 Cloud Run 인스턴스 간 공유 상태로 간주하지 않는다.

## D34. clock과 ID generator를 주입 가능하게 한다

- handler/service가 `Date.now()`와 `Math.random()`에 직접 흩어져 의존하지 않게 한다.
- production 기본 구현은 현재 시간과 현재 message ID 생성 의미를 보존한다.
- 테스트는 deterministic clock과 ID generator로 TTL, rate limit, ACK payload를 검증한다.

## D35. event/payload/ACK 형식을 그대로 보존한다

- 전역 success/error envelope를 새로 도입하지 않는다.
- 기존 event 이름, callback 호출 여부, optional key와 error code를 characterization test로 고정한다.
- iOS retry/outbox가 의존하는 ACK timing과 persist→emit→push→ACK 순서를 구조 정리 목적으로 변경하지 않는다.

## D36. Phase 5에서는 media dedupe 의미를 변경하지 않는다

- 현재 image/video delivered-key, Firestore message 확인, reservation과 sequence transaction 의미를 보존한다.
- Phase 5에서는 process-local delivered state를 명시적인 owner로 옮기되 동시 요청 병합, TTL/LRU와 side-effect winner 의미를 추가하지 않는다.
- media dedupe 강화는 D40의 별도 후속 단계로 구현·검증한다.

## D37. startup, health와 graceful shutdown 계약을 보존한다

- `/`, `/readyz`, `/healthz`, Cloud Run `PORT`, 종료 중 503 의미를 유지한다.
- SIGTERM/SIGINT 시 신규 요청 차단, Socket.IO/HTTP server 종료와 강제 종료 fallback 순서를 보존한다.
- lifecycle을 application 생성과 분리해 fake server/timer로 검증할 수 있게 한다.

## D38. dependency 없는 재귀 node:test runner를 사용한다

- 새 test framework dependency를 추가하지 않는다.
- Node built-in `node:test`를 사용하고 하위 `*.test.js`를 재귀 발견한다.
- test가 0개 발견되면 성공으로 처리하지 않는다.
- `npm --prefix Socket run check`와 test runner를 Phase 5 필수 자동 검증으로 둔다.

## D39. 배포 단위와 운영 배포 절차를 변경하지 않는다

- 기존 Docker image 하나와 Socket Cloud Run service 하나를 유지한다.
- MSA, Kubernetes, 별도 media service와 새 데이터 저장소를 추가하지 않는다.
- Phase 5 구현 중 운영 배포하지 않고 전체 check/test 완료 후 별도 사용자 승인을 받는다.

## D40. media dedupe는 in-flight 병합, bounded 완료 캐시와 단일 side effect 방식으로 후속 강화한다

### 해결할 현재 한계

- 현재 delivered `Set`은 같은 key가 처리 중이어도 Firestore message가 아직 없으면 후속 요청이 다시 finalize를 진행할 수 있다.
- Firestore transaction은 같은 message document와 sequence의 이중 생성을 막지만, transaction 이후의 Socket emit과 FCM push는 요청별로 다시 실행될 수 있다.
- key가 50,000개를 넘으면 전체 `clear()`하여 process-local 최적화가 한 번에 사라진다.
- process-local `Set`만으로는 서로 다른 Cloud Run instance의 동시 요청을 조정할 수 없다.

### 확정한 목표 동작

1. media dedupe capability는 `kind + roomID + messageID` namespace로 key를 구분한다.
2. 같은 instance에서 첫 요청은 owner가 되고, 같은 key의 후속 요청은 owner의 in-flight Promise 결과를 기다린다.
3. owner 성공 결과는 TTL과 최대 용량이 있는 LRU 완료 캐시에 제한적으로 보관한다.
4. 실패한 in-flight entry는 모든 실패 경로에서 해제해 재시도를 허용한다.
5. Firestore sequence/persist transaction은 `seq`뿐 아니라 새 message를 만든 winner인지 나타내는 결과를 반환한다.
6. transaction winner만 Socket emit과 FCM push를 수행한다. 이미 존재한 message를 확인한 요청은 side effect를 반복하지 않고 duplicate ACK를 반환한다.
7. Firestore message/reservation을 교차 instance의 최종 권위로 유지하고 local cache는 정확성의 유일한 근거로 사용하지 않는다.
8. 용량 초과 시 전체 cache를 비우지 않고 만료되었거나 가장 오래 사용되지 않은 entry부터 제거한다.

### 구현 전에 추가로 수치화할 항목

- 완료 결과 TTL.
- image/video 통합 최대 entry 수와 eviction 단위.
- in-flight 최대 대기 시간과 owner가 응답하지 않을 때의 timeout/error mapping.
- 동시 follower의 duplicate ACK optional key와 callback timing을 기존 iOS 계약과 대조한 최종 fixture.
- process 종료 중 in-flight 요청을 기다릴 시간과 취소 정책.

위 수치는 Phase 5 구조 리팩터링에 임의로 포함하지 않고 D40 구현 계획 승인 전에 확정한다.

### 필수 자동 테스트

- 같은 instance에서 같은 message ID를 동시에 두 번 finalize해 persist/emit/push가 각각 한 번만 호출된다.
- 서로 다른 local state를 가진 두 instance를 모사해 Firestore transaction winner만 emit/push한다.
- follower는 owner 완료 후 같은 `messageID`와 `seq`의 duplicate ACK를 받는다.
- owner 실패 시 follower가 같은 실패를 받고 entry가 해제되며 다음 요청은 재시도할 수 있다.
- 성공 결과가 TTL 전에는 재사용되고 TTL 후에는 Firestore 권위 확인 경로로 돌아간다.
- 최대 용량 초과 시 LRU entry만 제거되고 in-flight entry는 임의 제거되지 않는다.
- image와 video key namespace가 충돌하지 않는다.
- persist 실패 시 emit/push/success ACK가 없고, duplicate transaction 결과에서는 emit/push가 없다.

## 선택하지 않은 대안

- Phase 5에서 dedupe 의미까지 동시에 변경: 구조 이동 회귀와 동시성 동작 변경을 분리하기 어렵다.
- process-local Promise만으로 단일 side effect 보장: 같은 instance에는 유효하지만 여러 Cloud Run instance를 포괄하지 못한다.
- Redis 같은 새 분산 lock 저장소 도입: 현재 Firestore transaction으로 winner를 결정할 수 있어 운영 복잡성 증가 근거가 부족하다.
- 무제한 완료 Map/Set: 장기 실행 instance에서 메모리 상한이 없다.
- 용량 초과 시 전체 clear: 갑작스럽게 local dedupe 효과가 사라진다.

## 재검토 조건

- media finalize 처리량이나 Firestore read 비용이 실제 병목으로 측정되면 TTL/용량과 cache 계층을 재조정한다.
- Socket emit 또는 FCM fanout의 exactly-once 수준이 요구되고 현재 transaction winner만으로 장애 복구가 부족하면 transactional outbox를 별도 설계한다.
- media 기능을 독립 배포해야 할 구체적인 scaling/IAM/장애 격리 요구가 생기면 ADR-019의 배포 경계를 재검토한다.
