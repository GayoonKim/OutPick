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

## 주요 디렉터리

- `OutPick/App`: 앱 진입점, AppCoordinator, SceneDelegate, AppDelegate, 탭 조립 흐름.
- `OutPick/Features`: 기능별 화면, ViewModel, Coordinator, CompositionRoot, Container, Repository, UseCase.
- `OutPick/Infra`: 공통 인프라, 네트워크, 미디어, 알림, 토스트, 키체인 등.
- `OutPickTests`: 단위 테스트.
- `OutPickUITests`: UI 테스트.
- `functions/src`: Firebase Functions TypeScript 코드.
- `firestore.rules`: Firestore 보안 규칙.
- `firestore.indexes.json`: Firestore 인덱스.

## 기능별 구조 메모

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

### Profile/Login

- 로그인 진입은 `LoginCompositionRoot`와 `LoginManager`를 중심으로 확인한다.
- 프로필 플로우는 `ProfileCoordinator`, `ProfileCompositionRoot`, `UserProfileDetailCompositionRoot`를 중심으로 확인한다.
- 로그인 성공 후 bootstrapping은 `LoginManager+Bootstrapping.swift`와 `AppCoordinator` 흐름을 함께 본다.

### Firebase Functions

- 외부 export는 `functions/src/index.ts`에 둔다.
- Lookbook import처럼 길어진 작업은 worker/materializer/asset sync/candidate discovery 파일로 분리한다.
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
