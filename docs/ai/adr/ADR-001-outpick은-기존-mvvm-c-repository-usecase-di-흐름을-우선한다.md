# ADR-001: OutPick은 기존 MVVM-C + Repository + UseCase + DI 흐름을 우선한다


상태: accepted

결정:

- View, ViewModel, UseCase, Repository, Container, CompositionRoot, Coordinator 책임을 분리한다.
- View는 Firebase, Cloud Functions, Firestore SDK를 직접 생성하지 않는다.
- 화면 전환 책임은 Coordinator에 모으는 방향을 우선한다.

이유:

- 기능이 커져도 화면 렌더링, 비즈니스 흐름, 데이터 접근, 화면 이동 책임을 분리하기 위함이다.
- AI 에이전트가 새 기능을 추가할 때 기존 코드 경계를 유지하도록 만들기 위함이다.

트레이드오프:

- 작은 기능도 파일 수가 늘어날 수 있다.
- 대신 테스트 가능성과 변경 범위 예측 가능성이 좋아진다.

