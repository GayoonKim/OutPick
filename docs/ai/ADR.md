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

## ADR-002: UIKit 앱 수명주기 위에 SwiftUI 기능 화면을 점진 연결한다

상태: accepted

결정:

- 앱 시작, Scene 연결, root routing, 탭 조립은 기존 UIKit 흐름을 유지한다.
- SwiftUI 기능 화면은 필요한 경우 `UIHostingController`로 감싸 UIKit navigation/tab 흐름에 연결한다.
- 기존 UIKit 화면은 무리하게 한 번에 SwiftUI로 이전하지 않는다.

이유:

- 현재 앱은 `SceneDelegate`, `AppCoordinator`, `UINavigationController`, `CustomTabBarViewController` 기반 흐름이 이미 존재한다.
- Lookbook처럼 SwiftUI로 작성된 기능 화면은 기존 앱 수명주기와 탭 구조 안에 점진적으로 연결하는 편이 변경 범위가 작다.
- 레거시 UIKit 화면을 보존하면 새 기능 개발 속도와 기존 안정성을 동시에 지킬 수 있다.

트레이드오프:

- UIKit과 SwiftUI 브릿지 코드가 필요하다.
- 화면 이동 책임이 흐려질 수 있으므로 `CompositionRoot`와 `Coordinator` 경계를 명확히 유지해야 한다.

재검토 조건:

- 특정 Feature 전체가 SwiftUI로 안정화되고 UIKit 브릿지가 오히려 복잡도를 키우면 Feature 단위 전환을 검토한다.

## ADR-003: 공식 하네스와 로컬 하네스를 분리한다

상태: accepted

결정:

- 공식 하네스는 Git에 포함해 프로젝트의 장기 기억으로 관리한다.
- 로컬 하네스는 Git에서 제외해 현재 작업의 단기 기억으로 관리한다.

공식 하네스:

- `AGENTS.md`
- `docs/ai/PRD.md`
- `docs/ai/FLOW.md`
- `docs/ai/SCREEN_SPEC.md`
- `docs/ai/DATA_SCHEMA.md`
- `docs/ai/CODE_ARCHITECTURE.md`
- `docs/ai/ENTRYPOINTS.md`
- `docs/ai/ADR.md`
- `docs/ai/workflows/*`

로컬 하네스:

- `HANDOFF.md`
- `docs/ai/tasks/*`
- `LocalSecrets/*`
- 개인 작업 메모

이유:

- 프로젝트의 안정적인 설계, 아키텍처, 진입점, 기술 결정은 여러 세션과 환경에서 재사용되어야 한다.
- 현재 작업 진행상황, 임시 판단, 미확정 TODO는 개인 작업 맥락에 가까워 Git에 넣으면 잡음이 될 수 있다.

트레이드오프:

- 로컬 하네스는 다른 환경에 자동 공유되지 않는다.
- 대신 공식 문서가 단기 작업 메모로 비대해지는 문제를 줄인다.

재검토 조건:

- 여러 개발자가 같은 장기 작업을 동시에 이어받아야 하면 특정 task 문서를 공식 문서로 승격할 수 있다.

## ADR-004: 새 기능/수정은 하네스 문서를 먼저 보고 필요한 코드만 탐색한다

상태: accepted

결정:

- 새 기능, 큰 수정, 리팩토링은 `docs/ai` 문서를 먼저 확인한다.
- 기능별 진입점은 `docs/ai/ENTRYPOINTS.md`에서 확인한다.
- 코드 구조 원칙은 `docs/ai/CODE_ARCHITECTURE.md`를 따른다.
- 하네스 문서에 정보가 없거나 오래됐을 때만 관련 코드 범위를 탐색한다.
- 반복 재사용될 구조, 진입점, 검증 명령, 기술 결정은 작업 후 하네스 갱신 후보로 정리한다.

이유:

- AI 에이전트가 매번 코드베이스 전체를 다시 읽고 이해하는 비용을 줄이기 위함이다.
- 설계 의도와 코드 진입점을 문서화해 새 작업의 시작 비용을 낮춘다.
- 하네스에 없는 정보를 발견했을 때 다시 하네스에 흡수하면 다음 작업의 탐색 비용이 줄어든다.

트레이드오프:

- 하네스 문서가 오래되면 잘못된 진입점을 안내할 수 있다.
- 그래서 문서와 실제 코드가 충돌하면 실제 코드를 확인하고 문서 갱신 후보로 남긴다.

재검토 조건:

- 하네스 문서가 너무 길어져 매번 읽는 비용이 커지면 문서를 기능별로 분리한다.

## ADR-005: 모호한 제품/기술 결정은 구현 전에 사용자와 논의한다

상태: accepted

결정:

- 요구사항, 완료 기준, 화면 이동, 데이터 구조, API/Firebase Functions 필요 여부, 정책 리스크, 아키텍처 변경이 모호하면 임의로 확정하지 않는다.
- 논의가 필요한 경우 모호한 지점, 가능한 선택지, 장단점, 추천안, 사용자 결정이 필요한 항목을 정리해 사용자에게 묻는다.
- 사용자 결정 전에는 해당 결정에 의존하는 코드 수정, 문서 확정, 배포, 삭제, 마이그레이션을 진행하지 않는다.

이유:

- AI가 제품 방향이나 기술 경계를 임의로 결정하면 빠르게 구현하더라도 실제 목표와 어긋날 수 있다.
- 특히 OutPick은 화면 이동, Firebase/Firestore, 운영 배포, 정책 리스크가 얽힐 수 있어 결정 전 맥락 확인이 중요하다.

트레이드오프:

- 일부 작업은 질문으로 인해 속도가 느려질 수 있다.
- 대신 잘못된 방향으로 구현한 뒤 되돌리는 비용을 줄인다.

재검토 조건:

- 반복적으로 같은 질문이 발생하면 해당 결정 기준을 `docs/ai` 문서나 workflow에 승격한다.

## ADR-006: Firebase/Firestore 운영 변경은 명시 승인과 검증 절차를 우선한다

상태: accepted

결정:

- Firebase Functions, Firestore rules, Firestore indexes 변경은 관련 workflow를 확인한다.
- Functions 변경 시 기본 배포 대상은 `firebase deploy --only functions --project outpick-664ae`다.
- Firestore rules 변경 시 기본 배포 대상은 `firebase deploy --only firestore:rules --project outpick-664ae`다.
- Firestore indexes 변경 시 기본 배포 대상은 `firebase deploy --only firestore:indexes --project outpick-664ae`다.
- 운영 함수 삭제, 데이터 삭제, 마이그레이션, 보안 규칙 완화처럼 되돌리기 어려운 작업은 사용자 명시 승인 없이 진행하지 않는다.

이유:

- Firebase/Firestore 변경은 운영 데이터, 보안, 배포 상태에 직접 영향을 줄 수 있다.
- 특히 원격에만 남아 있는 Function 삭제는 실제 운영 영향이 불명확할 수 있어 자동으로 진행하면 위험하다.

트레이드오프:

- 배포와 삭제 작업에서 추가 확인 단계가 필요하다.
- 대신 운영 장애나 데이터 손상 가능성을 줄인다.

재검토 조건:

- 배포 자동화가 안정화되고 staging/production 분리가 명확해지면 승인 기준과 자동화 범위를 다시 정의한다.
