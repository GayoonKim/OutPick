# Lookbook Chat Share Progress

## 현재 상태

- 상태: Phase 3.5 Socket 서버 A안 모듈 분리 및 문법 검증 완료.
- 공식 하네스 반영 완료:
  - `docs/ai/PRD.md`
  - `docs/ai/FLOW.md`
  - `docs/ai/SCREEN_SPEC.md`
  - `docs/ai/DATA_SCHEMA.md`
  - `docs/ai/CODE_ARCHITECTURE.md`
  - `docs/ai/ADR.md`
- `.gitignore`에 Firebase Admin 키와 `Socket/node_modules/` 제외 패턴 반영 완료.
- `Socket/index.js`에서 Firebase Admin 서비스 계정 JSON 파일명 직접 참조를 제거했다.
- `Socket/index.js`는 `FIREBASE_SERVICE_ACCOUNT_JSON` env secret 또는 Application Default Credentials를 사용한다.
- `Socket/package.json`에 `start`, `check`, `check:adc` script를 추가했다.
- 로컬 Socket 서버 기본 인증은 ADC 방식으로 정리했다. `npm --prefix Socket run check:adc`로 현재 머신의 ADC 설정이 정상임을 확인했으므로 매번 Firebase Admin secret env를 주입하지 않는다.
- 현재 `Socket/`은 운영 배포 서버가 아니라 로컬 개발용 소켓 서버다.
- App Store 배포 계획이 아직 없으므로 운영 호스팅 경로는 지금 결정하지 않는다.
- 로컬 실행은 `Socket` 폴더 기준 `npm start`로 켜고 끄는 방식이다.
- `ChatMessageType`, `LookbookSharedContent`, `ChatMessage.messageType`, `ChatMessage.sharedContent`를 추가했다.
- `ChatMessage` dict/socket/codable 변환에서 `lookbookShare` 메시지와 legacy `Text/Image/Video` 값을 안전하게 처리한다.
- invalid `sharedContent`는 메시지를 버리지 않고 `sharedContent == nil`로 둔다.
- GRDB `chatMessage` 테이블에 `messageType`, `sharedContent` 컬럼 migration을 추가했다.
- GRDB 채팅 메시지 저장/조회 경로에서 공유 콘텐츠 JSON 저장과 복원을 처리한다.
- `ChatMessageLookbookShareTests`를 추가했다.
- `LoadShareableJoinedRoomsUseCase`를 추가해 기존 참여방 조회 결과에서 공유 가능한 방만 필터한다.
- `ShareLookbookContentToChatUseCase`를 추가해 공유 전송 전 방/콘텐츠 유효성을 검증한다.
- `LookbookChatShareSendingRepositoryProtocol`과 `SocketLookbookChatShareSendingRepository`를 추가했다.
- `SocketIOManager.sendLookbookShare(...) async throws`를 추가해 `chat:lookbookShare` 이벤트를 ACK 기반으로 전송한다.
- `LookbookChatShareAckMapper`와 `LookbookChatShareError`로 socket ACK 실패를 domain error로 매핑한다.
- `ChatContainer`에서 Phase 2 UseCase factory를 제공한다.
- `LookbookChatShareUseCaseTests`를 추가했다.
- `ChatMessage.swift`에 모여 있던 `ReplyPreview`, `VideoMetaPayload`, `ChatMessageType`, `LookbookSharedContent`, `Attachment`를 별도 모델 파일로 분리했다.
- `Socket/index.js`에 `chat:lookbookShare` 이벤트를 추가했다.
- 공유 이벤트는 payload size, `sharedContent` v1 shape, 필수 ID, room join 상태, Firestore room 존재, `isClosed == false`, 참여자 여부를 검증한다.
- 서버 저장 문서의 `msg`는 사용자 텍스트가 있으면 trim한 텍스트, 없으면 공유 타입 기반 fallback preview로 항상 채운다.
- 정상 공유 메시지는 `allocateSeqAndPersist`를 통해 `Rooms/{roomID}/Messages/{messageID}`와 `Rooms.lastMessage/lastMessageAt`을 갱신한다.
- 공유 메시지 broadcast는 기존 `chat message` 스트림을 사용한다.
- Phase 3.5에서 `Socket/index.js`의 공유 관련 로직과 공통 인프라를 `Socket/src/` 아래로 분리했다.
- 분리한 레이어:
  - `config.js`: env/상수.
  - `firebaseAdmin.js`: Firebase Admin 초기화와 `db`.
  - `utils/`: 문자열/시간/payload size/rate limit.
  - `users/`: 사용자 문서 조회.
  - `rooms/`: room registry와 access 검증.
  - `messages/`: sequence persistence와 preview 계산.
  - `push/`: chat push fanout.
  - `lookbookShare/`: `sharedContent` 검증과 `chat:lookbookShare` handler.
- `Socket/index.js`는 아직 text/image/video/room lifecycle handler를 포함하지만, 공유 기능과 공통 인프라는 factory 주입 방식으로 조립한다.

## 완료한 결정

- 내부 공유 대상은 브랜드/시즌/포스트와 참여 중인 그룹 오픈채팅방이다.
- 외부 공유, 1:1 채팅, 여러 방 동시 공유, 함께 보낼 텍스트 입력은 MVP 제외다.
- 공유 메시지는 `chat:lookbookShare`로 전송하고 기존 `chat message` 스트림으로 수신한다.
- 채팅방 카드는 snapshot만 렌더링하고 룩북 원본은 조회하지 않는다.
- 룩북 원본 최신성은 카드 탭 후 상세 화면에서 비동기로 확인한다.
- `ChatViewController`와 `ChatMessageCell`에 직접 기능을 덧붙이지 않고 접합부를 만든다.
- `AppContentRouting`은 얇게 시작하되 후속 `MainTabCoordinator` 승격이 가능하게 설계한다.

## 아직 구현하지 않은 것

- 공유 sheet UI.
- 채팅 공유 카드 UI.
- App-level routing.
- 통합 QA.
- 로컬 socket server 실제 실행 ACK smoke.
- 운영 socket server 배포.
- 공유 기능 완료 후 `ChatViewController.swift` 레이어 분리.
- `ChatViewController.swift` 레이어 분리 후 Socket 서버 전체 레이어 리팩토링.

## 다음 작업

1. 필요 시 로컬 socket server를 Firebase Admin credential과 함께 실행해 정상/권한 실패/payload 실패 ACK smoke를 확인한다.
2. Phase 4 공유 sheet UI 구현 전, `ShareLookbookContentToChatUseCase.execute(..., messageText:)`를 호출할 ViewModel 입력 정책을 확정한다.
3. 공유 기능 MVP 완료 후 `ChatViewController.swift`의 메시지 전송, 소켓 세션, 미디어 처리, 메뉴/action policy 책임을 단계적으로 분리한다.
4. `ChatViewController.swift` 레이어 분리 후 Socket 서버 전체 레이어 리팩토링을 진행한다.
   - 현재 Phase 3.5 A안은 공유 기능과 공통 인프라 중심의 얇은 분리다.
   - 후속 전체 리팩토링에서는 text/image/video/room lifecycle handler까지 `Socket/src` 레이어로 이동한다.
   - 목표는 `Socket/index.js`를 bootstrap과 handler registration만 담당하는 파일로 축소하는 것이다.
5. 운영 배포는 별도 승인 전까지 하지 않는다.

## 검증 기록

- `git check-ignore -v Socket/outpick-664ae-firebase-adminsdk-s16bx-6165221731.json Socket/node_modules/.package-lock.json` 확인 완료.
- `git diff --check -- docs/ai/...` 확인 완료.
- `npm --prefix Socket run check` 확인 완료.
- `git diff --check -- OutPick/Features/Chat/Domain/Models/ChatMessage.swift OutPick/DB/GRDB/GRDBManager.swift OutPickTests/ChatMessageLookbookShareTests.swift` 확인 완료.
- `xcodebuild -quiet -scheme OutPick -destination 'generic/platform=iOS Simulator' build-for-testing` 확인 완료.
- `xcodebuild test`는 사용자 명시 요청 전까지 실행 보류.
- `git diff --check -- OutPick/Features/Chat/Domain/UseCases/LoadShareableJoinedRoomsUseCase.swift OutPick/Features/Chat/Domain/UseCases/ShareLookbookContentToChatUseCase.swift OutPick/Features/Chat/Repositories/LookbookChatShareSendingRepository.swift OutPick/Socket/SocketIOManager.swift OutPick/Features/Chat/ChatContainer.swift OutPickTests/LookbookChatShareUseCaseTests.swift` 확인 완료.
- `xcodebuild -quiet -scheme OutPick -destination 'generic/platform=iOS Simulator' build-for-testing` 재확인 완료.
- `git diff --check -- OutPick/Features/Chat/Domain/Models/ChatMessage.swift OutPick/Features/Chat/Domain/Models/ReplyPreview.swift OutPick/Features/Chat/Domain/Models/VideoMetaPayload.swift OutPick/Features/Chat/Domain/Models/ChatMessageType.swift OutPick/Features/Chat/Domain/Models/LookbookSharedContent.swift OutPick/Features/Chat/Domain/Models/Attachment.swift` 확인 완료.
- Phase 2.5 이후 `xcodebuild -quiet -scheme OutPick -destination 'generic/platform=iOS Simulator' build-for-testing` 확인 완료.
- Phase 3 전 `msg` 계약 정리 후 `git diff --check` 확인 완료.
- Phase 3 전 `xcodebuild -quiet -scheme OutPick -destination 'generic/platform=iOS Simulator' build-for-testing` 확인 완료.
- Phase 3 후 `git diff --check -- Socket/index.js` 확인 완료.
- Phase 3 후 `npm --prefix Socket run check` 확인 완료.
- Phase 3.5 후 `git diff --check -- Socket/index.js Socket/src` 확인 완료.
- Phase 3.5 후 `npm --prefix Socket run check` 확인 완료.
- Phase 3.5 후 `for f in Socket/src/**/*.js; do node --check "$f" || exit 1; done` 확인 완료.
- ADC 로그인 후 `npm --prefix Socket run check:adc` 확인 완료.

## Phase 2 진입점 확인

- DI 조립: `OutPick/Features/Chat/ChatContainer.swift`
  - 기존 `JoinedRoomsUseCase`, `ChatRoomMessageUseCase`를 보관하고 ViewModel factory를 제공한다.
  - Phase 2의 `LoadShareableJoinedRoomsUseCase`, `ShareLookbookContentToChatUseCase`도 이 컨테이너에서 생성하는 방향이 자연스럽다.
- 참여방 조회: `OutPick/Features/Chat/Domain/UseCases/JoinedRoomsUseCase.swift`
  - `fetchJoinedRoomsHead(limit:)`, `loadMoreJoinedRooms(after:limit:)`가 이미 참여방 페이지를 반환한다.
  - `ChatRoom.participants`, `ChatRoom.isClosed`, `ChatRoom.ID`로 공유 가능 여부의 기본 필터를 만들 수 있다.
- 참여방 repository: `OutPick/DB/Firebase/DatabaseManager/Repositories/FirebaseChatRoomRepository.swift`
  - `participantIDs arrayContains current user` 쿼리로 참여방을 가져온다.
  - 현재 쿼리는 `isClosed == false`를 서버에서 필터하지 않으므로 Phase 2에서는 클라이언트 필터로 시작한다.
- 소켓 전송: `OutPick/Socket/SocketIOManager.swift`
  - 기존 전송은 `emitWithAck(...).timingOut(...)` callback 기반이다.
  - `sendVideo`/`requestLeaveOrCloseRoom`의 completion 패턴을 참고해 `sendLookbookShare(...) async throws` 래핑을 추가하는 방향이 적합하다.
- 기존 레거시 직접 호출: `OutPick/Features/Chat/Controllers/ChatViewController.swift`, `OutPick/Features/Chat/Controllers/ChatViewControllerExtension.swift`
  - 텍스트/이미지/비디오는 아직 `SocketIOManager.shared`를 직접 호출한다.
  - Phase 2에서는 룩북 공유 전송만 새 UseCase/Repository 경계로 시작하고, 기존 채팅 전송 리팩토링은 범위 밖으로 둔다.
- 테스트 진입점: `OutPickTests`
  - 기존 테스트는 Swift Testing 기반이며 fake/spy를 테스트 파일 내부에 두는 패턴이다.
  - Phase 2 테스트는 fake sending repository와 fake joined rooms loader 기반 unit test가 적합하다.

## Phase 2 구현 기록

- 공유 가능 방 필터는 새 Firestore 쿼리/인덱스 없이 기존 `JoinedRoomsUseCase.fetchJoinedRoomsHead(limit:)` 결과를 클라이언트에서 필터한다.
- 필터 조건은 `roomID` 존재, `isClosed == false`, 현재 사용자가 `participants`에 포함됨이다.
- 공유 전송은 View/ViewModel이 socket을 직접 호출하지 않도록 `ShareLookbookContentToChatUseCase -> LookbookChatShareSendingRepositoryProtocol -> SocketIOManager` 경계로 분리했다.
- `SocketIOManager.sendLookbookShare(...)`는 `chat:lookbookShare` payload에 `messageType`, 선택적 사용자 입력 `msg`, `sharedContent`, sender snapshot, `messageID`, `sentAt`을 담는다.
- Phase 3 서버는 `msg`가 비어 있으면 공유 타입 기반 fallback preview를 계산해 저장 문서 `msg`, `Rooms.lastMessage`, push preview에 사용한다.
- ACK success는 `ok/success/status/duplicate`를 지원하고, 실패는 `invalid_room_id`, `room_not_found`, `not_joined`, `room_closed`, `rate_limited`, `NO ACK`를 domain error로 매핑한다.
- Phase 3 서버는 iOS mapper와 맞춰 `{ ok: true, success: true, seq, messageID }` 또는 `{ ok: false, error: "..." }` 형태를 반환하는 것이 좋다.

## Phase 2.5 구현 기록

- 목적은 기능 변경이 아니라 Phase 3 전 모델 파일 경계를 정리하는 것이다.
- `ChatMessage.swift`는 `ChatMessage` 본체, socket/firestore dict 변환, Codable, attachment parsing, date parsing 중심으로 유지했다.
- 독립 타입은 다음 파일로 분리했다.
  - `ReplyPreview.swift`
  - `VideoMetaPayload.swift`
  - `ChatMessageType.swift`
  - `LookbookSharedContent.swift`
  - `Attachment.swift`
- 타입 이름, 프로퍼티, initializer, encode/decode, dict 변환 동작은 바꾸지 않았다.

## 재확인 필요

- 기존 룩북 상세 ViewModel이 snapshot 초기 상태를 받을 수 있는지.
- 공유 카드 답장 허용 여부의 최종 UX.
- 운영 소켓 서버 배포 명령과 호스팅 위치는 App Store 배포 또는 실제 운영 전환 시 다시 결정한다.
