# ChatViewController Layering Plan

## 목표

`ChatViewController.swift`의 책임을 기존 OutPick Chat 아키텍처에 맞춰 단계적으로 분리한다.

핵심 원칙:

- 파일 줄 수를 줄이는 것보다 런타임 책임의 소유권을 먼저 분리한다.
- 기존 MVVM-C + Repository + UseCase + DI 흐름을 우선 따른다.
- `ChatViewController`는 화면 조립, UIKit 이벤트 전달, collection view 렌더링에 집중한다.
- Socket/Firebase/GRDB/Storage 직접 접근은 Repository, UseCase, Service 경계 뒤로 이동한다.
- 미디어 업로드처럼 회귀 위험이 큰 영역은 작은 안정화 phase 이후에 다룬다.
- 룩북 공유 카드의 snapshot-only 렌더링과 `AppContentRouting` 접합부는 유지한다.

## 현재 문제

- `ChatViewController.swift`는 약 3,520줄이고 `ChatViewControllerExtension.swift`까지 합치면 약 3,935줄이다.
- 하나의 ViewController가 다음 책임을 동시에 가진다.
  - 초기 메시지 로드와 pagination.
  - 실시간 소켓 세션 관찰.
  - 텍스트 메시지 생성과 소켓 전송.
  - 이미지/비디오 선택, 변환, 업로드, 실패/재시도 상태.
  - diffable data source, 날짜 구분선, read marker, virtualization.
  - 검색, 하이라이트, 검색 결과 점프.
  - 롱프레스 메뉴, 답장/복사/삭제/공지/신고.
  - 공지 배너, 설정 패널, 프로필/룩북 상세 라우팅.
  - 읽음 seq 갱신과 앱 lifecycle observer.
  - 미디어 캐시, 프리페치, 이미지 뷰어, 비디오 재생/저장.
- 현재 `ChatRoomViewModel`, `ChatRoomMessageUseCase`, `ChatRoomLifecycleUseCase`, `ChatContainer`, `ChatCoordinator`가 있으므로 새 아키텍처를 만들기보다 기존 경계로 책임을 이동한다.

## 범위

포함:

- `ChatViewController`의 책임 인벤토리 문서화.
- phase 단위 리팩토링 계획 수립.
- 텍스트 메시지 전송, 소켓 세션 관찰, 메시지 액션, 메시지 window/diffable 상태, 미디어 처리 책임의 단계적 분리.
- phase별 완료 기준과 검증 계획 정리.
- 필요한 경우 테스트 후보와 수동 QA 항목 정리.

제외:

- 이번 작업 시작 시점의 기능 추가.
- 채팅 UI 전체 재디자인.
- Socket 서버 전체 리팩토링.
- 운영 소켓 서버 배포.
- `MainTabCoordinator` 정식 승격.
- 룩북 공유 기능의 제품 범위 변경.
- 이미지/비디오 업로드 정책 변경.

## 목표 레이어

`ChatViewController`:

- 하위 View 배치와 UIKit lifecycle.
- 사용자 입력 이벤트를 ViewModel/Coordinator로 전달.
- collection view cell 구성과 UI 반영.
- alert, toast, HUD 같은 화면 feedback 표시.

`ChatRoomViewModel`:

- 방 상태, 메시지 상태, 검색 상태, 읽음 seq 상태.
- UseCase 호출 orchestration.
- ViewController가 표시할 state/action 결과 제공.

UseCase:

- 텍스트 전송.
- 메시지 삭제.
- 공지 등록/해제.
- 방 참여와 room lifecycle.
- 실시간 수신 메시지 처리.
- 검색과 pagination.

Repository/Adapter:

- `SocketIOManager` 호출.
- Firebase/Firestore/GRDB 접근.
- Storage URL/업로드 접근.

Service:

- 이미지/비디오 변환.
- pending preview 파일 생성/정리.
- 업로드 progress 상태.
- 미디어 캐시와 프리페치.
- 비디오 재생/저장 보조.

Coordinator/Router:

- 방 설정.
- 사용자 프로필.
- 룩북 공유 카드 탭 후 상세 이동.
- 방 나가기/닫힘 후 화면 이동.

## Phase 0: 문서와 active task 정리

목표:

- `ChatViewController` 레이어 분리 작업을 독립 task로 시작한다.
- 기존 `lookbook-chat-share`의 후속 작업 후보를 새 active task로 승격한다.
- 구현 전 phase 경계와 검증 기준을 문서로 고정한다.

변경 범위:

- `docs/ai/tasks/chat-view-controller-layering/plan.md`
- `docs/ai/tasks/chat-view-controller-layering/progress.md`
- `docs/ai/tasks/chat-view-controller-layering/decisions.md`
- `docs/ai/tasks/active.md`

완료 기준:

- 새 task 문서가 생성된다.
- `active.md`가 새 task를 가리킨다.
- 코드 변경은 없다.

검증 방법:

- 문서 파일 존재 확인.
- `git diff --check` 문서 대상 확인.

논의 필요:

- 없음. 사용자가 Phase 0 진행을 승인했다.

## Phase 1: 텍스트 메시지 전송 경계 분리

목표:

- 텍스트 메시지 생성과 전송 책임을 `ChatViewController` 밖으로 이동한다.

변경 후보:

- `OutPick/Features/Chat/Controllers/ChatViewController.swift`
- `OutPick/Features/Chat/ViewModels/ChatRoomViewModel.swift`
- `OutPick/Features/Chat/Domain/UseCases/ChatRoomMessageUseCase.swift`
- 새 `ChatMessageSendingRepositoryProtocol`
- 새 `SocketChatMessageSendingRepository`
- `OutPick/Features/Chat/ChatContainer.swift`

완료 기준:

- `ChatViewController`는 입력 텍스트와 reply preview를 ViewModel에 전달한다.
- message ID, sender snapshot, socket 전송은 UseCase/Repository 경계에서 처리한다.
- optimistic render 동작은 유지한다.
- 실패 시 기존 failed message 표시 동작이 유지된다.

검증 방법:

- fake sending repository 기반 unit test.
- `git diff --check` 대상 파일 확인.
- 필요 시 `xcodebuild -scheme OutPick -destination 'generic/platform=iOS Simulator' build`.
- 수동 QA: 텍스트 전송, 소켓 미연결 실패 표시, 답장 전송.

논의 필요:

- optimistic message를 ViewModel이 만들어 반환할지, UseCase가 만들어 반환할지 결정 필요.
- 추천: UseCase가 sender snapshot과 message ID를 포함해 optimistic message를 반환한다.

## Phase 2: 실시간 소켓 세션 관찰 분리

목표:

- `ChatViewController`가 `ChatRoomSocketSession`, stream token, socket task를 직접 소유하지 않게 한다.

변경 후보:

- `ChatRoomRealtimeUseCase`
- `ChatRoomRealtimeRepositoryProtocol`
- `SocketChatRoomRealtimeRepository`
- `ChatRoomViewModel`
- `ChatContainer`
- `ChatViewController`

완료 기준:

- ViewController는 ViewModel 또는 UseCase가 제공하는 message stream 결과만 소비한다.
- 방 전환/화면 이탈 시 close/cancel 경계가 명확하다.
- catching-up/live buffering 동작이 유지된다.

검증 방법:

- fake realtime repository로 수신 메시지 append/buffer 상태 전이 테스트.
- 수동 QA: 방 진입, 실시간 수신, 화면 이탈 후 중복 수신 없음.

논의 필요:

- stream 소유권을 ViewModel에 둘지, 별도 runtime object에 둘지 결정 필요.
- 추천: ViewModel은 상태 판단, 별도 UseCase/Repository가 socket stream을 제공한다.

## Phase 3: 메시지 액션/menu 분리

목표:

- 롱프레스 메뉴 UI와 메시지 액션 실행 책임을 분리한다.

변경 후보:

- `ChatMessageActionPolicy`
- 새 `ChatMessageActionHandler` 또는 ViewModel methods
- `ChatRoomViewModel`
- `ChatRoomMessageUseCase`
- `ChatRoomLifecycleUseCase`
- `ChatViewController`

완료 기준:

- policy 계산은 순수 객체로 유지한다.
- reply state, copy, delete, report, announce 실행 경계가 명확하다.
- ViewController는 menu 표시와 사용자 선택 전달만 담당한다.

검증 방법:

- action policy 기존 테스트 유지.
- fake use case 기반 delete/announce action test.
- 수동 QA: 답장, 복사, 삭제, 공지 등록/해제, 신고 toast.

논의 결과:

- B안을 채택했다.
- copy/reply/report toast처럼 로컬 UI 성격의 액션은 ViewController에 남긴다.
- delete/announce처럼 서버 상태 변경이 있는 액션은 ViewModel/UseCase 경계로 이동한다.
- report는 기존 toast 동작만 유지하고, 실제 신고 저장/서버 처리는 후속 기능 phase에서 별도 설계한다.

## Phase 4: 메시지 window와 diffable helper 분리

목표:

- 메시지 중복 제거, 날짜 구분선, read marker, virtualization, `messageMap` 관리를 별도 순수 helper/store로 이동한다.

변경 후보:

- 새 `ChatMessageWindowStore`
- 새 `ChatMessageListItem`
- `ChatViewController`
- 테스트 파일

완료 기준:

- 메시지 window 생성/갱신 로직을 UI 없이 검증할 수 있다.
- collection view data source는 store 결과를 표시한다.
- 기존 pagination, 검색 jump, 삭제 reload, pending image replacement 동작이 유지된다.

검증 방법:

- unit test:
  - 중복 message ID 제거.
  - 날짜 구분선 삽입.
  - read marker 삽입.
  - older/newer virtualization.
  - 기존 메시지 reconfigure 대상 산출.
- 수동 QA: 스크롤 pagination, 검색 jump, 삭제 메시지 reload.

논의 필요:

- `ChatViewController.Item` enum을 유지할지 별도 타입으로 승격할지 결정 필요.
- 추천: 별도 `ChatMessageListItem`으로 승격한다.

## Phase 5: 이미지/비디오 pending upload 분리

목표:

- picker 결과 처리, pending image message, upload progress, retry, preview cleanup을 서비스/UseCase로 이동한다.

변경 후보:

- `ChatViewControllerExtension.swift`
- `ChatViewController.swift`
- 새 `ChatMediaUploadUseCase`
- 새 `ChatPendingMediaUploadStore`
- 새 `ChatMediaMessageSendingRepositoryProtocol`
- `ChatMediaManaging`

완료 기준:

- ViewController는 picker 표시와 progress UI 반영만 담당한다.
- Firebase Storage 직접 호출은 ViewController 밖으로 이동한다.
- `ChatMediaManaging.uploadCompressedVideoAndBroadcast`의 fatalError 기본 구현을 제거하거나 더 좁은 계약으로 대체한다.
- pending image retry가 유지된다.

검증 방법:

- fake upload service 기반 progress/failure/retry unit test.
- 수동 QA: 이미지 다중 전송, 업로드 실패/재시도, 비디오 전송, 비디오 재생/저장.

논의 필요:

- 완료. 이미지와 비디오는 `ChatMediaUploadUseCase`로 묶고, socket 전송은 `ChatMediaMessageSendingRepositoryProtocol`, pending 이미지 상태는 `ChatPendingMediaUploadStore`로 분리했다.
- 비디오 pending cell/retry UX 통합은 이번 phase에서 하지 않고 기존 실패 메시지 흐름을 유지했다.

## Phase 6: 읽음 seq와 lifecycle 정리

목표:

- 읽음 seq flush와 app lifecycle observer를 ViewController 밖으로 이동할 수 있는지 검토하고 정리한다.

변경 후보:

- `ChatRoomViewModel`
- `ChatRoomLifecycleUseCase`
- 새 `ChatReadStateStore`
- `ChatViewController`

완료 기준:

- ViewController는 near-bottom 여부 같은 UI state만 제공한다.
- flush/debounce/persist 정책은 ViewModel 또는 별도 controller가 소유한다.
- 화면 이탈, background, terminate에서 읽음 seq flush가 유지된다.

검증 방법:

- ViewModel/unit test: candidate 계산, final seq 계산, flush 조건.
- 수동 QA: 방 재진입 unread count.

논의 결과:

- 추천안을 채택했다.
- 읽음 seq 후보/final/flush 상태 계산은 `ChatReadStateStore`로 분리한다.
- debounce task와 persist orchestration은 `ChatRoomViewModel`에 유지한다.
- app lifecycle observer와 near-bottom 판정은 `ChatViewController`에 유지한다.

## Phase 7: 채팅 화면 라우팅과 Coordinator 경계 정리

목표:

- `ChatViewController`에 남아 있는 화면 이동, child flow 생성, UIKit present/push 책임을 `ChatCoordinator` 또는 좁은 routing/factory 경계로 이동한다.

변경 후보:

- `ChatCoordinator`
- `ChatViewController`
- `ChatRoomRouting`
- `AppContentRouting`
- `UserProfileDetailCoordinator`
- 방 설정, 유저 프로필, 룩북 카드 탭, 방 닫힘/나가기 후 이동 경로

완료 기준:

- `ChatViewController`는 사용자 이벤트와 표시 대상 데이터만 라우터/코디네이터에 전달한다.
- 프로필 상세, 룩북 상세, 방 설정, 방 닫힘/나가기 후 이동 책임이 ViewController 내부 생성 로직에 흩어져 있지 않다.
- 기존 룩북 공유 카드 snapshot-only 원칙과 `AppContentRouting` 접합부는 유지한다.
- 화면 이동 실패 시 assertion/fallback 정책이 명확하다.

검증 방법:

- route spy 기반 unit test 또는 얇은 coordinator test:
  - 프로필 탭 route 호출.
  - 룩북 공유 카드 탭 route 호출.
  - 방 설정 진입 route 호출.
  - 방 닫힘/나가기 후 dismissal/pop route 호출.
- 수동 QA:
  - 프로필 상세 이동.
  - 룩북 공유 카드 상세 이동.
  - 방 설정 진입/복귀.
  - 방 나가기/닫힘 후 목록 복귀.

논의 필요:

- 라우팅을 `ChatCoordinator`로 직접 모을지, 기존 `ChatRoomRouting` protocol을 확장해 ViewController에는 protocol만 남길지 결정 필요.
- 추천: 기존 `ChatRoomRouting`을 확장하고 실제 구현은 `ChatCoordinator`가 담당한다. `AppContentRouting`은 룩북 상세 같은 cross-feature route에 한해 유지한다.

## 테스트 설계

- 변경 유형: 리팩토링, 상태 관리 변경, 비동기/소켓 변경, View 렌더링 경계 변경.
- 위험도: 높음. 채팅방은 사용자에게 바로 보이고, 소켓/캐시/pagination/읽음 seq처럼 타이밍 의존성이 있다.

필요한 테스트:

- Phase 1: 텍스트 전송 UseCase/Repository fake 테스트.
- Phase 2: 실시간 수신 stream fake 테스트.
- Phase 3: action handler 테스트.
- Phase 4: 메시지 window 순수 로직 테스트.
- Phase 5: upload progress/failure/retry fake 테스트.
- Phase 6: 읽음 seq 상태 전이 테스트.
- Phase 7: route spy/coordinator boundary 테스트.

수동 QA 항목:

- 텍스트 메시지 전송.
- 답장 전송.
- 이미지 다중 전송과 retry.
- 비디오 전송/재생/저장.
- 실시간 수신.
- 이전/이후 메시지 pagination.
- 검색과 검색 결과 점프.
- 삭제/복사/공지/신고.
- 룩북 공유 카드 탭.
- 방 참여/나가기/닫힘.
- 앱 background/foreground 후 unread 상태.

보류할 테스트와 이유:

- UIKit collection view 렌더링 snapshot 테스트는 초기 phase에서 보류한다. 현재 위험 대비 비용이 높고 수동 QA가 더 직접적이다.
- 실제 Firebase/Socket integration test는 로컬 서버/credential 환경 의존성이 있어 별도 승인 전까지 보류한다.

테스트 실행 여부:

- Phase 0은 문서 작업이므로 자동 테스트를 실행하지 않는다.
- 코드 변경 phase부터 변경 위험도에 따라 `git diff --check`, unit test 또는 build를 선택한다.

## 완료 기준

- 각 phase는 한 번에 하나의 책임군만 이동한다.
- phase 종료마다 변경 파일, 핵심 결정, 검증 여부, 남은 위험을 `progress.md`에 기록한다.
- `ChatViewController`는 점진적으로 화면 조립/이벤트 전달 중심으로 축소된다.
- 기존 채팅 기본 흐름, 룩북 공유 카드, pagination, 미디어 전송이 유지된다.
