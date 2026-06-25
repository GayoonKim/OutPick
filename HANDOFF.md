# OutPick Handoff

## 1. 현재 목표

- 현재 작업은 `chat-view-controller-layering`이다.
- 목표는 `ChatViewController.swift`에 몰린 메시지 전송, 실시간 수신, 메시지 액션, 메시지 window/diffable, 미디어 업로드, 읽음 seq/lifecycle, 라우팅, 방 exit 실행 책임을 OutPick의 MVVM-C + Repository + UseCase + DI 흐름에 맞춰 단계적으로 분리하는 것이다.
- 현재 상태는 Phase 23/23.5/26 runtime DI 구현, Phase 23.6 JoinedRooms publisher 제거, Phase 23.7 QA runtime 안정화 검증 완료다.
  - Phase 19: 갤러리/뷰어 Photos 저장 흐름을 앱 공용 `PhotoLibrarySaving`으로 통합했다.
  - Phase 20: 검색 task/generation guard와 검색 표시 상태를 `ChatRoomViewModel` 경계로 이동했다.
  - Phase 21: 남은 runtime singleton/manager 직접 접근 audit 및 task 종료 기준을 확정했다.
  - Phase 21 후속 안정화: media preflight/finalize, reservation 기반 TTL cleanup, outbox GRDB seam, UI 소정리, avatar manager 축소, Lookbook current user adapter, `DefaultMediaProcessingService.shared` 직접 접근 제거를 완료했다.
  - Phase 22: `SocketIOManager` 제거, `RealtimeSocketService` actor와 `AppSessionRuntime` 도입, Socket/Realtime Combine bridge 제거를 완료했다.
  - Phase 23/23.5/26 설계: App session runtime ownership, joined rooms session store, realtime socket DI 축소 설계를 `phase-23-runtime-design.md`에 정리했다.
  - Phase 23/23.5/26 구현: `AppCompositionRoot`, `JoinedRoomsSessionStore`, same realtime instance 주입, Firebase repository socket side effect 제거를 완료했다.
  - Phase 23.6: `JoinedRoomsSessionStore.publisher`를 제거하고 joined-room socket/banner side effect를 `AppSessionRuntime` 명시 command API로 전환했다.
  - Phase 23.7: 수동 QA에서 확인된 로그인 routing, 마이페이지 로그아웃 후 재로그인, socket connect, 메시지 배너, 참여자 초기 표시, 방 나가기 목록 stale 문제를 runtime command/로컬 summary 보정으로 안정화했다.
- 다음 우선순위는 Phase A 또는 Phase C/D 등 남은 구조 개선 후보 중 무엇을 먼저 진행할지 사용자와 확정하는 것이다.
- Phase 19~21 진행 전 사용자가 확정한 운영 방식은 앞으로도 유지한다.
  - 다음 2~3개 phase를 함께 훑고, 설계 쟁점/예상 변경 파일/검증 계획을 통합 보고한다.
  - 코드 수정 없는 조사는 서브 에이전트로 병렬화한다.
  - 설계 쟁점은 메인 스레드에서 사용자와 확정한다.
  - 충돌 없는 phase는 별도 스레드 구현 후보로, 충돌 있는 phase는 메인 스레드 순차 구현으로 분류한다.

## 2. 압축된 문서 구조

- 현재 요약/인덱스:
  - `docs/ai/tasks/active.md`
  - `docs/ai/tasks/chat-view-controller-layering/progress.md`
  - `docs/ai/tasks/chat-view-controller-layering/decisions.md`
  - `docs/ai/tasks/chat-view-controller-layering/phase-23-runtime-design.md`
- 상세 원문 archive:
  - `docs/ai/tasks/chat-view-controller-layering/archive/progress-through-phase-9.md`
  - `docs/ai/tasks/chat-view-controller-layering/archive/decisions-through-phase-9.md`

## 3. 완료한 Phase 요약

| Phase | 상태 | 핵심 결과 |
| --- | --- | --- |
| 0 | 완료 | task 문서 생성, phase 계획 수립 |
| 1 | 완료 | 텍스트 메시지 생성/전송을 `ChatRoomMessageUseCase`와 socket sending repository 경계로 이동 |
| 2 | 완료 | 실시간 socket session/task/close 경계를 `ChatRoomRealtimeUseCase`, repository, subscription으로 이동 |
| 3 | 완료 | 메시지 action 값 분리, delete/announce 서버 액션을 ViewModel/UseCase 경계로 이동 |
| 4 | 완료 | `ChatMessageListItem`, `ChatMessageWindowStore`로 window/list item/reconfigure 계산 분리 |
| 5 | 완료 | pending media state/store, media upload use case, socket media repository 분리 |
| 6 | 완료 | `ChatReadStateStore`로 read seq 상태 계산 분리 |
| 6 보강 | 완료 | `ChatRoomReadStateStore`로 room별 read/latest snapshot 공유, NotificationCenter 제거 |
| 7 | 완료 | `ChatRoomRouting`/`ChatCoordinator`로 채팅 내부 라우팅 정리 |
| 8 | 완료 | `ChatRoomExitUseCase`/repository/local cleaner로 방 나가기/닫기 실행 경계 분리 |
| 9 | 완료 | 채팅 화면 storyboard/coder 우회 진입로 제거, 코드 기반 DI 경로 확정 |
| 9.5 | 완료 | 하네스 문서를 인덱스 + archive 구조로 압축 |
| 10 | 완료 | `ChatDependencyContainer` 제거, `ChatViewController` 핵심 ViewModel/UseCase 생성자 주입 전환 |
| 11 | 완료 | `room:closed` socket binding/해제와 미참여 방 transient GRDB cleanup을 runtime use case 경계로 이동 |
| 12 | 완료 | 앱 공통 `CurrentUserProviding`을 Chat에 주입하고 `ChatViewController`의 `LoginManager.shared` 직접 접근 제거 |
| 13 | 완료 | 채팅방 표시/이탈 presence-banner lifecycle을 runtime use case 경계로 이동 |
| 14 | 완료 | 채팅방 본문 이미지/비디오 preview present를 Coordinator 경계로 이동, 비디오 URL/cache/save 파일 해석과 Photos 저장을 service 경계로 분리 |
| 15 | 완료 | `OPStorageURLCache`를 `StorageDownloadURLCache.shared`로 Infra 승격하고 media preview concrete 선택을 `ChatContainer` 조립으로 이동 |
| 16 | 완료 | `ChatMessageCell` 단발 이벤트 Combine 제거, `ChatMessageCellCommands` 기반 messageID command 계약으로 전환 |
| 16.5 | 완료 | 텍스트 메시지 Socket.IO `"NO ACK"`/timeout ACK를 실패로 판정해 optimistic 메시지 실패 표시 경로 보정 |
| 16.6 | 완료 | 텍스트/media ACK 실패를 호출부까지 전파하고, media pending ID를 canonical ID/Storage/Firestore에서 제거하며 finalize retry는 재업로드 없이 수행 |
| 16.6.1 | 완료 | 실패 outgoing message를 GRDB outbox와 Application Support 파일로 영속화하고, 앱 재시작 후 text/image/video retry, local-only delete, 재시도 성공 즉시 재정렬/실패 UI 제거를 지원 |
| 16.6.2 | 완료 | Phase 17 전 `ChatOutgoingOutboxUseCase`/media upload storage repository DI 정합성 보정 |
| 17 | 완료 | Chat 이미지 로딩 경계를 `ChatAttachmentImageLoading` service로 분리 |
| 18 | 완료 | 비디오 asset warm-up/thumbnail 경계 분리 |
| 19 | 완료 | 갤러리/뷰어 Photos 저장 흐름을 앱 공용 `PhotoLibrarySaving`으로 통합 |
| 20 | 완료 | 검색 task/generation guard와 검색 표시 상태를 `ChatRoomViewModel` 경계로 이동 |
| 21 | 완료 | 남은 runtime singleton/manager 직접 접근 audit 및 task 종료 기준 확정 |
| 21 후속 안정화 | 완료 | media preflight/finalize, reservation TTL cleanup, outbox GRDB seam, UI 소정리, avatar manager 축소, Lookbook current user adapter, media processor shared 직접 접근 제거 |
| 22 | 완료 | `SocketIOManager` 제거, `RealtimeSocketService` actor와 `AppSessionRuntime` 도입, Socket/Realtime Combine bridge 제거 |
| 23/23.5/26 설계 | 완료 | App session runtime ownership, joined rooms session store, realtime socket DI 축소 설계 정리 |
| 23/23.5/26 구현 | 완료 | AppCompositionRoot 조립, JoinedRoomsSessionStore 승격, Chat realtime 주입, Firebase repository socket side effect 제거 |
| 23.6 | 완료 | `JoinedRoomsSessionStore.publisher` 제거, joined-room socket/banner side effect를 `AppSessionRuntime` command API로 전환 |
| 23.7 | 완료 | QA 회귀 대응: 로그인 routing race, socket connect retry, room session close membership 제거, 참여자/joined summary 즉시 보정 |

## 4. 최근 핵심 변경

- Phase 8:
  - `ChatRoomExitUseCase`를 추가했다.
  - socket leave-or-close 요청은 `ChatRoomExitRepositoryProtocol` 뒤로 이동했다.
  - local cleanup은 `DefaultChatRoomLocalExitCleaner`로 분리했다.
  - 설정 패널은 ConfirmView, 실패 alert, `.roomExited` 이벤트 전달만 담당한다.
  - 참여중인 목록 swipe 나가기도 exit use case로 통합했다.
  - 방장은 목록 swipe로 바로 방을 닫지 않고 설정 패널에서 닫도록 제한했다.
- Phase 9:
  - `Main.storyboard`에서 채팅 관련 scene과 tab relationship을 제거했다.
  - `ChatViewController`, `RoomListsCollectionViewController`, `JoinedRoomsViewController`의 `required init?(coder:)` fallback을 `fatalError`로 전환했다.
  - `ChatViewController(provider:)`의 `ChatDependencyContainer.provider` 기본값을 제거했다.
- Phase 9.5:
  - 긴 `progress.md`, `decisions.md` 원문을 archive로 보존했다.
  - top-level 문서는 현재 상태, 인덱스, 최신 결정 중심으로 압축했다.
- Phase 10:
  - `ChatDependencyContainer` enum을 제거했다.
  - `ChatContainer`/`ChatCoordinator`의 전역 bridge 세팅을 제거했다.
  - `ChatViewController`의 `injectedFirebaseRepositories`, `firebaseRepositories`, `makeMediaUploadUseCase()`, `ensureChatRoomViewModel()` fallback 경로를 제거했다.
  - `ChatRoomViewModel`은 optional/configure 경로 없이 `ChatViewController` 생성자에서 non-optional로 주입한다.
  - `ChatMediaUploadUseCase`는 `ChatContainer`가 생성하고 `ChatCoordinator`가 `ChatViewController`에 명시 주입한다.
  - `UserProfileDetailCompositionRoot`는 `ChatManagerProviding` 대신 `ChatAvatarImageManaging`만 받게 좁혔다.
- Phase 11:
  - `ChatRoomRuntimeUseCase`, `ChatRoomRuntimeRepositoryProtocol`, `SocketChatRoomRuntimeRepository`, `ChatRoomRuntimeSubscription`을 추가했다.
  - `room:closed` Socket.IO listener 등록/해제는 runtime repository/socket observer 경계로 이동했다.
  - `DefaultChatRoomTransientLocalDataCleaner`를 추가해 미참여 방 transient 메시지/이미지 cleanup의 `GRDBManager` 직접 호출을 VC 밖으로 이동했다.
  - `ChatRoomViewModel`은 runtime use case를 default fallback 없이 생성자 주입으로 받는다.
  - `ChatViewController`는 `SocketIOManager.shared.socket`과 `GRDBManager.shared.deleteMessages/deleteImages`를 직접 호출하지 않는다.
- Phase 12:
  - `OutPick/App/Session/CurrentUserProvider.swift`에 앱 공통 `CurrentUserProviding`을 추가했다.
  - `LoginManagerCurrentUserProvider`가 `LoginManager.shared`를 감싼다.
  - `ChatContainer`가 current user provider를 생성하고 `ChatRoomViewModel`에 명시 주입한다.
  - `ChatViewController`의 `LoginManager.shared` 직접 접근을 제거했다.
  - Lookbook의 기존 `CurrentUserIDProviding`은 유지하고, 앱 공통 provider 흡수는 후속 후보로 남겼다.
- Phase 13:
  - `ChatRoomRuntimeUseCase`에 `enterVisibleRoom(roomID:)`와 `leaveVisibleRoom()`을 추가했다.
  - `DefaultChatRoomVisibilityRuntimeManager`가 `BannerManager.setVisibleRoom`과 `PresenceManager.enter/leave` 호출을 담당한다.
  - `ChatRoomViewModel`은 `handleRoomWillAppear()`/`handleRoomWillDisappear()`를 제공한다.
  - `ChatViewController`의 `PresenceManager.shared`와 `BannerManager.shared.setVisibleRoom` 직접 접근을 제거했다.
- Phase 14:
  - `ChatRoomRouting`/`ChatCoordinator`가 채팅방 본문 이미지 viewer와 비디오 player present를 담당한다.
  - `DefaultChatVideoPlaybackResolver`가 로컬 파일, HTTP URL, Storage path, `OPVideoDiskCache`, 저장용 파일 확보를 담당한다.
  - `DefaultChatPhotoLibrarySaver`가 Photos add-only 권한 요청과 이미지/비디오 저장을 담당한다.
  - `ChatVideoPlayerViewController`가 AVPlayer 표시와 저장 버튼/HUD/alert feedback을 담당한다.
  - `ChatViewController`의 `PHPhotoLibrary`, `URLSession.shared`, `OPVideoDiskCache.shared`, `AVPlayerViewController` 직접 접근을 제거했다.
  - `Info.plist`의 Photos 목적 문자열을 보강하고 `NSPhotoLibraryAddUsageDescription`을 추가했다.
- Phase 15:
  - Chat 내부 `OPStorageURLCache`를 앱 공용 `StorageDownloadURLCache.shared`로 Infra 승격했다.
  - `StorageDownloadURLResolving` protocol을 추가했다.
  - 기존 `OPStorageURLCache.swift` 파일은 `OPVideoDiskCache.swift`로 이름을 맞췄다.
  - `DefaultChatVideoPlaybackResolver`의 기본 concrete 인자를 제거했다.
  - `ChatContainer`가 `StorageDownloadURLCache.shared`, `OPVideoDiskCache.shared`, `URLSessionChatRemoteFileDownloader()`를 명시 주입한다.
- Phase 16:
  - `ChatMessageCellCommands`를 추가했다.
  - `ChatMessageCell`의 `PassthroughSubject`/publisher 기반 media/profile/retry/lookbook share tap 이벤트를 제거했다.
  - `ChatMessageCell`의 `import Combine`을 제거했다.
  - `prepareForReuse`에서 commands를 no-op 기본값으로 초기화한다.
  - `ChatViewController`의 `cellSubscriptions` dictionary와 셀별 subscription 생성 로직을 제거했다.
  - `ChatViewController`는 command payload의 `messageID`로 최신 message를 다시 조회해 media/profile/retry를 처리한다.
  - 이미지 viewer는 `indexPath` capture 대신 visible cell의 `representedMessageID`로 preview image를 조회한다.
- Phase 16.5:
  - Socket.IO `emitWithAck(...).timingOut` timeout 응답인 `"NO ACK"`를 성공으로 오판하던 텍스트 메시지 ACK 판정을 보정했다.
  - `ChatMessageEmitAckMapper`를 추가해 ACK 판정을 테스트 가능한 경계로 분리했다.
  - `SocketIOManager.isEmitAckSuccess(_:)`는 기존 호출부 호환을 위해 유지하고 mapper로 위임한다.
  - `"NO ACK"`, `"no_ack"`, `"timeout"`은 실패로 판정한다.
  - 빈 ACK는 기존 서버 호환성을 위해 성공으로 유지한다.
- Phase 16.6:
  - 텍스트 메시지 전송 경로를 repository/use case/view model까지 `async throws`로 연결해 ACK 실패가 optimistic 메시지 failed 표시로 이어지게 했다.
  - 이미지/비디오 canonical messageID 생성에서 `pending-`/`pending-video-` prefix를 제거했다.
  - media Storage 업로드 전 socket connected 상태를 확인한다.
  - Storage 업로드 성공 후 socket finalize 실패 시 uploaded attachments/video payload를 pending store에 보존한다.
  - retry는 보존한 path/meta만 다시 socket finalize로 보내고 재업로드하지 않는다.
- Phase 16.6.1:
  - `ChatOutgoingOutboxRecord`와 `ChatOutgoingOutboxUseCase`를 추가했다.
  - GRDB `chatOutgoingOutbox` table이 실패 outgoing message의 kind/stage/local payload/uploaded payload를 보존한다.
  - 이미지/비디오 retry용 local asset은 `Application Support/ChatOutgoingOutbox`에 복사한다.
  - outbox 파일 경로는 앱 컨테이너 absolute path가 아니라 `ChatOutgoingOutbox` 기준 relative path로 저장하고, 사용할 때마다 현재 `Application Support`에서 해석한다.
  - `ChatMessageManager`는 방 window 로드 시 failed outgoing 메시지를 마지막에 append한다.
  - retry는 outbox stage를 기준으로 업로드부터 재시도하거나 uploaded payload finalize만 재시도한다.
  - local-only delete는 로컬 DB/outbox 파일을 제거하고, 업로드 완료 media Storage object도 삭제한다.
  - 재시도 성공 broadcast replacement 시 `isFailed`/`seq` 변경을 기준으로 `ChatMessageWindowStore`가 snapshot을 재정렬하고, 같은 ID cell reconfigure를 유지해 실패 느낌표/시간/overlay UI를 즉시 갱신한다.
- Phase 17:
  - Chat 이미지 로딩 경계를 `ChatAttachmentImageLoading` service로 분리했다.
  - remote Storage 첨부 이미지와 local outgoing preview cache를 source별 메서드로 분리했다.
  - 기존 `ChatImageCache`/`ChatImageCacheProtocol`은 `ChatAttachmentImageService`의 outgoing preview cache 메서드로 흡수했다.
- Phase 18:
  - `ChatMediaManager`/`ChatMediaManaging`을 제거했다.
  - `ChatVideoAssetLoading`/`ChatVideoAssetService`가 비디오 thumbnail cache와 원본 Storage downloadURL warm-up을 담당한다.
  - `ChatVideoThumbnailGenerating`/`DefaultChatVideoThumbnailGenerator`가 thumbnail data 생성을 담당한다.
- Phase 19:
  - `PhotoLibrarySaving`/`DefaultPhotoLibrarySaver`를 앱 공용 Infra media service로 추가했다.
  - `SimpleImageViewerVC`, `LocalImageViewerVC`, `VideoPlayerOverlayVC`, `ChatVideoPlayerViewController`의 직접 Photos 저장 흐름을 공용 saver 주입으로 정리했다.
  - gallery 비디오 저장은 `ChatVideoPlaybackResolving.localFileURLForSaving`을 재사용한다.
- Phase 20:
  - 검색 task와 generation guard를 `ChatRoomViewModel`로 이동했다.
  - `SearchDisplayState`를 추가해 내부 index와 UI 표시 index를 분리했다.
  - collection view scroll, `IndexPath`, shake animation은 `ChatViewController`에 유지했다.
- Phase 21:
  - 코드 수정 없는 audit + 종료 기준 확정 phase로 처리했다.
  - `LoadingIndicator.shared`, `AlertManager`, `ConfirmView`, keyboard/app lifecycle `NotificationCenter` observer는 이번 task 종료 기준에서 허용했다.
  - `DefaultMediaProcessingService.shared`, `provider.avatarImageManager`, media preflight/finalize, TTL cleanup, outbox GRDB seam, Lookbook current user provider 통합은 후속 후보로 분리했다.
- Phase 21 후속 안정화:
  - Socket `chat:mediaPreflight`를 추가하고 기존 `send images`/`chat:video` handler에 reservation finalize 검증을 붙였다.
  - preflight 성공 시 `Rooms/{roomID}/MediaUploads/{messageID}` reservation을 생성한다.
  - Firebase Functions scheduler가 오래된 pending reservation 기준으로 `rooms/{roomID}/messages/{messageID}/...` Storage prefix를 삭제한다.
  - `ChatOutgoingOutboxPersisting` protocol을 추가하고 `GRDBManager`가 채택한다.
  - `ChatSearchUIView` up/down 이벤트는 Combine publisher 대신 closure callback으로 전달한다.
  - `ChatSearchUIView`는 ViewModel 타입 대신 view 전용 `SearchResultState`를 받는다.
  - `LocalImageViewerVC`와 `VideoPlayerOverlayVC`를 `MediaGalleryViewController.swift`에서 별도 파일로 분리했다.
  - `ChatViewController`는 `ChatAvatarImageManaging`을 생성자 주입으로 받는다.
  - Lookbook은 앱 공용 `CurrentUserProviding`을 `LookbookContainer`에 주입하고, 내부 adapter가 `UserID?`로 변환한다.
  - `DefaultMediaProcessingService.shared` 직접 접근을 제거하고 composition/default injection 지점에서 instance를 주입한다.

## 5. 검증 결과

- Phase 8:
  - `xcodebuildmcp.build_run_sim` 통과.
  - `xcodebuildmcp.test_sim -only-testing:OutPickTests/ChatRoomExitUseCaseTests` 통과, 5개.
- Phase 9:
  - `xmllint --noout OutPick/Base.lproj/Main.storyboard` 통과.
  - `xcodebuildmcp.build_run_sim` 통과.
- Phase 9.5:
  - 문서 archive 생성 및 top-level 문서 압축 완료.
- Phase 10:
  - `xcodebuildmcp.build_run_sim` 통과.
- Phase 11:
  - `xcodebuildmcp.build_run_sim` 통과.
  - `xcodebuildmcp.test_sim -only-testing:OutPickTests/ChatRoomRuntimeUseCaseTests` 통과, 4개.
- Phase 12:
  - `xcodebuildmcp.build_run_sim` 통과.
  - `xcodebuildmcp.test_sim -only-testing:OutPickTests/ChatRoomViewModelMessageActionTests` 통과, 6개.
- Phase 13:
  - `xcodebuildmcp.build_run_sim` 통과.
  - `xcodebuildmcp.test_sim -only-testing:OutPickTests/ChatRoomRuntimeUseCaseTests` 통과, 5개.
- Phase 14:
  - `plutil -lint OutPick/Info.plist` 통과.
  - `xcodebuild -scheme OutPick -destination 'generic/platform=iOS Simulator' build` 통과.
  - `xcodebuild -scheme OutPick -destination 'id=5A3BB941-9538-4DD9-93C2-F18ACCFB03B9' test -only-testing:OutPickTests/ChatMediaPreviewServicesTests` 통과, 6개.
- Phase 15:
  - `xcodebuild -scheme OutPick -destination 'id=5A3BB941-9538-4DD9-93C2-F18ACCFB03B9' test -only-testing:OutPickTests/ChatMediaPreviewServicesTests` 통과, 6개.
  - `xcodebuild -scheme OutPick -destination 'generic/platform=iOS Simulator' build` 통과.
- Phase 16:
  - `xcodebuild -scheme OutPick -destination 'generic/platform=iOS Simulator' build` 통과.
  - 사용자 수동 QA 완료:
    - 이미지 탭 → 이미지 viewer 확인.
    - 비디오 탭 → video player 확인.
    - 프로필 탭 → 프로필 상세 확인.
    - retry 탭 → pending upload retry 확인.
    - 룩북 공유 카드 탭 → 룩북 공유 흐름 확인.
- Phase 16.5:
  - `xcodebuild -scheme OutPick -destination 'id=5A3BB941-9538-4DD9-93C2-F18ACCFB03B9' test -only-testing:OutPickTests/ChatMessageEmitAckMapperTests` 통과, 4개.
  - `xcodebuild -scheme OutPick -destination 'generic/platform=iOS Simulator' build` 통과.
  - `git diff --check` 통과.
- Phase 16.6:
  - `xcodebuild -scheme OutPick -destination 'generic/platform=iOS Simulator' build` 통과.
  - `xcodebuild -scheme OutPick -destination 'id=5A3BB941-9538-4DD9-93C2-F18ACCFB03B9' test -only-testing:OutPickTests/ChatPendingMediaUploadStoreTests -only-testing:OutPickTests/ChatMediaUploadUseCaseTests -only-testing:OutPickTests/ChatRoomMessageUseCaseTests` 통과.
- Phase 16.6.1:
  - `git diff --check` 통과.
  - `xcodebuild -scheme OutPick -destination 'generic/platform=iOS Simulator' build` 통과.
  - `xcodebuild -scheme OutPick -destination 'id=5A3BB941-9538-4DD9-93C2-F18ACCFB03B9' test -only-testing:OutPickTests/ChatPendingMediaUploadStoreTests -only-testing:OutPickTests/ChatMediaUploadUseCaseTests -only-testing:OutPickTests/ChatMessageWindowStoreTests` 통과.
  - 마지막 QA 보정 후 `xcodebuild -scheme OutPick -destination 'generic/platform=iOS Simulator' build` 재통과.
  - 마지막 QA 보정 후 `xcodebuild -scheme OutPick -destination 'id=5A3BB941-9538-4DD9-93C2-F18ACCFB03B9' test -only-testing:OutPickTests/ChatMessageWindowStoreTests` 재통과.
- Phase 19~21:
  - `git diff --check` 통과.
  - `xcodebuild -scheme OutPick -destination 'generic/platform=iOS Simulator' build` 통과.
  - Phase 21은 코드 변경 없는 audit/documentation phase로 처리했다.
- Phase 21 후속 안정화:
  - Firebase Functions 배포 완료.
  - `xcodebuild -scheme OutPick -destination 'generic/platform=iOS Simulator' build` 통과.
  - `xcodebuild -scheme OutPick -destination 'id=5A3BB941-9538-4DD9-93C2-F18ACCFB03B9' test -only-testing:OutPickTests/LookbookCurrentUserIDProviderTests -only-testing:OutPickTests/ChatMediaUploadUseCaseTests -only-testing:OutPickTests/ChatOutgoingOutboxUseCaseTests` 통과.
  - `git diff --check` 통과.

## 6. 후속 후보 처리 상태

- 메인 스레드 순차 구현 후보였던 media preflight/finalize, reservation 기반 TTL cleanup, outbox GRDB persistence seam은 완료했다.
- 별도 스레드/병렬 후보였던 UI 소정리, `provider.avatarImageManager` 접근 폭 축소, Lookbook current user adapter, `DefaultMediaProcessingService.shared` 직접 접근 제거는 완료했다.

### 구현 대기 Phase 계획

#### Phase Dev-Local: 개발용 Bonjour socket discovery

- 목표: 개발 환경에서 Xcode Scheme 환경변수 없이도 같은 로컬 네트워크의 Socket 서버를 자동 발견한다.
- 배경:
  - `OUTPICK_SOCKET_URL` Scheme 환경변수는 Xcode로 실행할 때만 주입된다.
  - 기기에서 앱 아이콘으로 직접 재실행하면 Scheme env가 없어 production fallback 또는 마지막 저장 URL에 의존한다.
- 추천 방향:
  - Socket Node 서버가 Bonjour/mDNS service를 advertise한다. 예: `_outpick-socket._tcp`.
  - iOS 앱은 개발 빌드에서 Bonjour discovery로 host/port를 resolve한다.
  - URL 결정 우선순위는 명시 URL, Bonjour 발견 URL, 마지막 성공 URL, production URL 순서로 둔다.
  - iOS 설정에는 `NSBonjourServices` 추가가 필요할 수 있다.
- 검증:
  - Xcode env 없이 앱 직접 실행 후 로컬 Socket 서버 발견 및 연결.
  - 로컬 IP 변경 후 재실행 시 새 IP로 연결.
  - Bonjour 실패 시 마지막 성공 URL 또는 production fallback 동작.

#### Phase A: Media processing concrete 타입 제거

- 목표: `DefaultMediaProcessingService.ImagePair`, `DefaultMediaProcessingService.VideoUploadPreset`, static `makeThumbnailData` 직접 노출을 제거한다.
- 앱 미배포 전제이므로 compatibility shim/typealias를 오래 유지하지 않고, concrete nested type 노출을 바로 공용 media 타입/utility로 전환한다.
- 추천 방향:
  - 이미지 타입은 `ProcessedImage` 같은 공용 Infra media 타입으로 분리한다.
  - video preset은 `VideoUploadPreset` 공용 enum으로 분리하되 payload 문자열은 유지한다.
  - thumbnail helper는 우선 `ImageThumbnailDataMaker` 같은 순수 utility로 분리한다.
  - 압축 정책 변경, dead code 제거는 이번 phase 범위 밖으로 둔다.
- 검증: `xcodebuild -scheme OutPick -destination 'generic/platform=iOS Simulator' build`, media/outbox 관련 unit test 재실행.

#### Phase B: 공통 `chat:mediaFinalize` 전송 이벤트 통합

- 목표: 이미지/비디오 업로드 완료 후 Socket finalize 전송 이벤트를 `chat:mediaFinalize`로 통합한다.
- 수신 이벤트 `receiveImages`/`receiveVideo`는 유지한다.
- 기존 `send images`/`chat:video` 서버 handler는 wrapper로 남기는 추천안을 적용한다.
- 앱 도메인 API는 우선 `sendUploadedImages`/`sendUploadedVideo` 같은 외부 메서드를 유지하고 내부 Socket event만 공통화한다.
- 검증: Swift media upload/outbox tests, Socket 서버 syntax/check, 이미지/비디오 finalize retry 수동 QA.

#### Phase C: `ChatViewController.provider` 제거

- 목표: `ChatViewController`가 `ChatManagerProviding` provider 묶음을 직접 보관하지 않게 한다.
- 범위:
  - `profileSyncManager`를 생성자에 직접 주입한다.
  - 현재 미사용인 `messageManager`, `searchManager`, `networkStatusProvider` 필드는 제거한다.
  - `ChatContainer.provider` 자체 제거는 이번 phase 범위 밖으로 둔다.
- 검증: `ChatViewController.swift` 내 provider 참조 0건 확인, iOS build, 채팅방 진입/수신/profile sync 수동 QA.

#### Phase D: Lookbook/Profile avatar/image service DI 정리

- 목표: Lookbook/Profile까지 포함해 `AvatarImageService.shared` 기본값/직접 접근과 provider 경유 avatar 접근을 명시 DI로 정리한다.
- 범위:
  - 앱 미배포 전제이므로 `AvatarImageService.shared` 자체 제거를 목표로 한다.
  - `ChatAvatarImageManaging` 이름은 이번 phase에서 유지한다.
  - Profile 상세의 `LoginManager.shared` current user 접근은 avatar/image service 범위 밖으로 둔다.
  - Lookbook VM/View, Profile coordinator, Chat 조립부의 avatar manager 전달을 정리한다.
- 검증: iOS build, Lookbook 댓글/avatar/profile sheet 수동 QA, 필요 시 Lookbook VM fake avatar manager unit test.

### 운영/성장 이후 보류

- 실제 GRDB in-memory integration test.
  - 목적은 이전 버전 호환성이 아니라 실제 SQL schema/migration/table column과 `ChatOutgoingOutboxPersisting` 계약 검증이다.
  - 앱 미배포 전제와 현재 fake persistence test 커버리지를 고려해 지금은 필수 phase에서 제외한다.
- Storage 전체 sweep 방식 cleanup.
  - reservation TTL cleanup이 현재 1차 방어 역할을 하므로, 전체 sweep은 사용자/트래픽/Storage 비용 증가 후 dry-run report부터 별도 운영 phase로 검토한다.
- 대량 cleanup용 Cloud Run worker 승격.
  - Functions scheduler timeout/대량 삭제 문제가 실제로 생긴 뒤 검토한다.

### 장기 재검토 후보

- `ChatContainer.provider` 자체 제거.
- `ChatAvatarImageManaging`을 앱 공용 `AvatarImageManaging` 이름으로 rename.
- Profile 상세 current user DI 정리.

## 7. 현재 주의사항

- `ChatDependencyContainer`는 제거됐다.
- `ChatViewController`에 남은 `LoadingIndicator.shared`, `AlertManager`, `ConfirmView`, keyboard/app lifecycle observer는 이번 task 종료 기준에서 UI feedback/lifecycle glue로 허용했다.
- 메시지 전송 실패 시 로컬 성공 표시되는 버그는 Phase 16.5~16.6.1에서 ACK 실패 전파, media finalize 실패 상태 보존, 실패 outgoing message 앱 재시작 후 retry/delete, 재시도 성공 후 즉시 재정렬/실패 UI 제거까지 보정했다.
- media 전송은 `chat:mediaPreflight` reservation과 기존 이미지/비디오 finalize handler 검증을 사용한다.
- Socket 서버는 사용자가 로컬에서 직접 실행하는 서버다. `Socket/index.js` 변경은 Firebase Functions 배포 대상이 아니며 별도 운영 Socket 배포 작업도 필요하지 않다.
- Firebase Functions 배포 대상은 `functions/src/index.ts`의 scheduler/API 변경만 해당한다.
- `ChatOutgoingOutboxUseCase`는 `ChatOutgoingOutboxPersisting` seam을 사용한다. 실제 GRDB in-memory integration test는 지금 필수 phase에서 제외하고 운영/성장 이후 보류한다.
- `DefaultMediaProcessingService.shared` 직접 접근과 `provider.avatarImageManager` 접근 폭 축소는 완료했다.
- `progress.md`, `decisions.md`의 과거 상세 내용은 삭제한 것이 아니라 archive에 보존했다.
- working tree에는 현재 task 외 untracked 파일이 많이 있다.
  - `Socket/index.html`
  - `output/`
  - `tmp/`
  - `tools/` 하위 다수 파일
- 커밋 전에는 `git status --short --untracked-files=all`로 반드시 재확인한다.
