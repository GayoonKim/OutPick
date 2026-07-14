# OutPick Handoff

## 1. 최종 목표

- `core-infrastructure-modularization`은 완료됐다. iOS Cloud Functions/GRDB, Firebase Functions와 Socket의 대형 concrete 진입점을 기능별 계약·구현과 공통 runtime, 얇은 entrypoint 구조로 전환하면서 기존 앱/Functions/Cloud Run 배포 단위와 wire/data 계약을 보존했다.
- 현재 진행 중인 핵심 task는 없다. 새 작업은 `docs/ai/tasks/active.md`에 등록하기 전에 관련 하네스를 읽고 설계·사용자 승인을 거친다.

## 2. 완료한 작업

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

이번 task의 필수 작업은 없다. 다음은 별도 후속이다.

1. FCM fanout: Apple 개발자 계정 결제 후 실제 APNs/FCM 환경에서 새 QA task로 진행한다.
2. D40 media dedupe: in-flight Promise, bounded TTL/LRU 완료 cache와 Firestore transaction winner 기반 단일 emit/push를 별도 기능으로 설계한다.
3. Firestore `I-FST000002`: `ChatRoom.init(from:)`, `SeasonDTO.fromDomain`과 나머지 `@DocumentID` 초기화, 문서 경로 ID/중복 `ID` field 범위를 확정한 뒤 별도 리팩토링한다.
4. Phase 2의 나머지 상태 변경 화면 수동 QA는 이번 종료 차단에서 제외했다. 관련 기능 변경이나 출시 회귀 범위 확대 시 수행한다.

## 4. 수정한 파일 목록

이번 최종화 직전 working tree 기준 변경은 다음과 같다.

- `OutPick/Infra/Realtime/RealtimeSocketService.swift`: one-time listener binder 조립, reconnect 중 handler mutation과 raw logger 제거.
- `OutPick/Infra/Realtime/RealtimeSocketListenerBinder.swift`: Socket listener 등록 전용 Protocol, production adapter와 binder 추가.
- `OutPickTests/RealtimeSocketListenerBinderTests.swift`: listener surface·중복 등록 방지·callback 전달 테스트 5개 추가.
- `docs/ai/entrypoints/CHAT.md`: listener lifetime과 Firestore `@DocumentID` 후속 진입점 추가.
- `docs/ai/entrypoints/TESTS.md`: D49 targeted test와 실제 reconnect gate 기록.
- `docs/ai/tasks/active.md`: 현재 task 없음과 핵심 인프라 모듈화 완료 상태 기록.
- `HANDOFF.md`: 완료 상태, 후속 작업과 다음 진입점을 7개 항목으로 갱신.
- `docs/ai/tasks/core-infrastructure-modularization/*`: 최종 진행·QA·Phase 상태를 담은 34개 하네스 문서. 기본 `.git/info/exclude` 대상이지만 사용자 명시 승인으로 완료 아카이브에 포함했다.

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

## 6. 다시 확인해야 할 불확실한 부분

- FCM fanout은 실제 APNs entitlement/profile 환경에서 검증하지 않았다. Apple 개발자 계정 결제 후 재확인 필요다.
- Phase 2의 모든 상태 변경 화면을 수동으로 순회한 것은 아니다. 자동 wire/export/runtime 계약과 승인된 운영 read/통합 QA까지만 확인했다.
- Firestore `I-FST000002`의 기능 장애는 확인되지 않았지만 정확한 정리 범위는 확실하지 않음이며 구현 전 inventory가 필요하다.
- 최신 Cloud Run revision, Functions 상태와 운영 데이터는 외부 상태이므로 후속 작업 시작 시 읽기 전용으로 재확인한다.

## 7. 다음 턴에서 바로 실행해야 할 작업

- 현재 진행 중인 task는 없다.
- 새 작업 요청 시 `docs/ai/tasks/active.md`, `docs/ai/ENTRYPOINTS.md`와 관련 entrypoint 문서를 먼저 읽는다.
- Apple 개발자 계정 결제 후 FCM fanout QA 요청이 오면 새 task 범위, 테스트 계정/기기, foreground/background/terminated 수신 완료 기준과 fixture cleanup을 먼저 논의한다.
