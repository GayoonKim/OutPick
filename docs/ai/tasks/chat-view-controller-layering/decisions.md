# ChatViewController Layering Decisions

## 문서 구조

- 이 문서는 현재 유효한 결정과 결정 인덱스만 유지한다.
- Phase 0~9의 상세 결정 원문은 `archive/decisions-through-phase-9.md`에 보존했다.
- 특정 phase의 배경, 대안, 세부 영향이 필요하면 archive를 확인한다.

## 결정 인덱스

| 범위 | 현재 결정 | 상세 기록 |
| --- | --- | --- |
| task 분리 | `lookbook-chat-share` 후속이던 `ChatViewController` 레이어 분리를 독립 task로 승격 | `archive/decisions-through-phase-9.md` |
| 리팩토링 기준 | 단순 파일 분할이 아니라 ViewModel/UseCase/Repository/Service/Coordinator로 책임 이동 | `archive/decisions-through-phase-9.md` |
| 메시지 전송 | 텍스트 메시지 생성/전송은 `ChatRoomMessageUseCase`와 sending repository 경계 | `archive/decisions-through-phase-9.md` |
| 실시간 수신 | socket stream open은 repository/use case, task/session close는 subscription 소유 | `archive/decisions-through-phase-9.md` |
| 메시지 액션 | 서버 상태 변경 action은 ViewModel/UseCase, 로컬 UI feedback은 ViewController 유지 | `archive/decisions-through-phase-9.md` |
| 메시지 목록 | list item/window/reconfigure 계산은 `ChatMessageWindowStore` 소유 | `archive/decisions-through-phase-9.md` |
| 미디어 업로드 | pending state는 store, upload orchestration은 `ChatMediaUploadUseCase`, socket broadcast는 repository | `archive/decisions-through-phase-9.md` |
| 읽음 seq | 단일 방 read seq 상태 계산은 `ChatReadStateStore`, orchestration은 ViewModel | `archive/decisions-through-phase-9.md` |
| 읽음 상태 공유 | room별 read/latest snapshot은 `ChatRoomReadStateStore`, 참여중인 목록은 stream 구독 | `archive/decisions-through-phase-9.md` |
| 라우팅 | 채팅 내부 route는 `ChatRoomRouting`과 `ChatCoordinator` 경계로 이동 | `archive/decisions-through-phase-9.md` |
| 설정 패널 이벤트 | `ChatRoomSettingEvent + onEvent` 단일 sink 유지, AsyncStream/Combine 미도입 | `archive/decisions-through-phase-9.md` |
| 방 exit 실행 | `ChatRoomExitUseCase`, socket repository, local cleaner로 분리 | `archive/decisions-through-phase-9.md` |
| storyboard fallback | 채팅 화면 storyboard/coder 우회 진입로 제거, 코드 기반 DI 경로 확정 | `archive/decisions-through-phase-9.md` |
| 문서 압축 | top-level progress/decisions는 인덱스와 최신 요약만 유지, 상세 원문은 archive 보존 | 현재 문서 |
| 전역 bridge 제거 | `ChatDependencyContainer` 제거, Chat 화면 DI는 Container/Coordinator 생성자 주입으로 통일 | 현재 문서 |
| runtime singleton 제거 1차 | `room:closed` socket binding/해제와 transient GRDB cleanup은 runtime use case 경계로 이동 | 현재 문서 |
| current user provider | 현재 사용자 identity는 앱 공통 `CurrentUserProviding`으로 두고 Chat에 먼저 적용 | 현재 문서 |
| visible room lifecycle | 채팅방 표시/이탈 presence-banner lifecycle은 runtime use case 경계로 이동 | 현재 문서 |
| 미디어 preview/save | 채팅방 본문 이미지/비디오 preview present는 `ChatRoomRouting`/`ChatCoordinator`, 비디오 URL/cache/save 파일 해석과 Photos 저장은 service 경계로 분리 | 현재 문서 |
| 후속 phase 재정렬 | Phase 15~19는 media/cell 구조 부채를 먼저 정리하고, 검색 분리와 최종 audit은 Phase 20~21로 이동 | 현재 문서 |
| 메시지 전송 ACK timeout | Socket.IO `"NO ACK"`/timeout ACK는 성공이 아니라 실패로 판정하고, 빈 ACK만 서버 호환성 차원에서 성공으로 유지 | 현재 문서 |
| Realtime socket actor | `SocketIOManager`를 제거하고 `RealtimeSocketService` actor + `AppSessionRuntime`으로 socket/session lifecycle을 분리 | 현재 문서 |
| media pending ID | pending은 로컬 UI/store 상태로만 보관하고 canonical messageID, Storage path, Firestore messageID에는 넣지 않음 | 현재 문서 |
| 실패 outgoing outbox | 전송 실패 메시지는 GRDB outbox + Application Support 파일로 영속화하고, retry 시 업로드 필요 여부를 stage/payload로 판단 | 현재 문서 |
| 실패 메시지 재시도 UI 정합성 | failed local message가 confirmed server message로 교체되면 `isFailed`/`seq` 변경을 재배치 신호로 보고 snapshot reorder와 reconfigure를 함께 수행 | 현재 문서 |
| Phase 16.6.2 예정 | Phase 17 전 storage repository concrete 선택을 UseCase 기본값이 아니라 Container/repository provider 경계로 올림 | 현재 문서 |

## 현재 유효한 아키텍처 원칙

- `ChatViewController`는 UIKit 화면 조립, 사용자 이벤트 전달, collection view 렌더링 반영에 집중한다.
- Socket/Firebase/GRDB/Storage 직접 접근은 ViewController 밖으로 이동한다.
- 서버 상태 변경은 Repository 또는 UseCase 뒤로 숨긴다.
- 화면 이동, sheet, fullScreenCover, UIKit present/dismiss 정책은 Coordinator로 모은다.
- CompositionRoot는 UIKit/SwiftUI 브릿지와 화면 조립을 담당한다.
- Container는 Feature 내부 Repository, UseCase, Store, ViewModel, Coordinator, 화면 factory를 생성하고 보관한다.
- 단발 UI event는 closure/event enum을 우선 사용한다.
- 지속적인 상태 변화 stream이 필요한 경우에만 `AsyncStream`/Combine을 도입한다.
- 룩북 공유 카드는 채팅에서 snapshot만 렌더링하고 원본 Repository를 조회하지 않는다.

## Phase 7 이후 핵심 결정

### RealtimeSocketService Actor 전환

결정:

- `SocketIOManager` compatibility shim을 두지 않고 `RealtimeSocketService` actor로 대체한다.
- `SocketManager.config`는 연결 시도마다 변경하지 않는다.
- 로그인 identity가 바뀌면 기존 Socket.IO manager/client를 닫고 새 `SocketSessionIdentity` 기반으로 다시 만든다.
- Socket/Realtime 경로의 Combine bridge는 제거하고 `AsyncStream` 중심으로 정리한다.
- `BannerManager`는 `AnyCancellable` 대신 room별 `Task`로 realtime stream을 소비한다.
- `AppSessionRuntime`이 인증 세션의 socket connect/disconnect, joined room join/leave, banner runtime 시작/정리를 담당한다.
- `ChatContainer`는 joined room runtime binding을 직접 소유하지 않는다.
- participant socket 이벤트는 현재 미사용/서버 계약 불명확 경로로 보고 actor public API로 승격하지 않는다.

이유:

- Socket.IO Swift `SocketManager`는 thread/queue safe가 아니므로 기존 singleton class에서 여러 Task/콜백이 직접 접근하면 data race와 `EXC_BAD_ACCESS` 위험이 있다.
- socket 연결은 화면 전환 책임이 아니라 인증 세션 runtime 책임이다.
- active manager config mutation보다 identity 단위 manager 재생성이 더 예측 가능하다.
- Socket/Realtime message stream은 이미 채팅방 본문에서 `AsyncStream`을 사용하므로 배너 경로도 같은 모델로 통일하는 편이 단순하다.

후속:

- `AppSessionRuntime`이 profile listener, brand admin preload, presence app lifecycle까지 흡수할지는 별도 phase에서 검토한다.
- participant realtime 계약은 서버 계약 확인 후 제거 또는 별도 use case 분리로 결정한다.
- media upload의 동기 `isSocketConnected` guard는 async 상태 모델 또는 preflight 중심 흐름으로 정리한다.
- `RealtimeSocketService.shared` 직접 접근은 장기 구조가 아니라 전환기 기본값으로 본다. race condition 방지는 actor isolation이 담당하고, lifecycle ownership과 동일 instance 공유는 composition root/DI가 담당하도록 후속 phase에서 정리한다.
- `JoinedRoomsStore`는 Chat domain model이 아니라 앱 세션 membership snapshot/store 성격으로 재분류하고, 위치와 event API를 후속 phase에서 정리한다.

### 메시지 전송 ACK timeout

결정:

- 텍스트 메시지 Socket.IO ACK에서 `"NO ACK"`, `"no_ack"`, `"timeout"`은 실패로 판정한다.
- 빈 ACK는 기존 서버 호환성을 위해 성공으로 유지한다.
- ACK 판정은 `ChatMessageEmitAckMapper`로 분리하고, `SocketIOManager.isEmitAckSuccess(_:)`는 기존 호출부 호환 wrapper로 유지한다.

이유:

- Socket.IO `emitWithAck(...).timingOut` timeout은 `"NO ACK"` 형태로 들어올 수 있다.
- 이를 성공으로 처리하면 서버 저장/브로드캐스트 실패 상황에서도 로컬 optimistic 메시지가 성공처럼 남는다.
- 기존 `isFailed` 메시지 reconfigure 경로를 활용하면 새 UX를 추가하지 않고도 실패 표시를 복구할 수 있다.

### Media Pending ID와 Finalize Retry

결정:

- 이미지/비디오 메시지의 `pending`은 canonical ID가 아니라 local UI/store 상태다.
- `pending-`/`pending-video-` prefix를 messageID, Storage path, Firestore messageID에 넣지 않는다.
- Storage 업로드 전에는 socket connected 상태를 먼저 확인한다.
- Storage 업로드가 성공했지만 socket finalize ACK가 실패하면 업로드된 attachments/video payload를 pending store에 보존한다.
- 사용자가 retry하면 Storage 재업로드 없이 보존한 path/meta만 다시 socket finalize로 전송한다.
- 방 존재, 참여 여부, 방 종료, rate limit, messageID 예약까지 확인하는 preflight + finalize API와 고아 Storage TTL cleanup은 후속 안정화로 분리한다.

이유:

- `pending` prefix가 Firestore/Storage에 남으면 실제 성공 메시지의 canonical ID에도 local state가 새어 들어간다.
- 업로드 성공 후 socket 실패 케이스에서 재업로드를 반복하면 비용과 중복 object 위험이 커진다.
- 다만 현재 socket connected 확인만으로는 서버가 메시지를 받을 수 있는 모든 조건을 검증하지 못하므로, 서버 preflight/finalize는 별도 설계가 필요하다.

### 실패 Outgoing Message Local Outbox

결정:

- 텍스트/이미지/비디오 전송 실패 메시지는 로컬에서 성공 메시지처럼 사라지지 않게 GRDB와 파일 outbox에 보존한다.
- GRDB `chatOutgoingOutbox`는 messageID 단위로 kind, stage, local payload, uploaded payload, lastError를 저장한다.
- 이미지/비디오 retry에 필요한 local asset은 `Application Support/ChatOutgoingOutbox`에 복사해 앱 재시작 후에도 접근 가능하게 한다.
- 저장 경로는 앱 컨테이너 절대경로가 아니라 `ChatOutgoingOutbox` 기준 relative path를 저장하고, 사용할 때마다 현재 실행 중인 `Application Support` 경로에서 해석한다.
- retry는 message kind와 stage를 기준으로 다음 중 하나를 수행한다.
  - 텍스트: socket send 재시도.
  - media `needsUpload`/`failed`: local asset으로 Storage 업로드부터 재시도.
  - media `uploaded`: uploaded attachment/video payload로 socket finalize만 재시도.
- 성공 확정은 ACK만으로 로컬 실패 메시지를 제거하지 않고, sender가 다시 받는 confirmed broadcast replacement 경로에서 outbox를 정리한다.
- confirmed replacement 시 `isFailed` 또는 `seq`가 바뀌면 `ChatMessageWindowStore`가 snapshot을 재정렬해 성공 메시지를 server seq 영역으로 올리고, 남은 failed local message를 tail에 유지한다.
- 같은 messageID diffable item은 ID 기반 identity 때문에 이동만으로 cell configure가 보장되지 않으므로, reorder snapshot에서도 reconfigure target을 유지해 실패 느낌표/시간/overlay를 즉시 갱신한다.
- 실패 메시지 local-only delete는 서버 메시지 삭제가 아니라 로컬 outbox 정리다.
  - 로컬 DB message/outbox record/file을 제거한다.
  - 이미 업로드된 이미지/비디오 Storage object도 삭제한다.

이유:

- 실패 메시지를 메모리 store에만 두면 채팅방 재진입 또는 앱 재시작 후 retry/delete가 불가능하다.
- 업로드 실패도 사용자가 retry할 수 있어야 하므로, 원본/썸네일/압축 비디오 파일을 캐시가 아닌 Application Support에 보존해야 한다.
- iOS 앱 컨테이너 경로는 재설치/시뮬레이터 실행 환경에서 달라질 수 있으므로 absolute path를 DB에 저장하면 앱 재시작 후 로컬 파일 복원이 깨질 수 있다.
- sender는 성공 broadcast를 다시 받는 서버 구조라, ACK 시점에 optimistic 메시지를 제거하면 confirmed replacement와 충돌할 수 있다.
- 재시도 성공 후 실패 메시지가 tail에 남아 있거나 실패 아이콘이 계속 보이면 사용자는 전송 상태를 오해하므로, data order와 cell UI state를 같은 update에서 확정해야 한다.
- local-only delete는 사용자가 재시도를 포기한 명시적 행위이므로, 이미 업로드된 media object도 삭제하는 편이 orphan 비용을 줄인다.
- 다만 앱 종료/네트워크 실패로 Storage delete가 누락될 수 있으므로, 최종 보정은 후속 TTL cleanup이 담당한다.

### 채팅 내부 라우팅

결정:

- `ChatRoomRouting`을 확장하고 실제 구현은 `ChatCoordinator`가 담당한다.
- `ChatViewController`는 설정 패널, 사용자 프로필 상세, 룩북 공유 카드 상세, 방 exit 후 닫기 route를 직접 조립하지 않는다.
- 설정 패널 이벤트는 `ChatRoomSettingEvent + onEvent`로 묶는다.

이유:

- `ChatViewController`가 `AppContentRouting`, `UserProfileDetailCoordinator`, CompositionRoot factory를 직접 알면 화면 이동 책임이 다시 누적된다.
- 설정 패널 이벤트는 상태 stream보다 단발 command 성격이 강해 AsyncStream/Combine보다 event enum + closure가 단순하다.

### 방 나가기/닫기 실행

결정:

- 방 나가기/닫기 실행은 `ChatRoomExitUseCase`가 담당한다.
- socket leave-or-close 요청은 `ChatRoomExitRepositoryProtocol` 뒤로 숨긴다.
- 서버 ACK의 `mode: left/closed`는 `ChatRoomExitResult`로 보존한다.
- GRDB cleanup은 참여중인 방 목록 캐시 삭제가 아니라 해당 방의 로컬 채팅 데이터 cleanup으로 정의한다.
- 참여중인 목록의 source of truth는 Firestore `Rooms.participantIDs` query/listener다.
- `JoinedRoomsStore.remove(roomID)`는 socket/banner runtime 구독 해제를 위한 즉시 보정으로 유지한다.
- 방장은 목록 swipe로 바로 방을 닫지 않고 설정 패널의 명시적 확인 흐름에서 닫는다.

이유:

- 설정 패널과 참여중인 목록 swipe가 다른 서버 경로를 쓰면 일반 leave, 방장 close, local cleanup 정책이 어긋날 수 있다.
- 서버 요청은 요청 1번과 결과 1번의 단발 command이므로 `async throws`가 적합하다.
- 방 닫기는 참여자 전체에게 영향을 주는 파괴적 동작이라 목록 swipe 한 번으로 실행하지 않는 편이 안전하다.

### Storyboard fallback 제거

결정:

- `Main.storyboard`에서 채팅 관련 scene과 relationship segue를 제거한다.
- `ChatViewController`, `RoomListsCollectionViewController`, `JoinedRoomsViewController`의 `required init?(coder:)` fallback은 `fatalError`로 전환한다.
- Cell, reusable view, custom UIView의 `required init?(coder:)`는 UIKit 호환 경로이므로 유지한다.
- `ChatViewController(provider:)`는 provider를 명시적으로 받게 하고 `ChatDependencyContainer.provider` 기본값을 제거한다.
- `ChatDependencyContainer` 전체 제거는 후속 phase 후보로 남긴다.

이유:

- 정상 채팅 진입 경로는 코드 기반 `ChatCoordinator`/`ChatContainer` 조립 경로다.
- storyboard scene과 coder fallback이 남아 있으면 같은 화면이 다른 DI 정책으로 생성될 수 있다.
- `ChatDependencyContainer`에는 아직 runtime bridge 용도가 남아 있어 이번 phase에서 삭제하면 범위가 커진다.

### ChatDependencyContainer 제거

결정:

- `ChatDependencyContainer` enum을 제거한다.
- `ChatContainer`는 provider/repository/store를 전역 bridge에 세팅하지 않는다.
- `ChatCoordinator`는 화면 생성 전 `ChatDependencyContainer`를 갱신하지 않는다.
- `ChatViewController`는 ViewModel, media upload use case, provider를 생성자 주입으로만 받는다.
- `ChatRoomViewModel`은 화면 핵심 의존성이므로 optional로 두지 않고 non-optional `let`으로 보관한다.
- `ChatViewController.ensureChatRoomViewModel()`과 post-init `configure(viewModel:)` 경로는 제거한다.
- `UserProfileDetailCompositionRoot`는 `ChatManagerProviding` 전체가 아니라 `ChatAvatarImageManaging`만 받는다.

이유:

- storyboard/coder 우회 경로를 제거한 뒤에는 전역 DI bridge를 유지할 이유가 줄었다.
- `ChatViewController` 내부 fallback 생성은 Container/Coordinator 주입 경로를 우회해 같은 화면을 다른 dependency graph로 만들 수 있다.
- `ChatRoomViewModel`이 없으면 채팅 화면은 정상 동작할 수 없으므로, 런타임 guard로 조용히 빠지는 것보다 생성 시점 계약으로 강제하는 편이 더 엄격하고 추적 가능하다.
- 프로필 상세는 avatar manager만 필요하므로 Chat provider 전체를 넘기는 것은 과한 결합이다.

영향:

- `ChatViewController`의 `injectedFirebaseRepositories`, `firebaseRepositories`, `makeMediaUploadUseCase()` fallback이 제거됐다.
- `ChatContainer`가 `ChatMediaUploadUseCase`를 생성하고 `ChatCoordinator`가 `ChatViewController`에 명시 주입한다.
- `ChatCoordinator`가 `ChatViewController` 생성 시 `container.makeChatRoomViewModel(room:)` 결과를 함께 주입한다.
- Lookbook 댓글 프로필 상세는 `AvatarImageService.shared`를 전달한다.
- 코드 검색 기준 archive 문서 외 `ChatDependencyContainer` 참조는 남지 않는다.

### Runtime singleton 제거 1차

결정:

- `room:closed` 이벤트 관찰은 `ChatRoomRuntimeUseCase`와 `ChatRoomRuntimeRepositoryProtocol` 뒤로 이동한다.
- Socket.IO `room:closed` listener 등록/해제는 `SocketChatRoomRuntimeRepository`/`ChatRoomRuntimeSocketObserving` 구현체 안에서 처리한다.
- `ChatViewController`는 `ChatRoomRuntimeSubscription`을 보관하고 lifecycle에서 `stop()`만 호출한다.
- `room:closed`는 고빈도 데이터 stream이 아니라 단발 lifecycle event이므로 AsyncStream/Combine 대신 subscription + closure를 사용한다.
- 미참여 방 transient local cleanup은 `DefaultChatRoomTransientLocalDataCleaner`가 담당한다.
- `ChatRoomViewModel`의 runtime use case는 default fallback 없이 `ChatContainer`가 생성자에서 명시 주입한다.

이유:

- `ChatViewController`가 `SocketIOManager.shared.socket.on/off`와 `GRDBManager.shared.deleteMessages/deleteImages`를 직접 호출하면 UIKit 화면이 transport/storage 구현 세부사항을 알게 된다.
- `room:closed`는 방 lifecycle/navigation event라 기존 메시지 realtime stream use case와 합치면 책임이 흐려진다.
- listener 해제가 핵심인 이벤트라 `stop()` 가능한 subscription 객체가 가장 단순하다.
- 미참여 방 local cleanup 실패는 화면 전환을 막을 이유가 없으므로 use case 내부에서 로그로 흡수한다.

영향:

- `ChatViewController`의 `roomClosedListenerID`, `SocketIOManager.shared.socket` 접근, `GRDBManager.shared.deleteMessages/deleteImages` 직접 호출이 제거됐다.
- `ChatRoomRuntimeUseCaseTests`가 runtime use case 위임, cleanup 실패 흡수, subscription 중복 stop 방지를 검증한다.

### CurrentUserProviding 도입

결정:

- 현재 사용자 identity는 Chat 전용 provider가 아니라 앱 공통 `CurrentUserProviding`으로 둔다.
- `LoginManagerCurrentUserProvider`가 `LoginManager.shared`를 감싼다.
- `ChatContainer`는 `CurrentUserProviding`을 생성하고 `ChatRoomViewModel`에 명시 주입한다.
- `ChatViewController`는 현재 사용자 email/documentID/profile을 직접 읽지 않고 `ChatRoomViewModel`의 의도 있는 메서드를 호출한다.
- Lookbook의 기존 `CurrentUserIDProviding`은 이번 phase에서 건드리지 않고, 앱 공통 provider로 흡수하는 후속 작업으로 기록한다.

이유:

- 현재 사용자 정보는 Chat 전용 개념이 아니라 앱 전체 세션/identity 개념이다.
- `ChatViewController`가 `LoginManager.shared`를 직접 알면 참여자 판단, 방장 판단, 메시지 권한, read seq user key 같은 정책이 화면에 남는다.
- 기존 Lookbook provider는 `UserID` 도메인 타입에 묶여 있어 즉시 교체하면 범위가 커진다.

영향:

- `ChatViewController`의 `LoginManager.shared` 직접 접근이 제거됐다.
- `ChatRoomViewModelMessageActionTests`가 current user provider 기반 메시지 권한/참여자/방장/read seq userID 흐름을 검증한다.

### Visible room lifecycle 분리

결정:

- 채팅방 화면의 `viewWillAppear`/`viewWillDisappear`에서 직접 처리하던 presence/banner lifecycle은 기존 `ChatRoomRuntimeUseCase`에 포함한다.
- `DefaultChatRoomVisibilityRuntimeManager`가 `BannerManager`와 `PresenceManager` 호출을 담당한다.
- `ChatViewController`는 ViewModel의 `handleRoomWillAppear()`/`handleRoomWillDisappear()`만 호출한다.
- 별도 use case를 새로 만들지 않고 Phase 11의 runtime use case를 확장한다.

이유:

- `room:closed`, transient cleanup, visible room presence/banner는 모두 채팅방 화면의 runtime lifecycle 책임이다.
- 별도 use case로 쪼개기에는 아직 작고, 기존 runtime 경계에 넣는 편이 DI와 테스트 범위를 단순하게 유지한다.
- `ChatViewController`가 앱 전역 manager를 직접 알지 않게 하는 것이 현재 레이어 분리 방향과 맞다.

영향:

- `ChatViewController`의 `PresenceManager.shared` 직접 접근과 `BannerManager.shared.setVisibleRoom` 직접 접근이 제거됐다.
- `ChatRoomRuntimeUseCaseTests`가 visible room lifecycle 위임을 검증한다.

### 미디어 preview/save orchestration 분리

결정:

- 채팅방 본문 이미지/비디오 preview의 실제 UIKit present는 `ChatRoomRouting`과 `ChatCoordinator`가 담당한다.
- `ChatViewController`는 이미지 viewer page data와 비디오 path를 라우터에 전달하고, `SimpleImageViewerVC`, `AVPlayerViewController`, Photos 저장, `OPVideoDiskCache`, `URLSession`을 직접 알지 않는다.
- 비디오 재생용 URL/cache resolve와 저장용 로컬 파일 확보는 `ChatVideoPlaybackResolving`/`DefaultChatVideoPlaybackResolver`가 담당한다.
- Photos add-only 권한 요청과 이미지/비디오 저장은 `ChatPhotoLibrarySaving`/`DefaultChatPhotoLibrarySaver`가 담당한다.
- `ChatVideoPlayerViewController`는 AVPlayer 표시와 저장 버튼/HUD/alert feedback만 담당한다.
- `ChatMediaManaging`은 UIKit present/저장 파일 해석 책임을 제거하고, 이미지/비디오 캐시, URL resolve, 썸네일 생성 중심으로 좁힌다.
- `Info.plist`에는 실제 사용 목적이 드러나는 Photos purpose string을 둔다.
- 이번 phase는 채팅방 본문 preview/save 경계를 우선 분리하고, `MediaGalleryViewController`, `SimpleImageViewerVC`, `LocalImageViewerVC` 내부 저장 로직 통합은 후속 후보로 남긴다.

이유:

- `ChatViewController`가 `AVPlayerViewController`, `PHPhotoLibrary`, `URLSession.shared`, `OPVideoDiskCache.shared`를 직접 알면 UIKit 화면이 media transport/storage/permission 구현 세부사항을 함께 소유한다.
- 이미지/비디오 preview는 full-screen present 흐름이라 Phase 7 이후 라우팅 결정과 동일하게 Coordinator 경계에 두는 편이 일관적이다.
- Photos 저장은 권한, 실패, 시스템 저장 API가 얽혀 fake 기반 테스트가 가능한 service 경계가 필요하다.
- 갤러리 전체 리팩토링까지 포함하면 Phase 14 범위가 커지므로 본문 채팅방 회귀 위험을 먼저 줄인다.

영향:

- `ChatViewController`의 비디오 재생/저장 helper와 `PHPhotoLibrary`/`URLSession.shared`/`OPVideoDiskCache.shared` 직접 접근이 제거됐다.
- `ChatCoordinator`가 이미지 viewer와 비디오 player를 생성/present한다.
- `ChatContainer`가 media preview/save service를 생성하고 보관한다.
- `ChatMediaPreviewServicesTests`가 로컬 파일, 캐시 hit, Storage URL resolve, 저장용 파일 다운로드, source 누락 실패를 검증한다.
- `Info.plist`에 `NSPhotoLibraryAddUsageDescription`이 추가됐다.

## 후속 결정 후보

- Phase 15에서 Chat 내부 `OPStorageURLCache`를 앱 공용 `StorageDownloadURLCache.shared`로 Infra 승격하고, media preview service의 concrete 기본 생성과 `.shared` 접근을 Container 조립으로 올린다.
- Phase 16에서 `ChatMessageCell` 단발 탭 이벤트의 Combine publisher를 `ChatMessageCellCommands` command 모델로 전환한다.
- Phase 17에서 `ChatMediaManager`의 이미지 로딩 책임을 `ImageCachePipeline` 기반 service로 분리한다.
- Phase 18에서 비디오 URL warm-up과 썸네일 생성 책임을 별도 service로 분리한다.
- Phase 19에서 갤러리/뷰어 Photos 저장 흐름을 `ChatPhotoLibrarySaving` 또는 앱 공용 saver로 통합한다.
- Phase 20에서 검색 UI orchestration의 상태/task/scroll 경계를 설계한다.
- Phase 21에서 `ChatViewController`에 남은 runtime singleton/manager 직접 접근을 최종 점검한다.
- Lookbook의 `CurrentUserIDProviding`을 앱 공통 `CurrentUserProviding`으로 흡수하는 작업은 `chat-view-controller-layering` 본류가 아니므로 별도 task 후보로 둔다.

### 후속 phase 재정렬

결정:

- Phase 15는 Media Preview DI 순도 정리로 둔다.
- Phase 16은 `ChatMessageCell` 단발 이벤트 Combine 제거로 둔다.
- Phase 17은 Chat 이미지 로딩 경계를 `ImageCachePipeline` 기반 service로 재정의하는 단계로 둔다.
- Phase 18은 비디오 asset warm-up/thumbnail 경계 분리로 둔다.
- Phase 19는 갤러리/뷰어 Photos 저장 흐름 통합으로 둔다.
- Phase 20은 검색 UI orchestration 분리로 둔다.
- Phase 21은 `ChatViewController` 최종 audit로 둔다.

이유:

- Phase 14 이후 가장 큰 구조 부채는 검색보다 media preview/save 주변의 DI 순도, 셀 이벤트 모델, 이미지/비디오 service 경계에 있다.
- `DefaultChatVideoPlaybackResolver`가 주입 가능하더라도 production 기본값에서 concrete와 `.shared`를 직접 선택하면 Container 중심 DI 원칙이 흐려진다.
- Firebase Storage path → downloadURL 변환은 Chat 전용 정책이 아니라 앱 공용 Infra 성격이므로 `StorageDownloadURLCache.shared`로 승격하는 편이 장기 구조에 맞다.
- `ChatMessageCell`의 단발 탭 이벤트는 지속 stream이 아니므로 Combine subscription을 셀 reuse마다 관리하는 비용이 기능 대비 크다.
- `ChatMediaManager`는 이미 `ImageCachePipeline`을 사용하지만 이미지 로딩, 비디오 URL warm-up, 비디오 썸네일 생성이 섞여 있어 이후 검색/audit 전에 큰 결합 덩어리를 먼저 줄이는 편이 최종 audit의 의미를 살린다.
- Lookbook current user provider 흡수는 cross-feature 정리라서 이 task 안에 넣으면 종료 기준이 흐려진다.

영향:

- 기존 Phase 15였던 검색 UI orchestration 분리는 Phase 20으로 이동한다.
- 기존 Phase 16이었던 runtime singleton/manager 최종 audit은 Phase 21로 이동한다.
- Phase 15~19는 Phase 14에서 드러난 media/cell 경계 부채를 순차적으로 정리하는 흐름이 된다.
- Phase 15 완료로 `DefaultChatVideoPlaybackResolver`의 production 기본 concrete 선택은 제거됐고, Storage URL cache는 `OutPick/Infra/Storage/StorageDownloadURLCache.swift`의 shared Infra actor로 승격됐다.
- `ChatMediaManager`의 URL resolver 기본값은 compatibility를 위해 `StorageDownloadURLCache.shared`로 유지하며, Phase 17~18의 media service 경계 재정의에서 다시 축소한다.
- Phase 16 완료로 `ChatMessageCell`의 단발 이벤트는 Combine publisher가 아니라 `ChatMessageCellCommands` command 객체로 전달한다.
- media/profile/retry command는 `messageID`를 payload로 사용하고, `ChatViewController`가 최신 message를 `messageWindowStore` 또는 현재 snapshot에서 다시 조회한다.
- Reducer/Store dispatch는 현재 OutPick MVVM-C + ViewModel + Coordinator 구조와 책임이 겹치므로 도입하지 않는다.

### Media upload/outbox storage repository DI 정합성

결정:

- `FirebaseRepositoryProviding`에 `videoStorageRepository`를 추가한다.
- `FirebaseRepositoryProvider.shared`는 image storage와 같은 provider 경계에서 `FirebaseVideoStorageRepository.shared`를 제공한다.
- `ChatContainer`는 `ChatMediaUploadUseCase`와 `ChatOutgoingOutboxUseCase`에 image/video storage repository를 모두 명시 주입한다.
- `ChatOutgoingOutboxUseCase` initializer의 image/video storage repository singleton 기본값은 제거한다.
- `GRDBManager.shared` 기본값은 이번 작은 DI 보정 범위에서 유지하고, local persistence protocol 분리는 후속 후보로 둔다.

이유:

- media upload와 outbox retry/delete는 같은 Storage repository graph를 사용해야 한다.
- `ChatContainer`가 Feature 내부 UseCase 조립을 담당한다는 기존 DI 원칙과 맞다.
- `ChatOutgoingOutboxUseCase`가 storage repository 기본값을 직접 선택하면 테스트/조립 경계가 흐려진다.
- GRDB seam까지 함께 분리하면 이번 phase가 persistence 리팩토링으로 커지므로, Phase 16.6.2는 storage repository 선택 위치만 보정한다.

### Chat attachment image loading service

결정:

- 채팅 첨부 이미지 로딩은 `ChatAttachmentImageLoading` protocol과 `ChatAttachmentImageService`가 담당한다.
- remote Storage 이미지와 local outgoing preview cache는 별도 service로 나누지 않고, 같은 service 안에서 source별 메서드로 구분한다.
- remote Storage 첨부 이미지는 기존 `ChatMediaManager`의 `ImageCachePipeline` 정책을 유지한다.
  - folder: `ChatImageCache`
  - max size: 350MB
  - trim target: 280MB
  - fetch location: `.roomImage`
- local outgoing preview cache는 기존 `ChatImageCache`의 `ThumbCache` folder와 `chatThumb|{key}` key prefix를 유지하되, `ChatAttachmentImageService.storeOutgoingPreview`/`cachedOutgoingPreview`로 흡수한다.
- outgoing preview cache도 `ImageCacheMemoryStore`, `ImageCacheDiskStore`, `ImageCacheInFlightRegistry`를 service가 직접 만지지 않고 `ImageCachePipeline`으로 감싼다.
- remote Storage image pipeline과 outgoing preview pipeline은 `ChatAttachmentImagePipelines`로 묶어 service 생성 시 주입한다.
- production 조립은 `ChatContainer`/`ChatManagerProvider`가 `FirebaseRepositoryProviding`을 기준으로 담당한다.
- `ChatAttachmentImageService`, `RoomImageService`, `AvatarImageService`, `ChatMessageManager`의 채팅 실행 경로는 `FirebaseImageStorageRepository.shared`를 직접 선택하지 않는다.
- `ChatImageCache`/`ChatImageCacheProtocol`은 별도 facade로 유지하지 않는다.

이유:

- 채팅 cell, 이미지 viewer, 룩북 공유 썸네일, 실패 outgoing preview 모두 사용자 관점에서는 채팅 첨부 이미지 표시 경계에 속한다.
- 다만 remote Storage path와 local outgoing preview key는 수명과 fetch 방식이 다르므로, 하나의 service 안에서 메서드로 구분하는 편이 책임을 모으면서도 의미를 잃지 않는다.
- 기존 cache folder/size 정책을 유지하면 Phase 17이 구조 분리로 제한되고, 디스크 사용량/성능 정책 변경에 따른 회귀를 피할 수 있다.
- 룩북 `BrandImageCache`처럼 도메인 service는 pipeline을 감싼 얇은 facade로 두고, fetcher/storage 정책은 pipeline 생성부에 모으는 편이 일관적이다.
- production repository 선택이 service initializer 기본값에 남으면 Phase 16.6.2에서 올린 DI 경계와 어긋나므로, provider/container 조립으로 올린다.
- `ChatMediaManager`는 이미지, 비디오 URL warm-up, 썸네일 생성이 섞여 있었으므로 이미지 책임을 먼저 빼야 Phase 18의 비디오 service 분리가 작아진다.

### Chat video asset service

결정:

- `ChatMediaManager`/`ChatMediaManaging`은 제거한다.
- 비디오 asset warm-up은 `ChatVideoAssetLoading` protocol과 `ChatVideoAssetService`가 담당한다.
- 비디오 warm-up은 thumbnail image cache/load와 원본 Storage path downloadURL warm-up까지만 수행한다.
- 원본 비디오 파일 선다운로드는 하지 않는다.
- messageID 단위 중복 warm-up은 service 내부 actor registry가 담당한다.
- 비디오 thumbnail data 생성은 `ChatVideoThumbnailGenerating` protocol과 `DefaultChatVideoThumbnailGenerator`가 담당한다.
- `ChatViewController`와 설정 화면은 `ChatAttachmentImageLoading`, `ChatVideoAssetLoading`, `ChatStorageURLResolving`, `ChatVideoThumbnailGenerating`처럼 필요한 좁은 dependency만 주입받는다.
- `ChatManagerProviding`은 더 이상 media manager를 제공하지 않는다.

이유:

- Phase 17 이후 `ChatMediaManager`는 이미지 facade와 비디오 warm-up/URL/thumbnail 생성이 섞인 낮은 응집도의 객체가 됐다.
- 비디오 prefetch에서 원본 파일까지 다운로드하면 사용자가 보지 않을 대용량 파일을 네트워크/디스크에 쌓을 수 있다.
- thumbnail cache와 downloadURL warm-up은 스크롤 체감 개선에 충분하고, 실제 파일 확보는 재생/저장 시점의 `ChatVideoPlaybackResolving` 경계가 담당하는 편이 비용 제어에 유리하다.
- thumbnail data 생성은 `AVAssetImageGenerator` 작업이므로 ViewController 동기 helper보다 async service 뒤에 두는 편이 호출부 책임을 줄인다.

## 미결정 사항

- Phase 15 결정: Storage URL cache는 feature-scoped instance가 아니라 앱 공용 `StorageDownloadURLCache.shared`로 둔다.
- Phase 19 결정: Photos saver는 Chat feature service에 유지하지 않고 앱 공용 `PhotoLibrarySaving` 계열로 승격한다. `SimpleImageViewerVC`/`LocalImageViewerVC` 등 viewer에는 init 주입을 우선하고, 갤러리 비디오 저장은 `ChatVideoPlaybackResolving.localFileURLForSaving` 흐름을 재사용한다.
- Phase 20 결정: 검색 task/generation guard는 `ChatRoomViewModel`과 작은 search state/helper 쪽으로 이동하고, 별도 search controller/store 도입은 보류한다. Collection view scroll, `IndexPath`, shake animation은 UIKit 책임으로 `ChatViewController`에 남긴다. 내부 index와 UI 표시 index는 명시적으로 분리한다.
- Phase 21 결정: 1차는 코드 대수술이 아니라 audit + 종료 기준 확정 phase로 둔다. `LoadingIndicator.shared`, `AlertManager`, `ConfirmView` 같은 화면 feedback singleton과 keyboard/app lifecycle `NotificationCenter` observer는 이번 task 종료 기준에서 일단 허용 가능 항목으로 분류하고, `DefaultMediaProcessingService.shared` 직접 접근은 후속 제거 후보로 기록한다.
- Phase 19/20 후속 소정리 결정: 기능 변경 없이 구조만 정리하는 후속 후보로 둔다.
  - `ChatSearchUIView`의 up/down 단발 이벤트는 Combine `PassthroughSubject` 대신 클로저 callback으로 줄인다.
  - `ChatSearchUIView.updateSearchResult` 위치는 view rendering 책임으로 유지하되, `ChatRoomViewModel.SearchDisplayState` 직접 의존은 view 전용 state 또는 원시 표시 값으로 낮춘다.
  - `LocalImageViewerVC`의 fallback 의미는 "원격 path 없는 메모리 `UIImage` 전용 viewer"로 문서/주석을 명확히 한다.
  - `LocalImageViewerVC`와 `VideoPlayerOverlayVC`는 `MediaGalleryViewController.swift`에서 별도 파일로 분리한다.
- 후속 후보 일괄 설계 결정:
  - media preflight는 Socket event `chat:mediaPreflight`로 둔다. 현재 채팅 전송, ACK, socket room join 검증이 Socket 중심이므로 Functions callable보다 기존 흐름과 잘 맞는다.
  - Socket 서버는 사용자가 로컬에서 직접 실행하는 서버이므로 `Socket/index.js` 변경은 Firebase Functions 배포 대상이 아니고, 별도 운영 Socket 배포도 필요하지 않다.
  - media finalize는 새 공통 `chat:mediaFinalize`를 바로 만들지 않고 기존 `send images`/`chat:video` handler를 강화한다. 이미지/비디오 finalize 공통화는 후속으로 남긴다.
  - preflight 성공 시 Firestore `Rooms/{roomID}/MediaUploads/{messageID}` reservation 문서를 만든다. 이 문서는 upload prefix/messageID 소유권, retry/idempotency, TTL cleanup 기준으로 사용한다.
  - TTL cleanup은 reservation 기준 pending 만료 항목의 `rooms/{roomID}/messages/{messageID}/...` Storage prefix를 삭제하는 방식으로 시작한다. 실행 위치는 Firebase Functions scheduler로 둔다.
  - outbox GRDB seam은 별도 repository 대수술 대신 `ChatOutgoingOutboxPersisting` protocol을 만들고 `GRDBManager`가 채택하는 방향으로 둔다. 실제 GRDB in-memory integration test는 후속으로 분리하고, 1차는 fake persistence 기반 unit test를 작성한다.
  - `DefaultMediaProcessingService.shared` 직접 접근 제거는 이번에는 shared 주입 제거까지만 한다. `ImagePair`, `VideoUploadPreset`, static `makeThumbnailData` 타입 분리는 후속으로 남긴다.
  - `provider.avatarImageManager` 접근 축소는 `ChatViewController`에 `ChatAvatarImageManaging`을 생성자 주입하는 수준으로 제한한다. `provider` 전체 제거는 후속으로 남긴다.
  - Lookbook current user 통합은 앱 공용 `CurrentUserProviding`을 `LookbookContainer`에 주입하고, Lookbook 내부 adapter가 `UserID?`로 변환하는 방식으로 둔다. 앱 공용 provider가 Lookbook의 `UserID` 타입을 직접 알게 하지 않는다.

### Phase 21 후속 안정화 완료 기록

- media preflight/finalize는 확정한 방향대로 구현했다.
  - Socket event는 `chat:mediaPreflight`다.
  - finalize는 새 공통 이벤트를 만들지 않고 기존 `send images`/`chat:video` handler를 강화했다.
  - reservation 위치는 `Rooms/{roomID}/MediaUploads/{messageID}`다.
- TTL cleanup은 Firebase Functions scheduler가 reservation 기준 pending 만료 항목의 `rooms/{roomID}/messages/{messageID}/...` Storage prefix를 삭제한다.
- outbox seam은 `ChatOutgoingOutboxPersisting` protocol + `GRDBManager` 채택으로 구현했다.
- UI 소정리는 확정한 방향대로 구현했다.
  - `ChatSearchUIView` 단발 이벤트는 closure callback이다.
  - search result 표시는 view 전용 `SearchResultState`를 사용한다.
  - `LocalImageViewerVC`/`VideoPlayerOverlayVC`는 viewer 전용 파일로 분리했다.
- `provider.avatarImageManager` 접근 축소는 `ChatViewController` 생성자에 `ChatAvatarImageManaging`을 주입하는 수준으로 구현했다.
- Lookbook current user adapter는 앱 공용 `CurrentUserProviding` 주입 + Lookbook 내부 adapter 변환으로 구현했다.
- `DefaultMediaProcessingService.shared` 직접 접근 제거는 shared 직접 접근 제거까지만 구현했다. nested type/static helper 분리는 아래 후속 기록에 유지한다.

### 다음 리팩토링 Phase A~D 결정

- Phase A는 media processing concrete 타입 제거로 둔다.
  - 앱 미배포 전제이므로 `DefaultMediaProcessingService.ImagePair`/`VideoUploadPreset` 호환 shim을 길게 유지하지 않고 직접 노출을 바로 제거한다.
  - 이미지 타입은 `ProcessedImage` 같은 공용 Infra media 타입으로 분리한다.
  - video preset은 공용 `VideoUploadPreset`으로 분리하되 server/storage payload 문자열은 유지한다.
  - thumbnail helper는 우선 `ImageThumbnailDataMaker` 같은 순수 utility로 분리한다.
  - 압축 정책 변경과 dead code 제거는 이번 phase 범위 밖이다.
- Phase B는 공통 `chat:mediaFinalize` 전송 이벤트 통합으로 둔다.
  - 전송 finalize만 통합하고 수신 이벤트 `receiveImages`/`receiveVideo`는 유지한다.
  - 기존 `send images`/`chat:video` Socket handler는 wrapper로 남긴다.
  - 앱 도메인 API는 우선 `sendUploadedImages`/`sendUploadedVideo` 외부 메서드를 유지하고 내부 Socket event만 공통화한다.
- Phase C는 `ChatViewController.provider` 제거로 둔다.
  - `profileSyncManager`를 직접 주입한다.
  - 현재 미사용인 `messageManager`, `searchManager`, `networkStatusProvider` 필드는 제거한다.
  - `ChatContainer.provider` 자체 제거는 별도 장기 재검토 후보로 둔다.
- Phase D는 Lookbook/Profile avatar/image service DI 정리로 둔다.
  - 앱 미배포 전제이므로 `AvatarImageService.shared` 자체 제거를 목표로 한다.
  - `ChatAvatarImageManaging` 이름은 이번 phase에서 유지한다.
  - Profile 상세의 `LoginManager.shared` current user 접근은 avatar/image service 범위 밖으로 둔다.
- 실제 GRDB in-memory integration test는 지금 필수 phase에서 제외한다.
  - 목적은 이전 버전 호환성이 아니라 실제 SQL schema/migration/table column과 `ChatOutgoingOutboxPersisting` 계약 검증이다.
  - 앱 미배포 전제와 fake persistence test 커버리지를 고려해 GRDB schema를 더 건드릴 때 재검토한다.
- Storage 전체 sweep cleanup과 Cloud Run worker 승격은 운영/성장 이후 보류한다.
  - 현재는 reservation TTL cleanup이 1차 방어 역할을 한다.
  - 전체 sweep은 사용자/트래픽/Storage 비용 증가 후 dry-run report부터 별도 운영 phase로 검토한다.
