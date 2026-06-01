# OutPick Code Architecture

## 목적

OutPick의 코드 구조와 계층별 책임을 AI 에이전트가 매번 코드 전체를 다시 읽지 않고 파악하기 위한 문서다.

## 기본 구조

OutPick은 기존 MVVM-C + Repository + UseCase + DI 흐름을 우선 따른다.

## 계층별 책임

- View: 화면 렌더링과 사용자 이벤트 전달에 집중한다.
- ViewModel: 화면 상태를 관리하고 UseCase를 호출한다.
- UseCase: 기능 단위 비즈니스 흐름을 담당한다.
- Repository: Firebase, Cloud Functions, Firestore, 네트워크, 저장소 접근을 숨긴다.
- Container: Feature 내부 Repository, UseCase, Store, ViewModel, Coordinator, 화면 factory를 생성하고 보관한다.
- CompositionRoot: 앱, 탭, Feature 진입점 조립과 UIKit/SwiftUI 브릿지를 담당한다.
- Coordinator: push, sheet, fullScreenCover, UIKit present/dismiss 등 화면 전환과 사용자 흐름 제어를 담당한다.

## 구현 원칙

- View는 Repository, UseCase, Firebase, Cloud Functions, Firestore SDK를 직접 생성하지 않는다.
- ViewModel은 생성자 주입으로 UseCase, Repository, Store를 받는다.
- 서버 상태 변경은 가능한 Repository 또는 Cloud Functions 계층 뒤로 숨긴다.
- 화면 이동 책임이 View나 ViewModel에 흩어지면 Coordinator로 모으는 방향을 우선 검토한다.
- 불필요한 추상화와 요청 범위 밖 리팩토링은 피한다.

## 주요 디렉터리

- `OutPick/App`: 앱 진입점, AppCoordinator, SceneDelegate, AppDelegate, 탭 조립 흐름.
- `OutPick/Features`: 기능별 화면, ViewModel, Coordinator, CompositionRoot, Container, Repository, UseCase.
- `OutPick/Infra`: 공통 인프라, 네트워크, 미디어, 알림, 토스트, 키체인 등.
- `OutPickTests`: 단위 테스트.
- `OutPickUITests`: UI 테스트.
- `functions/src`: Firebase Functions TypeScript 코드.
- `firestore.rules`: Firestore 보안 규칙.
- `firestore.indexes.json`: Firestore 인덱스.
