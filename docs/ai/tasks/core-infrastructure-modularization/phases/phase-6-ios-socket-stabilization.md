# Phase 6 iOS Socket Reconnect Stabilization

## 상태와 승인 경계

- 2026-07-14 사용자 승인으로 추천안 A를 D49로 확정했다.
- 이 문서는 배포 후 발견된 iOS Socket reconnect 크래시의 변경 파일, 구현 순서, 자동 테스트와 수동 QA를 고정한다.
- 2026-07-14 사용자 구현 승인 후 Step 6H-1~5를 모두 완료했고 실제 reconnect gate를 통과했다.
- 현재 Socket revision `outpick-socket-00006-k8k`와 Firebase Functions 49개 배포는 유지한다. 서버 계약 회귀 증거가 없으므로 이 안정화 계획만으로 rollback하지 않는다.

## 핵심 문제

개발 앱 완전 재실행 시 `server:connect:ready` 처리 직후 `SocketIOClient.handleEvent`의 handler 배열 subscript에서 `Index out of range`가 발생했다.

확인된 사실:

- crash report의 faulting thread는 Socket.IO handler 배열을 순회 중이었다.
- 동시에 `RealtimeSocketService.handleConnected()`에서 message listener의 `off/on` 재등록이 수행됐다.
- `RealtimeSocketService.swift`는 배포 candidate에서 변경되지 않았다.
- 새 Socket server의 `server:connect:ready` payload와 `room list` 전송 순서는 previous source와 동일하다.
- `.log(true)`가 Socket handshake raw payload를 console에 기록한다.

가장 유력한 원인은 Socket.IO event dispatch 중 다른 executor에서 handler collection을 변경하는 경쟁 상태다. 수정 후 반복 reconnect 검증 전까지 최종 원인 확정으로 단정하지 않는다.

## D49 확정 구조

1. 한 `SocketIOClient`가 생성될 때 lifecycle과 domain event listener를 연결 전에 한 번만 등록한다.
2. active connection과 reconnect 중 `off/on`으로 handler를 재등록하지 않는다.
3. chat/image/video/room-closed listener lifetime은 해당 `SocketIOClient` lifetime과 동일하게 유지한다.
4. room consumer가 없을 때 수신된 event는 현재 actor state에서 안전하게 drop한다.
5. socket identity가 바뀌어 새 `SocketManager`/`SocketIOClient`를 만들 때만 새 listener binder를 만든다.
6. Socket.IO raw logger는 비활성화한다. 앱이 소유한 상태·오류 로그만 유지한다.
7. Socket event 이름, payload, ACK, reconnect policy, room membership과 서버 배포 계약은 변경하지 않는다.

## 변경 파일 후보

| 파일 | 변경 |
| --- | --- |
| `OutPick/Infra/Realtime/RealtimeSocketService.swift` | socket 생성 직후 one-time binder 조립, connect 중 listener off/on과 listener flag/detach 경로 제거, raw logger 비활성화 |
| `OutPick/Infra/Realtime/RealtimeSocketListenerBinder.swift` | listener 등록만 표현하는 좁은 내부 Protocol, production Socket.IO adapter와 one-time binder |
| `OutPickTests/RealtimeSocketListenerBinderTests.swift` | fake listener로 1회 등록·재호출 무효·event surface·raw off 부재 검증 |
| `OutPick.xcodeproj/project.pbxproj` | 파일이 자동 포함되지 않는 프로젝트 구조일 때만 target membership 추가 |
| `docs/ai/entrypoints/CHAT.md` | Socket listener lifetime, reconnect 경계와 QA 진입점 기록 |
| `docs/ai/entrypoints/TESTS.md` | targeted test와 reconnect 수동 QA 경로 기록 |
| `docs/ai/tasks/core-infrastructure-modularization/*` | D49 구현·검증·배포 후 QA 결과 갱신 |
| `HANDOFF.md` | 현재 blocker와 다음 실행 지점 갱신 |

## 경계 설계

`RealtimeSocketListenerBinder`는 Socket 연결, emit, ACK, room state를 소유하지 않는다. 다음 listener 등록 surface만 감싼다.

- client event: connect, error, disconnect.
- server event: `server:connect:ready`.
- message event: `chat message`, `receiveImages`, `receiveVideo`.
- room event: `room:closed`.

각 callback은 기존처럼 `Task { await service... }`로 `RealtimeSocketService` actor에 전달한다. Binder는 한 번 bind된 뒤 같은 Socket 인스턴스에 대한 재호출을 무시한다.

`RealtimeSocketService`는 다음 동적 listener lifecycle을 제거한다.

- connect 직후 `bindMessageListenersIfNeeded()`.
- room session 종료 시 chat/image/video listener detach.
- room-closed observer 추가/제거 시 `off/on`.
- listener별 `is*ListenerBound` flag.
- 새 Socket에 불필요한 선행 `off`.

## 구현 순서

### Step 6H-1. Characterization seam

1. Socket event 등록에 필요한 최소 callback 타입과 Protocol을 정의한다.
2. `SocketIOClient` production adapter를 연결한다.
3. fake가 등록 event와 횟수를 기록할 수 있게 한다.

완료 기준:

- emit/ACK/manager 전체를 추상화하지 않는다.
- production wire 동작을 변경하지 않은 상태에서 binder 단위 테스트가 compile된다.

### Step 6H-2. One-time binding

1. 새 Socket 생성 직후 binder를 생성하고 모든 listener를 한 번 등록한다.
2. connect callback에서는 emit/rejoin만 수행하고 listener collection을 변경하지 않는다.
3. room consumer와 room-closed continuation 종료 시 listener를 detach하지 않는다.
4. 새 Socket 교체 시 기존 manager disconnect 후 새 binder로 교체한다.

완료 기준:

- active connection 경로에서 `SocketIOClient.off` 호출이 없다.
- reconnect 횟수와 무관하게 같은 Socket 인스턴스의 handler 수가 증가하지 않는다.
- consumer가 없는 message는 기존 drop 정책을 유지한다.

### Step 6H-3. Raw logging 제거

1. SocketManager의 `.log(true)`를 제거한다.
2. ID Token, Authorization header와 auth payload가 앱 console에 출력되지 않는지 확인한다.
3. 연결 성공·실패·reconnect 상태를 판단할 최소 앱 로그는 유지한다.

완료 기준:

- 인증 secret이 raw Socket.IO log에 남지 않는다.
- 운영 연결 진단에 필요한 비민감 상태 로그는 유지된다.

### Step 6H-4. 자동 검증과 빌드

1. binder targeted unit test를 실행한다.
2. 기존 Phase 6 iOS targeted tests를 재실행한다.
3. generic Simulator build를 실행한다.

완료 기준:

- 신규/기존 targeted test와 build가 통과한다.
- Functions/Socket source에는 변경이 없다.

### Step 6H-5. 배포 후 iOS reconnect gate 재개

1. 로그인 세션 앱 완전 종료 후 재실행을 최소 5회 반복한다.
2. background/foreground reconnect를 최소 5회 반복한다.
3. 각 회차에서 authenticated connect/ready, room rejoin과 text 송수신을 확인한다.
4. crash report, 중복 handler 반응, 중복 message/ACK와 신규 Socket server error log가 없는지 확인한다.
5. 통과 후 남은 Functions read smoke와 전체 Phase 2~6 수동 QA를 재개한다.

완료 기준:

- `Index out of range`가 재현되지 않는다.
- handler duplicate, message duplicate와 reconnect loop가 없다.
- raw log에 Firebase ID Token 또는 Authorization 값이 없다.

## 테스트 설계

### 자동 테스트 대상

`OutPickTests/RealtimeSocketListenerBinderTests.swift`:

1. 첫 bind가 client event 3개와 named event 5개를 각각 한 번 등록한다.
2. 같은 binder의 두 번째 bind는 등록 횟수를 늘리지 않는다.
3. connect callback을 반복 실행해도 listener 등록 횟수가 바뀌지 않는다.
4. 새 binder와 새 fake socket은 독립적으로 listener를 한 번 등록한다.
5. `chat message`, image, video와 room-closed callback이 기존 actor bridge closure로 전달된다.
6. binder Protocol에는 handler mutation을 위한 `off` surface가 없다.

필요한 test double:

- `SocketEventListenerSpy`: client/named event와 callback을 저장한다.
- `RealtimeSocketListenerCallbacksSpy` 또는 closure counter: event별 actor bridge 호출을 기록한다.

### 기존 자동 회귀

- Phase 2 Cloud Functions targeted tests.
- Phase 3 GRDB/Chat targeted tests.
- D19 bootstrap unit/UI tests.
- generic Simulator build.

Socket server와 Functions source가 바뀌지 않으므로 Node test/lint/build 재실행은 필수 범위가 아니다. 최종 통합 회귀를 다시 묶을 때는 기존 Phase 6 명령을 사용할 수 있다.

### 수동 QA

- 앱 cold launch reconnect 5회.
- background/foreground reconnect 5회.
- 기존 room 자동 rejoin.
- text send/receive와 중복 부재.
- image/video/lookbook share는 전체 QA 단계에서 각 1회.
- console과 runtime log의 credential 비노출.

### 보류할 테스트와 이유

- 실제 운영 Socket을 호출하는 unit test: 자격 증명과 timing에 의존하므로 deterministic unit test가 아니다.
- race를 sleep으로 재현하는 test: 불안정하고 false pass 가능성이 높아 사용하지 않는다.
- Socket.IO 라이브러리 내부 handler 배열 직접 검사: 외부 라이브러리 private 구현에 결합되므로 등록 spy와 실제 반복 reconnect QA로 대체한다.
- 화면 snapshot test: 화면 렌더링 변경이 아니다.

## 중단 조건

- one-time binding 후 기존 message 수신이 누락된다.
- reconnect 시 room rejoin 또는 ACK 계약이 깨진다.
- 같은 Socket 인스턴스에서 handler 등록이 증가한다.
- 앱 crash, 중복 message/ACK 또는 credential raw log가 남는다.
- 수정 범위가 Socket server event나 Firebase Functions 계약 변경으로 확대된다.

## 완료 조건

- D49 구조가 코드와 자동 테스트에 반영된다.
- targeted test와 generic Simulator build가 통과한다.
- cold launch/background reconnect 반복 gate가 통과한다.
- 남은 Functions read smoke와 전체 수동 QA를 재개할 수 있다.
- CHAT/TESTS/task/HANDOFF 하네스가 실제 구현과 검증 결과를 가리킨다.

## 2026-07-14 구현·자동 검증 결과

- `RealtimeSocketListenerBinder`와 listener 등록 전용 Protocol/Socket.IO adapter를 추가했다.
- `RealtimeSocketService`가 새 Socket 생성 직후 listener 8개를 한 번 등록하도록 전환하고 active reconnect/consumer lifecycle의 모든 `off/on`을 제거했다.
- SocketManager의 `.log(true)`를 제거했다.
- 신규 binder test 5개와 `ChatRoomRealtimeUseCaseTests`, `ChatRoomRuntimeUseCaseTests`, `ChatMessageEmitAckMapperTests`가 통과했다.
- `CODE_SIGNING_ALLOWED=NO` generic Simulator build가 통과했다.
- source 검색에서 `OutPick/Infra/Realtime`의 `socket.off`, `.log(true)`, 제거한 listener flag/detach 경로가 없음을 확인했다.
- Step 6H-5에서 D49 빌드를 로그인 데이터 보존 상태로 iPhone 17 Pro Max Simulator에 설치했다.
- cold launch 5회와 설정 앱을 이용한 background/foreground 5회를 반복했고 모든 회차에서 OutPick 프로세스가 생존했다.
- 해당 구간 신규 crash report는 0건이며 `Index out of range`, crash signal도 재현되지 않았다.
- 수집한 runtime log에서 `Authorization`, `Bearer`, `idToken`, JWT 형태 credential 노출은 모두 0건이었다.
- 사용자가 기존 room 재입장, text 1건 송수신과 화면상 단일 표시를 확인했다.
- 확인 직후 앱 프로세스는 생존했고 Socket revision `outpick-socket-00006-k8k`의 최근 로그에서 room join과 message 관련 entry를 확인했다. ERROR/FATAL entry는 0건이었다.
- D49 Step 6H-5와 안정화 gate를 최종 통과했다.
- 작업 종료 최종화에서 binder/Chat 관련 15개 targeted test와 `CODE_SIGNING_ALLOWED=NO` generic Simulator build가 다시 통과했다.
- 앱 코드 commit은 `4a628dd`, 테스트 commit은 `6ab8d73`이다.
