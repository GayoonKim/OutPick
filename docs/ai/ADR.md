# OutPick ADR

## 목적

중요한 기술 결정과 그 이유를 기록한다.

## 작성 기준

ADR에 기록할 것:

- 기술 스택 선택
- 아키텍처 패턴 선택 또는 변경
- 저장소, 서버, Firebase, Cloud Functions, Firestore rules 관련 중요한 결정
- 사용자 흐름이나 데이터 구조에 큰 영향을 주는 결정
- 기존 결정을 바꾼 이유

ADR에 기록하지 않을 것:

- 단순 UI 문구 변경
- 작은 버그 수정
- 파일명 변경만 있는 작업
- 일회성 로그나 임시 디버깅 메모

## ADR-001: OutPick은 기존 MVVM-C + Repository + UseCase + DI 흐름을 우선한다

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
