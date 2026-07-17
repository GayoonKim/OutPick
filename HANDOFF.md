# OutPick Handoff

## 1. 최종 목표

- `socket-ingress-ordering-hardening`은 2026-07-17 Phase 1~6 구현, 자동 회귀와 실제 Firebase/Simulator 핵심 QA를 완료하고 종료했다. realtime-only 3초 preview와 Phase 6 관련 52개 자동 테스트를 완료했고, explicit persistence는 `92 → transaction 89→92 → server 92`, 재진입 `lastRead/latest=92`로 정상 확인했다. 초기 latest 위치도 reload-data snapshot + bounded self-sizing 안정화로 수정해 `999999` 재진입 표시가 통과했다.
- `socket-message-dedupe-hardening`은 2026-07-16 구현·자동 회귀·candidate closeout을 완료하고 종료했다.
- 서버는 instance 내부 single-flight와 Firestore transaction winner로 persist 이후 emit/push를 한 번만 수행하고, iOS는 `ChatRoomSessionActor`에서 방별 최근 message ID 300개를 consumer fan-out 전에 제거한다. Phase 1~3 구현, 공통 send receipt 수렴, Socket 62개와 iOS receipt/ingress 회귀 및 candidate text 동일 ID retry QA를 완료했다.
- `core-infrastructure-modularization`은 완료됐다. iOS Cloud Functions/GRDB, Firebase Functions와 Socket의 대형 concrete 진입점을 기능별 계약·구현과 공통 runtime, 얇은 entrypoint 구조로 전환하면서 기존 앱/Functions/Cloud Run 배포 단위와 wire/data 계약을 보존했다.
- `firestore-document-id-boundary-cleanup`은 완료됐다. 문서 경로 ID를 canonical source로 통일하고 앱 `@DocumentID`, 신규 중복 ID write, 운영 Rooms의 legacy `ID`를 제거했다.
- 해당 task의 Phase 1~4 구현·자동·수동 검증, Firestore rules 운영 배포, 운영 `Rooms.ID` 4건 cleanup과 사후 재감사를 모두 완료했다.

## 2. 완료한 작업

### Socket message dedupe 설계·계획

- 기존 `socket-media-dedupe-hardening`을 `socket-message-dedupe-hardening`으로 확장했다. 서버 대상은 text, Lookbook, image, video 전체다.
- 요청별 인증·권한·rate limit과 media reservation 검증 후 `kind + roomID + messageID` 단위 single-flight에 참여한다.
- 공통 sequence transaction은 `{ seq, created }`를 반환하고 새 문서를 만든 winner만 transaction 밖에서 Socket emit과 FCM push를 수행한다.
- 완료 캐시와 별도 owner timeout은 첫 구현에서 제외한다. local in-flight는 같은 instance의 동시 요청 병합 최적화이고 Firestore message document가 instance 간 최종 권위다.
- iOS는 `ChatRoomSessionActor`가 방별 최근 message ID 300개를 보관하며 첫 ingress event만 consumer에게 전달한다. 같은 ID의 다른 seq는 두 번째 event를 drop하고 DEBUG에서 식별자와 old/new seq만 기록한다.
- `BannerManager`의 별도 최근 ID cache는 제거하고 `ChatMessageWindowStore`와 GRDB upsert는 최종 방어선으로 유지하는 계획을 확정했다.
- task의 design, D1~D13, Phase 1~4 계획과 QA checklist를 개정했다.
- Phase 1에서 `messageDeliverySingleFlight`와 상세 sequence outcome을 구현했고, Phase 2에서 `allocateSeqAndPersist`를 최종 `{ seq, created }` 계약으로 통일했다.
- text/Lookbook/image/video handler가 공통 single-flight를 공유하며 Firestore `created: true` winner만 emit/push한다. follower와 transaction loser는 기존 seq의 duplicate ACK만 반환한다.
- 완료된 media retry는 저장된 senderUID, media 종류와 attachment path가 일치할 때만 성공한다. reservation 삭제 race에서는 기존 message를 한 번 재확인한다.
- legacy `mediaDeliveryState`와 숫자 sequence wrapper를 제거했다. Socket syntax check와 전체 62개 테스트가 통과했다.
- Phase 3에서 `ChatRoomSessionActor`의 방별 최근 ID 300개 first-wins ingress dedupe와 actor lifecycle 정리를 구현했다.
- 로컬 실패 메시지 publish는 ingress recent-ID state를 우회해 같은 ID의 후속 서버 확인 event가 차단되지 않게 했다.
- `BannerManager`의 `recentPerRoom`/`RecentSet`을 제거하고 ingress actor를 중복 제거 단일 owner로 통일했다.
- 신규 actor 테스트 6개와 window/GRDB/listener 회귀를 합친 고유 테스트 20개, generic Simulator build가 통과했다.
- text/Lookbook/images/video ACK를 `ChatMessageSendReceipt`로 통일하고 optimistic message의 seq/attachment/실패 상태, GRDB와 outbox를 공통 reconciliation 경로로 수렴시켰다.
- Lookbook 결과 불명 retry는 최초 message ID를 재사용한다.
- candidate text `messageID=9B79F1C2-E3BC-431A-AF3E-D4C0D50C8B4E`, `seq=17`에서 ACK 유실→동일 ID retry 후 발신 실패 아이콘 해제와 수신 room preview 단일 표시를 확인했다.
- candidate Lookbook `seq=19`, image `seq=20`, video `seq=21`의 ACK 유실→동일 ID retry에서 서버 문서·Storage·수신·발신 GRDB/outbox 단일 수렴을 확인했다. image/video는 자기 ingress가 먼저 성공 수렴해 Simulator GRDB/outbox만 결과 불명 상태로 복원한 뒤 동일 ID finalize를 재전송했다.
- 더 오래된 image retry가 최신 video 이후 수행될 때 iOS ACK 후 client summary write가 Firestore `lastMessage`를 image로 역행시키는 회귀를 발견했다. iOS ACK 후 summary write를 제거하고 Socket transaction을 단일 owner로 확정했다.
- 신규 source 계약 테스트와 ACK/outbox/Lookbook targeted test 26개가 통과했다. candidate에서 최신 video B(`seq=21`) 뒤 오래된 image A(`seq=20`) retry를 재검증해 Firestore room `[동영상]`/`lastMessageSeq=21`/기존 `lastMessageAt`, 수신 preview와 A/B 단일 행 유지를 확인했다.
- 실제 transport 실패 text `F35EAECA-58D2-4EF1-B09B-BE9131407756`는 Firestore 미생성·발신 `seq=0/isFailed=1`·outbox failed에서 앱 재연결 후 같은 ID retry로 `seq=22`, Firestore 한 문서, 발신 성공/outbox 삭제와 수신 preview 한 건에 수렴했다. candidate Chat emit과 push fanout log는 각각 한 세트였고 ERROR log는 0건이었다.
- candidate revision은 배포했지만 운영 traffic 전환은 수행하지 않았다. 운영 `outpick-socket-00006-k8k`가 100%를 유지한다.

### Socket ingress ordering Phase 6 계획 확정·6-A~C 및 persistence/preview 후속 구현 완료

- 방 진입 자동 전체 읽음 대신 사용자가 `최신 메시지로 이동`을 탭하고 bounded target window의 로딩·snapshot·표시가 성공한 경우에만 고정 target까지 읽음 처리하기로 확정했다.
- [폐기된 기존 구현] 새 realtime 메시지가 없어도 entry tail이 read frontier보다 크면 preview card를 표시하도록 구현했다. 아래 최종 realtime-only 결정으로 제거 대상이다.
- 일반 읽음은 실제 visible candidate만 사용하고 newer page load, search jump, route 종료와 window max 자체는 frontier를 올리지 않는다.
- catching-up의 `liveBuffer` payload 보관을 제거하고 realtime은 persistence로 수렴시키며 UI는 scalar 상태와 최신 요약 1개, 이동 중 고정 요약 1개만 유지하는 계획을 확정했다.
- Phase 6-A read frontier 상태 → 6-B bounded persistence/target load → 6-C UI/render handshake → 6-D 통합 회귀·QA 순으로 진행한다. 상세 계획은 `docs/ai/tasks/socket-ingress-ordering-hardening/phase-6-unread-catch-up-read-frontier.md`다.
- Phase 6-A에서 `ChatReadStateStore`의 seeded monotonic frontier, 연속 visible candidate와 explicit gap candidate를 분리하고 window 없는 final frontier를 추가했다.
- 신규 `ChatUnreadCatchUpState`가 scalar high watermark/unread badge, 고정 target과 generation/loading을 소유하며 stale completion을 거부한다. 2개 suite 19개 테스트와 generic Simulator build가 통과했다.
- Phase 6-B에서 `liveBuffer`를 제거하고 catching-up incoming을 scalar latest + persistence-only로 전환했다. target window는 서버 권위 최대 80개이며 `Int64.max`를 안전하게 분기하고 target 포함을 검증한다.
- authoritative initial/history/latest와 realtime incoming은 GRDB 저장 성공 후 서버 확정 ID를 batch outbox reconciliation한다. 관련 4개 suite 22개 테스트와 generic iOS Simulator build가 통과했다.
- [폐기된 기존 구현] Phase 6-C에서 initial entry tail만으로 `ChatLatestMessageJumpView`를 표시하도록 구현했다. bounded snapshot/target 표시 handshake와 탭 target 고정은 realtime card 탭에도 유지한다.
- [폐기된 기존 구현] initial room summary의 `lastMessageSenderUID`를 GRDB local profile repository에서 읽도록 추가했다. 최종 계약에서는 realtime payload를 사용하므로 해당 DI와 테스트를 제거한다.
- 실패·취소·stale/search/route overlap은 기존 window·offset·frontier를 보존한다. 일반 읽음은 settled visible max와 증명된 연속 seq 상한만 사용하고 final flush의 `windowMaxSeq` 의존을 제거했다.
- Phase 6-D 부분 QA에서 최신 이동 후 pop/re-entry 시 unread 82가 복원되는 결함을 재현했다. 원인은 표시 성공 후 3초 debounce와 route lifecycle 경쟁, server write 이전 shared mark 순서였으며 표시 성공 직후 pending frontier를 await 저장하고 server 성공 뒤에만 flushed mark하도록 수정했다. 실패 pending은 final flush에 남긴다.
- 후속 변경 관련 5개 suite 고유 테스트 48개와 iPhone 17 Pro Max Simulator build가 통과했다. 실제 Firebase 재진입 persistence와 preview card/keyboard/VoiceOver는 Phase 6-D 수동 재QA에 남아 있다.
- 실제 두 Firebase 개발 계정으로 `OOTD 공유`에 `1848001`, `1848002`를 전송해 재QA했다. card의 한 줄 요약·generic 아이콘·시각적 숫자 제거, AX label/value/button과 한글 software keyboard 배치는 통과했다.
- explicit target 표시 직후 pop-re-entry에서는 `1848001`이 unread 83개로, 충분히 대기한 pop-re-entry에서는 `1848002`가 unread 84개로 재노출됐다. card 제거가 server write 완료보다 먼저 발생하므로 즉시 이탈 cancellation 경합은 가능하지만, 대기 후에도 실패해 이것만으로 원인을 단정할 수 없다.
- 다음은 update 직전 pending seq와 masked room/user key, Firestore transaction result, 직후 authoritative fetch를 계측해 호출 누락·권한/transaction 실패·document key 불일치를 구분한다. 원인 확정 전 persistence 코드를 추가 수정하지 않는다.
- iOS 26.2 Simulator 설정에는 VoiceOver 항목이 없어 실제 음성/포커스 탐색은 실행하지 못했다. AX tree 계약은 통과했고 실기기 VoiceOver가 남아 있다.
- 2026-07-17 최종 사용자 결정으로 위 initial entry/local profile card 정책은 폐기했다. 기존 unread는 anchor에서 읽고 현재 세션 realtime에만 3초 preview card를 제공한다. realtime payload의 닉네임+내용을 정상 정보로 사용하고 payload 정보가 없을 때만 `새 메시지`로 fallback한다. target이 이미 실제로 보이면 card를 표시하지 않거나 즉시 제거한다.
- 이 결정은 `decisions.md` D15/D19, Phase 6 계획·QA와 Chat/Test 진입점에 반영하고 구현했다. `ChatRoomViewModel.initialLatestPreview`, `localProfileRepository` DI와 initial preview 테스트를 제거했으며 realtime payload 기반 테스트로 교체했다. `ChatViewController`가 3초 task, 실제 visible target 억제와 route/search cleanup을 담당한다.

### 다음 핵심 task 선정과 사전 조사

- 2026-07-14 사용자 결정으로 `firestore-document-id-boundary-cleanup`을 당시 `socket-media-dedupe-hardening`보다 먼저 진행할 핵심 task로 선정했다.
- `HANDOFF.md`, `docs/ai/tasks/active.md`, `ENTRYPOINTS.md`, Chat/Data entrypoint와 Data Schema를 확인했다.
- 코드 수정 없이 `@DocumentID` inventory를 확인했다. 현재 선언은 Chat `ChatRoom` 1개와 Lookbook DTO 14개다.
- `ChatRoom.init(from:)`의 wrapper 재초기화, `ChatRoom.toDictionary()`의 중복 `ID` write, `SeasonDTO.fromDomain`의 non-nil `@DocumentID` 초기화를 주요 경계 후보로 확인했다.

### Firestore document ID boundary Phase 1

- 문서 경로 ID를 canonical source로 하고 저장 payload의 자기 `ID`/`id`를 제거하는 ADR-020과 task/phase 하네스를 생성했다.
- Lookbook DTO 14개의 `@DocumentID`를 제거하고 read DTO를 `Decodable`로 제한했다.
- 기본 identity가 필요한 10개 DTO mapper가 `documentID`를 명시적으로 받으며 14개 Firestore Repository가 snapshot 경로 ID를 전달한다.
- `SeasonWriteDTO`를 분리해 Season 생성 payload에서 자기 문서 ID를 제거했다.
- `FirestoreDocumentIDBoundaryTests` 3개가 통과했고 generic iOS Simulator build가 성공했다.
- 빌드 경고는 기존 Chat actor isolation, deprecated API와 link search path 항목이며 Phase 1 신규 warning은 확인되지 않았다.

### Firestore document ID boundary Phase 2

- `ChatRoom.id: String`을 non-optional로 전환하고 Domain에서 Firebase import, Codable, `@DocumentID`, write dictionary를 제거했다.
- `ChatRoomFirestoreDTO`와 `ChatRoomFirestoreMapper`를 추가했다. 경로 document ID, 방 이름, 생성자 UID, 생성일은 엄격히 검증하고 부가 필드는 legacy 기본값을 허용한다.
- `CreateRoomRepositoryProtocol`로 생성 UseCase의 최소 계약을 분리하고, document ID 생성 책임을 Repository로 이동했다.
- 새 방의 room/member/joined projection을 한 Firestore transaction으로 생성한다. room payload에는 `ID`, `id`, `participantUIDs`가 없다.
- 앱 target의 `@DocumentID`는 0개다.
- Chat mapper 5개와 CreateRoomUseCase 3개 테스트, RoomSearch/Message/Exit/PendingMedia/LookbookShare 영향 테스트가 통과했다.
- 전체 test target build-for-testing과 generic iOS Simulator build가 성공했다.
- 현재 rules의 `existsAfter/getAfter` 조건과 새 transaction payload가 정적으로 호환됨을 확인했다. 실제 rules 허용/거부는 Phase 3 emulator test로 남겼다.

### Firestore document ID boundary Phase 3

- `Rooms` create에서 `ID`/`id`를 거부하고 update에서는 해당 필드 추가·변경·삭제를 거부하도록 `firestore.rules`를 강화했다.
- legacy `ID`/`id`가 불변인 metadata update는 허용한다.
- `firebase.json`에 Firestore Emulator 8080과 UI 비활성 설정을 추가하고 `firestore-tests/` Node test 하네스를 만들었다.
- 정상 owner room/member/joined transaction과 10개 경계·권한 실패 시나리오, 총 11개 Emulator 테스트가 통과했다.
- Firebase rules `--dry-run` 컴파일이 성공했으며 운영 rules는 배포하지 않았다.
- Emulator 실행을 위해 Homebrew OpenJDK 21을 설치했다. 설치 중 기존 Node 22.5.1의 ICU 연결이 깨져 Node 22.23.1로 같은 메이저 범위에서 복구했으며 `node v22.23.1`, `npm 10.9.8` 정상 동작을 확인했다.

### Firestore document ID boundary Phase 4

- 정적 검사, Firestore Emulator 11개, rules dry-run, generic Simulator build와 test target build-for-testing이 통과했다.
- iOS 26.2 iPhone 17 Pro Max Simulator의 targeted runtime test 59개가 모두 통과했다.
- 실제 로그인 상태에서 Chat 목록·검색·기존 방·방 생성·이미지 patch·정보 수정·종료와 Lookbook read를 검증했고 `I-FST000002`와 permission/decode/mapping 오류는 0건이었다.
- QA 방과 Storage 객체를 정리했으며 운영 Rooms 4건의 legacy `ID`가 모두 경로 ID와 일치하고 소문자 `id`는 0건임을 읽기 전용으로 재확인했다.
- D8에 따라 Season write는 `SeasonWriteDTO` 자동 테스트로 완료 판정했다. production 진입점이 없는 직접 시즌 생성 UI는 별도 후속 후보로 분리했다.
- Firestore Emulator 11/11과 rules dry-run을 다시 통과한 뒤 2026-07-14 `outpick-664ae`에 `firestore.rules`를 운영 배포했다.
- cleanup 직전 Rooms 4건의 `ID == documentID`, lowercase `id` 0건을 재확인하고 transaction으로 uppercase `ID`만 삭제했다.
- 사후 감사에서 방 4개 유지, `ID`/`id` 보유 0건, 핵심 불변식 누락 0건을 확인했다. 로그인 앱 재실행에서도 방 4개가 정상 표시되고 관련 mapping/permission 오류가 0건이었다.
- 루트 ENTRYPOINTS와 CHAT/LOOKBOOK/DATA/FIREBASE/TESTS 세부 진입점을 DTO→Mapper→Repository, rules, 회귀 테스트와 운영 cleanup 기준으로 최종 최신화했다.

### 핵심 인프라 모듈화

- Phase 2: iOS callable 38개를 공통 transport와 기능별 adapter/capability/mapper로 이전하고 `CloudFunctionsManager.swift`와 `callHelloUser`를 제거했다.
- Phase 3: `GRDBManager.swift`를 `AppDatabase`, 기능별 Store와 소비자별 persistence Protocol로 전환했다. fresh migration, FTS strict rollback, outbox 포함 room cleanup을 자동 테스트로 고정했다.
- D19: database bootstrap 오류를 `SceneDelegate`까지 전파하고 독립 실패 화면·수동 재시도·DEBUG once/always 실패 주입을 구현했다.
- Phase 4: `functions/src/index.ts`를 49개 명시적 export의 얇은 entrypoint로 만들고 Firebase Admin/runtime 단일 owner와 기능별 module로 분리했다.
- Phase 5: `Socket/index.js`를 41줄 bootstrap으로 축소하고 application/production DI, 기능별 handler/service/state/lifecycle 경계를 추가했다.
- Phase 6: candidate SHA `7580a1e`의 전체 자동 회귀를 통과하고 Socket revision `outpick-socket-00006-k8k`와 Firebase Functions 49개를 운영 배포했다. Functions source hash는 `6ab1e46ab24ec61401c312e92ad4e7e1c5c133d9`다.
- D49: `RealtimeSocketListenerBinder`로 한 Socket client의 listener 8개를 연결 전에 한 번만 등록하고 reconnect/consumer lifecycle의 `off/on`과 raw Socket.IO logger를 제거했다.

### 검증과 수동 QA

- 최종화 재검증에서 D49 binder/Chat 관련 15개 테스트가 통과했고 generic iOS Simulator build가 성공했다.
- iOS targeted tests와 generic Simulator build, Functions 51 tests/lint/build, Socket check/43 tests와 ADC local smoke가 통과했다.
- D49 binder test 5개와 관련 Chat tests, cold launch 5회, background/foreground 5회, room rejoin/text 단일 표시와 credential log 비노출 gate가 통과했다.
- 로그인 앱에서 Functions `searchBrands`, `listMyBrandRequests` 인증 read smoke가 통과했다.
- 채팅 text/image/video/lookbook 전송과 앱 재실행 GRDB 복원, 검색, 이미지/동영상 모아보기를 확인했다.
- 실패 메시지 retry의 failed message/outbox 생성과 단일 서버 persist, 정상 상태 복원을 확인했다.
- 일반 구성원 leave와 방장 close 후 Firestore·GRDB cleanup을 확인했다.
- `QA-P6-PAGE-0714` 105-message fixture에서 최초 `seq 26...105` 80개 로드, `loadOlderMessages(before: seq 26)` 호출과 `seq 1...105` 확장, 중복 부재, 최상단 `001` 표시를 확인했다. fixture는 전부 삭제했다.

### 배포와 rollback

- Socket 현재 revision: `outpick-socket-00006-k8k`, previous rollback revision: `outpick-socket-00005-jwg`.
- Functions prior source rollback 기준: Git `ccc141e`.
- Socket/Functions 배포 gate에서 rollback은 필요하지 않았다.
- D49 앱 코드 commit은 `4a628dd`, 테스트 commit은 `6ab8d73`이다.
- task 상세 기록은 `docs/ai/tasks/core-infrastructure-modularization/`의 `progress.md`, `qa-checklist.md`, Phase 6 문서를 따른다.

## 3. 아직 남은 작업

1. Chat route/ViewModel 중복 생존 가능성을 별도 후속 분석으로 진행한다. 현재는 결함 확정이나 수정 승인이 아니며, navigation stack·동일 방 재진입·Controller/ViewModel `deinit`을 먼저 증명한다.
2. 이미 보이는 realtime target의 card 억제와 실제 VoiceOver 발화·포커스 순서는 필요할 때 선택적 후속 QA로 확인한다.
3. 실제 APNs delivery는 유효한 push target이 준비된 FCM 후속 QA로 유지한다.
4. Socket candidate 운영 traffic 전환은 별도 사용자 승인을 받는다. 현재 운영 revision은 기존 100%를 유지한다.
5. 시즌 직접 생성 진입점은 별도 후속 task로 유지한다.

## 4. 수정한 파일 목록

- `docs/ai/tasks/socket-message-dedupe-hardening/`: 전체 메시지 서버 idempotency와 iOS ingress dedupe의 design, D1~D13, Phase 계획, progress, QA checklist.
- `docs/ai/tasks/socket-ingress-ordering-hardening/`: Phase 0 D1~D14, 최종 design, Phase 1~5 plan, progress와 확정 QA checklist.
- `docs/ai/tasks/active.md`, core infrastructure D40 결정 문서: media 전용 참조를 새 task와 전체 메시지 범위로 전환.
- `HANDOFF.md`: 현재 설계 확정 상태, 다음 구현 순서와 승인 gate 반영.
- `Socket/src/messages/messageDeliverySingleFlight.js`: message identity single-flight owner/follower 병합.
- `Socket/src/messages/sequenceStore.js`: 최종 `{ seq, created }` transaction outcome과 duplicate no-write.
- `Socket/src/handlers/messageHandlers.js`, `lookbookShare/lookbookShareHandler.js`, `mediaHandlers.js`: 전체 message winner-only emit/push와 duplicate ACK.
- `Socket/src/media/mediaUploadService.js`: 완료된 media retry의 persisted sender/kind/path 검증.
- `Socket/src/app/createProductionDependencies.js`: process 공통 single-flight 생성·주입.
- 삭제: `Socket/src/media/mediaDeliveryState.js`, `Socket/test/media/mediaDeliveryState.test.js`.
- `Socket/test/messages/`, `test/handlers/`, `test/lookbookShare/`, `test/media/`, architecture contract: Phase 1~2 동시성·winner·retry 검증.
- `OutPick/Infra/Realtime/RealtimeSocketService.swift`: 방별 최근 ID 300개 Socket ingress dedupe와 local publish 분리.
- `OutPick/Infra/Realtime/RealtimeChatIngressOrdering.swift`, `FirebaseChatRealtimeGapRecoveryLoader.swift`: visible strict actor와 narrow Firestore recovery adapter.
- `OutPick/Infra/Banner/BannerManager.swift`, `BannerPresentationQueueState.swift`: lightweight watermark stream 소비와 bounded FIFO/summary presentation.
- `ChatRoomRealtimeRepository.swift`, `ChatRoomRealtimeUseCase.swift`, `ChatRoomViewModel.swift`, `ChatViewController.swift`: initial `entryTailSeq` baseline 전달.
- `AppCompositionRoot.swift`: production recovery loader를 단일 socket service에 주입.
- `OutPick/Features/Chat/Stores/ChatReadStateStore.swift`, `OutPick/Features/Chat/Domain/Models/ChatUnreadCatchUpState.swift`: Phase 6-A 단조 read frontier, Phase 6-B 고정 80개 latest target window, bounded 최신/고정 preview 계약.
- `ChatMessageManager.swift`, `ChatRoomMessageUseCase.swift`, `ChatInitialLoadUseCase.swift`, `ChatOutgoingOutboxUseCase.swift`: authoritative persistence 이후 서버 확정 ID batch outbox 수렴.
- `ChatRoomViewModel.swift`, `ChatViewController.swift`: catching-up scalar latest + persistence-only 처리, offscreen UI append/media warmup 차단.
- `ChatLatestMessageJumpView.swift`, `ChatMessageCollectionView.swift`, `ChatMessageWindowStore.swift`, `ChatRoomViewModel.swift`, `ChatViewController.swift`: Phase 6-C preview card, bounded snapshot/target 표시 handshake, explicit 즉시 persistence와 visible frontier.
- `OutPickTests/ChatReadStateStoreTests.swift`, `ChatUnreadCatchUpStateTests.swift`, `ChatLatestMessageWindowTests.swift`, `ChatMessageWindowStoreTests.swift`, `ChatRoomMessageUseCaseTests.swift`, `ChatOutgoingOutboxUseCaseTests.swift`, `ChatRoomViewModelMessageActionTests.swift`: Phase 6-A~C 상태·query·persistence/outbox/window/read 회귀.
- `OutPickTests/RealtimeChatIngressOrderingTests.swift`, `BannerPresentationQueueStateTests.swift`: strict/recovery와 Banner cap 회귀.
- `OutPickTests/ChatRoomSessionActorTests.swift`: ingress first-wins, 300개 eviction, reset, local/server 경계 테스트 6개.
- `OutPick/Features/Chat/Domain/Models/ChatMessageSendReceipt.swift`: 네 발신 종류 공통 ACK receipt와 optimistic message merger.
- `ChatViewController.swift`, `ChatViewControllerExtension.swift`: 최초 text/outbox retry/image/video finalize의 receipt 기반 UI·GRDB·outbox 수렴.
- `LookbookChatShareViewModel.swift`: 결과 불명 retry의 동일 message ID 재사용.
- `ChatMessageCell.swift`: 실패 메시지 재시도 아이콘의 버튼 접근성.
- `ChatMessageEmitAckMapperTests.swift`, `ChatOutgoingOutboxUseCaseTests.swift`, `LookbookChatShareUseCaseTests.swift`: receipt 파싱·병합·저장·ID 재사용 회귀.
- `docs/ai/ENTRYPOINTS.md`, `docs/ai/entrypoints/CHAT.md`, `docs/ai/entrypoints/TESTS.md`, task 문서: Phase 3 코드 진입점과 검증 결과 반영.
- `docs/ai/ENTRYPOINTS.md`, `docs/ai/entrypoints/CHAT.md`, `TESTS.md`: Phase 1 코드·검증 진입점.
- `OutPick/Features/Lookbook/Models/DTOs/`: read DTO 14개 경로 ID 분리와 새 `SeasonWriteDTO`.
- `OutPick/Features/Lookbook/Repositories/Implementations/Firestore*Repository.swift`: snapshot 문서 ID를 mapper에 명시 전달.
- `OutPick/Features/Lookbook/Models/Mapping/MappingError.swift`: 경로 ID 기준 오류 문구.
- `OutPickTests/FirestoreDocumentIDBoundaryTests.swift`: 경로 ID 우선·빈 ID 실패·Season write payload 테스트.
- `OutPick/Features/Chat/Domain/Models/ChatRoom.swift`, `CreateChatRoomInput.swift`: pure Domain room identity와 생성 입력.
- `OutPick/DB/Firebase/DatabaseManager/DTOs/ChatRoomFirestoreDTO.swift`, `Mappers/ChatRoomFirestoreMapper.swift`: Chat read DTO와 경로 ID/write payload mapper.
- `FirebaseChatRoomRepositoryProtocol.swift`, `FirebaseChatRoomRepository.swift`, `CreateRoomUseCase.swift`: narrow create 계약, Repository ID 생성, room/member/joined 단일 transaction.
- Chat room `.ID` 소비 파일과 관련 테스트: non-optional `.id` 계약으로 전환.
- `OutPickTests/ChatRoomFirestoreMapperTests.swift`, `CreateRoomUseCaseTests.swift`: mapper/write payload와 생성 UseCase 계약 테스트.
- `firestore.rules`: Rooms create/update의 `ID`/`id` 재유입 차단.
- `firebase.json`: Firestore Emulator 로컬 설정.
- `firestore-tests/`: rules unit testing package, 11개 계약 테스트와 Java 경로 감지 runner.
- `docs/ai/tasks/firestore-document-id-boundary-cleanup/`: design, decisions, plan, progress, QA와 Phase 1~4 문서.
- ADR-020, ENTRYPOINTS/CHAT/LOOKBOOK/DATA/TESTS/DATA_SCHEMA/active 문서: canonical document ID 경계와 Phase 1~2 결과.
- Functions와 Firestore indexes는 수정하지 않았다. 강화한 `firestore.rules`를 운영 배포하고 운영 Rooms 4개의 uppercase `ID` 필드만 삭제했다.

## 5. 중요한 아키텍처 결정

### Socket ingress ordering과 gap recovery

- 선택: `RealtimeSocketService`가 message callback의 단일 순차 ingress를, visible 방의 `ChatRoomStrictSessionActor`가 ordering/pending/gap을 소유한다. background `ChatRoomSessionActor`는 lightweight watermark 이후 metadata/Banner fan-out만 담당하고 history catch-up은 기존 UseCase/ViewModel에 유지한다.
- 선택: strict actor는 initial load의 `entryTailSeq`를 checkpoint로 삼고 `lastReleasedSeq + 1`을 expected seq로 사용한다. 같은 사용자 reconnect state 유지와 rejoin 감사 연결은 Phase 4에서 완료한다.
- 선택: pending 100개에서 즉시 recovery, 300개에서 authoritative mode, gap grace 0.5초, backfill page 100개와 최대 3회 retry를 사용한다.
- 이유: consumer별 정렬과 history/realtime 중복 상태를 피하고 기존 window/newer/reconnect 수치를 재사용해 bounded recovery를 만든다.
- 트레이드오프: recovery DI와 reconnect lifecycle 변경 범위가 넓어지지만 서버 wire/schema 변경 없이 client에서 누락·역순을 통제한다.
- 보류한 대안: room tail/read seq seed, unbounded buffer, checkpoint skip, ViewModel/Banner별 recovery와 actor의 Firestore 직접 접근은 identity 오판, 메모리 무제한, 누락 은폐 또는 아키텍처 위반 때문에 제외했다.
- 재검토 조건: server replay cursor/API, 개별 message hard delete, durable client checkpoint 또는 운영 recovery 비용 증거가 생길 때 D4/D7~D12를 다시 검토한다.

### 실시간 message end-to-end idempotency

- 선택: 인증·권한·rate limit 등 요청별 검증 뒤 같은 instance의 `kind + roomID + messageID` 요청은 single-flight로 합치고, Firestore transaction의 `{ seq, created }` 결과에서 `created == true`인 winner만 emit/push한다.
- 이유: local Promise는 같은 instance의 중복 작업을 효율적으로 합치고, Firestore winner는 재연결·재시도·다른 instance에서도 단일 side effect의 권위를 제공한다.
- 트레이드오프: 정확성 보장은 Firestore transaction에 의존하며 이미 완료된 재요청은 매번 Firestore 권위를 확인한다. 첫 구현에는 근거 없는 완료 cache와 별도 owner timeout을 넣지 않는다.
- 보류한 대안: process-local state만으로 보장, Redis 분산 lock, transactional outbox/exactly-once delivery는 각각 instance 경계 한계 또는 현재 요구 대비 운영 복잡성 때문에 제외했다.
- 재검토 조건: Firestore 확인 비용이 관측 가능한 병목이 되거나 emit/push 유실까지 복구해야 하는 요구가 생길 때 완료 cache 또는 outbox를 별도 설계한다.

### iOS ingress message ID dedupe

- 선택: `ChatRoomSessionActor`가 방별 최근 message ID 300개를 actor lifetime 동안 유지하고 첫 event만 consumer fan-out한다.
- 이유: 현재 UI active window 300개와 같은 bounded 기준을 사용하며 attachment cache, profile refresh, read state, preview, persistence 전에 중복을 차단한다.
- 트레이드오프: 300개를 벗어난 오래된 ID가 다시 유입되면 최종 `ChatMessageWindowStore`와 GRDB upsert 방어선이 처리한다. 같은 ID의 다른 seq는 첫 event를 보존하고 두 번째 event를 drop한다.
- 보류한 대안: consumer별 dedupe와 영구 저장 dedupe만 유지하는 방식은 중복된 선행 부작용을 막지 못해 제외했다.
- 재검토 조건: UI window 크기 변경, 장기 offline replay 도입 또는 room session actor lifecycle 변경 시 용량과 owner를 다시 검토한다.

### iOS 공통 send receipt 수렴

- 선택: text/Lookbook/images/video ACK를 `ChatMessageSendReceipt`로 통일하고 identity가 일치할 때만 optimistic message를 서버 확정 seq/attachment와 병합한다.
- 이유: duplicate ACK를 단순 성공 Bool로만 소비하면 서버 성공 뒤에도 실패 UI와 outbox가 남아 사용자가 재시도를 반복할 수 있다.
- 트레이드오프: legacy 빈 성공 ACK 호환을 위해 seq는 optional이지만 candidate 상세 ACK에서는 authoritative seq를 반영한다.
- 보류한 대안: text만 별도 보강하는 방식은 공통 결과 불명 계약을 종류별로 다시 분기하므로 제외했다.

### Modular monolith와 기존 배포 단위 유지

- 선택: 기능별 Protocol/Client/Store/handler/service와 공통 transport/database/runtime를 두고 앱, Functions default codebase, 단일 Socket Cloud Run service 배포 단위는 유지한다.
- 이유: giant concrete dependency와 변경 충돌은 줄이면서 MSA/codebase 분리의 운영 복잡성은 도입하지 않는다.
- 트레이드오프: 파일과 조립 type은 늘었지만 기능 소유권, 테스트 경계와 rollback 범위가 명확해졌다.
- 보류한 대안: 독립 service/codebase/Kubernetes는 독립 배포·IAM·autoscaling 요구가 구체화될 때 ADR-019 기준으로 재검토한다.

### D49 one-time Socket listener

- 선택: listener lifetime을 Socket client lifetime과 동일하게 두고 새 client 생성 때만 새 binder를 만든다.
- 이유: Socket.IO handler dispatch와 reconnect 중 `off/on`의 경쟁 가능성을 제거하고 event surface를 unit test로 고정한다.
- 트레이드오프: consumer가 없어도 listener는 유지되지만 actor의 room session lookup에서 payload를 안전하게 drop한다.
- 보류한 대안: reconnect마다 listener를 재등록하거나 Socket.IO 내부 handler 배열을 직접 검사하는 방식은 경쟁 상태와 라이브러리 private 구현 결합 때문에 제외했다.

### 종료 예외 분리

- 선택: FCM, D40, `@DocumentID` 경고와 일부 선택적 수동 QA를 미완료 Phase로 남기지 않고 별도 후속으로 분리한다.
- 이유: FCM은 외부 계정 조건, D40은 동작 변경 기능, `@DocumentID`는 별도 데이터 설계가 필요하며 이번 리팩토링의 완료 기준과 분리된다.
- 재검토 조건: Apple 개발자 계정 결제, media duplicate 운영 증거, Firestore mapping 기능 실패 또는 관련 기능 변경이 발생할 때 각각 새 task로 시작한다.

### Firestore document ID canonical boundary

- 선택: `DocumentSnapshot.documentID`만 자기 문서 identity의 source로 사용하고 write payload에 같은 `ID`/`id`를 저장하지 않는다.
- 이유: 경로 ID, 저장 필드와 `@DocumentID` wrapper의 우선순위 충돌과 `I-FST000002` 경고를 구조적으로 제거한다.
- 트레이드오프: Repository와 mapper 호출부가 문서 ID를 명시적으로 전달하고 Chat의 `.ID` 사용처를 넓게 변경해야 한다.
- 보류한 대안: wrapper read-only 최소 수정과 ChatRoomID 단독 도입은 각각 SDK 결합 잔존과 ID 체계 비대칭 때문에 제외했다.
- 추가 강제: Phase 3에서 Rooms create/update rules가 `ID`/`id` 재유입을 차단하며 2026-07-14 운영 배포했다. 기존 legacy `ID` 4건도 별도 승인 후 cleanup했다.

### Chat Domain/Firestore 생성 경계

- 선택: `ChatRoom`은 non-optional `id`와 화면에 필요한 상태만 소유하고 Firestore decode/write는 DTO/Mapper가 담당한다. `CreateRoomUseCase`는 narrow Repository 계약만 의존한다.
- 이유: Domain의 Firebase SDK 결합과 경로 ID/저장 ID 이중 source를 제거하고, 생성의 부분 성공을 Repository transaction에서 막는다.
- 트레이드오프: `.ID` optional 방어를 앱 전반에서 `.id` 계약으로 바꿔 영향 파일이 넓어졌지만 잘못된 identity 상태를 타입 경계 밖으로 밀어냈다.
- 보류한 대안: `ChatRoomID` 별도 값 타입은 현재 String 기반 경계와 비대칭 비용 때문에 도입하지 않았다. 부가 필드까지 모두 필수 decode하는 방식은 legacy room 호환성 때문에 제외했다.
- 재검토 조건: 다른 room backend 또는 복수 ID namespace가 도입되면 `ChatRoomID` 값을 다시 검토한다.

### Legacy ID를 보존하는 Rules update 경계

- 선택: create는 `ID`/`id` 키 존재를 거부하고 update는 해당 키의 diff만 거부한다.
- 이유: 신규 오염은 즉시 차단하면서 운영에 남은 legacy `Rooms.ID` 때문에 정상 방 정보 수정이 막히지 않게 한다.
- 트레이드오프: rules 배포만으로 legacy 필드는 자동 삭제되지 않아 별도 승인된 Admin SDK transaction으로 제거했다.
- 보류한 대안: legacy ID가 있는 모든 update를 거부하는 방식은 정상 metadata 수정 회귀 때문에 제외했다.
- 재검토 조건: 향후 rules 테스트 fixture를 현재 운영 상태에 맞춰 단순화할 때 legacy 불변 update 호환 테스트의 보존 여부를 별도로 결정한다.

## 6. 다시 확인해야 할 불확실한 부분

- 재확인 필요: `ChatCoordinator.push`가 기존 Chat route의 lifecycle만 종료하고 navigation stack에서 제거하지 않으므로, 반복 Chat 진입에서 종료된 `ChatViewController`와 강하게 소유된 `ChatRoomViewModel`/message window가 실제 중복 생존하는지 진입 경로별 재현과 `deinit` 증거가 필요하다. 값 타입인 `ChatReadStateStore`/`ChatUnreadCatchUpState` 자체의 누적 문제로 단정하지 않는다.
- traffic 0% candidate의 네 종류 실제 retry와 오래된 duplicate ACK room summary 역행 수정·재검증은 완료했다.
- 실제 Cloud Run 서로 다른 두 instance에 같은 요청을 deterministic하게 분산하는 검증은 수행하지 않았고 공유 Firestore transaction fake로 대체했다.
- 현재 Cloud Run 구성과 revision은 외부 상태다. 운영 전환 전 instance 수, concurrency와 reconnect 조건을 읽기 전용으로 다시 확인한다.
- 서로 다른 instance의 동시 요청 자동 테스트는 독립 local single-flight state와 공유 Firestore transaction fake로 재현할 계획이며 실제 다중 revision 운영 검증 범위는 구현 후 별도 승인한다.
- FCM fanout은 실제 APNs entitlement/profile 환경에서 검증하지 않았다. Apple 개발자 계정 결제 후 재확인 필요다.
- Phase 2의 모든 상태 변경 화면을 수동으로 순회한 것은 아니다. 자동 wire/export/runtime 계약과 승인된 운영 read/통합 QA까지만 확인했다.
- `I-FST000002`는 Phase 4 전체 수동 QA 로그에서 0건이었고 기존 room 실제 read도 통과했다.
- 운영 rules는 2026-07-14 배포했다. 배포 직전 Emulator 11/11과 dry-run을 다시 통과했다.
- 운영 Rooms 4건 cleanup과 사후 재감사는 완료됐다. 감사 시점 이후 운영 데이터는 외부 상태이므로 관련 회귀 조사 시 다시 확인한다.
- Phase 1 실제 Firebase 브랜드·시즌·포스트·댓글 read는 통과했다. 시즌 직접 생성은 production 조립·표시 진입점이 없어 D8에 따라 자동 write 계약으로 완료 판정했으며, UI 처리는 별도 후속 후보다.
- 최신 Cloud Run revision, Functions 상태와 운영 데이터는 외부 상태이므로 후속 작업 시작 시 읽기 전용으로 재확인한다.

## 7. 다음 턴에서 바로 실행해야 할 작업

- `socket-message-dedupe-hardening`은 종료됐다. 실제 transport 실패→재연결→동일 ID retry까지 `seq=22` 단일 수렴을 확인했다.
- `socket-ingress-ordering-hardening`의 Phase 1~6 구현·자동 회귀·실제 Firebase/Simulator 핵심 QA는 완료됐고 task를 종료했다.
- 실제 QA에서 확인한 날짜 separator 중복은 bounded visible window 전체 재구성으로 수정했다.
- room join은 `RealtimeRoomJoinState` single-flight와 공동 waiter로 통일하고, stale Socket generation callback 차단과 Banner recoverable retry를 추가했다.
- reconnect는 갱신 token과 새 Socket generation으로 복구하고, room close observer는 route lifetime에 결합했다. 실기기 `680001 → 680004`, `990001` leave, 최종 room close 자동 이동과 종료 뒤 join 재시도 0회를 확인했다.
- 다음 핵심 후보는 `ChatCoordinator`, `ChatViewController`, `ChatRoomViewModel`의 navigation stack 보관·해제 경로 분석이다. 먼저 분석 결과와 선택지의 장단점을 보고하며 사용자 승인 전에는 route 제거/재사용 코드를 수정하지 않는다.
- candidate 운영 traffic 전환은 별도 사용자 승인을 기다린다.
