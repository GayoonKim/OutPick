# Core Infrastructure Modularization QA Checklist

## 검증 원칙

이번 작업은 기능 추가가 아니라 동작 보존형 구조 리팩터링이다. 화면 happy path만 반복하기보다 외부 계약, 실패 분기, transaction, idempotency, event/ACK처럼 사람이 안정적으로 재현하기 어려운 경계를 자동 검증한다.

실제 테스트 파일과 실행 범위는 각 구현 phase 승인 전에 다시 확정한다.

## Phase 0 문서 검증

- [x] task 문서 링크가 유효하다.
- [x] ADR-019가 ADR index에서 발견된다.
- [x] active task와 ENTRYPOINTS가 새 task를 가리킨다.
- [x] git diff --check가 통과한다.
- [x] 이번 Phase에서 코드 파일을 변경하지 않았다.

## Phase 1 계약 inventory

### Cloud Functions iOS

- [x] 모든 CloudFunctionsManager public method와 소비자가 mapping된다.
- [x] 함수 이름, payload key, response key, region이 기록된다.
- [x] direct shared 사용과 constructor injection 사용이 구분된다.
- [x] 제거 확정 debug API와 미참조 후보가 구분된다.

### GRDB

- [x] migration identifier와 등록 순서가 기록된다.
- [x] table/column/index schema가 기록된다.
- [x] operation별 transaction 범위가 기록된다.
- [x] message/outbox/media/profile/cleanup 소비자가 mapping된다.

### Firebase Functions

- [x] export된 callable/trigger/scheduler 이름이 snapshot된다.
- [x] region, memory, timeout, schedule/timezone이 비교 가능하게 기록된다.
- [x] Firestore trigger path와 Cloud Tasks queue/worker endpoint가 기록된다.
- [x] admin.initializeApp와 global option owner가 확인된다.

### Socket

- [x] event 이름과 ACK 형식이 inventory된다.
- [x] auth middleware와 connection handler 등록 순서가 기록된다.
- [x] message persist, sequence, emit, FCM fanout 순서가 기록된다.
- [x] media idempotency state와 reservation 계약이 기록된다.

## Phase 2 iOS Cloud Functions 자동 테스트 후보

- [x] `CloudFunctionsTransportSpy`가 요청 function name과 payload를 기록한다.
- [x] primitive/NSNumber/`NSNull`/date decoder.
- [x] Auth token exchange 1개.
- [x] Brand admin capabilities 1개.
- [x] Brand create/update/manager/logo 5개와 search 1개.
- [x] Brand request list/group/cursor/mutation 6개.
- [x] Brand/season/post/comment engagement 4개.
- [x] Comment/reply/delete/report/block/hidden IDs 6개.
- [x] Season import/job/diagnostic/retry 4개.
- [x] Lookbook deletion/list/retry 10개.
- [x] 사용 중인 callable 38개의 function name/payload가 모두 검증된다.
- [x] optional nil의 key 생략과 `NSNull` 사용이 기존과 동일하다.
- [x] Firebase Functions 원본 NSError domain/code가 보존된다.
- [x] invalid response와 missing field 오류.
- [x] Repository가 좁은 Protocol만 받는지 compile로 확인.
- [x] View/ViewController direct Functions 호출 검색.
- [x] CloudFunctionsManager.shared 잔여 검색.
- [x] `Functions.functions`와 `httpsCallable`이 concrete transport 밖에 없는지 검색.

### Phase 2 수동 QA

- [ ] Kakao 로그인.
- [ ] 관리자 capability 표시.
- [ ] 브랜드 생성/수정과 manager 변경.
- [ ] 좋아요/저장.
- [ ] 댓글/답글/신고/차단.
- [ ] 시즌 import/진단.
- [ ] 삭제 요청 목록/복구/재시도.

## Phase 3 GRDB 자동 테스트 후보

- [x] N3~N5와 FTS 실패 정책을 D15~D18로 확정했다.
- [x] 변경 파일·Protocol/Store 경계·구현 순서·테스트 파일 계획을 문서화했다.

- [x] fresh database migration.
- [x] D15 적용 후 15개 migration과 legacy table 부재.
- [x] chatMessage senderUID schema rebuild.
- [x] 메시지 저장과 image/video index 동일 transaction.
- [x] FTS 실패 시 message/FTS/media 전체 rollback.
- [x] 최근/이전/이후 message pagination.
- [x] failed outgoing message와 outbox 저장/복원/삭제.
- [x] media index upsert/delete/duration update.
- [x] RoomProfileDisplayCache LRU 20명 eviction.
- [x] room local data cleanup과 orphan user pruning.
- [x] room exit cleanup의 outbox 포함 rollback과 transient cleanup의 outbox/profile 보존.
- [x] current user 보존.
- [x] Store별 임시 `AppDatabase` 통합 테스트.

### Phase 3 수동 QA

- [x] 채팅방 진입 후 최근 메시지 표시: `OOTD 공유`에서 확인.
- [x] 이전 메시지 pagination: `QA-P6-PAGE-0714`에 105개 메시지를 구성하고 `latestTail` 80개(`seq 26...105`) 로드 후 `loadOlderMessages(before: seq 26)` 호출로 25개가 추가되어 GRDB가 중복 없이 `seq 1...105`로 확장되는 것과 화면 최상단 `001` 노출을 확인. 방장 종료 후 Firestore/GRDB fixture 0건 확인.
- [x] 메시지 검색: `OOTD 공유`에서 `12` 검색과 결과 이동 확인.
- [x] 이미지/동영상 모아보기: `해칭룸 정보 공유방`에서 확인.
- [x] 실패 메시지 재시도: process-local Socket 실패를 통제 주입해 `isFailed=1`/outbox 생성, 확인 UI 이후 retry, 단일 server persist, `isFailed=0`/outbox 제거와 앱 재실행 복원 확인. 실패 아이콘의 실제 좌표 탭은 접근성 target 부재로 debugger에서 동일 confirm 진입점을 호출해 대체.
- [x] 일반 구성원 방 나가기 후 로컬 데이터 정리: `QA-P6-LEAVE-0714`에서 Google 구성원의 member 문서 제거, room/방장/서버 메시지 유지, 해당 room GRDB 관련 row 0건 확인.
- [x] 방장 room 닫기 후 원격/로컬 데이터 정리: `QA-P6-CLOSE-0714` fixture의 Firestore room/members/messages와 GRDB 관련 row 0건 확인.
- [x] 앱 완전 재실행 후 같은 방 최근 메시지와 검색 흐름 복원.

### D19 AppDatabase bootstrap 후속 검증

- [x] `throws` 전파와 SceneDelegate 실패 화면 정책을 확정했다.
- [x] DEBUG `once`/`always` failure injection과 테스트 파일 범위를 확정했다.
- [x] `AppDatabase.live()` 내부 `fatalError` 제거.
- [x] CompositionRoot database factory 오류 mapping.
- [x] 실패 시 Coordinator 미보관과 bootstrap failure root 표시.
- [x] `once` 최초 실패 후 재시도 성공.
- [x] `always` 반복 실패와 앱 foreground 생존.
- [x] bootstrap 전 pending notification route 저장.
- [x] 실패 주입이 실제 DB 파일을 변경·삭제하지 않음.
- [x] D19 targeted tests와 generic Simulator build 통과.

## Phase 4 Firebase Functions 자동 검증

- [x] D20~D26과 추가 추천안 3개를 확정했다.
- [x] 변경 파일·Step 4A~4I·rollback·중단 조건을 문서화했다.
- [x] contract/policy/service 테스트 파일과 시나리오를 문서화했다.
- [x] npm test 51개 통과.
- [x] npm run lint 통과.
- [x] npm run build 통과.
- [x] 기존 export 이름 49개 비교.
- [x] runtime option과 trigger path/schedule 비교.
- [x] feature 직접 import 위반과 initialization duplication 없음.
- [x] 하위 디렉터리 test가 실제 npm test에 포함된다.
- [x] 기존 purge drain/lease tests 통과.
- [x] helper/service 단위 test가 feature 폴더에서 발견된다.

### Phase 4 smoke QA

- [x] 인증 실패 callable이 기존 HttpsError code를 반환한다: `getBrandAdminCapabilities` HTTP 401/`UNAUTHENTICATED`.
- [ ] 대표 Auth/Brand/Comment/Import/Deletion callable.
- [ ] Firestore trigger 대표 경로.
- [x] scheduler 3개가 기존 cron/`Asia/Seoul`로 `ENABLED` 상태다.
- [x] 사용자 명시 승인 후 Functions 49개 전체 update 배포를 완료했다.

## Phase 5 Socket 자동 검증 후보

- [x] D27~D39 구조·계약 결정과 D40 media dedupe 후속 방향을 확정했다.
- [x] Phase 5 변경 파일·Step 5A~5H·rollback·중단 조건을 문서화했다.
- [x] Phase 5 test file·fake/spy·자동/수동 QA 경계를 문서화했다.
- [x] npm --prefix Socket run check.
- [x] npm --prefix Socket test: 43개 통과.
- [x] handler 등록 event 이름.
- [x] token 없음/변조 token connection 거절.
- [x] room join/leave ACK.
- [x] message validation failure ACK.
- [x] sequence allocation/persist/emit/fanout 순서.
- [x] media preflight/finalize idempotency.
- [x] lookbook share handler 계약.
- [x] disconnect cleanup.
- [x] shutdown 중 readyz 503와 server close.
- [x] ADC 기반 local room preload, readyz/healthz 200, SIGINT graceful shutdown.

### D40 media dedupe 후속 자동 검증

- [ ] 동일 instance의 같은 message ID 동시 finalize를 하나의 in-flight Promise로 병합한다.
- [ ] persist/emit/push가 각각 한 번만 호출된다.
- [ ] 서로 다른 instance를 모사해 Firestore transaction winner만 emit/push한다.
- [ ] follower가 owner 결과의 `messageID`와 `seq`로 duplicate ACK를 받는다.
- [ ] owner 실패 시 entry 해제 후 재시도할 수 있다.
- [ ] deterministic clock으로 TTL 전 hit와 TTL 후 Firestore 확인을 검증한다.
- [ ] 최대 용량 초과 시 LRU 완료 entry만 제거하고 in-flight entry는 보존한다.
- [ ] image/video namespace가 충돌하지 않는다.
- [ ] persist 실패와 duplicate transaction 결과에서 emit/push가 없다.

### Phase 5 수동 QA

- [x] Cloud Run Socket Firebase 인증 connect/ready.
- [x] room join/rejoin: D49 수정 후 반복 reconnect와 `OOTD 공유` 재실행 rejoin 확인.
- [x] 텍스트 메시지 persist/emit과 앱 전송 성공.
- [x] 이미지/동영상 메시지 송수신: `OOTD 공유`에서 사진 1장과 8초 동영상 1개 단일 표시 확인.
- [x] 룩북 공유 메시지 송수신: UNAFFECTED 시즌 공유 1건 단일 표시와 server sequence 확인.
- [x] background/foreground reconnect: D49 gate에서 5회 통과.
- [x] 방 나가기/방 닫기: 전용 fixture에서 일반 구성원 leave와 방장 close semantics를 각각 통과하고 `QA-P6-LEAVE-0714`의 Firestore·GRDB 최종 cleanup까지 확인.
- [ ] FCM fanout: 사용자 Apple 개발자 계정 환경 제약으로 보류, 실제 가능 조건 재확인 필요.
- [x] 앱 완전 재실행 후 text/image/video/lookbook 4종 GRDB 복원과 단일 표시.
- [x] 사용자 명시 승인 후 Cloud Run revision `outpick-socket-00006-k8k`를 traffic 100%로 배포했다.

## Phase 6 통합 검증

- [x] D41~D48 통합 회귀·배포 순서를 확정했다.
- [x] Phase 6 통합 회귀, 배포 gate와 rollback 계획을 문서화했다.
- [x] 배포할 Functions/Socket commit SHA와 working tree 범위를 확정했다: `7580a1e`.
- [x] 운영 Functions prior source rollback 기준을 Git HEAD `ccc141e`로 확보했다.
- [x] Socket previous ready revision/image digest를 확인했다. 실제 배포 직전 재확인은 남아 있다.
- [x] iOS generic simulator build.
- [x] 승인된 targeted iOS tests.
- [x] Functions test/lint/build: 51개 test 포함 통과.
- [x] Socket check/test: 43개 test 포함 통과.
- [x] git diff --check.
- [x] giant file 또는 giant public surface 잔여 검색.
- [x] direct singleton/concrete dependency 잔여 검색.
- [x] ENTRYPOINTS, DATA, FIREBASE, CHAT, TESTS 문서 갱신.
- [x] Socket 배포/health/auth/fixture smoke와 필요 시 revision rollback: 배포, readyz, invalid/정상 auth와 room/text를 통과했고 D49 후 cold launch·background/foreground reconnect gate도 통과했다. rollback은 필요하지 않았다.
- [x] Functions 전체 배포/export/callable/log smoke와 필요 시 prior source rollback: 49개 배포/state/trigger/scheduler/비인증·capability 호출/log와 `searchBrands`, `listMyBrandRequests` 인증 read smoke가 통과했다. rollback은 필요하지 않았다.
- [x] 양쪽 gate 통과 후 iOS 종단 QA와 승인된 fixture cleanup: 채팅 4종 전송·재실행 복원, 검색·미디어, 일반 구성원 leave와 방장 close의 Firestore·GRDB cleanup 확인.
- [x] Socket/Functions 배포 결과와 rollback revision/source를 기록했다. 실제 rollback은 수행하지 않았다.

### D49 iOS Socket reconnect 안정화

- [x] one-time listener binding과 active reconnect 중 off/on 금지를 확정했다.
- [x] Socket.IO raw auth logging 제거를 확정했다.
- [x] 좁은 Binder/Protocol, fake spy와 targeted test 범위를 문서화했다.
- [x] 같은 binder 두 번째 bind가 handler 등록 수를 늘리지 않는다.
- [x] connect callback 반복 실행이 handler 등록 수를 바꾸지 않는다.
- [x] 새 Socket/binder만 독립적인 listener 1세트를 등록한다.
- [x] cold launch reconnect 5회.
- [x] background/foreground reconnect 5회.
- [x] room rejoin과 text 송수신 중복 부재.
- [x] runtime log credential 비노출.
- [x] 기존 관련 targeted tests와 generic Simulator build.

## 보류할 테스트와 이유

- SwiftUI snapshot/UI test: 화면 구조 변경이 아니므로 기본 범위에서 제외한다.

## 후속: Firestore `@DocumentID` 경고 정리

- [ ] `ChatRoom.init(from:)`의 non-nil `@DocumentID` 재초기화 경로를 제거한다.
- [ ] room 목록/검색/joined room decode 후 `I-FST000002`가 출력되지 않는지 확인한다.
- [ ] `SeasonDTO.fromDomain`과 나머지 `@DocumentID` DTO의 non-nil 초기화 지점을 점검한다.
- [ ] 문서 경로 ID와 저장된 `ID` field의 소비자를 inventory한 뒤 중복 field 제거 여부를 결정한다.
- [ ] read document ID, create/update write와 기존 room/season mapping 회귀 테스트 범위를 확정한다.
- 실제 Firebase emulator integration test: `firebase-functions-test` 의존성은 있지만 `firebase.json` emulator 설정/fixture를 확인하지 못해 Phase 4 기본 범위에서 보류하고 필요 시 별도 설계한다.
- 성능 benchmark: 우선 목표는 dependency boundary와 동작 보존이며 실제 성능 회귀가 발견될 때 추가한다.
- Kubernetes/deployment orchestration test: 이번 작업의 비목표다.

## 테스트 실행 승인 상태

- Phase 0~1 문서 검사: 수행 가능.
- 코드 build/test: Phase 2~5와 Phase 6 candidate SHA `7580a1e` 회귀 완료.
- Functions/Socket 운영 배포: 사용자 승인 후 완료.
- 승인된 전용 fixture의 방 생성·메시지 생성·일반 구성원 leave·방장 close·원격/로컬 cleanup QA를 완료했다.

## 작업 종료 예외와 후속

- FCM fanout은 Apple 개발자 계정 결제 후 별도 QA로 이관했다.
- D40 media dedupe 자동 검증 항목은 이번 동작 보존 리팩토링의 비목표이며 별도 기능 task에서 다룬다.
- Firestore `@DocumentID` 경고 항목은 현재 기능 실패가 확인되지 않은 별도 후속 리팩토링이다.
- Phase 2의 미체크 상태 변경 화면 QA와 Phase 4 일부 대표 callable/trigger smoke는 자동 wire/export/runtime 계약, 운영 인증 read smoke와 승인된 통합 QA를 근거로 이번 task 종료 차단에서 제외했다. 미수행 항목을 완료로 표시하지 않는다.
