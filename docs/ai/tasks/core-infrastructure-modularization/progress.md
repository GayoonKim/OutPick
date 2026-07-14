# Core Infrastructure Modularization Progress

## 현재 상태

- 상태: 완료. Phase 2~5 구현과 자동 검증, Phase 6 동일 SHA 회귀·운영 배포·D49 안정화·통합 수동 QA를 마쳤다.
- 현재 phase: 종료. FCM fanout은 Apple 개발자 계정 결제 후 별도 QA로 이관했다.
- 코드 변경: iOS 공통 Functions transport/기능 adapter, `AppDatabase`/기능별 GRDB Store, Firebase Functions core/feature module, Socket application/handler/service/state/lifecycle과 계약 테스트 반영.
- 배포: Socket `outpick-socket-00006-k8k` traffic 100%, Firebase Functions 49개 source hash `6ab1e46ab24ec61401c312e92ad4e7e1c5c133d9`.

## 완료한 작업

### 2026-07-14 작업 종료 최종화

- `active.md`에서 현재 핵심 task를 비우고 `core-infrastructure-modularization`을 최근 완료 작업으로 이동했다.
- FCM fanout, D40 media dedupe, Firestore `@DocumentID` 경고와 일부 선택적 화면 QA를 각각 별도 후속으로 분리했다.
- D49 binder/Chat 관련 15개 targeted test와 `CODE_SIGNING_ALLOWED=NO` generic Simulator build가 재통과했다.
- D49 앱 코드 commit `4a628dd`, 테스트 commit `6ab8d73`을 생성했다.
- tracked entrypoint와 `HANDOFF.md`, 로컬 task plan/progress/QA/Phase 문서를 실제 완료 상태로 갱신했다.

### 2026-07-14 Phase 6 이전 메시지 pagination 수동 QA

- 사용자 승인으로 공개 room `QA-P6-PAGE-0714`와 text message 105개(`QA-P6-PAGE-001...105`, `seq 1...105`)를 전용 fixture로 구성했다.
- `lastReadSeq=105`, room latest `seq=105` 상태와 비어 있는 로컬 room cache에서 재진입해 `latestTail` 최초 80개가 `seq 26...105`로 로드되는 것을 확인했다.
- debugger breakpoint에서 `ChatViewController.loadOlderMessages(before: "qa-p6-page-0714-026")` 실제 호출을 포착했다.
- 호출 전 GRDB는 80개·`minSeq=26`·`maxSeq=105`, 호출 완료 후 105개·`minSeq=1`·`maxSeq=105`였고 ID와 seq의 distinct count도 각각 105로 중복이 없었다.
- 화면을 최상단까지 스크롤해 `QA-P6-PAGE-001` 노출을 확인했다.
- 방장 종료 후 Firestore room과 joined projection은 `NOT_FOUND`, members/messages는 0건이었다. GRDB message/FTS/outbox/image/video/profile/roomImage 관련 row도 모두 0건으로 fixture cleanup을 완료했다.

### 2026-07-14 Phase 6 실패 메시지 재시도 수동 QA

- 운영 서버나 호스트 네트워크를 중단하지 않고 Simulator 앱 프로세스의 `RealtimeSocketService.sendMessage` 진입점에서 해당 process의 `socket` 참조만 일시적으로 `nil` 처리해 텍스트 전송 실패를 통제 재현했다.
- `OOTD 공유`의 `재시도-0714` 버블에 실패 아이콘이 표시됐고, GRDB에서 동일 message ID의 `isFailed=1`과 text outbox `stage=failed`를 확인했다.
- 실패 아이콘은 접근성 target을 노출하지 않아 debugger에서 같은 `confirmRetryUpload(for:)` 진입점을 호출한 뒤 실제 확인 UI의 `재시도` 버튼을 탭했다. 따라서 확인 UI 이후 retry 경로는 검증했지만 실패 아이콘 자체의 실제 좌표 탭은 수행하지 않았다.
- room 재진입으로 Socket을 복구한 뒤 retry가 성공했고 실패 아이콘이 사라지며 server sequence가 부여됐다.
- Firestore에 동일 message ID 문서가 존재하고 Socket server 수신은 1회였으며, GRDB는 해당 message 1건·`isFailed=0`·outbox 0건이었다.
- 앱 완전 종료·재실행 후에도 같은 메시지가 정상 상태로 1건만 복원됐고 최근 Socket `severity>=ERROR` 로그는 0건이었다.

### 2026-07-14 Phase 6 일반 구성원 leave·local cleanup 수동 QA

- Kakao 방장 계정으로 공개 room `QA-P6-LEAVE-0714`를 앱 UI에서 생성했다.
- Firestore room ID는 `erwk4SfDZwjBA8FEvA5e`다.
- 별도 Google 로그인 사용자가 room에 가입해 테스트 메시지 1건을 전송한 뒤 설정 화면의 일반 구성원 종료 확인 UI로 leave했다.
- leave 후 Google 사용자에게 room이 목록에서 제거됐고, Firestore room과 방장 member 및 `Messages` 1건은 유지되는 반면 Google member 문서는 제거됐다.
- Simulator 운영 `OutPick.sqlite`의 `chatMessage`, FTS, outbox, image/video index와 room profile cache에서 해당 room row가 모두 0건임을 확인했다.
- 같은 시간대 Socket log에서 Google 사용자의 leave request를 확인했고 `ERROR`/`FATAL` 로그는 없었다.
- Kakao 방장 계정으로 복귀해 방장 종료 경고와 복구 불가 안내를 확인하고 fixture room을 닫았다.
- 최종 확인에서 Firestore room 문서는 `NOT_FOUND`, `members`와 `Messages`는 각각 0건이었고 해당 room의 GRDB message/FTS/outbox/media/profile/roomImage row도 모두 0건이었다.
- Socket log에 방장 leave request가 기록됐고 같은 조회 범위의 `ERROR` 이상 로그는 없었다. fixture cleanup까지 완료했다.

### 2026-07-14 Phase 6 room close·local cleanup 수동 QA

- 사용자 승인으로 전용 공개 room `QA-P6-CLOSE-0714`를 앱 UI에서 생성했다.
- 생성자 계정 설정 화면에서 `채팅을 종료하시겠어요?`와 복구 불가 안내를 확인하고 방장 종료를 실행했다.
- 종료 후 room이 앱 목록에서 제거됐고 Socket log에 생성·join·leave request가 기록됐다.
- Firestore `Rooms/2tFXMcmuHzlX3GZ17FXo` 문서는 존재하지 않았고 `members`, `messages` subcollection 조회 결과도 각각 0건이었다.
- Simulator 운영 `OutPick.sqlite`의 `chatMessage`, FTS, outbox, image/video index와 room profile cache에서 해당 room row가 모두 0건임을 확인했다.
- 같은 시간대 Cloud Run Socket `severity>=ERROR` 로그는 0건이었다.
- 일반 구성원 leave는 이후 별도 Google 로그인 계정과 전용 fixture로 검증했다.

### 2026-07-14 Phase 6 채팅 쓰기·GRDB 복원 수동 QA

- 사용자 승인으로 `OOTD 공유` 운영 room에 통제된 테스트 메시지를 전송했다.
- 텍스트 `QA-P6-20260714-TEXT`, 사진 1장, 8초 동영상 1개와 UNAFFECTED 시즌 룩북 공유 1건이 각각 한 번만 표시됐다.
- 앱을 완전히 종료·재실행한 뒤 같은 room에 재진입해 텍스트, 사진, 동영상과 룩북 공유 4종이 모두 복원되는 것을 확인했다.
- 재실행 후 Socket 인증 reconnect와 room join이 정상 동작했고 최근 Cloud Run Socket `severity>=ERROR` 로그는 0건이었다.
- 룩북 공유 server log에서 `contentType: season`과 새 sequence 할당을 확인했다.
- FCM은 사용자가 Apple 개발자 계정 환경 제약을 알렸으므로 이번 QA에서 보류했다. 실제 APNs/FCM 가능 조건은 재확인 필요다.
- 방 나가기/닫기, 실패 메시지 재시도와 이전 메시지 pagination은 후속 통제 QA에서 완료했다.

### 2026-07-14 Phase 6 채팅·GRDB 비파괴 수동 QA

- 사용자가 `OOTD 공유` 채팅방에서 최근 메시지 표시, `12` 키워드 검색, 검색 결과 이동과 앱 완전 재실행 후 같은 방 메시지 복원을 확인했다.
- 사용자가 `해칭룸 정보 공유방`에서 이미지/동영상 모아보기 진입과 표시를 확인했다.
- 위 흐름에서 빈 화면, 무한 로딩, 중복 표시와 크래시는 보고되지 않았다.
- 이전 메시지 pagination은 해당 방의 메시지 수가 적어 추가 page를 만들 수 없었으므로 실패가 아니라 검증 보류로 기록한다.
- 메시지 전송·미디어 업로드·룩북 공유는 후속 쓰기 QA에서 완료했다. 실패 재시도·FCM·방 나가기/닫기는 이 비파괴 묶음에서 수행하지 않았다.

### 2026-07-14 Phase 6 Functions 인증 read smoke

- 로그인 세션이 유지된 iPhone 17 Pro Max Simulator 개발 앱에서 비파괴 읽기 호출만 수행했다.
- `listMyBrandRequests` active scope가 HTTP 200으로 성공했고 앱은 `진행 중인 요청이 없어요` ready 상태를 표시했다.
- `listMyBrandRequests` history scope가 HTTP 200으로 성공했고 앱은 `이전 요청이 없어요` ready 상태를 표시했다.
- `searchBrands`는 빈 결과 경로와 `UNAFFECTED` 실제 결과 1건 경로가 모두 HTTP 200으로 성공했다.
- 같은 시간대 두 Cloud Run service의 `severity>=ERROR` 로그는 0건이었다.
- 데이터 생성·수정·삭제, Functions source 변경과 재배포는 수행하지 않았다.

### Firestore `@DocumentID` console warning 후속 기록

- D49 실제 gate 중 room 목록 문서별 `I-FST000002` 경고가 출력되는 것을 확인했다.
- 가장 유력한 원인은 `ChatRoom.init(from:)`에서 Firestore가 디코딩한 document ID를 wrapped property에 non-nil로 다시 초기화하는 경로다.
- 현재 room 조회/재입장/text 송수신은 정상이고 D49 crash와 직접 관련된 증거는 없다.
- `ChatRoom` backing wrapper 디코딩 최소 수정과 Firestore DTO/domain 분리·중복 `ID` field 제거 중 어느 범위로 갈지는 후속 설계에서 확정한다.
- `SeasonDTO.fromDomain`을 포함한 다른 `@DocumentID` non-nil 초기화 지점도 같은 후속 점검 범위에 둔다.
- 이번 단계에서는 코드와 Firestore data/schema를 변경하지 않았다.

### 2026-07-14 Phase 6 candidate commit과 Socket 배포

- iOS 앱 `db1b9ce`, iOS test `ab8c386`, Functions `04c7474`, Socket `df00999`, 추적 문서 `7580a1e`의 작업 단위별 commit을 생성했다.
- candidate HEAD `7580a1e`에서 iOS targeted unit/UI test와 generic build, Functions 51 test/lint/build, Socket check/43 test/ADC local smoke를 재실행해 통과했다.
- Socket image `7580a1e`를 Cloud Build로 생성하고 digest `sha256:1cec132d...1065a1`을 Cloud Run revision `outpick-socket-00006-k8k`에 traffic 100%로 배포했다.
- root/readyz 200, container health, missing/invalid token 거절과 신규 ERROR log 부재를 확인했다.
- 정상 token 자동 발급 경로는 Password/anonymous provider 비활성화와 token signing 권한 부재로 사용할 수 없었다. 운영 사용자 가장이나 IAM/provider 변경은 하지 않았다.
- 정상 Firebase token connect/ready와 room/message gate가 남아 있어 확정한 중단 조건에 따라 Functions 배포는 수행하지 않았다.

### 2026-07-14 Phase 6 Socket gate 완료와 Functions 배포

- 사용자가 개발 앱에서 정상 Kakao 로그인, 기존 채팅방 진입과 텍스트 1건 전송을 수행했다.
- 새 Socket revision 로그에서 Firebase UID 연결, room join과 text persist/emit 로그 및 `seq: 1`을 확인해 최소 Socket gate를 통과했다.
- candidate HEAD `7580a1e`의 `functions/`가 깨끗한 상태임을 재확인하고 `firebase deploy --only functions --project outpick-664ae`로 전체 배포했다.
- predeploy lint/build와 49개 update가 모두 성공했다. 배포 후 49개가 `ACTIVE`, `asia-northeast3`, `nodejs24`, 동일 source hash `6ab1e46ab24ec61401c312e92ad4e7e1c5c133d9`임을 확인했다.
- trigger 구성은 callable 43개, schedule 3개, Firestore event 3개다. scheduler 3개는 기존 cron과 `Asia/Seoul` timezone으로 `ENABLED` 상태다.
- 비인증 `getBrandAdminCapabilities`는 HTTP 401/`UNAUTHENTICATED`, 로그인 앱 재실행의 인증 호출은 HTTP 200으로 확인했다. 신규 Functions ERROR log는 없었다.
- 앱 완전 재실행 시 Socket 인증 connect/ready 직후 `Swift/ContiguousArrayBuffer.swift:691: Fatal error: Index out of range`가 재현돼 종단 QA를 중단했다.
- crash report는 `SocketIOClient.handleEvent`의 handler 배열 순회 중 subscript에서 종료됐고, 다른 task에서 `RealtimeSocketService.handleConnected()`가 listener off/on을 수행 중이었다. server ready payload/order와 iOS service source는 이전 배포 기준과 동일해 이번 서버 모듈화의 wire 변경 증거는 없다.
- `RealtimeSocketService`의 event handler 재등록 thread-safety 수정 여부와 별도 작업 범위를 사용자와 확정하기 전 코드는 변경하지 않는다.

### 2026-07-14 D49 iOS Socket reconnect 안정화 결정

- 추천안 A를 별도 Step 6H와 D49로 확정했다.
- 새 `SocketIOClient` 생성 시 lifecycle/chat/image/video/room-closed listener를 연결 전에 한 번 등록하고 active reconnect 중 `off/on`을 금지한다.
- listener lifetime은 Socket client lifetime과 같게 유지하며 consumer 부재는 `RealtimeSocketService` actor state에서 처리한다.
- Socket.IO `.log(true)`를 제거해 handshake credential raw logging을 차단한다.
- 전체 Socket client를 추상화하지 않고 listener 등록만 담당하는 좁은 Binder/Protocol과 fake spy test를 계획했다.
- cold launch와 background/foreground reconnect를 각각 5회 반복하는 수동 gate를 통과한 뒤 남은 Functions read smoke와 전체 QA를 재개한다.
- 사용자 승인 후 `RealtimeSocketListenerBinder`와 등록 전용 Protocol/adapter를 추가하고, 새 Socket 생성 직후 lifecycle/named listener 8개를 한 번만 등록하도록 구현했다.
- reconnect와 room consumer lifecycle의 `off/on`, listener flag/detach 경로를 제거하고 Socket.IO `.log(true)`를 삭제했다.
- binder test 5개와 관련 Chat realtime/runtime/ACK 회귀 테스트, generic Simulator build가 통과했다.
- iPhone 17 Pro Max Simulator에서 D49 빌드의 cold launch와 background/foreground를 각각 5회 반복했고 모든 회차에서 앱이 생존했다.
- 신규 crash report와 `Index out of range`/crash signal은 0건이었다. runtime log의 Authorization/Bearer/idToken/JWT 형태 credential 노출도 0건이었다.
- 사용자가 기존 room 재입장, text 1건 송수신과 화면상 단일 표시를 확인했다.
- 앱 프로세스 생존과 Socket revision `outpick-socket-00006-k8k`의 최근 room join/message 관련 log, ERROR/FATAL 0건을 확인해 D49 gate를 최종 마감했다.

### 2026-07-14 Phase 6 Step 6A와 전체 자동 회귀

- 운영 Functions 49개가 모두 ACTIVE이고 동일 Firebase source hash를 사용하는 것을 확인했다.
- 대표 배포 source archive 전체 `src`, package/lock, TypeScript/ESLint 설정이 Git HEAD `ccc141e`의 `functions/`와 일치해 prior Functions rollback source를 확보했다.
- archive의 환경 파일은 읽거나 보존하지 않고 비교 후 임시 디렉터리를 삭제했다.
- Socket previous ready revision `outpick-socket-00005-jwg`, traffic 100%, image digest와 service 설정을 기록했다.
- iOS Phase 2/3/D19 관련 unit 21개 test type, D19 UI suite와 generic Simulator build가 통과했다.
- Functions 51개 test, lint와 clean build가 통과했다.
- Socket check, 43개 test, ADC와 Firestore room preload/root/ready/health/SIGINT local smoke가 통과했다.
- 제거 manager 참조, root entrypoint 구현 잔여와 D40 유입 검색 및 `git diff --check`가 통과했다.
- iOS 기존 warning 3건과 Node `punycode` deprecation warning은 실패가 아니며 후속 정리 후보로 남겼다.
- 현재 변경은 아직 commit되지 않아 배포 candidate SHA 기준 재검증은 남아 있다. commit과 배포는 수행하지 않았다.

### 2026-07-14 Phase 6 통합 회귀·배포 결정과 계획

- N27~N34를 D41~D48로 확정했다.
- Phase 2~5 관련 targeted test, iOS generic build, Functions test/lint/build, Socket check/test와 구조 검색을 한 release candidate 기준으로 실행하기로 했다.
- 새 Firebase emulator는 도입하지 않고 기존 fake/contract test와 local/운영 smoke를 결합한다.
- dirty worktree 배포를 금지하고 Functions/Socket 배포 commit SHA와 prior rollback source/revision을 먼저 확보한다.
- Functions와 Socket 사이 직접 호출 의존성이 없음을 확인하고 rollback이 빠른 Socket을 먼저 배포한 뒤 독립 gate 통과 후 Functions 전체 49개 export를 배포한다.
- Socket은 process-local state 분리를 피하기 위해 traffic split 없이 새 revision 100%로 전환한다.
- Socket/Functions 각 중단·rollback 조건, 비파괴 smoke와 승인된 fixture smoke, 최종 iOS 종단 QA 범위를 문서화했다.
- 2026-07-14 읽기 전용 확인 시 Socket 운영 traffic 100%는 `outpick-socket-00005-jwg`였으나 배포 직전에 재확인한다.
- 문서만 변경했으며 자동 회귀 실행, commit, 운영 배포와 운영 fixture 생성은 수행하지 않았다.

### 2026-07-14 Phase 5 Socket 구현

- dependency 없는 재귀 `node:test` runner와 HTTP/middleware/event surface characterization부터 추가했다.
- Firebase Admin을 명시적 bootstrap으로 바꾸고 rate limiter, clock, ID generator와 media delivered state owner를 분리했다.
- auth/connection/room/message/media/lifecycle handler와 작업 단위 service를 기능별 module로 이동했다.
- `createSocketApplication`과 `createProductionDependencies`에서 application과 production dependency graph를 조립한다.
- `Socket/index.js`를 1,414줄에서 41줄로 축소했으며 import 시 listen/process 종료 부작용이 application factory에 들어가지 않도록 계약 테스트로 고정했다.
- 기존 HTTP route 3개, middleware 2개, client event 11개와 disconnect, ACK 및 persist→emit→push→ACK 순서를 보존했다.
- D40 in-flight Promise, TTL/LRU, transaction winner는 구현하지 않고 기존 process-local delivered `Set` 의미를 유지했다.
- 최초 local start에서 Socket.IO가 동결 option 객체를 확장하지 못하는 runtime 오류를 발견해 새 option 객체를 전달하도록 수정하고 회귀 테스트를 추가했다.
- `npm --prefix Socket run check`와 43개 `node:test`, ADC 기반 Firestore room preload, `/readyz`·`/healthz` 200과 SIGINT graceful shutdown local smoke가 통과했다.
- Docker/deploy 설정은 변경하지 않았고 Cloud Run/iOS 실제 송수신 smoke와 배포는 수행하지 않았다.

### 2026-07-14 Phase 5 Socket 설계 결정

- N14~N26을 D27~D39로 확정해 Node 22 JavaScript ESM, 얇은 `index.js`, application factory, explicit Firebase bootstrap과 기능별 handler/service 경계를 선택했다.
- socket runtime, room registry, rate limiter와 media dedupe state owner를 구분하고 clock/ID generator 주입 경계를 확정했다.
- 기존 event/payload/ACK, persist→emit→push→ACK, health/startup/shutdown과 단일 Cloud Run 배포 경계를 보존한다.
- dependency 없는 재귀 `node:test` runner를 Phase 5 검증 경계로 확정했다.
- D40으로 media dedupe의 in-flight Promise 병합, TTL/LRU 완료 캐시와 Firestore transaction winner 기반 단일 emit/push 방향을 기록했다.
- D40은 Phase 5 동작 보존 모듈화와 분리하며 TTL·용량·timeout과 follower ACK fixture는 후속 구현 계획 전에 확정한다.
- 문서만 변경했고 Socket 코드·package script·배포 설정은 수정하지 않았으며 test/check도 실행하지 않았다.

### 2026-07-14 Phase 5 Socket 구현·테스트 계획

- application/bootstrap, explicit Firebase, runtime state, auth/connection, room, text/lookbook, media, lifecycle의 구체적인 변경·신규·재사용 파일을 확정했다.
- Step 5A~5H를 characterization/test runner → runtime/Firebase → auth/connection/lifecycle → room → message → media → application/index 축소 → 전체 검증 순서로 작성했다.
- 모든 Step이 `index.js`와 production dependency graph를 공유하므로 병렬화하지 않고 순차 진행한다.
- HTTP route 3개, middleware 2개, client event 11개와 disconnect 1개, ACK와 side-effect 순서를 fake socket/io/service/clock/timer로 검증한다.
- dependency 없는 `Socket/scripts/run-tests.mjs`와 `Socket/test/` 하위 10개 영역의 구체적인 test file·시나리오를 작성했다.
- D40 in-flight/TTL/LRU/winner는 제외하고 현재 delivered `Set`과 `sequenceStore` 반환 의미를 보존하도록 중단 조건을 명시했다.
- 운영 배포, Docker/Cloud Run 설정, Firebase schema/path, iOS 코드는 변경 범위에서 제외했다.
- 문서만 변경했으므로 Socket test/check는 실행하지 않았다.

### 2026-07-14 Phase 4 Firebase Functions 구현

- `functions/src/index.ts` 7,809줄 구현을 65줄의 기존 49개 명시적 flat re-export로 축소했다.
- `core/firebase.ts`, `core/runtime.ts`가 Admin 초기화와 global option을 각각 한 번 소유하며 callable/error/concurrency primitive와 공유 브랜드 권한을 분리했다.
- Auth, Brand admin/requests, Chat cleanup, Lookbook deletion/engagement/comments/safety/import 기능 경계로 handler를 이동했다.
- Kakao와 Chat cleanup에는 dependency seam을 두고 호출 순서·실패 전파·Storage 삭제 순서를 fake 기반 테스트로 고정했다.
- Lookbook import discovery/parser와 deletion purge drain/lease를 기능 디렉터리로 이동했다.
- build 전에 `lib/`를 지우고 compiled test를 재귀 발견하는 dependency 없는 Node script를 연결했다.
- export 49개, callable 43개, Firestore trigger 3개, scheduler 3개의 region/path/schedule/timeout/memory metadata를 characterization test로 고정했다.
- architecture contract가 초기화/global option 단일 owner, root 구현 부재, feature 간 직접 import 금지와 이동 전 helper 부재를 검증한다.
- `npm test` 51개, `npm run lint`, `npm run build`가 통과했다.
- Firebase/Firestore schema, rules/indexes, queue/worker API와 운영 배포는 변경하지 않았다. emulator/운영 smoke는 미수행이다.

### 2026-07-14 D19 bootstrap 안정화 구현

- `AppDatabase.live()`, `AppCompositionRoot.makeCoordinator`의 throws 전파와 SceneDelegate catch 경계를 확정했다.
- 앱 일부를 조립하는 대신 독립 bootstrap 실패 화면과 수동 재시도를 제공하기로 했다.
- 자동 재시도, Chat 제한 모드와 로컬 DB 초기화/삭제는 범위에서 제외했다.
- pending notification route는 DB bootstrap보다 먼저 저장하기로 했다.
- DEBUG `once`/`always` launch argument로 실제 SQLite 손상 없이 최초 실패→재시도 성공과 반복 실패를 검증하기로 했다.
- `AppDatabase.live()`를 `throws`로 바꾸고 `AppCompositionRoot`가 database factory를 가장 먼저 실행해 `AppBootstrapError`로 mapping하도록 구현했다.
- `SceneDelegate`가 성공한 Coordinator만 보관하고 실패 시 독립 `AppBootstrapFailureViewController`를 root로 표시하며 수동 재시도를 수행한다.
- `AppBootstrapFailureInjector`의 DEBUG once/always argument로 실제 DB 파일 변경 없이 실패를 주입한다.
- unit test 5개와 UI test 2개가 통과했고 generic Simulator build와 DB fail-fast/삭제 잔여 정적 검색, `git diff --check`가 통과했다.

### 2026-07-14 Phase 4 설계 결정

- N7~N13을 D20~D26으로 확정했다.
- 기능 하위 도메인별 module과 functions/service/validator/mapper 책임 분리를 선택했다.
- Firebase Admin 초기화와 global runtime option을 core의 단일 owner에 두고 `onInit`을 registration 초기화에 사용하지 않기로 했다.
- 얇은 wrapper와 작업 단위 service를 분리하되 모든 함수의 interface/factory화는 제외했다.
- infrastructure `core`, 공유 도메인 정책 `shared`, feature-local helper 승격 기준을 고정했다.
- `index.ts`는 기존 49개 이름의 명시적 flat export만 유지하기로 했다.
- stale `lib` clean과 하위 test 재귀 발견, export/runtime metadata contract test를 함께 도입하기로 했다.
- Auth/Chat부터 deletion까지 위험도 순서로 이전하고 운영 배포는 완료 후 별도 승인된 전체 배포만 하기로 했다.
- 설계 문서만 변경했고 Functions 코드·package script·배포 설정은 변경하지 않았다.

### 2026-07-14 Phase 4 구현·테스트 계획

- 필요한 책임만 파일로 분리하고 단순 feature에는 `functions.ts` 하나를 허용하는 A안을 확정했다.
- Auth/Chat cleanup/import/deletion처럼 복잡한 부작용 service에만 dependency object seam을 두기로 했다.
- dependency 없는 `clean-lib.mjs`, `run-tests.mjs`로 stale `lib` 제거, 재귀 test 발견과 0개 test 방지를 구현하기로 했다.
- core/shared와 9개 기능 경계의 구체적인 신규·이동·수정·제거 파일을 작성했다.
- Step 4A~4I를 계약 characterization → core → 저위험 feature → import → deletion → index 축소 → 전체 검증 순서로 확정했다.
- module별 rollback 지점, 중단 조건과 운영 무배포 원칙을 기록했다.
- export/metadata/architecture contract, 순수 policy/mapper, 고위험 service fake를 포함한 테스트 파일과 시나리오를 확정했다.
- 문서만 변경했으며 Functions source/package script와 배포 설정은 수정하지 않았고 test/lint/build도 실행하지 않았다.

### 2026-07-13 Phase 3 구현

- `GRDBManager.swift`를 제거하고 `AppDatabase`, 15개 migration registry와 senderUID schema rebuilder를 추가했다.
- 메시지·프로필·미디어 persistence record/mapper와 message/outbox/media/profile/room cleanup Store 5개를 추가했다.
- `ChatPersistenceProvider`가 같은 `AppDatabase`로 Store를 조립하고 소비자는 message/search/profile/outbox/media/cleanup의 좁은 Protocol만 받도록 전환했다.
- `AppCompositionRoot → AppCoordinator → ChatContainer` DI 경로에서 provider를 한 번 생성·공유한다.
- 메시지 저장의 FTS 실패를 전파해 message/FTS/media 전체 rollback을 보장하고, exit cleanup은 outbox/profile cache 삭제와 orphan user prune까지 한 transaction으로 묶었다.
- transient cleanup은 message/FTS/media만 삭제하고 outbox/profile cache를 보존한다.
- legacy no-op migration 3개, `createRoomImage`, `roomImage` table/API와 pass-through GRDB repository 구현을 제거했다.
- GRDB 7개 test suite와 관련 UseCase/Manager 회귀 테스트를 추가·수정했다.
- targeted test 10개 suite와 generic Simulator build가 통과했다. 수동 채팅 QA는 수행하지 않았다.

### 2026-07-13 Phase 3 설계와 구현 계획

- N3~N5와 FTS 실패 정책을 D15~D18로 확정했다.
- 앱 미배포를 근거로 legacy no-op migration 3개와 `createRoomImage` migration/table/API를 제거하고 fresh 기준선을 15개로 정했다.
- 소비자별 persistence Protocol과 operation-owning Store를 정하고 `AppDatabase`는 pool/migration 책임만 갖도록 했다.
- 복잡한 row/JSON mapping에만 선택적 persistence record와 mapper를 도입하기로 했다.
- FTS 오류를 전파해 message/FTS/media write 전체를 엄격히 rollback하도록 확정했다.
- room exit cleanup은 outbox까지 같은 transaction에서 삭제하고, transient cleanup은 outbox/profile cache를 보존하도록 경계를 고정했다.
- 변경 파일, Store/Protocol 경계, Step 3A~3G 구현 순서와 테스트 fixture·실패 주입·검증 명령을 별도 문서로 작성했다.
- 코드·schema는 수정하지 않았고 테스트·빌드·배포도 실행하지 않았다.

### 2026-07-13 Phase 2 구현

- 공통 `CloudFunctionsTransporting`, Firebase transport, primitive decoder와 로컬 client error를 추가했다.
- Auth/Kakao bridge와 BrandAdmin capability를 좁은 Protocol/Client로 분리했다.
- Lookbook의 Brand/Request/Engagement/Comment/Import/Deletion adapter 15개를 공통 transport 주입 방식으로 전환했다.
- Domain mapper 7개로 응답 변환을 분리하고 callable 이름·payload·기존 기본값을 유지했다.
- `LookbookRepositoryProvider.live(transport:)`와 `AppCompositionRoot`에서 같은 transport를 명시적으로 조립했다.
- preview와 UI test fixture의 live Functions fallback을 제거했다.
- `CloudFunctionsManager.swift`와 채팅 목록의 `callHelloUser` 임시 호출을 제거했다.
- test double과 test type 9개로 사용 중인 callable 38개 계약을 검증했다.
- targeted tests와 generic Simulator build가 통과했다.
- 운영 서버, Functions 코드, schema, 배포는 변경하지 않았다.
- Kakao/관리자/삭제 등 실제 자격 증명과 운영 상태 변경이 필요한 수동 QA는 수행하지 않았다.

### 2026-07-13 Phase 2 설계와 구현 계획

- D9~D14를 사용자 승인으로 확정했다.
- 기존 Lookbook Repository Protocol을 재사용하고 구현체가 feature adapter 역할을 직접 맡도록 결정했다.
- 공통 transport/primitive decoder와 기능별 Domain mapper 책임을 분리했다.
- production DI를 명시화하되 앱 전체 singleton lifecycle 정리는 범위 밖으로 고정했다.
- 사용 중인 callable 38개만 이전하고 미사용 wrapper 2개와 서버 전용 callable 3개를 iOS에 복제하지 않기로 했다.
- 공통 core, Auth/Admin capability, Lookbook adapter 15개, mapper 7개, DI/fixture/제거 파일을 구현 계획에 기록했다.
- test double 1개와 test file 9개로 callable 38개를 검증하는 계획을 작성했다.
- 코드는 수정하지 않았고 테스트·빌드·배포도 실행하지 않았다.

### 2026-07-13 Phase 1

- D4~D8 추천안을 사용자 승인으로 확정했다.
- `contracts/`에 iOS Functions, GRDB, Firebase Functions, Socket 기준선을 작성했다.
- iOS callable wrapper와 소비자/목표 capability를 mapping했다.
- GRDB migration identifier 19개, schema, operation과 원자적 transaction 경계를 기록했다.
- Firebase export 49개와 runtime/trigger/schedule/Cloud Tasks 계약을 기록했다.
- Socket HTTP, 인증, event/ACK, persist/emit/push 순서와 process-local state를 기록했다.
- `callHelloUser`는 제거 확정, 단순 미참조 API는 N1~N4 논의 항목으로 분리했다.
- 코드, schema, runtime option, 배포 설정은 변경하지 않았다.

### 2026-07-13 Phase 0

- 네 대형 파일의 현재 책임과 소비자/배포 구성을 조사했다.
- 파일만 분리하지 않고 기능별 Protocol/Client/Store와 공통 transport/database, 얇은 entrypoint를 사용하는 방향을 확정했다.
- 현재 iOS 앱, Firebase Functions default codebase, Socket Cloud Run 배포 경계를 유지하고 MSA/Kubernetes 도입을 비목표로 정했다.
- design.md에 요구사항, 비목표, 구현 가능성, 기술 스택, 사용자/화면/API/데이터/아키텍처/배포 설계, 완료 기준을 기록했다.
- decisions.md와 상세 결정 문서에 확정 결정과 승인 대기 제안을 분리했다.
- plan.md에 제안 Phase 지도와 phase별 목표/범위/완료 기준/검증/논의 항목을 기록했다.
- qa-checklist.md에 자동 검증과 수동 QA 경계를 기록했다.
- ADR-019에 장기 모듈·배포 경계 결정을 기록했다.
- active/ENTRYPOINTS/CODE_ARCHITECTURE/HANDOFF 연결을 갱신했다.

## 초기 조사 발견과 처리 결과

- `RoomListsCollectionViewController`의 `callHelloUser` debug 호출과 `CloudFunctionsManager.swift`를 제거했다.
- Lookbook Repository의 callable 접근을 공통 transport 기반 기능별 adapter로 전환했다.
- 기존 `ChatOutgoingOutboxPersisting`의 혼합 책임을 소비자별 persistence capability와 Store로 분리했다.
- `Socket/index.js`의 조립과 기능 구현을 application/handler/service/state/lifecycle 경계로 분리했다.
- 미사용 iOS wrapper 2개는 제거하고 서버 전용 callable 3개는 앱에 추가하지 않았다.
- legacy migration과 `roomImage` table/API를 제거하고 fresh migration 기준선을 확정했다.
- FTS 오류를 전파해 message/FTS/media transaction을 rollback하도록 변경했다.
- room exit cleanup transaction에 outbox를 포함했다.
- Functions test runner를 재귀 발견 방식으로 전환해 하위 feature test 누락을 막았다.

## 아직 남은 작업

이 task의 필수 작업은 남아 있지 않다. 다음 항목은 별도 후속이다.

1. FCM fanout은 Apple 개발자 계정 결제 후 별도 QA task로 진행한다.
2. D40 media dedupe 강화는 동작 보존 리팩토링 범위 밖 후속 기능이다.
3. Firestore `I-FST000002`와 `@DocumentID`/중복 `ID` field 정리는 별도 설계 후 진행한다.
4. Phase 2의 나머지 상태 변경 화면 수동 QA는 자동 wire 계약·운영 read smoke·이번 통합 QA를 근거로 종료 차단에서 제외했다. 해당 기능을 수정하거나 출시 회귀 범위를 넓힐 때 별도 수행한다.

## 검증

- Phase 5 `npm --prefix Socket run check`와 `npm --prefix Socket test`를 실행해 43개 테스트가 통과했다.
- ADC 기반 local server가 Firestore room을 preload하고 `/readyz`·`/healthz` 200을 반환한 뒤 SIGINT로 정상 종료되는 것을 확인했다.
- `index.js`의 handler/Firestore 구현 잔여, import-time Firebase 초기화와 D40 유입 여부를 정적으로 확인했다.
- Phase 4 최종 검증에서 Functions `npm test` 51개, lint, build와 구조 검색을 수행했다.
- source 검색으로 public method/export/event/migration/소비자를 대조했다.
- 이번 Phase에서 코드 파일은 변경하지 않았다.
- 계약 문서 5개 존재와 링크 경로를 확인했다.
- task 문서 trailing whitespace 검색과 `git diff --check`가 통과했다.
- source count를 재확인했다: iOS public method 41, Functions export 49, GRDB migration 19, Socket client handler 12.
- Phase 2 계획 문서를 구현 계획 262줄과 테스트 계획 101줄로 분리하고 내부 링크 존재를 확인했다.
- 현재 source 기준 Lookbook Cloud Functions adapter 15개와 `CloudFunctionsManager` 참조 파일 19개를 다시 확인했다.
- Phase 2 문서 갱신 후 trailing whitespace 검색과 `git diff --check`가 통과했다.
- Phase 3 설계·구현·테스트 문서 작성 턴은 문서만 변경했으므로 앱 테스트와 빌드는 실행하지 않는다.
- Phase 3 신규 문서 3개의 존재·상대 링크, 관련 문서 trailing whitespace, stale `Phase 3 논의 전` 표현, `git diff --check`를 검증했다.
- Simulator `5A3BB941-9538-4DD9-93C2-F18ACCFB03B9`에서 Phase 3 GRDB 7개 suite와 `ChatOutgoingOutboxUseCaseTests`, `ChatProfileSyncManagerTests`, `ChatRoomExitUseCaseTests` targeted test가 통과했다.
- `generic/platform=iOS Simulator`, `CODE_SIGNING_ALLOWED=NO` build가 통과했다.
- `GRDBManager`, pass-through GRDB repository, production의 추가 `DatabasePool`, legacy migration/API 잔여 검색과 `git diff --check`가 통과했다.
- 실제 화면 기반 Phase 3 채팅·GRDB 수동 QA는 Phase 6 통합 QA에서 완료했다.
- Simulator `7544249E-D0EE-4B88-A48F-E384DF84E6A4`에서 D19 unit test 5개와 UI test 2개가 통과했다.
- D19 반영 후 `generic/platform=iOS Simulator`, `CODE_SIGNING_ALLOWED=NO` build와 `git diff --check`가 통과했다. 기존 누락된 node_modules search path linker warning은 남아 있으나 build 결과는 성공이다.

## 다음 작업

- 현재 진행 중인 작업은 없다. Apple 개발자 계정 결제 후 FCM fanout QA를 새 task로 등록한다.
