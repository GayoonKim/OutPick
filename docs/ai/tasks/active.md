# Active Task

## 현재 작업

- 작업명: `chat-view-controller-layering`
- 현재 상태: Phase 16.6.1 실패 outgoing message 로컬 outbox 영속화와 재시도 성공 후 즉시 UI 정합성 보정 완료.
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

## 핵심 원칙

- `ChatViewController`는 UIKit 화면 조립, 사용자 이벤트 전달, collection view 렌더링 반영에 집중한다.
- Socket/Firebase/GRDB/Storage 직접 접근은 ViewController 밖으로 이동한다.
- 서버 상태 변경은 Repository 또는 UseCase 뒤로 숨긴다.
- 화면 이동, sheet, fullScreenCover, UIKit present/dismiss 정책은 Coordinator로 모은다.
- 단발 UI event는 closure/event enum을 우선 사용하고, 지속 stream이 필요한 경우에만 `AsyncStream`/Combine을 도입한다.
- 룩북 공유 카드는 채팅에서 snapshot만 렌더링하고 원본 Repository를 조회하지 않는다.
- iOS 검증은 가능한 경우 `xcodebuildmcp.session_show_defaults` 확인 뒤 `build_run_sim`, `test_sim`을 우선 사용한다.

## 다음 작업 후보

1. Phase 16.6.2: Phase 17 진입 전 `ChatOutgoingOutboxUseCase`/media upload storage repository DI 정합성 보정.
   - `FirebaseRepositoryProviding`에 video storage repository 제공 경로를 추가한다.
   - `ChatOutgoingOutboxUseCase`의 image/video storage repository singleton 기본값을 제거한다.
   - `ChatMediaUploadUseCase`와 `ChatOutgoingOutboxUseCase` 모두 `ChatContainer`가 repository provider에서 명시 주입하도록 맞춘다.
2. Phase 17: Chat 이미지 로딩 경계를 `ImageCachePipeline` 기반 service로 재정의.
3. 후속 안정화 후보: media message preflight + finalize API 설계.
   - Storage 업로드 전 서버가 방 존재, 참여 여부, 방 종료, rate limit, messageID 예약/업로드 prefix를 확인한다.
4. 후속 안정화 후보: 고아 Storage 파일 TTL cleanup.
   - Firestore 메시지에 참조되지 않거나 장시간 finalize되지 않은 media object를 Cloud Functions/Scheduler로 정리한다.
5. Phase 18: 비디오 asset warm-up/thumbnail 경계 분리.
6. Phase 19: 갤러리/뷰어 Photos 저장 흐름을 `ChatPhotoLibrarySaving` 또는 앱 공용 saver로 통합.
7. Phase 20: 검색 UI orchestration 분리.
8. Phase 21: `ChatViewController` 남은 runtime singleton/manager 직접 접근 최종 audit.
9. 별도 task 후보: Lookbook의 `CurrentUserIDProviding`을 앱 공통 `CurrentUserProviding`으로 흡수.

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
- `ChatViewController`에는 아직 일부 runtime singleton 직접 접근과 UI orchestration 책임이 남아 있다.
- Phase 14 이후 새로 확정한 흐름은 media/cell 구조 부채를 먼저 줄인 뒤 검색 분리와 최종 audit으로 이동하는 순서다.
- 메시지 전송 실패가 로컬에서 성공처럼 표시되는 버그는 Phase 16.5~16.6.1에서 ACK 실패 전파, media finalize 실패 상태 보존, 실패 메시지 영속 retry/delete, 재시도 성공 후 즉시 재정렬/실패 UI 제거까지 보정했다.
- working tree에는 task와 무관해 보이는 untracked `tools/`, `output/`, `tmp/`, `Socket/index.html` 등이 있다.
- 커밋 전 `git status --short --untracked-files=all`로 범위를 재확인한다.
