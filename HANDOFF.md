# OutPick Handoff

## 1. 최종 목표

- `core-infrastructure-modularization`은 완료됐다. iOS Cloud Functions/GRDB, Firebase Functions와 Socket의 대형 concrete 진입점을 기능별 계약·구현과 공통 runtime, 얇은 entrypoint 구조로 전환하면서 기존 앱/Functions/Cloud Run 배포 단위와 wire/data 계약을 보존했다.
- `firestore-document-id-boundary-cleanup`은 완료됐다. 문서 경로 ID를 canonical source로 통일하고 앱 `@DocumentID`, 신규 중복 ID write, 운영 Rooms의 legacy `ID`를 제거했다.
- Phase 1~4 구현·자동·수동 검증, Firestore rules 운영 배포, 운영 `Rooms.ID` 4건 cleanup과 사후 재감사를 모두 완료했다. 현재 진행 중인 핵심 task는 없다.

## 2. 완료한 작업

### 다음 핵심 task 선정과 사전 조사

- 2026-07-14 사용자 결정으로 `firestore-document-id-boundary-cleanup`을 `socket-media-dedupe-hardening`보다 먼저 진행할 핵심 task로 선정했다.
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

현재 task의 필수 작업은 없다. 다음은 별도 후속 후보다.

1. `socket-media-dedupe-hardening`을 다음 핵심 task 후보로 설계한다.
2. 시즌 직접 생성 진입점 복원 또는 미사용 코드 제거를 별도 설계한다.
3. FCM fanout은 Apple 개발자 계정 결제 후 실제 APNs/FCM 환경에서 별도 QA task로 진행한다.

## 4. 수정한 파일 목록

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

- FCM fanout은 실제 APNs entitlement/profile 환경에서 검증하지 않았다. Apple 개발자 계정 결제 후 재확인 필요다.
- Phase 2의 모든 상태 변경 화면을 수동으로 순회한 것은 아니다. 자동 wire/export/runtime 계약과 승인된 운영 read/통합 QA까지만 확인했다.
- `I-FST000002`는 Phase 4 전체 수동 QA 로그에서 0건이었고 기존 room 실제 read도 통과했다.
- 운영 rules는 2026-07-14 배포했다. 배포 직전 Emulator 11/11과 dry-run을 다시 통과했다.
- 운영 Rooms 4건 cleanup과 사후 재감사는 완료됐다. 감사 시점 이후 운영 데이터는 외부 상태이므로 관련 회귀 조사 시 다시 확인한다.
- Phase 1 실제 Firebase 브랜드·시즌·포스트·댓글 read는 통과했다. 시즌 직접 생성은 production 조립·표시 진입점이 없어 D8에 따라 자동 write 계약으로 완료 판정했으며, UI 처리는 별도 후속 후보다.
- 최신 Cloud Run revision, Functions 상태와 운영 데이터는 외부 상태이므로 후속 작업 시작 시 읽기 전용으로 재확인한다.

## 7. 다음 턴에서 바로 실행해야 할 작업

- 현재 진행 중인 task는 없다.
- 다음 핵심 후보는 `socket-media-dedupe-hardening`이며, 시작 전 관련 하네스와 운영 중복 증거를 읽고 설계 쟁점을 사용자와 확정한다.
- 시즌 직접 생성 UI와 FCM fanout은 각각 별도 조건이 충족될 때 새 task로 진행한다.
