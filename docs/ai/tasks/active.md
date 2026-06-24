# Active Task

## 현재 작업

- 작업명: `chat-view-controller-layering`
- 현재 상태: Phase 22 `RealtimeSocketService` actor 전환 구현 및 빌드 검증 완료. 수동 QA는 남아 있다.
- 진행 문서:
  - `docs/ai/tasks/chat-view-controller-layering/plan.md`
  - `docs/ai/tasks/chat-view-controller-layering/progress.md`
  - `docs/ai/tasks/chat-view-controller-layering/decisions.md`
- 상세 archive:
  - `docs/ai/tasks/chat-view-controller-layering/archive/progress-through-phase-9.md`
  - `docs/ai/tasks/chat-view-controller-layering/archive/decisions-through-phase-9.md`

## 현재 목표

- `ChatViewController.swift`에 몰려 있던 책임을 기존 OutPick MVVM-C + Repository + UseCase + DI 흐름에 맞춰 단계적으로 분리한다.
- 파일 분할만으로 완료하지 않고 책임 소유권을 ViewModel, UseCase, Repository, Service, Coordinator 경계로 이동한다.

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
  - Socket `chat:mediaPreflight`와 기존 `send images`/`chat:video` finalize handler reservation 검증을 추가했다.
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

### 구현 대기 Phase 계획

#### Phase 23: App session runtime 확장 후보 정리

- 목표: Phase 22에서 작게 도입한 `AppSessionRuntime`의 장기 책임 범위를 정리한다.
- 후보:
  - `AppCoordinator` 생성자 기본값에서 `LoginManagerCurrentUserProvider()`와 `AppSessionRuntime()`을 직접 생성하는 경로를 CompositionRoot/SceneDelegate 조립으로 올린다.
  - `CurrentUserProviding`, `AppSessionRuntime`, `RealtimeSocketService`, `JoinedRoomsSessionStore`를 앱 진입점에서 같은 dependency graph로 조립한다.
  - Presence start/logout만 유지할지, app lifecycle/push device sync까지 session runtime 하위로 옮길지 검토한다.
  - `LoginManager.bootstrapAfterLogin`의 profile listener, joined rooms 선주입, brand admin preload를 session runtime으로 옮길지 검토한다.
- 제외:
  - Firebase repository Combine 전체 제거.
  - Profile/Login 구조 전면 재설계.

#### Phase 23.5: Joined rooms session store 위치/API 정리

- 목표: `JoinedRoomsStore`를 Chat domain model이 아니라 앱 인증 세션 membership runtime state로 재정의한다.
- 현재 문제:
  - `OutPick/Features/Chat/Domain/Models`에 있지만 실제로는 로그인 세션 전체의 joined room snapshot과 변경 이벤트를 가진다.
  - `Combine` publisher 기반이라 Phase 22의 Socket/Realtime `AsyncStream` 방향과 결이 다르다.
- 추천 방향:
  - `OutPick/App/Session` 또는 `OutPick/App/Runtime` 하위 `JoinedRoomsSessionStore`로 이동/rename한다.
  - `replace/add/remove/clear`는 유지하되 변경 관찰은 `AsyncStream<Set<String>>` 또는 명시적인 membership event stream으로 제공한다.
  - 단순 1회성 command가 아니라 bootstrap replace, profile listener replace, room add/remove, logout clear를 포함하는 session snapshot store로 정의한다.
- 검증:
  - joined rooms 변경 시 AppSessionRuntime이 신규 방 join, 제거 방 leave, banner start/remove를 수행하는지 fake runtime으로 검증한다.

#### Phase 24: Participant realtime 계약 정리

- 목표: 기존 `room participant updated` / `new participant joined` socket 경로의 필요 여부를 확정한다.
- 현재 판단:
  - 앱 코드 기준 `participantUpdatePublisher`와 `notifyNewParticipant`는 사용처가 없다.
  - 참여자 수/목록 갱신은 Firestore room document listener와 participant reconcile 흐름이 기준이다.
- 후보:
  - 미사용 API 제거.
  - 서버 계약이 필요하면 transport actor는 raw event만 제공하고, profile fetch/GRDB 저장은 별도 use case로 분리한다.

#### Phase 25: Media upload socket state model 정리

- 목표: `ChatMediaUploadUseCase.isSocketConnected`의 동기 guard를 async 상태 모델 또는 preflight 중심 흐름으로 정리한다.
- 배경:
  - actor 전환 후 정확한 socket 상태는 async로 확인하는 편이 자연스럽다.
  - 현재 Phase 22에서는 실제 업로드 전 preflight/send에서 최종 실패를 확정한다.

#### Phase 26: RealtimeSocketService singleton 직접 접근 제거

- 목표: `RealtimeSocketService.shared` 직접 접근을 composition root 주입 경로로 축소한다.
- 현재 판단:
  - actor isolation은 race condition을 막지만, `.shared` 직접 접근은 lifecycle ownership과 테스트 가능성을 흐린다.
  - 장기 구조에서 race condition 방지는 actor가 담당하고, 객체 생명주기와 동일 instance 공유는 DI가 담당해야 한다.
- 추천 방향:
  - `AppSessionRuntime`이 주입받은 `RealtimeSocketService` instance를 앱 세션 runtime의 기준 instance로 둔다.
  - `ChatContainer`가 socket-facing repository를 만들 때 같은 instance를 명시 주입한다.
  - `FirebaseChatRoomRepository`의 socket create/join side effect는 repository 밖 use case/runtime 경계로 이동한다.
  - `RealtimeSocketService.shared`는 transition default 또는 composition root fallback으로만 남기고 직접 호출 지점을 0에 가깝게 줄인다.
- 검증:
  - `rg "RealtimeSocketService.shared"`로 production 직접 접근 축소 확인.
  - fake realtime service 주입 기반 repository/use case 테스트 보강.

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
