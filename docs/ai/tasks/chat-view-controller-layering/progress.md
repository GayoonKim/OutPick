# ChatViewController Layering Progress

## 현재 상태

- 상태: Phase 21 완료, 갤러리/뷰어 Photos 저장 통합, 검색 task/generation guard ViewModel 이동, 남은 runtime singleton/manager 직접 접근 audit 및 종료 기준 확정 완료.
- 원본 상세 기록은 `archive/progress-through-phase-9.md`에 보존했다.
- 현재 task 목표는 `ChatViewController`에 몰려 있던 메시지 전송, 실시간 수신, 메시지 액션, 메시지 window/diffable, 미디어 업로드, 읽음 seq/lifecycle, 라우팅, 방 exit 실행 책임을 MVVM-C + Repository + UseCase + DI 흐름에 맞춰 분리하는 것이다.
- Phase 19부터는 `AGENTS.md`의 phase 기반 운영 원칙과 `docs/ai/ADR.md`의 ADR-015에 따라 조사/설계 쟁점 발굴은 병렬화하고, 구현은 파일 충돌 가능성과 의존성 기준으로 순차 또는 별도 스레드 병렬 진행을 결정한다.

## Phase 인덱스

| Phase | 상태 | 핵심 결과 | 상세 기록 |
| --- | --- | --- | --- |
| 0 | 완료 | task 문서 생성, phase 계획 수립 | `archive/progress-through-phase-9.md` |
| 1 | 완료 | 텍스트 메시지 생성/전송을 `ChatRoomMessageUseCase`와 socket sending repository 경계로 이동 | `archive/progress-through-phase-9.md` |
| 2 | 완료 | 실시간 socket session/task/close 경계를 `ChatRoomRealtimeUseCase`, repository, subscription으로 이동 | `archive/progress-through-phase-9.md` |
| 3 | 완료 | 메시지 action 값 분리, delete/announce 서버 액션을 ViewModel/UseCase 경계로 이동 | `archive/progress-through-phase-9.md` |
| 4 | 완료 | `ChatMessageListItem`, `ChatMessageWindowStore`로 window/list item/reconfigure 계산 분리 | `archive/progress-through-phase-9.md` |
| 5 | 완료 | pending media state/store, media upload use case, socket media repository 분리 | `archive/progress-through-phase-9.md` |
| 6 | 완료 | `ChatReadStateStore`로 read seq 상태 계산 분리 | `archive/progress-through-phase-9.md` |
| 6 보강 | 완료 | `ChatRoomReadStateStore`로 room별 read/latest snapshot 공유, NotificationCenter 제거 | `archive/progress-through-phase-9.md` |
| 7 | 완료 | `ChatRoomRouting`/`ChatCoordinator`로 채팅 내부 라우팅 정리, 설정 패널 이벤트 `ChatRoomSettingEvent + onEvent` 통합 | `archive/progress-through-phase-9.md` |
| 8 | 완료 | `ChatRoomExitUseCase`/repository/local cleaner로 방 나가기/닫기 실행 경계 분리 | `archive/progress-through-phase-9.md` |
| 9 | 완료 | 채팅 화면 storyboard/coder 우회 진입로 제거, 코드 기반 DI 경로 확정 | `archive/progress-through-phase-9.md` |
| 9.5 | 완료 | 긴 하네스 문서를 인덱스 + archive 구조로 압축 | 현재 문서 |
| 10 | 완료 | `ChatDependencyContainer` 제거, `ChatViewController`의 핵심 ViewModel/UseCase 명시 주입 전환 | 현재 문서 |
| 11 | 완료 | `room:closed` socket binding/해제와 미참여 방 transient GRDB cleanup을 runtime use case 경계로 이동 | 현재 문서 |
| 12 | 완료 | 앱 공통 `CurrentUserProviding`을 Chat에 주입하고 `ChatViewController`의 `LoginManager.shared` 직접 접근 제거 | 현재 문서 |
| 13 | 완료 | 채팅방 표시/이탈 presence-banner lifecycle을 runtime use case 경계로 이동 | 현재 문서 |
| 14 | 완료 | 채팅방 본문 이미지/비디오 preview present는 `ChatRoomRouting`/`ChatCoordinator`, 비디오 URL/cache/save 파일 해석과 Photos 저장은 service 경계로 분리 | 현재 문서 |
| 15 | 완료 | `OPStorageURLCache`를 `StorageDownloadURLCache.shared`로 Infra 승격하고 media preview concrete 선택을 `ChatContainer` 조립으로 이동 | 현재 문서 |
| 16 | 완료 | `ChatMessageCell` 단발 이벤트 Combine 제거, `ChatMessageCellCommands` 기반 messageID command 계약으로 전환 | 현재 문서 |
| 16.5 | 완료 | 텍스트 메시지 Socket.IO `"NO ACK"`/timeout ACK를 실패로 판정해 기존 optimistic 메시지가 failed 상태로 reconfigure되도록 보정 | 현재 문서 |
| 16.6 | 완료 | 텍스트/media 전송 ACK 실패를 호출부까지 전파하고, media canonical ID에서 `pending` prefix를 제거하며 업로드 완료 후 finalize retry는 재업로드 없이 수행 | 현재 문서 |
| 16.6.1 | 완료 | 실패 outgoing message를 GRDB outbox와 Application Support 파일로 영속화하고, 앱 재시작 후 text/image/video retry, local-only delete, 재시도 성공 즉시 재정렬/실패 UI 제거를 지원 | 현재 문서 |
| 16.6.2 | 완료 | Phase 17 전 `ChatOutgoingOutboxUseCase`/media upload storage repository DI 정합성 보정 | 현재 문서 |
| 17 | 완료 | Chat 이미지 로딩 경계를 `ChatAttachmentImageLoading` service로 분리하고 remote Storage 이미지와 local outgoing preview cache를 한 service에서 source별로 처리 | 현재 문서 |
| 18 | 완료 | `ChatMediaManager` 제거, 비디오 asset warm-up/thumbnail 생성/URL resolve를 좁은 service 경계로 분리 | 현재 문서 |
| 19 | 완료 | 갤러리/뷰어 Photos 저장 흐름을 앱 공용 `PhotoLibrarySaving`으로 통합 | 현재 문서 |
| 20 | 완료 | 검색 task/generation guard와 검색 표시 상태를 `ChatRoomViewModel` 경계로 이동 | 현재 문서 |
| 21 | 완료 | 남은 runtime singleton/manager 직접 접근 audit 및 task 종료 기준 확정 | 현재 문서 |

## 최근 완료 상세

### Phase 8

- `ChatRoomExitUseCase`를 추가했다.
  - 서버 leave/close 요청 성공 뒤 local cleanup을 실행한다.
  - 서버 실패 시 local cleanup을 실행하지 않는다.
  - local cleanup 실패는 로그만 남기고 성공 결과를 유지한다.
- `ChatRoomExitRepositoryProtocol`과 `SocketChatRoomExitRepository`를 추가했다.
  - Socket.IO ACK의 `mode: left/closed` 값을 `ChatRoomExitResult`로 보존한다.
  - 기존 `requestLeaveOrCloseRoom(... Result<Void, Error>)` API는 호환용으로 유지한다.
- `DefaultChatRoomLocalExitCleaner`를 추가했다.
  - GRDB 정리는 참여중인 방 목록 캐시 삭제가 아니라 해당 방의 메시지/미디어/참여자 로컬 채팅 데이터 cleanup으로 정의했다.
  - `JoinedRoomsStore.remove(roomID)`는 목록 캐시 삭제가 아니라 socket/banner runtime 구독 해제 보정으로 유지했다.
- 설정 패널은 ConfirmView, 실패 alert, `.roomExited` 이벤트 전달만 담당한다.
- 참여중인 목록 swipe 나가기도 exit use case로 통합했다.
- 방장은 목록 swipe로 바로 방을 닫지 않고 설정 패널에서 닫도록 제한했다.

검증:

- `xcodebuildmcp.build_run_sim` 통과.
- `xcodebuildmcp.test_sim -only-testing:OutPickTests/ChatRoomExitUseCaseTests` 통과, 5개.

### Phase 9

- `Main.storyboard`에서 채팅 관련 scene과 tab relationship을 제거했다.
  - `ChatList`
  - `chatListVC`
  - `chatRoomVC`
  - `chatRoomCreateVC`
  - 기존 dummy 채팅 tab scene
- 화면 단위 ViewController의 storyboard 생성 fallback을 닫았다.
  - `ChatViewController.required init?(coder:)`
  - `RoomListsCollectionViewController.required init?(coder:)`
  - `JoinedRoomsViewController.required init?(coder:)`
- `ChatViewController(provider:)`의 `ChatDependencyContainer.provider` 기본값을 제거했다.
- `ChatContainer`의 storyboard fallback 관련 주석을 제거했다.
- `ChatDependencyContainer` 자체는 제거하지 않았다.
  - 아직 `ChatViewController` 내부 `requireFirebaseRepositories`, `requireJoinedRoomsStore`, `requireRoomReadStateStore` bridge가 남아 있다.
  - 전체 제거는 후속 phase 후보로 남겼다.

검증:

- `xmllint --noout OutPick/Base.lproj/Main.storyboard` 통과.
- `xcodebuildmcp.build_run_sim` 통과.

### Phase 10

- `ChatDependencyContainer` enum을 제거했다.
- `ChatContainer`는 더 이상 전역 bridge에 provider/repository/store를 세팅하지 않는다.
- `ChatCoordinator`는 더 이상 화면 생성 전에 `ChatDependencyContainer`를 갱신하지 않는다.
- `ChatViewController`의 직접 DI 조립 경로를 제거했다.
  - `injectedFirebaseRepositories` 제거.
  - `firebaseRepositories` fallback 제거.
  - `makeMediaUploadUseCase()` 제거.
  - `ensureChatRoomViewModel()` 제거.
- `ChatViewController`는 `ChatCoordinator`가 생성자에서 주입한 `ChatRoomViewModel`과 `ChatMediaUploadUseCaseProtocol`을 사용한다.
- `ChatRoomViewModel`은 화면 핵심 의존성이므로 optional/configure 경로를 두지 않고 non-optional `let`으로 보관한다.
- `ChatContainer`가 `ChatMediaUploadUseCase`를 생성/보관하고 `makeChatMediaUploadUseCase()`로 제공한다.
- `UserProfileDetailCompositionRoot` 입력을 `ChatManagerProviding`에서 `ChatAvatarImageManaging`으로 좁혔다.
  - Lookbook 댓글 프로필 상세가 `ChatDependencyContainer.provider` 대신 `AvatarImageService.shared`를 직접 전달한다.

검증:

- `xcodebuildmcp.build_run_sim` 통과.

### Phase 11

- `ChatRoomRuntimeUseCase`를 추가했다.
  - `room:closed` 관찰은 runtime repository에 위임한다.
  - 미참여 방 transient local data cleanup은 cleaner에 위임하고 실패는 로그로 흡수한다.
- `ChatRoomRuntimeRepositoryProtocol`, `SocketChatRoomRuntimeRepository`, `ChatRoomRuntimeSubscription`을 추가했다.
  - Socket.IO `room:closed` listener 등록/해제는 repository/socket observer 경계 안으로 이동했다.
  - subscription `stop()`은 중복 호출되어도 한 번만 해제한다.
- `DefaultChatRoomTransientLocalDataCleaner`를 추가했다.
  - `GRDBManager.deleteMessages(inRoom:)`, `deleteImages(inRoom:)` 호출은 cleaner 구현체 안으로 이동했다.
- `ChatRoomViewModel`은 runtime use case를 생성자 주입으로 받는다.
  - default fallback 생성 없이 `ChatContainer`가 명시 주입한다.
- `ChatViewController`는 더 이상 `SocketIOManager.shared.socket`이나 `GRDBManager.shared.deleteMessages/deleteImages`를 직접 호출하지 않는다.
  - `roomClosedSubscription`만 보관하고 lifecycle에서 `stop()`한다.
  - 방 닫힘 이벤트 수신 뒤 route 요청은 기존처럼 `router?.handleRoomExit(from:roomID:)`로 유지한다.

검증:

- `xcodebuildmcp.build_run_sim` 통과.
- `xcodebuildmcp.test_sim -only-testing:OutPickTests/ChatRoomRuntimeUseCaseTests` 통과, 4개.

### Phase 12

- `OutPick/App/Session/CurrentUserProvider.swift`를 추가했다.
  - `CurrentUserProviding`은 email, documentID, authIdentityKey, nickname, avatarPath, profile을 제공한다.
  - `LoginManagerCurrentUserProvider`가 내부에서 `LoginManager.shared`를 감싼다.
- `ChatContainer`가 `LoginManagerCurrentUserProvider`를 생성하고 `ChatRoomViewModel`에 명시 주입한다.
- `ChatRoomViewModel`은 현재 사용자 판단과 값을 제공한다.
  - 참여자 여부, 방장 여부, 현재 사용자 비교.
  - 메시지 action policy 계산.
  - read seq 저장용 current user documentID.
  - 공지 author nickname.
- `ChatViewController`의 `LoginManager.shared` 직접 접근을 제거했다.
- Lookbook의 기존 `CurrentUserIDProviding`은 유지했다.
  - 앱 공통 `CurrentUserProviding`으로 흡수하는 작업은 후속 후보로 남겼다.

검증:

- `xcodebuildmcp.build_run_sim` 통과.
- `xcodebuildmcp.test_sim -only-testing:OutPickTests/ChatRoomViewModelMessageActionTests` 통과, 6개.

### Phase 13

- `ChatRoomRuntimeUseCase`에 visible room lifecycle을 추가했다.
  - `enterVisibleRoom(roomID:)`
  - `leaveVisibleRoom()`
- `DefaultChatRoomVisibilityRuntimeManager`를 추가했다.
  - `BannerManager.setVisibleRoom(roomID)`와 `PresenceManager.enterRoom(roomID)`를 runtime 경계 안으로 이동했다.
  - `BannerManager.setVisibleRoom(nil)`와 `PresenceManager.leaveCurrentRoom()`도 runtime 경계 안으로 이동했다.
- `ChatRoomViewModel`은 `handleRoomWillAppear()`/`handleRoomWillDisappear()`로 lifecycle intent를 노출한다.
- `ChatViewController`는 `viewWillAppear`/`viewWillDisappear`에서 ViewModel 메서드만 호출한다.
- `ChatViewController`의 `PresenceManager.shared`와 `BannerManager.shared.setVisibleRoom` 직접 접근을 제거했다.

검증:

- `xcodebuildmcp.build_run_sim` 통과.
- `xcodebuildmcp.test_sim -only-testing:OutPickTests/ChatRoomRuntimeUseCaseTests` 통과, 5개.

### Phase 14

- 채팅방 본문 이미지/비디오 preview present 책임을 `ChatRoomRouting`/`ChatCoordinator`로 이동했다.
  - `ChatViewController`는 이미지 viewer page data와 비디오 path만 라우터로 전달한다.
  - `ChatCoordinator`가 `SimpleImageViewerVC`와 `ChatVideoPlayerViewController`를 생성/present한다.
- `ChatMediaPreviewServices`를 추가했다.
  - `DefaultChatVideoPlaybackResolver`가 로컬 파일, HTTP URL, Storage path, `OPVideoDiskCache`, downloadURL resolve, 저장용 로컬 파일 확보를 담당한다.
  - `DefaultChatPhotoLibrarySaver`가 add-only Photos 권한 요청과 이미지/비디오 저장을 담당한다.
- `ChatVideoPlayerViewController`를 추가했다.
  - `AVPlayerViewController` embed, 저장 버튼, 저장 HUD/alert feedback만 담당한다.
  - 저장 실행은 `ChatVideoPlaybackResolving`과 `ChatPhotoLibrarySaving`에 위임한다.
- `ChatMediaManaging`에서 UIKit present/저장 파일 해석 메서드를 제거했다.
  - `ChatMediaManager`는 이미지/비디오 캐시, URL resolve, 썸네일 생성 중심으로 좁혔다.
- `Info.plist`의 Photos purpose string을 보강했다.
  - `NSPhotoLibraryUsageDescription`의 `"Yes"` 문구를 실제 사용 목적 문구로 교체했다.
  - `NSPhotoLibraryAddUsageDescription`을 추가했다.

검증:

- `plutil -lint OutPick/Info.plist` 통과.
- `xcodebuild -scheme OutPick -destination 'generic/platform=iOS Simulator' build` 통과.
- `xcodebuild -scheme OutPick -destination 'id=5A3BB941-9538-4DD9-93C2-F18ACCFB03B9' test -only-testing:OutPickTests/ChatMediaPreviewServicesTests` 통과, 6개.

남은 위험:

- `MediaGalleryViewController`, `SimpleImageViewerVC`, `LocalImageViewerVC` 내부에는 아직 Photos 저장 로직 중복이 남아 있다.
- 이번 phase는 채팅방 본문 preview/save 경계 분리를 우선했고, 갤러리/뷰어 저장 흐름 통합은 후속 후보로 남긴다.

### Phase 15

- Chat 내부에 있던 `OPStorageURLCache`를 앱 공용 Infra cache인 `StorageDownloadURLCache.shared`로 승격했다.
  - 위치: `OutPick/Infra/Storage/StorageDownloadURLCache.swift`
  - 역할: 앱 실행 중 Firebase Storage path → downloadURL 변환 결과를 메모리에 캐시한다.
  - `private init`으로 단일 shared instance 정책을 명확히 했다.
- `StorageDownloadURLResolving` protocol을 추가해 호출부가 concrete actor가 아니라 URL resolve 계약에 의존할 수 있게 했다.
- 기존 `OPStorageURLCache.swift` 파일은 `OPVideoDiskCache.swift`로 이름을 맞췄다.
  - `OPVideoDiskCache.shared`와 비디오 디스크 캐시 정책은 유지했다.
- `DefaultChatVideoPlaybackResolver`의 기본 concrete 인자를 제거했다.
  - 더 이상 resolver 내부에서 Storage URL cache, `OPVideoDiskCache.shared`, `URLSessionChatRemoteFileDownloader()`를 직접 선택하지 않는다.
- `ChatContainer`가 media preview dependency graph를 명시적으로 조립한다.
  - `StorageDownloadURLCache.shared`
  - `OPVideoDiskCache.shared`
  - `URLSessionChatRemoteFileDownloader()`
- `ChatMediaManager`는 기존 compatibility를 위해 `StorageDownloadURLCache.shared`를 기본값으로 사용한다.
  - 이미지/비디오 service 경계 재정의는 Phase 17~18에서 정리한다.

검증:

- `xcodebuild -scheme OutPick -destination 'id=5A3BB941-9538-4DD9-93C2-F18ACCFB03B9' test -only-testing:OutPickTests/ChatMediaPreviewServicesTests` 통과.
- `xcodebuild -scheme OutPick -destination 'generic/platform=iOS Simulator' build` 통과.

### Phase 16

- `ChatMessageCell`의 단발 이벤트 전달을 Combine publisher에서 `ChatMessageCellCommands`로 전환했다.
  - media tap은 `messageID + attachmentIndex` command로 전달한다.
  - profile tap은 `messageID` command로 전달한다.
  - retry tap은 `messageID` command로 전달한다.
  - lookbook share tap은 `LookbookSharedContent` command로 전달한다.
- `ChatMessageCell`에서 `PassthroughSubject`와 publisher 4개를 제거했다.
  - `imageTapPublisher`
  - `profileTapPublisher`
  - `retryTapPublisher`
  - `lookbookShareTapPublisher`
- `ChatMessageCell`의 `import Combine`을 제거했다.
- `prepareForReuse`에서 `commands = ChatMessageCellCommands()`로 이전 message closure capture를 초기화한다.
- `ChatViewController`의 `cellSubscriptions` dictionary와 셀별 subscription 생성 로직을 제거했다.
- `ChatViewController`는 cell configure 시점에 command 구현을 주입한다.
- media/profile/retry 처리는 `messageID`로 최신 message를 `messageWindowStore` 또는 현재 snapshot에서 다시 조회한다.
- 이미지 viewer는 기존 `indexPath` capture 대신 현재 visible cell의 `representedMessageID`로 preview image를 조회한다.

검증:

- `xcodebuild -scheme OutPick -destination 'generic/platform=iOS Simulator' build` 통과.
- 사용자 수동 QA 완료.
  - 이미지 탭 → 이미지 viewer 확인.
  - 비디오 탭 → video player 확인.
  - 프로필 탭 → 프로필 상세 확인.
  - retry 탭 → pending upload retry 확인.
  - 룩북 공유 카드 탭 → 룩북 공유 흐름 확인.

### Phase 16.5

- 메시지 전송 실패 시 로컬 기기에서 성공 메시지처럼 보이는 문제를 긴급 수정했다.
- 원인은 Socket.IO `emitWithAck(...).timingOut` timeout 응답인 `"NO ACK"`를 텍스트 메시지 ACK 판별에서 성공으로 처리하던 로직이었다.
- `ChatMessageEmitAckMapper`를 추가해 ACK 성공/실패 판정을 테스트 가능한 작은 경계로 분리했다.
- `SocketIOManager.isEmitAckSuccess(_:)`는 기존 join/create/media 호출부 호환을 위해 유지하되, 내부 판정을 `ChatMessageEmitAckMapper`로 위임한다.
- `"NO ACK"`, `"no_ack"`, `"timeout"`은 실패로 판정한다.
- 빈 ACK는 기존 서버 호환성을 위해 성공으로 유지한다.
- 실패 판정 시 기존 `SocketIOManager.sendMessage`의 `isFailed = true` publish 경로가 동작하고, `ChatMessageWindowStore.apply`의 동일 messageID replacement/reconfigure 경로로 실패 아이콘이 표시된다.

검증:

- `xcodebuild -scheme OutPick -destination 'id=5A3BB941-9538-4DD9-93C2-F18ACCFB03B9' test -only-testing:OutPickTests/ChatMessageEmitAckMapperTests` 통과.
- `xcodebuild -scheme OutPick -destination 'generic/platform=iOS Simulator' build` 통과.
- `git diff --check` 통과.

### Phase 16.6

- 텍스트 메시지 전송 경로를 `ChatMessageSendingRepositoryProtocol` -> `ChatRoomMessageUseCaseProtocol` -> `ChatRoomViewModel`까지 `async throws`로 연결했다.
- `SocketIOManager.sendMessage(_:_:ackTimeout:)`가 Socket.IO ACK 실패/timeout을 throw하고, `ChatViewController`는 기존 optimistic 메시지를 `isFailed = true`로 reconfigure한다.
- 이미지/비디오 선택 시 `pending-`/`pending-video-` prefix가 붙은 messageID를 생성하지 않도록 변경했다.
  - pending 여부는 local UI/store 상태로만 보관한다.
  - canonical messageID, Storage path, Firestore messageID에는 pending 의미를 넣지 않는다.
- `ChatMediaUploadUseCaseProtocol`/repository에 socket 연결 상태와 ACK 기반 media finalize API를 추가했다.
- 이미지/비디오 Storage 업로드 시작 전에 socket 연결 상태를 확인한다.
  - 연결되어 있지 않으면 Storage 업로드를 시작하지 않고 local failed 메시지로 전환한다.
- Storage 업로드 성공 후 socket finalize 실패 시 업로드된 attachments/video payload를 `ChatPendingMediaUploadStore`에 보존한다.
  - retry는 이미 업로드된 path/meta만 다시 socket finalize로 전송한다.
  - 재업로드는 하지 않는다.

검증:

- `xcodebuild -scheme OutPick -destination 'generic/platform=iOS Simulator' build` 통과.
- `xcodebuild -scheme OutPick -destination 'id=5A3BB941-9538-4DD9-93C2-F18ACCFB03B9' test -only-testing:OutPickTests/ChatPendingMediaUploadStoreTests -only-testing:OutPickTests/ChatMediaUploadUseCaseTests -only-testing:OutPickTests/ChatRoomMessageUseCaseTests` 통과.

### Phase 16.6.1

- 실패 outgoing message를 앱 재시작 후에도 복원할 수 있도록 로컬 outbox를 추가했다.
  - GRDB `chatOutgoingOutbox` table이 messageID, roomID, kind, stage, local payload, uploaded payload, lastError를 저장한다.
  - 이미지/비디오 원본/썸네일/압축 파일은 `Application Support/ChatOutgoingOutbox` 하위에 복사해 retry 가능한 local asset으로 보존한다.
  - outbox 파일 경로는 앱 컨테이너 절대경로가 아니라 `ChatOutgoingOutbox` 기준 relative path로 저장하고, 사용할 때마다 현재 실행 중인 `Application Support` 경로에서 다시 해석한다.
  - 기존 absolute path row는 `ChatOutgoingOutbox/` 이후 경로를 잘라 현재 컨테이너 기준으로 복구한다.
- 텍스트/이미지/비디오 실패 메시지를 local DB에 `isFailed = true` 상태로 저장한다.
  - 방 재진입 또는 앱 재시작 후 `ChatMessageManager`가 서버/로컬 window 뒤에 failed outgoing 메시지를 append한다.
  - 실패 메시지는 서버 메시지와 섞이지 않고 로컬 목록 마지막에 `sentAt`, messageID 기준으로 정렬된다.
- retry는 outbox stage와 payload를 보고 필요한 단계만 수행한다.
  - 업로드 전 실패: 보존된 local asset으로 Storage 업로드부터 다시 수행한다.
  - 업로드 후 finalize 실패: 보존된 uploaded attachment/video payload로 socket finalize만 다시 수행한다.
  - 텍스트 실패: 기존 client messageID로 socket send만 다시 수행한다.
- sender가 성공 broadcast를 다시 받는 서버 구조를 기준으로, 성공 확정은 broadcast 수신 replacement 경로를 사용한다.
  - confirmed message 수신 후 outbox record와 local outbox 파일을 정리한다.
  - 같은 messageID의 failed local message가 confirmed server message로 교체될 때 `isFailed` 또는 `seq` 변경을 재배치 신호로 보고 `ChatMessageWindowStore`가 snapshot을 재정렬한다.
  - 성공 메시지는 server `seq` 기준 영역으로 올라가고, 남은 failed local message는 목록 tail에 유지된다.
  - `ChatMessage` diffable identity가 ID 기반이라 같은 item 이동만으로는 cell configure가 다시 불리지 않을 수 있으므로, reorder snapshot에도 reconfigure target을 유지해 실패 느낌표/시간/overlay UI를 즉시 갱신한다.
- 실패 메시지 local-only 삭제를 추가했다.
  - UI에서는 로컬 목록에서만 제거한다.
  - outbox record/local file을 삭제한다.
  - 이미 Storage 업로드가 끝난 이미지/비디오는 local delete 시 Storage object도 삭제해 orphan을 줄인다.
- 텍스트 실패 아이콘도 tap retry command를 실행하도록 `ChatMessageCell` 실패 아이콘 tap gesture를 연결했다.

검증:

- `git diff --check` 통과.
- `xcodebuild -scheme OutPick -destination 'generic/platform=iOS Simulator' build` 통과.
- `xcodebuild -scheme OutPick -destination 'id=5A3BB941-9538-4DD9-93C2-F18ACCFB03B9' test -only-testing:OutPickTests/ChatPendingMediaUploadStoreTests -only-testing:OutPickTests/ChatMediaUploadUseCaseTests -only-testing:OutPickTests/ChatMessageWindowStoreTests` 통과.
- 마지막 QA 보정 후 `xcodebuild -scheme OutPick -destination 'generic/platform=iOS Simulator' build` 재통과.
- 마지막 QA 보정 후 `xcodebuild -scheme OutPick -destination 'id=5A3BB941-9538-4DD9-93C2-F18ACCFB03B9' test -only-testing:OutPickTests/ChatMessageWindowStoreTests` 재통과.

테스트 한계:

- `ChatOutgoingOutboxUseCase`는 현재 `GRDBManager.shared` 파일 DB에 묶여 있어 in-memory GRDB seam이 없다.
- 추후 GRDB test seam을 추가하면 앱 재시작 후 outbox retry payload 복원과 local-only delete의 Storage delete 호출을 fake repository 기반으로 보강한다.

## 현재 남은 주요 위험

- 현재 media 전송은 Storage 업로드 전 socket connected만 확인하므로, 방 존재/참여/종료/rate limit까지 검증하는 서버 preflight + finalize API는 후속 안정화로 남아 있다.
- Storage 업로드 성공 후 finalize가 장기간 실패한 고아 object의 서버 TTL cleanup은 후속 안정화로 남아 있다.
- local-only delete 시 업로드 완료 media object는 삭제하지만, 앱이 삭제 작업 중 종료되는 극단 케이스는 서버 TTL cleanup이 최종 보정해야 한다.
- `ChatViewController`에는 아직 일부 runtime singleton 직접 접근과 UI orchestration 책임이 남아 있다.
- `ChatMediaManager`는 `ImageCachePipeline`을 내부에서 사용하지만 이미지 로딩, 비디오 URL warm-up, 비디오 썸네일 생성 책임이 한 객체에 섞여 있다.
- `ChatMediaManager`는 Phase 17~18 전까지 `StorageDownloadURLCache.shared`를 기본 URL resolver로 사용한다.
- `ChatViewController`에는 아직 검색 UI orchestration 등이 남아 있다.
- 갤러리/뷰어 계층에는 아직 Photos 저장 로직 중복이 남아 있다.
- 기존 warning은 일부 남아 있다.
  - `LoadChatRoomParticipantsUseCase` main actor isolation warning.
  - `ChatViewController.swift`의 `contentEdgeInsets` deprecation warning.
  - functions node_modules search path warning.

## 다음 후보

1. 후속 안정화 후보: media message preflight + finalize API 설계.
   - Storage 업로드 전 서버가 방 존재, 참여 여부, 방 종료, rate limit, messageID 예약/업로드 prefix를 확인한다.
   - 업로드 완료 후 finalize ACK로 Firestore 저장과 broadcast를 확정한다.
2. 후속 안정화 후보: 고아 Storage 파일 TTL cleanup.
   - Firestore 메시지에 참조되지 않는 media object 또는 장시간 finalize되지 않은 object를 Cloud Functions/Scheduler로 정리한다.
3. Phase 19: 갤러리/뷰어 Photos 저장 흐름 통합.
4. Phase 20: 검색 UI orchestration 분리.
5. Phase 21: `ChatViewController` 남은 runtime singleton/manager 직접 접근 최종 audit.
6. 별도 task 후보: Lookbook의 `CurrentUserIDProviding`을 앱 공통 `CurrentUserProviding`으로 흡수.

### Phase 17

목표:

- `ChatMediaManager`에 섞여 있던 이미지 로딩/cache/prefetch 책임을 `ImageCachePipeline` 기반 service로 분리한다.
- remote Storage 첨부 이미지와 local outgoing preview cache는 같은 채팅 첨부 이미지 service 안에서 source별 메서드로 구분한다.

완료 범위:

- `ChatAttachmentImageLoading` protocol과 `ChatAttachmentImageService`를 추가했다.
- remote Storage 첨부 이미지는 기존 `ChatImageCache` disk folder/size 정책을 유지했다.
  - folder: `ChatImageCache`
  - max size: 350MB
  - trim target: 280MB
  - fetch location: `.roomImage`
- local outgoing preview cache는 기존 `ThumbCache` folder와 `chatThumb|{key}` key prefix를 `ChatAttachmentImageService` 내부 메서드로 흡수했다.
- local outgoing preview cache도 memory/disk/inflight store를 service가 직접 조합하지 않고 `ImageCachePipeline`으로 감쌌다.
- remote Storage 이미지 pipeline과 local outgoing preview pipeline은 `ChatAttachmentImagePipelines`로 묶어 source별 정책을 명확히 분리했다.
- `ChatContainer`와 `ChatManagerProvider`가 `FirebaseRepositoryProviding`을 기준으로 `ChatAttachmentImageService`, room/avatar image service, message manager를 조립하도록 보정했다.
- 채팅 실행 경로의 `FirebaseImageStorageRepository.shared` 직접 접근을 repository provider 경계로 올렸다.
- `ChatMediaManager`는 이미지 로딩/cache/prefetch를 `ChatAttachmentImageLoading`에 위임하고, 비디오 URL warm-up/thumbnail 생성 책임만 유지한다.
- `ChatMediaUploadUseCase`는 실패 이미지/비디오 썸네일 preview 저장을 `ChatAttachmentImageLoading.storeOutgoingPreview(data:forKey:)`에 위임한다.
- 기존 `ChatImageCache.swift`, `ChatImageCacheProtocol.swift`는 제거했다.

검증:

- `git diff --check` 통과.
- `xcodebuild -scheme OutPick -destination 'generic/platform=iOS Simulator' build` 통과.
- `xcodebuild -scheme OutPick -destination 'id=5A3BB941-9538-4DD9-93C2-F18ACCFB03B9' test -only-testing:OutPickTests/ChatAttachmentImageServiceTests -only-testing:OutPickTests/ChatMediaUploadUseCaseTests` 통과.

후속:

- 비디오 URL warm-up과 썸네일 생성은 Phase 18에서 `ChatMediaManager` 밖 service 경계로 분리한다.

### Phase 18

목표:

- `ChatMediaManager`에 남아 있던 비디오 asset warm-up, URL resolve, thumbnail 생성 책임을 좁은 service 경계로 분리한다.
- 비디오 prefetch는 원본 파일 다운로드 없이 thumbnail cache와 Storage downloadURL warm-up까지만 수행한다.

완료 범위:

- `ChatMediaManager.swift`와 `ChatMediaManaging.swift`를 제거했다.
- `ChatVideoAssetLoading` protocol과 `ChatVideoAssetService`를 추가했다.
  - 비디오 thumbnail path는 `ChatAttachmentImageLoading`으로 cache/load한다.
  - 원본 비디오 Storage path는 `ChatStorageURLResolving`으로 downloadURL만 warm-up한다.
  - local file path, `file://`, `http/https` 원본 path는 Storage URL resolver를 호출하지 않는다.
  - messageID 단위 중복 warm-up은 `ChatVideoAssetPreparedRegistry` actor가 담당한다.
- `ChatVideoThumbnailGenerating` protocol과 `DefaultChatVideoThumbnailGenerator`를 추가했다.
  - `AVAssetImageGenerator` 기반 thumbnail data 생성은 async service 뒤로 이동했다.
- `ChatViewController`는 `ChatMediaManaging` 대신 아래 의존성을 좁게 받는다.
  - `ChatAttachmentImageLoading`
  - `ChatVideoAssetLoading`
  - `ChatStorageURLResolving`
  - `ChatVideoThumbnailGenerating`
- `ChatRoomSettingViewModel`은 media thumbnail materialize에 `ChatAttachmentImageLoading`만 사용한다.
- `ChatRoomSettingViewController`는 gallery image provider에 `ChatAttachmentImageLoading`, video downloadURL resolver에 `ChatStorageURLResolving`을 사용한다.
- `ChatManagerProviding`에서 `mediaManager`를 제거했다.
- `ChatContainer`가 attachment image loader, video asset loader, video thumbnail generator, storage URL resolver를 명시 조립한다.

검증:

- `git diff --check` 통과.
- `xcodebuild -scheme OutPick -destination 'generic/platform=iOS Simulator' build` 통과.
- `xcodebuild -scheme OutPick -destination 'id=5A3BB941-9538-4DD9-93C2-F18ACCFB03B9' test -only-testing:OutPickTests/ChatVideoAssetServiceTests -only-testing:OutPickTests/ChatAttachmentImageServiceTests -only-testing:OutPickTests/ChatMediaUploadUseCaseTests` 통과.

후속:

- Phase 19에서 gallery/viewer Photos 저장 흐름을 `ChatPhotoLibrarySaving` 또는 앱 공용 saver로 통합한다.

### Phase 16.6.2

목표:

- Phase 17 진입 전에 media upload/outbox storage repository 선택 위치를 `ChatContainer`/repository provider 경계로 정리한다.

주요 검토 범위:

- `FirebaseRepositoryProviding`에 `videoStorageRepository` 추가.
- `FirebaseRepositoryProvider`가 `FirebaseVideoStorageRepository.shared`를 제공.
- `ChatOutgoingOutboxUseCase`의 `imageStorageRepository`, `videoStorageRepository` 기본 singleton 인자 제거.
- `ChatMediaUploadUseCase`와 `ChatOutgoingOutboxUseCase` 생성부를 `repositories.videoStorageRepository`로 통일.

구현 전 논의 필요:

- 현재 기준 추가 논의 필요 사항 없음.
- `GRDBManager.shared`는 이번 작은 DI 보정 범위에서는 유지하고, local persistence protocol 분리는 후속 후보로 둔다.

완료 범위:

- `FirebaseRepositoryProviding`에 `videoStorageRepository` 제공 경로를 추가했다.
- `FirebaseRepositoryProvider.shared`가 `FirebaseVideoStorageRepository.shared`를 제공한다.
- `ChatMediaUploadUseCase`와 `ChatOutgoingOutboxUseCase` 생성부가 모두 `repositories.imageStorageRepository`, `repositories.videoStorageRepository`를 사용한다.
- `ChatOutgoingOutboxUseCase` initializer에서 image/video storage repository singleton 기본값을 제거했다.

검증:

- `git diff --check` 통과.
- `xcodebuild -scheme OutPick -destination 'generic/platform=iOS Simulator' build` 통과.

### Phase 15 설계 예정

목표:

- `DefaultChatVideoPlaybackResolver`가 production concrete를 직접 선택하지 않도록 하고, media preview dependency graph를 `ChatContainer`에서 명시적으로 조립한다.

주요 검토 범위:

- `DefaultChatVideoPlaybackResolver` initializer의 기본 concrete 인자 제거.
- Chat 내부 `OPStorageURLCache`를 앱 공용 `StorageDownloadURLCache.shared`로 Infra 승격.
- `StorageDownloadURLCache.shared`, `OPVideoDiskCache.shared`, `URLSessionChatRemoteFileDownloader` 선택 위치를 `ChatContainer`로 이동.
- 기존 `ChatMediaPreviewServicesTests`의 fake 주입 구조 유지.

구현 전 논의 필요:

- `StorageDownloadURLCache.shared`는 앱 실행 중 Firebase Storage path → downloadURL 변환 결과를 공유하는 공용 Infra cache로 둔다.
- `OPVideoDiskCache.shared`는 기존 캐시 생명주기 때문에 유지하되 접근 위치만 Container로 올리는 방안을 우선 적용한다.
- 개발 편의용 기본 initializer는 제거하고, production 경로는 Container 명시 주입으로 통일한다.

### Phase 16 완료 요약

목표:

- `ChatMessageCell`의 이미지/프로필/retry/lookbook 단발 탭 이벤트를 Combine publisher에서 `ChatMessageCellCommands` 기반 command 모델로 전환한다.

완료 범위:

- `ChatMessageCellCommands` 도입.
- `imageTapPublisher`, `profileTapPublisher`, `retryTapPublisher`, `lookbookShareTapPublisher` 제거.
- `ChatViewController`의 `cellSubscriptions[ObjectIdentifier(cell)]` 패턴 제거.
- 셀 reuse 시 command 초기화로 오래된 message closure capture 방지.
- media/profile/retry command payload는 `messageID`를 사용하고, VC가 최신 message를 다시 조회.

후속 재검토 조건:

- 셀 이벤트가 analytics/logging 또는 cross-feature command로 크게 늘어나면 `ChatMessageCellCommandHandling` protocol 분리 여부를 검토한다.
- Reducer/Store dispatch는 현재 MVVM-C + ViewModel + Coordinator 경계와 겹치므로 이번 task에서는 도입하지 않는다.

### Phase 19

목표:

- `MediaGalleryViewController`, `SimpleImageViewerVC`, `LocalImageViewerVC`, 비디오 overlay의 Photos 저장 중복을 앱 공용 saver로 통합한다.

완료 범위:

- `OutPick/Infra/Media/PhotoLibrarySaver.swift`에 앱 공용 `PhotoLibrarySaving`과 `DefaultPhotoLibrarySaver`를 추가했다.
  - 이미지 저장과 비디오 저장을 같은 add-only Photos 권한 요청 경계로 통합했다.
  - 권한 거부와 저장 실패를 `PhotoLibrarySaveError`로 구분한다.
- Chat feature 전용 `ChatPhotoLibrarySaving`/`DefaultChatPhotoLibrarySaver`를 제거했다.
- `ChatVideoPlayerViewController`는 공용 `PhotoLibrarySaving`을 생성자 주입으로 받는다.
- `SimpleImageViewerVC`는 직접 `UIImageWriteToSavedPhotosAlbum`을 호출하지 않고, 생성자 주입된 `PhotoLibrarySaving`으로 이미지를 저장한다.
  - Chat 이미지 viewer는 `ChatCoordinator`가 `ChatContainer`의 saver를 주입한다.
  - Profile 이미지 viewer는 `UserProfileDetailViewController`가 `DefaultPhotoLibrarySaver`를 주입한다.
- `MediaGalleryViewController`는 `PhotoLibrarySaving`과 `ChatVideoPlaybackResolving`을 생성자 주입으로 받는다.
  - gallery 비디오 저장은 새 resolver를 만들지 않고 기존 `ChatVideoPlaybackResolving.localFileURLForSaving`을 재사용한다.
  - `LocalImageViewerVC`와 `VideoPlayerOverlayVC`의 직접 Photos API 호출을 제거했다.
- `ChatRoomSettingViewController`/`ChatCompositionRoot`는 `storageURLResolver` 직접 주입 대신 `videoResolver`와 `photoLibrarySaver`를 전달한다.

검증:

- `git diff --check` 통과.
- `xcodebuild -scheme OutPick -destination 'generic/platform=iOS Simulator' build` 통과.

### Phase 20

목표:

- `ChatViewController`에 남은 검색 UI orchestration을 검색 상태/검색 실행/검색 결과 점프 책임과 화면 표시 책임으로 분리한다.

완료 범위:

- `ChatRoomViewModel`이 검색 task와 generation guard를 소유한다.
  - `startSearch(containing:onResultApplied:)`가 기존 검색 task 취소, generation 증가, 검색 fetch, 최신 generation guard, 검색 결과 적용을 담당한다.
  - `cancelSearchWork()`가 view lifecycle/deinit cleanup에서 호출된다.
- `ChatRoomViewModel.SearchDisplayState`를 추가했다.
  - 내부 검색 index는 seq ASC 기준 1-based 값을 유지한다.
  - UI 표시 index는 최신 메시지 기준 표시를 위해 `totalCount - currentIndex + 1`로 분리했다.
  - up/down 버튼 가능 여부도 ViewModel state로 제공한다.
- `ChatSearchUIView`는 count/current index 원시값 대신 `SearchDisplayState`를 받아 표시한다.
- `ChatViewController`는 검색 keyword publisher, collection view scroll, `IndexPath` 계산, shake animation 같은 UIKit 책임만 유지한다.
- `filterMessages(containing:generation:)`, `searchMessagesTask`, `searchGeneration`은 `ChatViewController`에서 제거했다.

검증:

- `git diff --check` 통과.
- `xcodebuild -scheme OutPick -destination 'generic/platform=iOS Simulator' build` 통과.

### Phase 21

목표:

- Phase 15~20 이후 `ChatViewController`에 남은 runtime singleton/manager 직접 접근을 최종 점검하고, 분리할 대상과 UIKit 화면 책임으로 남길 대상을 확정한다.

완료 범위:

- Phase 21은 코드 대수술이 아니라 audit + 종료 기준 확정 phase로 처리했다.
- 이번 task 종료 기준에서 아래 항목은 UIKit 화면 feedback 또는 lifecycle glue로 허용한다.
  - `LoadingIndicator.shared`
  - `AlertManager`
  - `ConfirmView`
  - keyboard/app lifecycle `NotificationCenter` observer
- 아래 항목은 task 종료를 막지 않는 후속 후보로 분리했다.
  - `DefaultMediaProcessingService.shared` 직접 접근 제거.
  - `provider.avatarImageManager` 접근 폭 축소.
  - media message preflight + finalize API 설계.
  - 고아 Storage 파일 TTL cleanup.
  - outbox GRDB persistence test seam.
  - Lookbook `CurrentUserIDProviding`을 앱 공통 `CurrentUserProviding`으로 흡수.
- `ChatViewController`는 현재 기준 UIKit 화면 조립, 사용자 이벤트 전달, collection view scroll/rendering 반영, 단순 화면 feedback 책임을 유지한다.

검증:

- 코드 변경 없는 audit/documentation phase로 처리했다.
- Phase 19~20 구현 후 `xcodebuild -scheme OutPick -destination 'generic/platform=iOS Simulator' build` 통과 상태를 기준으로 종료한다.

후속 소정리 후보:

- `ChatSearchUIView`의 up/down 단발 탭 이벤트는 Combine publisher 대신 클로저 callback으로 줄인다.
- `ChatSearchUIView.updateSearchResult`는 view rendering 책임으로 유지하되, `ChatRoomViewModel.SearchDisplayState` 직접 의존을 view 전용 state 또는 원시 표시 값으로 낮춘다.
- `LocalImageViewerVC`의 fallback 의미를 원격 path 없는 메모리 `UIImage` 전용 viewer로 명확히 한다.
- `LocalImageViewerVC`와 `VideoPlayerOverlayVC`는 `MediaGalleryViewController.swift`에서 별도 파일로 분리한다.

### Phase 21 후속 안정화 완료

목표:

- Phase 21에서 후속 후보로 분리한 media 안정화, outbox seam, UI 소정리, current user adapter, singleton 직접 접근 축소를 확정한 범위 안에서 마무리한다.

완료 범위:

- Socket `chat:mediaPreflight`와 기존 `send images`/`chat:video` finalize handler reservation 검증을 추가했다.
- Firebase Functions scheduler 기반 reservation TTL cleanup을 추가하고 배포했다.
- `ChatOutgoingOutboxPersisting` protocol을 추가하고 `GRDBManager`가 채택하도록 outbox persistence seam을 만들었다.
- `ChatSearchUIView` up/down 단발 이벤트를 closure callback으로 축소했다.
- `ChatSearchUIView`는 ViewModel 타입 대신 view 전용 `SearchResultState`를 받는다.
- `LocalImageViewerVC`/`VideoPlayerOverlayVC`를 별도 파일로 분리하고, 원격 path 없는 메모리 이미지 fallback 의미를 주석으로 명확히 했다.
- `ChatViewController`는 avatar manager를 생성자 주입으로 받는다.
- Lookbook은 앱 공용 `CurrentUserProviding`을 `LookbookContainer`에 주입하고 내부 adapter가 `UserID?`로 변환한다.
- `DefaultMediaProcessingService.shared` 직접 접근을 제거하고 composition/default injection 지점에서 instance를 주입한다.

검증:

- Firebase Functions 배포 완료.
- `xcodebuild -scheme OutPick -destination 'generic/platform=iOS Simulator' build` 통과.
- `xcodebuild -scheme OutPick -destination 'id=5A3BB941-9538-4DD9-93C2-F18ACCFB03B9' test -only-testing:OutPickTests/LookbookCurrentUserIDProviderTests -only-testing:OutPickTests/ChatMediaUploadUseCaseTests -only-testing:OutPickTests/ChatOutgoingOutboxUseCaseTests` 통과.
- `git diff --check` 통과.

후속 재검토 조건:

- `DefaultMediaProcessingService.ImagePair`, `VideoUploadPreset`, static `makeThumbnailData` 타입 분리는 이번 범위에서 제외했다.
- 실제 GRDB in-memory integration test는 이번 seam 이후 별도 보강 후보로 남긴다.
- `ChatViewController`의 `provider` 전체 제거와 Lookbook/Profile 전체 avatar/image service DI 정리는 별도 큰 리팩토링으로 남긴다.

### 다음 리팩토링 Phase 계획

목표:

- Phase 21 후속 안정화 이후 남은 구조 개선 후보를 구현 대기 Phase A~D와 운영/성장 이후 보류 항목으로 재분류한다.

확정한 Phase:

- Phase A: Media processing concrete 타입 제거.
  - `DefaultMediaProcessingService.ImagePair`, `DefaultMediaProcessingService.VideoUploadPreset`, static `makeThumbnailData` 직접 노출을 제거한다.
  - 앱 미배포 전제이므로 compatibility shim/typealias를 오래 유지하지 않는다.
  - 이미지 타입은 `ProcessedImage` 같은 공용 Infra media 타입으로 분리한다.
  - video preset은 공용 `VideoUploadPreset`으로 분리하고 payload 문자열은 유지한다.
  - thumbnail helper는 우선 순수 utility로 분리한다.
- Phase B: 공통 `chat:mediaFinalize` 전송 이벤트 통합.
  - 전송 finalize만 통합하고 수신 이벤트는 유지한다.
  - 기존 `send images`/`chat:video` 서버 handler는 wrapper로 남긴다.
  - 앱 도메인 API는 우선 기존 이미지/비디오 외부 메서드를 유지한다.
- Phase C: `ChatViewController.provider` 제거.
  - `profileSyncManager` 직접 주입.
  - 미사용 `messageManager`, `searchManager`, `networkStatusProvider` 필드 제거.
  - `ChatContainer.provider` 자체 제거는 범위 밖.
- Phase D: Lookbook/Profile avatar/image service DI 정리.
  - 앱 미배포 전제로 `AvatarImageService.shared` 자체 제거를 목표로 한다.
  - `ChatAvatarImageManaging` 이름은 유지한다.
  - Profile 상세 current user DI 정리는 범위 밖.

운영/성장 이후 보류:

- 실제 GRDB in-memory integration test.
  - 이전 버전 호환성 목적이 아니라 실제 SQL schema와 persistence seam 계약 검증 목적이다.
  - 현재는 fake persistence test와 앱 미배포 전제를 고려해 보류한다.
- Storage 전체 sweep cleanup.
  - 사용자/트래픽/Storage 비용 증가 후 dry-run report부터 별도 운영 phase로 검토한다.
- 대량 cleanup용 Cloud Run worker 승격.
  - Functions scheduler timeout/대량 삭제 문제가 실제로 생긴 뒤 검토한다.

검증 계획:

- 이번 단계는 문서 계획 수립만 수행한다.
- 구현은 아직 시작하지 않는다.
