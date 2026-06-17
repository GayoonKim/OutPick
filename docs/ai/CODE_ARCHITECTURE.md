# OutPick Code Architecture

## 목적

OutPick의 코드 구조와 계층별 책임을 AI 에이전트가 매번 코드 전체를 다시 읽지 않고 파악하기 위한 문서다.

## 기본 구조

OutPick은 기존 MVVM-C + Repository + UseCase + DI 흐름을 우선 따른다.

현재 앱은 UIKit 기반 앱 수명주기와 일부 UIKit 화면 위에 SwiftUI 기능 화면을 함께 사용한다. SwiftUI 화면은 필요한 경우 `UIHostingController`로 감싸 UIKit navigation/tab 흐름에 연결한다.

## 계층별 책임

- View: 화면 렌더링과 사용자 이벤트 전달에 집중한다.
- ViewModel: 화면 상태를 관리하고 UseCase를 호출한다.
- UseCase: 기능 단위 비즈니스 흐름을 담당한다.
- Repository: Firebase, Cloud Functions, Firestore, 네트워크, 저장소 접근을 숨긴다.
- Container: Feature 내부 Repository, UseCase, Store, ViewModel, Coordinator, 화면 factory를 생성하고 보관한다.
- CompositionRoot: 앱, 탭, Feature 진입점 조립과 UIKit/SwiftUI 브릿지를 담당한다.
- Coordinator: push, sheet, fullScreenCover, UIKit present/dismiss 등 화면 전환과 사용자 흐름 제어를 담당한다.

## 앱 조립 흐름

1. `SceneDelegate`가 `UIWindow`와 `AppCoordinator`를 생성한다.
2. `AppCoordinator`가 로그인 상태를 확인하고 로그인, 프로필 플로우, 메인 탭 중 하나로 루트 화면을 전환한다.
3. 메인 탭 진입 시 `AppCoordinator`가 Lookbook/Chat Container를 준비한다.
4. `MainTabCompositionRoot`와 `DefaultMainTabBuilder`가 탭별 root ViewController를 조립한다.
5. 각 Feature의 `CompositionRoot`가 UIKit/SwiftUI 브릿지와 Feature root 조립을 담당한다.

## Feature 조립 흐름

Feature 내부에서는 아래 흐름을 우선 따른다.

```text
CompositionRoot
→ Container
→ Coordinator
→ View / ViewController
→ ViewModel
→ UseCase
→ Repository protocol
→ Repository implementation
→ Firebase / Firestore / Cloud Functions / Network / Local service
```

예외:

- 기존 UIKit 화면이나 레거시 영역은 한 번에 전면 이전하지 않는다.
- 새 기능 또는 큰 리팩토링 시에는 위 흐름으로 점진 정리한다.
- 작은 leaf View의 단발 이벤트는 클로저로 유지할 수 있다.

## 구현 원칙

- View는 Repository, UseCase, Firebase, Cloud Functions, Firestore SDK를 직접 생성하지 않는다.
- ViewModel은 생성자 주입으로 UseCase, Repository, Store를 받는다.
- 서버 상태 변경은 가능한 Repository 또는 Cloud Functions 계층 뒤로 숨긴다.
- 화면 이동 책임이 View나 ViewModel에 흩어지면 Coordinator로 모으는 방향을 우선 검토한다.
- 불필요한 추상화와 요청 범위 밖 리팩토링은 피한다.
- 화면 이동이 2단계 이상 이어지거나 push/sheet/fullScreenCover/present 정책이 섞이면 Coordinator 책임을 먼저 검토한다.
- Feature 내부 의존성 생성은 Container로 모으고, 앱/탭/Feature 진입점 조립은 CompositionRoot에 둔다.
- Firebase/Firestore/Cloud Functions 접근은 Repository protocol과 implementation 뒤로 숨긴다.
- 외부 구현 세부사항이 ViewModel에 들어오면 UseCase 또는 Repository 경계로 밀어낸다.

## 코드 파일 분리 원칙

새 기능을 구현할 때 한 파일에 화면 root, 하위 View, row, preview, confirmation bar, fallback view, presentation modifier, 상태 모델, factory를 한꺼번에 넣지 않는다. 초기 구현 속도 때문에 임시로 묶더라도 phase 종료 전 또는 다음 phase 진입 전에는 독립 책임 단위로 파일을 분리한다.

우선 분리 대상:

- SwiftUI root View: 화면 전체 orchestration, sheet/overlay 연결, ViewModel binding만 담당한다.
- 반복 row/cell View: 목록 row, 카드, 메시지 bubble처럼 반복 렌더링되는 단위는 별도 파일로 둔다.
- preview/summary View: 공유 preview, compact card, header summary처럼 독립 표시 단위는 별도 파일로 둔다.
- confirmation/status/fallback View: 성공 bar, empty/failed/unavailable 상태처럼 다른 화면에서도 재사용될 수 있거나 root 흐름과 책임이 다른 View는 별도 파일로 둔다.
- presentation/helper modifier: sheet detent, 공통 overlay, navigation modifier처럼 UI 정책 helper는 별도 파일로 둔다.
- ViewModel/UseCase/factory: 화면 상태, 도메인 변환, DI 조립은 View 파일 안에 중첩하지 않고 각 계층 위치에 둔다.

분리하지 않아도 되는 경우:

- 20~30줄 이하의 매우 작은 private View이고, 해당 root View 밖에서 재사용 가능성이 낮으며, 독립 상태나 비동기 로딩이 없다.
- 한 화면의 단순 레이아웃 조각이라 별도 파일명이 오히려 의미를 흐리는 경우.

분리 판단 기준:

- 파일이 200줄에 가까워지거나 넘으면 책임 분리 후보를 먼저 찾는다.
- 하위 View가 `@State`, 비동기 로딩, 이미지 로딩, gesture, menu, action policy를 갖기 시작하면 별도 파일로 분리한다.
- 같은 파일 안에서 root orchestration과 row rendering, 상태/fallback UI가 함께 보이면 분리한다.
- 사용자가 리뷰에서 “이 파일이 너무 크다”, “이 요소는 따로 관리하자”라고 지적한 패턴은 이후 유사 구현에 선제 적용한다.
- 파일 수를 줄이는 것보다 책임과 탐색 비용을 줄이는 것을 우선한다.

## 주요 디렉터리

- `OutPick/App`: 앱 진입점, AppCoordinator, SceneDelegate, AppDelegate, 탭 조립 흐름.
- `OutPick/Features`: 기능별 화면, ViewModel, Coordinator, CompositionRoot, Container, Repository, UseCase.
- `OutPick/Infra`: 공통 인프라, 네트워크, 미디어, 알림, 토스트, 키체인 등.
- `OutPickTests`: 단위 테스트.
- `OutPickUITests`: UI 테스트.
- `functions/src`: Firebase Functions TypeScript 코드.
- `firestore.rules`: Firestore 보안 규칙.
- `firestore.indexes.json`: Firestore 인덱스.
- `tools`: 앱 바깥의 운영성 도구, worker, CLI를 두는 후보 디렉터리.
- `scripts/ai`: 반복 검증, 배포, 운영 보조 자동화 스크립트.

## 기능별 구조 메모

기능별 세부 아키텍처는 필요한 문서만 추가로 읽는다.

- Lookbook URL Import Worker: `docs/ai/architecture/LOOKBOOK_IMPORT_WORKER.md`

### Lookbook

- `LookbookCompositionRoot`는 룩북 탭과 좋아요 탭 root를 조립한다.
- `LookbookContainer`는 Lookbook Repository provider, shared store, UseCase, ViewModel factory를 보관한다.
- `LookbookCoordinator`는 브랜드/시즌/포스트 상세, 댓글, 생성 플로우 등 화면 이동을 담당한다.
- `LookbookInteractionStore` 계열 store는 브랜드/시즌/포스트/댓글 상호작용 상태를 공유한다.
- Firestore DTO/mapper는 `Models` 아래에 두고, Domain entity와 외부 저장소 표현을 분리한다.

### Chat

- `ChatCompositionRoot`, `ChatContainer`, `ChatCoordinator`가 채팅 root와 방 진입 흐름을 조립한다.
- ViewController 기반 화면이 많으므로 UIKit 흐름을 존중한다.
- Repositories, Managers, Domain UseCases가 혼재하므로 변경 전 관련 manager/protocol/usecase 흐름을 확인한다.
- `ChatViewController`는 현재 메시지 생성, 소켓 세션, 미디어 캐시, 메뉴 액션 등 책임이 크다. 새 기능은 여기에 직접 붙이지 말고 UseCase/Repository/Coordinator/ActionPolicy 접합부를 먼저 만든다.
- 룩북 공유 메시지는 `ChatViewController`에 전송 로직을 직접 추가하지 않는다. `ShareLookbookContentToChatUseCase`와 socket adapter 경계를 통해 전송한다.
- 공유 카드 렌더링은 `ChatMessageCell`에 큰 레이아웃 분기를 직접 추가하지 않고 `LookbookShareMessageContentView` 같은 하위 view로 분리한다.
- 메시지 타입별 답장/복사/삭제/공지 허용 여부는 `ChatMessageActionPolicy` 같은 순수 정책 객체로 분리하는 방향을 우선한다.

### Cross-feature Routing

- 기능 간 이동은 특정 Feature Coordinator나 `CustomTabBarViewController`에 직접 쌓지 않는다.
- 장기 방향은 `MainTabCoordinator` 또는 `AppContentRouting` 같은 앱 레벨 라우터가 탭 전환과 cross-feature route를 담당하는 것이다.
- 룩북 채팅 공유 MVP에서는 얇은 `AppContentRouting` 계약으로 시작하되, 후속 작업에서 정식 `MainTabCoordinator`로 승격 가능한 형태로 설계한다.
- `CustomTabBarViewController`는 탭 UI와 child 교체만 담당한다.
- `DefaultMainTabBuilder`는 탭 root 생성만 담당한다.
- 예시 계약:

```swift
protocol AppContentRouting: AnyObject {
    func openJoinedChatRoom(roomID: String) async throws
    func openLookbookSharedContent(_ content: LookbookSharedContent) async throws
}
```

- 룩북 공유 완료 후 `이동`은 앱 레벨 라우터가 참여방 탭 전환과 해당 방 열기를 담당한다.
- 채팅방 공유 카드 탭도 앱 레벨 라우터를 통해 룩북 상세로 이동한다. Chat이 LookbookContainer를 직접 참조하지 않는다.

### Profile/Login

- 로그인 진입은 `LoginCompositionRoot`와 `LoginManager`를 중심으로 확인한다.
- 프로필 플로우는 `ProfileCoordinator`, `ProfileCompositionRoot`, `UserProfileDetailCompositionRoot`를 중심으로 확인한다.
- 로그인 성공 후 bootstrapping은 `LoginManager+Bootstrapping.swift`와 `AppCoordinator` 흐름을 함께 본다.

### Firebase Functions

- 외부 export는 `functions/src/index.ts`에 둔다.
- Lookbook import 후보 발견처럼 짧은 작업은 Functions에서 처리할 수 있다.
- URL 파싱, 대량 포스트 생성, 이미지 thumb/detail asset sync처럼 길고 무거운 작업은 Cloud Run worker로 넘기는 방향을 우선한다.
- Cloud Run 전환 후 Functions는 import job 생성 감지와 worker wake-up처럼 짧고 재시도 가능한 orchestration을 담당한다.
- callable payload 검증은 index의 helper를 우선 재사용한다.
- 운영 함수 삭제는 사용자 명시 승인 없이 진행하지 않는다.

## 변경 전 확인 순서

새 기능 또는 큰 수정에서 코드 전체를 먼저 읽지 않는다. 아래 순서를 우선 따른다.

1. `docs/ai/ENTRYPOINTS.md`에서 관련 Feature 진입점을 확인한다.
2. 현재 작업이 있으면 `HANDOFF.md`와 `docs/ai/tasks/{task-name}`을 확인한다.
3. Feature의 CompositionRoot, Container, Coordinator를 먼저 읽는다.
4. 관련 View/ViewModel/UseCase/Repository protocol/implementation을 필요한 범위만 읽는다.
5. 하네스 문서에 없는 반복 지식을 발견하면 작업 후 `docs/ai` 갱신 후보로 정리한다.

## 테스트와 검증 원칙

- 단위 테스트는 `OutPickTests`, UI 테스트는 `OutPickUITests`를 기준으로 한다.
- 테스트 코드를 작성했더라도 매번 자동 실행하지 않는다. 변경 위험도와 사용자 요청에 따라 실행 여부를 정한다.
- 앱 실행으로 쉽게 확인 가능한 단순 happy path UI는 자동 테스트를 과하게 작성하지 않고 수동 QA를 우선한다.
- 서버 실패, 빈 응답, 권한 실패, 일부 API 실패, 비동기, 중복 호출, 캐시, pagination, 상태 전이처럼 사용자가 직접 제어하거나 재현하기 어려운 케이스는 자동 테스트를 우선한다.
- 실제 Firebase 상태를 제어하기 어려운 테스트는 Firebase SDK에 직접 의존하지 않고 fake repository, fake use case, spy 기반으로 검증한다.
- 화면의 시각적 완성도, 터치 흐름, 스크롤, navigation 감각, 실제 기기 실행은 수동 QA 체크리스트로 검증한다.
- 인증, 결제, 데이터 삭제, 보안 규칙, 배포 전 검증처럼 실패 비용이 큰 변경은 실행 검증을 우선한다.
- Firebase Functions 변경은 lint/build 후 배포 흐름을 확인한다.
- Firestore rules/indexes 변경은 관련 workflow와 배포 대상을 확인한다.
