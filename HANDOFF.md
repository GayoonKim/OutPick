# OutPick Handoff

## 1. 최종 목표

- 현재 작업은 `chat-view-controller-layering`이다.
- 최종 목표는 `ChatViewController.swift`에 몰려 있던 메시지 전송, 실시간 수신, 메시지 액션, 메시지 window/diffable, 미디어 업로드, 읽음 seq/lifecycle 책임을 기존 OutPick MVVM-C + Repository + UseCase + DI 흐름에 맞춰 단계적으로 분리하는 것이다.
- 성공 기준은 기능 동작을 유지하면서 `ChatViewController`가 UIKit 화면 조립, 사용자 이벤트 전달, collection view 렌더링 반영에 집중하도록 만드는 것이다.

## 2. 완료한 작업

- Phase 1 완료: 텍스트 메시지 생성/전송을 `ChatRoomMessageUseCase`와 `ChatMessageSendingRepositoryProtocol` 경계로 이동했다.
- Phase 2 완료: 실시간 수신 socket session/task/close 경계를 `ChatRoomRealtimeUseCase`, `ChatRoomRealtimeRepositoryProtocol`, `ChatRoomRealtimeSubscription`으로 이동했다.
- Phase 3 완료: 메시지 롱프레스 메뉴 선택 이벤트를 `ChatMessageAction`으로 분리하고, delete/announce 서버 상태 변경은 `ChatRoomViewModel.performMessageServerAction`으로 이동했다.
- Phase 3 후속 완료: 답장 preview separator 대비를 보정했고, 삭제 대상이 마지막 메시지일 때 참여중인 목록/오픈채팅 목록에 "삭제된 메시지입니다."가 반영되도록 room summary와 preview 렌더링을 보정했다.
- Phase 4 완료: `ChatMessageListItem`과 `ChatMessageWindowStore`를 추가해 메시지 window, 날짜선, read marker, virtualization, reconfigure 대상 계산을 ViewController 밖으로 이동했다.
- Phase 4 사용자 수동 QA 완료: 스크롤 pagination, 검색 jump, 삭제 메시지 reload, pending image 기존 흐름 정상.
- Phase 5 완료: pending image 상태/task/retry payload는 `ChatPendingMediaUploadStore`, preview attachment 생성과 이미지/비디오 Storage 업로드는 `ChatMediaUploadUseCase`, socket media broadcast는 `ChatMediaMessageSendingRepositoryProtocol`로 분리했다.
- Phase 5에서 `ChatMediaManaging.uploadCompressedVideoAndBroadcast`의 fatalError 계약을 제거했다.
- Phase 5 수동 QA 후 비디오 전송 UX 보정을 완료했다.
  - 기존 화면 중앙 `CircularProgressHUD` 업로드 표시를 제거했다.
  - 비디오 변환 완료 후 `PreparedVideo` 썸네일로 pending video message를 먼저 timeline에 추가한다.
  - 비디오 업로드 progress는 이미지와 같은 attachment overlay ring에 표시한다.
  - 성공 시 pending video message와 같은 `messageID`로 `VideoMetaPayload`를 보내 서버 메시지가 대체하게 한다.
  - 업로드 실패 시 중복 failed video message를 만들지 않고 pending video message 자체를 failed 상태로 표시한다.
- Phase 5 targeted unit test 통과:
  - `xcodebuildmcp.test_sim`
  - `OutPickTests/ChatMediaUploadUseCaseTests`
  - `OutPickTests/ChatPendingMediaUploadStoreTests`
  - `OutPickTests/ChatMessageWindowStoreTests`
  - `OutPickTests/ChatRoomMessageUseCaseTests`
  - `OutPickTests/ChatRoomViewModelMessageActionTests`
  - 총 21개 통과.
- Phase 5 앱 빌드/실행 검증 통과:
  - `xcodebuildmcp.build_run_sim`
  - bundle id `GayoonKim.OutPick`
  - simulator `7544249E-D0EE-4B88-A48F-E384DF84E6A4`.
- Phase 5 비디오 UX 보정 후 추가 검증:
  - `xcodebuildmcp.test_sim` with `OutPickTests/ChatMediaUploadUseCaseTests`, `OutPickTests/ChatPendingMediaUploadStoreTests`
  - 10개 통과.
  - `xcodebuildmcp.build_run_sim` 통과.
- Phase 6 완료: Chat Store 파일을 `OutPick/Features/Chat/Stores/`로 모으고, 읽음 seq 후보/final/flush 상태 계산을 `ChatReadStateStore`로 분리했다.
- Phase 6 targeted unit test 통과:
  - `xcodebuildmcp.test_sim`
  - `OutPickTests/ChatReadStateStoreTests`
  - `OutPickTests/ChatMessageWindowStoreTests`
  - `OutPickTests/ChatPendingMediaUploadStoreTests`
  - 총 14개 통과.
- Phase 6 앱 빌드/실행 검증 통과:
  - `xcodebuildmcp.build_run_sim`
  - bundle id `GayoonKim.OutPick`
  - simulator `7544249E-D0EE-4B88-A48F-E384DF84E6A4`.
- Phase 6 보강 완료 후보: `ChatRoomReadStateStore`를 추가해 roomID별 read/latest snapshot과 `AsyncStream` invalidation을 공유하고, 참여중인 목록 unread 갱신의 `NotificationCenter` 경로를 제거했다.
- Phase 6 보강 targeted unit test 통과:
  - `xcodebuildmcp.test_sim`
  - `OutPickTests/ChatRoomReadStateStoreTests`
  - `OutPickTests/ChatReadStateStoreTests`
  - `OutPickTests/ChatRoomViewModelMessageActionTests`
  - `OutPickTests/LookbookChatShareUseCaseTests`
  - 총 23개 통과.
- Phase 6 보강 앱 빌드/실행 검증 통과:
  - `xcodebuildmcp.build_run_sim`
  - bundle id `GayoonKim.OutPick`
  - simulator `7544249E-D0EE-4B88-A48F-E384DF84E6A4`.
- Phase 6 보강 사용자 수동 QA 완료:
  - read-state Store 기반 참여중인 목록 unread 갱신 정상 동작 확인.
  - 현재 채팅방 읽음 상태 공유 정상 동작 확인.
- 하네스 문서 갱신:
  - `docs/ai/tasks/active.md`
  - `docs/ai/tasks/chat-view-controller-layering/plan.md`
  - `docs/ai/tasks/chat-view-controller-layering/progress.md`
  - `docs/ai/tasks/chat-view-controller-layering/decisions.md`

## 3. 아직 남은 작업

- Phase 7 진입 전 논의:
  - 라우팅을 `ChatCoordinator`로 직접 모을지, 기존 `ChatRoomRouting` protocol을 확장해 ViewController에는 protocol만 남길지 결정한다.
  - `AppContentRouting`은 룩북 상세 같은 cross-feature route에만 유지할지 확인한다.
- Phase 7 구현 후보:
  - 프로필 상세 이동.
  - 룩북 공유 카드 상세 이동.
  - 방 설정 진입/복귀.
  - 방 나가기/닫힘 후 목록 복귀.
  - route spy/coordinator boundary 테스트.
- 커밋 정리:
  - 현재 working tree에는 이전 phase 변경과 무관해 보이는 untracked `tools/`, `output/`, `tmp/`, `Socket/index.html` 등이 섞여 있다.
  - 커밋 전 `git status --short --untracked-files=all`로 반드시 재확인한다.

## 4. 수정한 파일 목록

- Phase 5 앱 코드:
  - `OutPick/Features/Chat/Domain/UseCases/ChatMediaUploadUseCase.swift`
    - pending image/video message/preview 생성, 이미지 업로드, 비디오 업로드, cache, media send 위임 경계 추가.
  - `OutPick/Features/Chat/Stores/ChatPendingMediaUploadStore.swift`
    - pending image upload state/task/retry payload와 pending video upload state/task store 추가.
  - `OutPick/Features/Chat/Repositories/ChatMediaMessageSendingRepository.swift`
    - Socket media send adapter 추가.
  - `OutPick/Features/Chat/Controllers/ChatViewController.swift`
    - pending image dictionaries/task 직접 소유 제거, store/usecase 연결.
  - `OutPick/Features/Chat/Controllers/ChatViewControllerExtension.swift`
    - Firebase Storage/Socket 직접 호출 제거, media upload usecase 위임.
  - `OutPick/Features/Chat/Managers/Protocols/ChatMediaManaging.swift`
    - video upload/broadcast fatalError 요구사항 제거.
  - `OutPick/Features/Chat/Managers/Implementations/ChatMediaManager.swift`
    - fatalError 기본 구현 제거.
- Phase 5 테스트:
  - `OutPickTests/ChatMediaUploadUseCaseTests.swift`
  - `OutPickTests/ChatPendingMediaUploadStoreTests.swift`
- Phase 6 앱 코드:
  - `OutPick/Features/Chat/Stores/ChatReadStateStore.swift`
    - 읽음 seq 후보/final/flush 상태 계산 Store 추가.
  - `OutPick/Features/Chat/Stores/ChatRoomReadStateStore.swift`
    - roomID별 read/latest snapshot과 AsyncStream invalidation shared Store 추가.
  - `OutPick/Features/Chat/ViewModels/ChatRoomViewModel.swift`
    - read seq 숫자 필드 직접 소유 제거, `ChatReadStateStore` 위임.
    - flush 성공, room update, 실시간 수신 시 shared read-state Store 반영.
  - `OutPick/Features/Chat/ViewModels/JoinedRoomsViewModel.swift`
    - `NotificationCenter` 대신 shared read-state Store stream 구독.
  - `OutPick/Features/Chat/Controllers/JoinedRoomsViewController.swift`
    - lastRead notification observer 제거.
  - `OutPick/Features/Chat/Domain/Models/ChatNotifications.swift`
    - 삭제.
- Phase 6 테스트:
  - `OutPickTests/ChatReadStateStoreTests.swift`
  - `OutPickTests/ChatRoomReadStateStoreTests.swift`
- 이전 phase 관련 변경도 같은 working tree에 남아 있다:
  - `OutPick/Features/Chat/Stores/ChatMessageWindowStore.swift`
  - `OutPickTests/ChatMessageWindowStoreTests.swift`
  - `OutPickTests/ChatRoomViewModelMessageActionTests.swift`
  - `OutPickTests/ChatRoomMessageUseCaseTests.swift`
  - Phase 3/삭제 요약 보정 관련 Chat 파일들.
- 문서:
  - `docs/ai/workflows/implementation/validation.md`
  - `docs/ai/tasks/active.md`
  - `docs/ai/tasks/chat-view-controller-layering/plan.md`
  - `docs/ai/tasks/chat-view-controller-layering/progress.md`
  - `docs/ai/tasks/chat-view-controller-layering/decisions.md`
  - `HANDOFF.md`
- 재확인 필요:
  - `OutPick.xcodeproj/xcshareddata/xcschemes/OutPick.xcscheme`는 현재 modified 상태다. 이번 Phase 5에서 의도적으로 수정한 파일은 아니다.
  - `docs/ai/tasks/`와 `HANDOFF.md`는 `.git/info/exclude` 영향으로 `git status`에 보이지 않을 수 있다.

## 5. 중요한 아키텍처 결정

선택:

- Phase 5에서 이미지와 비디오 업로드는 `ChatMediaUploadUseCase` 하나로 묶고, pending media state는 `ChatPendingMediaUploadStore`, socket 전송은 `ChatMediaMessageSendingRepositoryProtocol`로 분리했다.
- Phase 6에서 읽음 seq 후보/final/flush 상태 계산은 `ChatReadStateStore`로 분리하고, debounce/persist orchestration은 `ChatRoomViewModel`, near-bottom/lifecycle observer는 `ChatViewController`에 유지했다.
- Phase 6 보강에서 여러 화면이 공유하는 read/latest snapshot은 `ChatRoomReadStateStore`로 분리하고, 참여중인 목록은 `AsyncStream`을 구독한다.

이유:

- 이미지와 비디오는 모두 "가공된 media를 Storage에 올리고 socket으로 meta를 보낸다"는 같은 usecase 흐름을 공유한다.
- pending image는 progress overlay/retry/local preview 파일이 있어 별도 상태 store가 필요하다.
- Socket/Firebase 직접 호출을 ViewController 밖으로 이동해야 fake repository 기반 unit test가 가능하다.
- 읽음 seq 상태 전이는 순수 로직으로 분리하면 unit test로 고정하기 쉽다.
- lifecycle observer까지 한 번에 옮기면 background/terminate 타이밍 회귀 반경이 커진다.
- 참여중인 목록과 현재 채팅방은 같은 읽음 상태를 봐야 하므로 NotificationCenter보다 shared Store가 더 명확하다.

트레이드오프:

- 비디오도 완전한 pending cell/retry UX로 통합하는 것이 장기적으로는 더 일관적일 수 있다.
- 다만 이번 phase에서 비디오 UX까지 바꾸면 기존 실패 메시지 표시, HUD, 재생/저장 흐름의 회귀 반경이 커지므로 기존 local failed video message 방식을 유지했다.

보류한 대안:

- 이미지 업로드 usecase와 비디오 업로드 usecase를 처음부터 완전히 분리하는 방식은 이번 범위에서는 추상화가 과해 보였다.
- 비디오 pending store를 이미지 pending store와 완전 통합하는 방식은 UX 결정이 추가로 필요해 보류했다.

재검토 조건:

- 비디오 업로드 실패 후 재시도 UX를 제품적으로 이미지와 통일하기로 결정하면, `ChatPendingMediaUploadStore`를 video pending payload까지 확장한다.
- media upload 정책이 더 복잡해지면 image/video 내부 service를 `ChatMediaUploadUseCase` 아래로 분리한다.

검증 도구 결정:

- iOS 빌드/테스트/실행은 가능한 경우 Build iOS Apps 플러그인의 `xcodebuildmcp`를 우선 사용한다.
- 첫 build/run/test 전 `session_show_defaults`로 project/scheme/simulator 기본값을 확인한다.

## 6. 다시 확인해야 할 불확실한 부분

- Phase 5 수동 QA 중 비디오 전송 pending UI 이슈는 보정 완료했다.
- 보정 후 사용자의 재수동 QA에서 원하는 대로 동작한다고 확인됐다.
- 실제 Firebase Storage 업로드 실패를 재현한 retry 수동 QA는 아직 필요하다.
- 실제 Socket disconnected 상태에서 video send ack 실패/failed video 표시 흐름은 재확인 필요.
- Phase 6 보강 read-state Store 수동 QA는 사용자 확인 기준 정상 동작했다.
- `OutPick.xcscheme` 변경은 이번 phase 변경으로 보이지 않는다. 추측입니다. 커밋 전 재확인 필요.
- working tree의 untracked `tools/`, `output/`, `tmp/`, `Socket/index.html`는 이번 chat layering 작업 범위와 무관해 보인다. 추측입니다. 커밋 전 재확인 필요.
- 기존 warning은 남아 있다:
  - `LoadChatRoomParticipantsUseCase` main actor isolation warning.
  - functions node_modules linker search path warning.

## 7. 다음 턴에서 바로 실행해야 할 작업

1. `git status --short --untracked-files=all`로 실제 working tree를 다시 확인한다.
2. 필요하면 다음 문서를 이 순서로 읽는다.
   - `docs/ai/tasks/active.md`
   - `docs/ai/tasks/chat-view-controller-layering/progress.md`
   - `docs/ai/tasks/chat-view-controller-layering/decisions.md`
   - `docs/ai/tasks/chat-view-controller-layering/plan.md`
3. Phase 7 라우팅 책임 inventory를 확인한다.
4. `ChatRoomRouting` 확장 범위와 `AppContentRouting` 유지 범위를 논의한 뒤 Phase 7 구현 계획을 확정한다.
