# ADR-013: 룩북 채팅 공유는 Chat 접합부를 먼저 만들고 거대 ViewController에 직접 붙이지 않는다


상태: accepted

결정:

- 공유 기능은 `ChatViewController`에 직접 구현하지 않는다.
- 공유 전송은 `ShareLookbookContentToChatUseCase` → `LookbookChatShareSendingRepositoryProtocol` → socket adapter 경계를 탄다.
- 공유 sheet 상태는 `ObservableObject` + `@Published`와 `async/await`로 관리한다.
- 메시지 타입별 렌더링은 `ChatMessageCell` 내부 거대 분기를 키우지 않고 하위 content view로 분리한다.
- cross-feature 이동은 `MainTabCoordinator` 또는 `AppContentRouting` 같은 앱 레벨 라우터로 분리한다.
- MVP에서는 얇은 `AppContentRouting` 계약으로 시작하고, 후속 작업에서 정식 `MainTabCoordinator`로 승격 가능한 형태로 설계한다.

이유:

- 현재 `ChatViewController`와 `ChatMessageCell`은 이미 책임이 크다.
- 공유 기능은 Lookbook과 Chat을 잇는 cross-feature workflow라 ViewController에 붙이면 라우팅, 전송, 렌더링, 정책이 뒤섞인다.
- 안전한 접합부를 만들면 MVP 속도를 유지하면서 장기 유지보수 비용을 줄일 수 있다.

트레이드오프:

- 작은 기능처럼 보여도 UseCase/Repository/Router 파일이 추가된다.
- 대신 채팅 코드의 기존 부채를 더 키우지 않고 공유 기능을 확장할 수 있다.

