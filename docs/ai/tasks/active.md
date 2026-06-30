# Active Task

## 현재 작업

- 작업명: `main-tab-shell-standardization`
- 현재 상태: 종료.
- 진행 문서:
  - `docs/ai/tasks/main-tab-shell-standardization/design.md`
  - `docs/ai/tasks/main-tab-shell-standardization/plan.md`
  - `docs/ai/tasks/main-tab-shell-standardization/decisions.md`
  - `docs/ai/tasks/main-tab-shell-standardization/progress.md`
  - `docs/ai/tasks/main-tab-shell-standardization/qa-checklist.md`
- 현재 기준:
  - 메인 탭 shell은 `UITabBarController + 각 탭 UINavigationController` 구조로 전환한다.
  - 상세 push 화면의 탭 바 숨김은 `hidesBottomBarWhenPushed`를 기준으로 처리한다.
  - UIKit navigation bar는 계속 숨기고, OutPick 커스텀 navigation bar가 화면 chrome을 담당한다.
  - 기존 `CustomTabBarView` 외형은 `UITabBarAppearance`로 근사한다.
  - 탭 바는 현재처럼 60pt 성격을 유지하고, 필요하면 `UITabBar` subclass를 도입한다.
  - 같은 탭 재선택은 아무 동작도 하지 않는다.
  - Chat 검색/방 생성/방 본문과 Lookbook 브랜드/시즌/포스트 상세에서는 탭 바를 숨긴다.

## 최근 종료 작업

- 작업명: `image-viewer-unification`
- 현재 상태: 종료.
- 종료 기준:
  - Phase 1~5 구현 완료.
  - `SecondProfileViewController` swipe-back draft preservation 구현 완료.
  - 전체 수동 QA는 2026-06-27 사용자 확인 완료.
  - 검증 명령 통과:
    - `git diff --check`
    - `xcodebuild -scheme OutPick -destination 'id=5A3BB941-9538-4DD9-93C2-F18ACCFB03B9' test -only-testing:OutPickTests/ImageViewerPagePolicyTests`
    - `xcodebuild -scheme OutPick -destination 'generic/platform=iOS Simulator' build`
  - 커밋 패키징 완료:
    - `cb3a268` 이미지 뷰어 공용화와 제스처 정리
    - `8c5e91d` 이미지 뷰어 정책 테스트 추가
    - `98e6932` 이미지 뷰어 설계 문서 정리
  - 브랜치 `codex/image-viewer-unification` push 완료.
  - GitHub connector PR 생성은 권한 403으로 실패했으며, 수동 PR 생성 URL은 `https://github.com/GayoonKim/OutPick/pull/new/codex/image-viewer-unification`이다.
- 진행 문서:
  - `docs/ai/tasks/image-viewer-unification/design.md`
  - `docs/ai/tasks/image-viewer-unification/plan.md`
  - `docs/ai/tasks/image-viewer-unification/decisions.md`
  - `docs/ai/tasks/image-viewer-unification/progress.md`
  - `docs/ai/tasks/image-viewer-unification/qa-checklist.md`
- 현재 기준:
  - 공용 image viewer는 `OutPick/Infra/Media/ImageViewer/SimpleImageViewerVC.swift`에 있다.
  - `ImageViewerPage`가 공용 page/source 계약이다.
  - `SimpleImageViewerVC.ProgressivePage`는 기존 호출부 호환 typealias다.
  - `LocalImageViewerVC`는 공용 viewer에 흡수되어 제거됐다.
  - Chat media gallery, Profile avatar, Lookbook post hero, Lookbook brand header가 공용 viewer에 연결됐다.
  - SwiftUI full-screen cover 경로를 위해 공용 viewer는 optional `onClose` hook을 제공한다.
  - 공용 viewer는 minimum zoom 상태에서 viewer 전용 swipe-down dismiss를 지원한다.
  - swipe-down threshold는 운영/QA 튜닝값이다.
  - `SecondProfileViewController`는 완료된 UIKit interactive pop에서 로컬 draft를 저장하고, 저장 중에는 swipe-back을 막는다.
  - 전체 수동 QA는 2026-06-27 사용자 확인 완료.
  - 다음 단계는 수동 PR 생성 또는 다음 작업 선택이다.
- 완료한 worker:
  - Worker C / Peirce / `019f0464-46b4-7963-b3d6-2cc9e5cbf2f1`: Chat media gallery + Profile avatar viewer.
  - Worker D / Hume / `019f0464-7c07-7c83-b0cd-c4ddd30b7dc7`: Lookbook post/brand image viewer.
  - Worker F / Lovelace / `019f0464-aa4e-7892-824c-20b85ffdd6ba`: tests + QA/docs.

## 이전 종료 작업

- 작업명: `chat-view-controller-layering`
- 현재 상태: 종료.
- 종료 기준:
  - Phase 24/25/A/B/C/D 및 작은 구조 정리 2건 구현 완료.
  - Dev-Local Bonjour discovery는 개발 편의 대비 복잡도가 높아 task 범위에서 제외.
  - `chat-view-controller-layering` 본류의 구현 대기 구조 개선 phase 없음.
  - 남은 항목은 운영/성장 이후 보류 항목으로 분리.
- 진행 문서:
  - `docs/ai/tasks/chat-view-controller-layering/plan.md`
  - `docs/ai/tasks/chat-view-controller-layering/progress.md`
  - `docs/ai/tasks/chat-view-controller-layering/decisions.md`
  - `docs/ai/tasks/chat-view-controller-layering/phase-23-runtime-design.md`
- 상세 archive:
  - `docs/ai/tasks/chat-view-controller-layering/archive/progress-through-phase-9.md`
  - `docs/ai/tasks/chat-view-controller-layering/archive/decisions-through-phase-9.md`

## 종료 목표

- `ChatViewController.swift`에 몰려 있던 책임을 기존 OutPick MVVM-C + Repository + UseCase + DI 흐름에 맞춰 단계적으로 분리한다.
- 파일 분할만으로 완료하지 않고 책임 소유권을 ViewModel, UseCase, Repository, Service, Coordinator 경계로 이동한다.

## 코드 지도

- OutPick 전체 코드 지도는 `docs/ai/ENTRYPOINTS.md`에서 시작한다.
- 도메인별 상세 지도:
  - 앱 조립/탭: `docs/ai/entrypoints/APP.md`
  - Chat/realtime/joined rooms/media/outbox/avatar DI: `docs/ai/entrypoints/CHAT.md`
  - Login/auth/bootstrap: `docs/ai/entrypoints/LOGIN.md`
  - Lookbook: `docs/ai/entrypoints/LOOKBOOK.md`
  - Profile: `docs/ai/entrypoints/PROFILE.md`
  - MyPage/logout: `docs/ai/entrypoints/MYPAGE.md`
  - 앱 data layer/Firebase/GRDB: `docs/ai/entrypoints/DATA.md`
  - 공통 Infra/shared services: `docs/ai/entrypoints/INFRA.md`
  - Functions/Firestore/worker: `docs/ai/entrypoints/FIREBASE.md`
  - 테스트: `docs/ai/entrypoints/TESTS.md`
- 코드 파일 추가/수정/이동/삭제가 생기면 관련 도메인 entrypoint 문서에 “어떤 내용을 알고 싶으면 어떤 파일을 보면 되는지”를 같은 phase 안에서 갱신한다.

## 완료한 주요 단계

- Phase 1: 텍스트 메시지 생성/전송 경계 분리.
- Phase 2: 실시간 socket session/task/close 경계 분리.
- Phase 3: 메시지 액션 값 분리와 서버 액션 실행 경계 이동.
- Phase 4: 메시지 window/list item/reconfigure 계산 분리.
- Phase 5: pending media upload store/usecase/repository 분리.
- Phase 6: 읽음 seq 상태 계산 분리.
- Phase 6 보강: room별 read/latest snapshot 공유 Store 추가, NotificationCenter 제거.
- Phase 7: 채팅 내부 라우팅을 `ChatRoomRouting`/`ChatCoordinator`로 정리.
- Phase 8: 방 나가기/닫기 실행을 `ChatRoomExitUseCase`/repository/local cleaner로 분리.
- Phase 9: 채팅 화면 storyboard/coder 우회 진입로 제거.
- Phase 9.5: `progress.md`, `decisions.md`, `HANDOFF.md`, `active.md`를 인덱스 + archive 구조로 압축.
- Phase 10: `ChatDependencyContainer` 제거, `ChatViewController` 핵심 ViewModel/UseCase 생성자 주입 전환.
- Phase 11: `room:closed` socket binding/해제와 미참여 방 transient GRDB cleanup을 runtime use case 경계로 이동.
- Phase 12: 앱 공통 `CurrentUserProviding`을 Chat에 주입하고 `ChatViewController`의 `LoginManager.shared` 직접 접근 제거.
- Phase 13: 채팅방 표시/이탈 presence-banner lifecycle을 runtime use case 경계로 이동.
- Phase 14: 채팅방 본문 이미지/비디오 preview present를 `ChatRoomRouting`/`ChatCoordinator`로 이동하고, 비디오 URL/cache/save 파일 해석과 Photos 저장을 service 경계로 분리.
- Phase 15: `OPStorageURLCache`를 앱 공용 `StorageDownloadURLCache.shared`로 Infra 승격하고, media preview concrete 선택을 `ChatContainer` 조립으로 이동.
- Phase 16: `ChatMessageCell`의 Combine publisher 기반 단발 이벤트를 제거하고, `ChatMessageCellCommands` 기반 messageID command 계약으로 전환.
  - 사용자 수동 QA 완료: 이미지/비디오/프로필/retry/룩북 공유 카드 탭 흐름 정상 확인.
- Phase 16.5: 텍스트 메시지 Socket.IO ACK timeout 실패 표시 보정.
  - `"NO ACK"`/`"no_ack"`/`"timeout"` ACK를 실패로 판정하도록 `ChatMessageEmitAckMapper`를 추가했다.
  - 실패 판정 시 기존 optimistic 메시지가 `isFailed = true`로 reconfigure되어 실패 아이콘 표시 경로를 탄다.
- Phase 16.6: 메시지 전송 확정 상태와 media pending ID 분리.
  - 텍스트 메시지 전송 경로를 `async throws`로 연결해 Socket.IO ACK 실패 시 optimistic 메시지를 failed 상태로 전환한다.
  - 이미지/비디오 canonical messageID, Storage path, Firestore messageID에서 `pending` prefix를 제거했다.
  - Storage 업로드 전 socket 연결을 확인해 서버가 명백히 꺼진 경우 업로드를 시작하지 않는다.
  - Storage 업로드 성공 후 socket finalize 실패 시 업로드된 path/meta를 보존하고, retry는 재업로드 없이 finalize만 재시도한다.
- Phase 16.6.1: 실패 outgoing message 로컬 outbox 영속화.
  - 텍스트/이미지/비디오 실패 메시지를 GRDB `chatOutgoingOutbox`와 Application Support outbox 파일에 보존한다.
  - 앱 재시작 또는 채팅방 재진입 후에도 실패 메시지를 로컬 목록 마지막에 복원한다.
  - retry 시 업로드 필요 여부를 outbox stage/payload로 판단해 업로드 또는 finalize만 수행한다.
  - local-only 삭제 시 로컬 메시지/outbox 파일을 제거하고, 이미 업로드된 media Storage object도 삭제한다.
  - outbox 파일 경로는 앱 컨테이너 absolute path가 아니라 `ChatOutgoingOutbox` 기준 relative path로 저장한다.
  - 재시도 성공 broadcast replacement 시 `isFailed`/`seq` 변경을 기준으로 snapshot을 재정렬하고, 같은 ID cell도 reconfigure해 실패 느낌표를 즉시 제거한다.
- Phase 16.6.2: media upload/outbox storage repository DI 정합성 보정.
  - `FirebaseRepositoryProviding`에 `videoStorageRepository` 제공 경로를 추가했다.
  - `FirebaseRepositoryProvider.shared`가 `FirebaseVideoStorageRepository.shared`를 제공한다.
  - `ChatContainer`가 `ChatMediaUploadUseCase`와 `ChatOutgoingOutboxUseCase`에 image/video storage repository를 명시 주입한다.
  - `ChatOutgoingOutboxUseCase`의 image/video storage repository singleton 기본값을 제거했다.
- Phase 17: Chat 이미지 로딩 경계를 `ChatAttachmentImageLoading` service로 분리.
  - remote Storage 첨부 이미지와 local outgoing preview cache를 하나의 채팅 첨부 이미지 service에서 source별 메서드로 다룬다.
  - remote Storage image pipeline과 local outgoing preview pipeline은 `ChatAttachmentImagePipelines`로 묶고, outgoing preview도 `ImageCachePipeline`을 통과한다.
  - production 조립은 `ChatContainer`/`ChatManagerProvider`가 `FirebaseRepositoryProviding`을 기준으로 담당해 채팅 실행 경로의 image storage repository 직접 선택을 제거했다.
  - 기존 `ChatMediaManager`의 이미지 로딩, 이미지 prefetch, message thumbnail cache 책임을 `ChatAttachmentImageService`로 이동했다.
  - 기존 `ChatImageCache`/`ChatImageCacheProtocol`은 `ChatAttachmentImageService`의 outgoing preview cache 메서드로 흡수했다.
- Phase 18: 비디오 asset warm-up/thumbnail 경계 분리.
  - `ChatMediaManager`/`ChatMediaManaging`을 제거했다.
  - `ChatVideoAssetLoading`/`ChatVideoAssetService`가 비디오 thumbnail cache와 원본 Storage downloadURL warm-up을 담당한다.
  - 원본 비디오 파일은 prefetch하지 않고, 사용자가 실제 재생/저장할 때 기존 playback/save resolver 흐름에서 확보한다.
  - `ChatVideoThumbnailGenerating`/`DefaultChatVideoThumbnailGenerator`가 `AVAssetImageGenerator` 기반 thumbnail data 생성을 담당한다.
  - `ChatViewController`와 설정 화면은 `ChatAttachmentImageLoading`, `ChatVideoAssetLoading`, `ChatStorageURLResolving`, `ChatVideoThumbnailGenerating` 같은 좁은 dependency에 의존한다.
- Phase 19: 갤러리/뷰어 Photos 저장 흐름을 앱 공용 `PhotoLibrarySaving`으로 통합.
  - `DefaultPhotoLibrarySaver`를 `OutPick/Infra/Media`로 승격했다.
  - `SimpleImageViewerVC`, `LocalImageViewerVC`, `VideoPlayerOverlayVC`, `ChatVideoPlayerViewController`의 직접 Photos 저장 흐름을 공용 saver 주입으로 정리했다.
  - gallery 비디오 저장은 `ChatVideoPlaybackResolving.localFileURLForSaving`을 재사용한다.
- Phase 20: 검색 UI orchestration 일부를 `ChatRoomViewModel` 경계로 이동.
  - 검색 task와 generation guard를 ViewModel이 소유한다.
  - `SearchDisplayState`로 내부 index와 UI 표시 index를 분리했다.
  - collection view scroll, `IndexPath`, shake animation은 UIKit 책임으로 `ChatViewController`에 유지했다.
- Phase 21: 남은 runtime singleton/manager 직접 접근 audit 및 종료 기준 확정.
  - `LoadingIndicator.shared`, `AlertManager`, `ConfirmView`, keyboard/app lifecycle `NotificationCenter` observer는 이번 task 종료 기준에서 허용한다.
  - `DefaultMediaProcessingService.shared`, `provider.avatarImageManager`, media preflight/finalize, TTL cleanup, outbox GRDB seam, Lookbook current user provider 통합은 후속 후보로 분리했다.
- Phase 21 후속 안정화:
  - Socket `chat:mediaPreflight`와 당시 남아 있던 `send images`/`chat:video` finalize handler reservation 검증을 추가했다.
  - 현재 설계에서는 `chat:mediaFinalize` 단일 finalize 계약을 기준으로 하며 `send images`/`chat:video` legacy wrapper는 이후 Phase B에서 제거 완료했다.
  - Firebase Functions scheduler 기반 reservation TTL cleanup을 추가하고 배포했다.
  - `ChatOutgoingOutboxPersisting` protocol을 추가하고 `GRDBManager`가 채택하도록 outbox persistence seam을 만들었다.
  - `ChatSearchUIView` 단발 탭 이벤트를 closure로 축소하고 view 전용 search result state로 ViewModel 타입 의존을 제거했다.
  - `LocalImageViewerVC`/`VideoPlayerOverlayVC`를 별도 파일로 분리했다.
  - `ChatViewController`는 avatar manager를 생성자 주입으로 받는다.
  - Lookbook은 앱 공용 `CurrentUserProviding`을 `LookbookContainer`에 주입하고 내부 adapter가 `UserID?`로 변환한다.
  - `DefaultMediaProcessingService.shared` 직접 접근을 제거하고 composition/default injection 지점에서 instance를 주입한다.
- Phase 22: Socket/Realtime runtime을 actor 기반으로 재구성.
  - `SocketIOManager`를 제거하고 `RealtimeSocketService` actor를 도입했다.
  - `SocketManager.config` 런타임 변경을 제거하고, `SocketSessionIdentity` 변경 시 새 Socket.IO manager/client를 만든다.
  - Socket/Realtime 경로의 Combine bridge를 제거하고 `AsyncStream` 중심으로 정리했다.
  - `BannerManager`는 room별 `Task`로 realtime stream을 소비한다.
  - `AppSessionRuntime`을 도입해 인증 세션의 socket connect/disconnect, joined room join/leave, banner runtime 시작/정리를 담당한다.
  - `ChatContainer.bindJoinedRoomsRuntimeIfNeeded()`는 제거했다.
  - participant socket publisher/listener 경로는 미사용/계약 불명확 경로로 보고 actor public API로 승격하지 않았다.
  - 검증: `xcodebuildmcp.build_run_sim` 통과.
  - 사용자 수동 QA 완료: 로그인 후 socket 연결, joined room runtime, 채팅방 진입/이탈, 배너/로그아웃 관련 Phase 22 핵심 흐름 확인 완료.
- Phase 23/23.5/26 설계 하네스:
  - 하위 에이전트 3개로 AppSessionRuntime 조립, JoinedRoomsStore 위치/API, RealtimeSocketService 직접 접근을 병렬 조사했다.
  - `phase-23-runtime-design.md`에 runtime DI 설계, 결정 필요 사항, phase 분할, 예상 변경 파일, 검증 계획을 정리했다.
- Phase 23/23.5/26 구현:
  - `AppCompositionRoot`를 추가해 앱 세션 dependency graph 조립을 `SceneDelegate`/`AppCoordinator` 밖으로 올렸다.
  - `AppCoordinator`는 `JoinedRoomsSessionStore`, `BrandAdminSessionStore`, `CurrentUserProviding`, `RealtimeSocketService`, `AppSessionRuntime`을 주입받는다.
  - Scene lifecycle의 presence 호출은 `AppCoordinator`를 거쳐 `AppSessionRuntime`으로 위임한다.
  - `JoinedRoomsStore`를 `OutPick/App/Session/JoinedRoomsSessionStore.swift`로 이동/rename하고 `JoinedRoomsSessionStoring` protocol seam을 추가했다.
  - `ChatContainer`가 same `RealtimeSocketService` instance를 socket-facing repository/use case에 명시 주입한다.
  - `FirebaseChatRoomRepository.saveRoomInfoToFirestore`의 socket create/join side effect를 제거했다.
  - `ChatRoomLifecycleUseCase`의 `BannerManager.shared.addRoom` 우회 호출을 제거하고 joined rooms session store 변경 경로로 통일했다.
  - `JoinedRoomsSessionStoreTests`를 추가했다.
- Phase 23.6 JoinedRooms publisher 제거:
  - `JoinedRoomsSessionStore.publisher`와 Combine subject를 제거하고 snapshot API만 남겼다.
  - `AppSessionRuntime`에 `replaceJoinedRooms`, `addJoinedRoom`, `removeJoinedRoom`, `clearJoinedRooms` command API를 추가했다.
  - 로그인 bootstrap, 방 생성/참여, 방 나가기 cleanup에서 store 갱신 직후 runtime command를 명시 호출한다.
  - 검증: `git diff --check`, `xcodebuild -scheme OutPick -destination 'generic/platform=iOS Simulator' build`, `xcodebuild -scheme OutPick -destination 'id=5A3BB941-9538-4DD9-93C2-F18ACCFB03B9' test -only-testing:OutPickTests/JoinedRoomsSessionStoreTests` 통과.
- Phase 23.7 QA runtime 안정화:
  - 로그아웃 직후 새 로그인 routing이 이전 authenticated session stop 작업과 경합하지 않도록 reset task 대기를 제거하고 generation guard로 늦은 stop을 무시한다.
  - 마이페이지 로그아웃 후 재로그인 성공도 `AppCoordinator.routeAfterAuthenticated()`를 타도록 레거시 root 교체 경로를 연결했다.
  - `AppSessionRuntime`은 socket connect를 fire-and-forget으로 던지지 않고 retry 후 joined room sync/banner runtime을 시작한다.
  - `RealtimeSocketService.closeRoomSession`은 화면/배너 consumer 종료만 처리하고 실제 socket room leave는 joined-room command 경로에서만 수행한다.
  - 방 생성/참여 직후 설정 화면 참여자 초기값은 room document participants 기반 reconcile로 보정한다.
  - 방 나가기 성공 후 joined room summary publisher도 로컬에서 즉시 제거한다.
  - 검증: `git diff --check`, `xcodebuild -scheme OutPick -destination 'generic/platform=iOS Simulator' build`, `xcodebuild -scheme OutPick -destination 'id=5A3BB941-9538-4DD9-93C2-F18ACCFB03B9' test -only-testing:OutPickTests/ChatRoomExitUseCaseTests -only-testing:OutPickTests/JoinedRoomsSessionStoreTests` 통과.
  - 사용자 수동 QA 완료: 로그아웃 후 재로그인 메인 탭 진입, socket connect, 배너, 참여자 목록, 방 나가기.
- Phase 24: Participant realtime 계약 정리.
  - participant socket event는 앱 public 계약으로 복원하지 않는 것으로 확정했다.
  - 설정 화면 진입 시 `ChatRoomSettingViewModel.loadInitialParticipants()`가 Firestore room document participants 기준 reconcile을 수행하는 현재 구조를 source of truth로 확인했다.
  - 설정 화면이 이미 열린 상태에서 참여자 변경을 실시간 반영하는 것은 완료 기준에서 제외했다.
- Phase 25: Media upload socket state model 정리.
  - `ChatMediaUploadUseCaseProtocol`, `ChatMediaMessageSendingRepositoryProtocol`, socket sending 경계에서 동기 `isSocketConnected` guard를 제거했다.
  - media upload 실패 확정은 `chat:mediaPreflight`와 `chat:mediaFinalize` ACK 실패 경로로 통일했다.
- Phase A/B: Media processing concrete 타입 노출과 legacy socket wrapper 정리.
  - `DefaultMediaProcessingService.ImagePair`/nested `VideoUploadPreset` 직접 노출 잔여가 없음을 확인했다.
  - `Socket/index.js`에서 `send images`, `chat:video` legacy finalize wrapper를 제거하고 `chat:mediaFinalize` 단일 finalize 계약으로 정리했다.
- Phase C/D: Provider/Avatar DI 일괄 정리.
  - `ChatManagerProviding` protocol과 `ChatContainer.provider` 외부 노출을 제거했다.
  - `AvatarImageService`는 `AppCompositionRoot`에서 앱 세션 단위로 생성해 Chat, Lookbook, Profile 경로에 명시 주입한다.
  - `LookbookContainer`의 production avatar default 생성도 제거했다.
  - 검증: `node --check Socket/index.js`, `git diff --check`, `xcodebuild -scheme OutPick -destination 'generic/platform=iOS Simulator' build`, `xcodebuild -scheme OutPick -destination 'id=5A3BB941-9538-4DD9-93C2-F18ACCFB03B9' test -only-testing:OutPickTests/ChatMediaUploadUseCaseTests` 통과.
- 작은 구조 정리:
  - `ChatAvatarImageManaging`을 앱 공용 성격의 `AvatarImageManaging`으로 rename했다.
  - Profile 상세 화면 조립부의 current user 판정 값은 `LoginManager.shared` 직접 접근 대신 `CurrentUserProviding` 주입으로 받는다.
  - Lookbook 댓글/답글에서 Profile 상세로 진입하는 SwiftUI wrapper도 같은 `CurrentUserProviding`을 전달한다.

## 핵심 원칙

- `ChatViewController`는 UIKit 화면 조립, 사용자 이벤트 전달, collection view 렌더링 반영에 집중한다.
- Socket/Firebase/GRDB/Storage 직접 접근은 ViewController 밖으로 이동한다.
- 서버 상태 변경은 Repository 또는 UseCase 뒤로 숨긴다.
- 화면 이동, sheet, fullScreenCover, UIKit present/dismiss 정책은 Coordinator로 모은다.
- 단발 UI event는 closure/event enum을 우선 사용하고, 지속 stream이 필요한 경우에만 `AsyncStream`/Combine을 도입한다.
- 룩북 공유 카드는 채팅에서 snapshot만 렌더링하고 원본 Repository를 조회하지 않는다.
- iOS 검증은 가능한 경우 `xcodebuildmcp.session_show_defaults` 확인 뒤 `build_run_sim`, `test_sim`을 우선 사용한다.

## 후속 후보 처리 상태

- 메인 스레드 순차 구현 후보였던 media preflight/finalize, reservation 기반 TTL cleanup, outbox GRDB persistence seam은 완료했다.
- 별도 스레드/병렬 후보였던 UI 소정리, `provider.avatarImageManager` 접근 폭 축소, Lookbook current user adapter, `DefaultMediaProcessingService.shared` 직접 접근 제거는 완료했다.

### 남은 후속 Phase 계획

- `chat-view-controller-layering` 본류의 구현 대기 구조 개선 phase는 현재 없다.
- Dev-Local Bonjour socket discovery는 이번 task 범위에서 제외한다.
  - 이유: 현재 불편은 사이드 프로젝트의 로컬 Socket 서버 직접 실행 구조에서 오는 개발 편의 문제이며, 실서비스/실무 환경의 서버 연결 요청 흐름에서는 별도 Bonjour discovery까지 도입할 필요성이 낮다.
  - 현재 유지 방식: Xcode Scheme 환경변수 `OUTPICK_SOCKET_URL`과 마지막 성공 URL 저장 경로를 사용한다.

### 운영/성장 이후 보류

- 실제 GRDB in-memory integration test.
  - 목적은 이전 버전 호환성이 아니라 실제 SQL schema/migration/table column과 `ChatOutgoingOutboxPersisting` 계약 검증이다.
  - 앱 미배포 전제와 현재 fake persistence test 커버리지를 고려해 지금은 필수 phase에서 제외한다.
- Storage 전체 sweep 방식 cleanup.
  - reservation TTL cleanup이 현재 1차 방어 역할을 하므로, 전체 sweep은 사용자/트래픽/Storage 비용 증가 후 dry-run report부터 별도 운영 phase로 검토한다.
- 대량 cleanup용 Cloud Run worker 승격.
  - Functions scheduler timeout/대량 삭제 문제가 실제로 생긴 뒤 검토한다.

### 장기 재검토 후보

- 현재 없음.

## 압축 후 읽는 순서

1. `HANDOFF.md`
2. `docs/ai/tasks/active.md`
3. `docs/ai/tasks/chat-view-controller-layering/progress.md`
4. `docs/ai/tasks/chat-view-controller-layering/decisions.md`
5. 필요한 경우 archive:
   - `docs/ai/tasks/chat-view-controller-layering/archive/progress-through-phase-9.md`
   - `docs/ai/tasks/chat-view-controller-layering/archive/decisions-through-phase-9.md`
6. `docs/ai/CODE_ARCHITECTURE.md`
7. `docs/ai/SCREEN_SPEC.md`
8. `docs/ai/FLOW.md`

## 주의사항

- `ChatDependencyContainer`는 삭제됐다.
- `ChatViewController`에 남은 `LoadingIndicator.shared`, `AlertManager`, `ConfirmView`, keyboard/app lifecycle observer는 이번 task 종료 기준에서 UI feedback/lifecycle glue로 허용했다.
- Phase 19~21 진행 전 사용자가 확정한 운영 방식에 따라, 다음 2~3개 phase를 함께 훑고 설계 쟁점/변경 파일/검증 계획을 통합 보고한 뒤 구현한다.
- 메시지 전송 실패가 로컬에서 성공처럼 표시되는 버그는 Phase 16.5~16.6.1에서 ACK 실패 전파, media finalize 실패 상태 보존, 실패 메시지 영속 retry/delete, 재시도 성공 후 즉시 재정렬/실패 UI 제거까지 보정했다.
- working tree에는 task와 무관해 보이는 untracked `tools/`, `output/`, `tmp/`, `Socket/index.html` 등이 있다.
- 커밋 전 `git status --short --untracked-files=all`로 범위를 재확인한다.
