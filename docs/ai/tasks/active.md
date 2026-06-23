# Active Task

## 현재 작업

- 작업명: `chat-view-controller-layering`
- 현재 상태: Phase 21 완료. 갤러리/뷰어 Photos 저장 통합, 검색 task/generation guard ViewModel 이동, 남은 runtime singleton/manager 직접 접근 audit 및 종료 기준 확정 완료.
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

## 핵심 원칙

- `ChatViewController`는 UIKit 화면 조립, 사용자 이벤트 전달, collection view 렌더링 반영에 집중한다.
- Socket/Firebase/GRDB/Storage 직접 접근은 ViewController 밖으로 이동한다.
- 서버 상태 변경은 Repository 또는 UseCase 뒤로 숨긴다.
- 화면 이동, sheet, fullScreenCover, UIKit present/dismiss 정책은 Coordinator로 모은다.
- 단발 UI event는 closure/event enum을 우선 사용하고, 지속 stream이 필요한 경우에만 `AsyncStream`/Combine을 도입한다.
- 룩북 공유 카드는 채팅에서 snapshot만 렌더링하고 원본 Repository를 조회하지 않는다.
- iOS 검증은 가능한 경우 `xcodebuildmcp.session_show_defaults` 확인 뒤 `build_run_sim`, `test_sim`을 우선 사용한다.

## 다음 작업 후보

### 메인 스레드 순차 구현 추천

1. media preflight/finalize 안정화.
   - Socket event `chat:mediaPreflight`를 추가한다.
   - 기존 `send images`/`chat:video` finalize handler를 reservation 확인/idempotency 기준으로 강화한다.
   - `Rooms/{roomID}/MediaUploads/{messageID}` reservation으로 upload prefix/messageID 소유권을 기록한다.
2. reservation 기반 TTL cleanup.
   - Firebase Functions scheduler가 오래된 pending reservation의 `rooms/{roomID}/messages/{messageID}/...` Storage prefix를 삭제한다.
3. outbox GRDB persistence test seam.
   - `ChatOutgoingOutboxPersisting` protocol을 만들고 `GRDBManager`가 채택한다.
   - 실제 GRDB in-memory integration test는 후속으로 두고 fake persistence 기반 unit test를 우선 작성한다.

### 별도 스레드/병렬 후보

1. Phase 19/20 후속 소정리.
   - `ChatSearchUIView` up/down 단발 이벤트를 Combine publisher에서 클로저 callback으로 축소한다.
   - `ChatSearchUIView.updateSearchResult`는 유지하되 ViewModel 타입 직접 의존을 낮춘다.
   - `LocalImageViewerVC` fallback 의미를 명확히 하고 `LocalImageViewerVC`/`VideoPlayerOverlayVC`를 별도 파일로 분리한다.
2. `provider.avatarImageManager` 접근 폭 축소.
   - `ChatViewController`에 `ChatAvatarImageManaging`을 생성자 주입하는 수준으로 제한한다.
3. Lookbook current user adapter.
   - 앱 공용 `CurrentUserProviding`을 `LookbookContainer`에 주입하고, Lookbook 내부 adapter가 `UserID?`로 변환한다.
4. `DefaultMediaProcessingService.shared` 직접 접근 제거.
   - 이번에는 shared 주입 제거까지만 하고, `ImagePair`/preset 타입 분리는 후속으로 남긴다.

### 이번 범위 제외 후속

- 새 공통 `chat:mediaFinalize` 이벤트로 이미지/비디오 finalize 통합.
- `DefaultMediaProcessingService.ImagePair`, `VideoUploadPreset`, static `makeThumbnailData` 타입 분리.
- 실제 GRDB in-memory integration test.
- Storage 전체 sweep 방식 cleanup.
- 대량 cleanup용 Cloud Run worker 승격.
- `ChatViewController`의 `provider` 전체 제거.
- Lookbook/Profile까지 포함한 avatar/image service 전면 DI 정리.

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
