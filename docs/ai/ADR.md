# OutPick ADR

## 목적

중요한 기술 결정과 그 이유를 기록한다.

## 작성 기준

ADR에 기록할 것:

- 기술 스택 선택
- 아키텍처 패턴 선택 또는 변경
- 저장소, 서버, Firebase, Cloud Functions, Firestore rules 관련 중요한 결정
- 사용자 흐름이나 데이터 구조에 큰 영향을 주는 결정
- 앱 실행 중 상태 동기화, 캐시, invalidation stream처럼 여러 화면의 정합성에 영향을 주는 결정
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

## ADR-007: 좋아요 탭은 상호작용 Store 기반으로 앱 실행 중 상태를 반영한다

상태: accepted

결정:

- 좋아요 탭은 브랜드, 시즌, 포스트 섹션을 독립 상태로 관리한다.
- 초기 로드, pull-to-refresh, 앱 재시작은 서버 기준으로 좋아요 목록을 조회한다.
- 앱 실행 중 사용자가 브랜드, 시즌, 포스트 좋아요를 누르거나 취소한 변경은 `LookbookInteractionStore` 계열 store의 invalidation stream으로 즉시 반영한다.
- 브랜드, 시즌, 포스트 store는 좋아요 탭이 새 좋아요와 좋아요 취소를 받을 수 있도록 all-state invalidation stream을 제공한다.
- 포스트 좋아요 목록은 카드 렌더링에 이미지와 상세 이동 데이터가 필요하므로, `LookbookPostInteractionState`는 가능하면 `LookbookPost` 전체를 보존한다.
- 좋아요 탭은 포스트 invalidation을 받았더라도 `LookbookPost`가 없는 state는 목록에 새로 insert하지 않고, 서버 refresh 시 보완한다.
- 좋아요 취소는 optimistic remove를 우선 적용하고, 서버 반영 실패 시 기존 위치로 복구한다.

이유:

- 사용자가 직접 수행한 좋아요/취소 액션은 앱 실행 중 즉시 피드백되어야 한다.
- 매번 좋아요 탭 진입 때 서버 최신화를 강제하면 불필요한 네트워크 요청이 늘고, 사용자가 원한 pull-to-refresh 중심 최신화 정책과 어긋난다.
- 브랜드, 시즌, 포스트가 서로 다른 상태 전파 방식을 가지면 좋아요 탭 정합성이 섹션마다 다르게 보인다.
- 포스트는 브랜드/시즌과 달리 카드 렌더링에 media 정보가 필요하므로, 상태 store에 표시 가능한 `LookbookPost`를 함께 보존해야 새 좋아요를 로컬에서 바로 목록에 추가할 수 있다.

트레이드오프:

- `LookbookInteractionStore`가 포스트 metrics/userState뿐 아니라 표시용 post 객체 일부도 보존하므로 store 책임이 조금 커진다.
- store에 없는 포스트 데이터는 즉시 insert할 수 없고 서버 refresh에 의존한다.
- cached post 객체가 서버 최신 문서와 다를 수 있지만, 사용자가 직접 만든 상호작용 반영에는 충분하고 최신화는 pull-to-refresh와 재시작이 담당한다.
- 좋아요 포스트 목록은 page size와 pagination threshold로 한 번에 합성하는 문서 수를 제한한다.
- 빠른 스크롤, 이미지 로드, prefetch 병목은 MVP 단계에서 과도하게 고도화하지 않고, 실제 사용자 피드백이나 지표가 확인되면 이미지 로딩 경계에서 확장한다.

재검토 조건:

- 좋아요 목록의 로드된 item 배열, store 보존 객체, 표시용 `LookbookPost` 보존 범위가 커져 메모리 부담이 확인되면 `PinAwareInteractionCache` 상한, visible/prefetch pinning, liked list windowing 정책을 재검토한다.
- 다중 기기 실시간 동기화, 외부 변경 즉시 반영, 운영상 서버 기준 강제 최신화가 제품 요구사항이 되면 좋아요 탭 초기 로드와 refresh 정책을 재검토한다.
- 좋아요 포스트 목록의 페이지 단위 post 문서 재조회가 실제 사용에서 latency나 Firestore 읽기 비용 문제로 확인되면 fetch 병렬화, page size 조정, liked post summary denormalization을 검토한다.
- 빠른 위아래 스크롤에서 이미지 요청이 쌓이거나 prefetch가 현재 viewport를 따라가지 못하는 문제가 확인되면 cancellation 실패 UI 방지, prefetch generation cancel, prefetch 범위 제한, priority queue 기반 image request scheduler를 순서대로 검토한다.
- SwiftUI `LazyVGrid` 자체가 대규모 이미지 그리드 성능 병목으로 확인되면 UIKit `UICollectionView` prefetching 또는 검증된 외부 이미지 pipeline 도입을 검토한다.

## ADR-008: URL 기반 시즌 import는 Firestore job queue와 Cloud Run worker로 처리한다

상태: accepted

결정:

- 앱은 브랜드 생성, 시즌 후보 선택, import job 등록, 진행 상태 표시를 담당한다.
- `seasonCandidates`와 `importJobs`는 Firestore에 저장해 앱 종료, 재진입, 실패, 재시도, 중복 방지를 견딜 수 있게 한다.
- URL 기반 시즌 import의 무거운 작업은 Cloud Run worker가 담당한다.
- Cloud Run worker는 queued import job을 가져와 URL 파싱, 이미지 후보 추출, 시즌/포스트 문서 생성, Storage thumb/detail asset sync, Firestore 상태 갱신을 처리한다.
- Firebase Functions는 긴 import 작업을 직접 수행하지 않고, Firestore trigger로 Cloud Run worker를 깨우는 wake-up 역할을 우선 담당한다.
- worker는 batch size, 동시성 제한, retry/backoff, already-synced skip 정책을 내부에서 관리한다.
- 앱은 Firestore의 job 상태와 생성된 시즌/포스트 문서를 구독하거나 재조회해 사용자에게 진행률, 실패, 재시도 진입점을 표시한다.

이유:

- Swift `Task` registry만으로는 앱 종료, 네트워크 실패, Cloud Functions 중단, 다른 기기 재진입을 견딜 수 없다.
- URL 기반 import는 서버 작업이 길고 여러 단계로 나뉘므로, Firestore job 상태가 복구 기준이 되어야 한다.
- 40개 이상의 시즌을 선택한 경우 외부 URL fetch/parse와 이미지 asset sync를 한 번의 callable timeout 안에 모두 끝내기 어렵다.
- Cloud Run은 컨테이너 기반 worker를 배포할 수 있어 URL 파싱, 이미지 처리, retry/backoff, 동시성 제한을 Functions callable보다 명확하게 제어하기 좋다.
- Functions는 wake-up만 담당하면 timeout과 부분 실패 표면을 줄이고, 앱은 기존 Firestore job 흐름을 유지할 수 있다.
- 이미지 asset sync가 중간에 멈추면 grid가 detail/remote fallback에 의존해 성능과 표시 안정성이 나빠질 수 있다.
- 이미 성공한 asset을 재생성하지 않으면 retry 비용과 실패 표면을 줄일 수 있다.

트레이드오프:

- Firestore에 임시 후보/job 문서가 남으므로 정리 정책이 필요하다.
- Cloud Run, Artifact Registry, IAM, 배포 스크립트 같은 운영 요소가 추가된다.
- Functions trigger와 Cloud Run worker 사이의 인증, 중복 wake-up, idempotency를 설계해야 한다.
- worker가 꺼져 있거나 배포 실패 상태면 import job이 queued/pending에 머물 수 있다.
- Cloud Scheduler 또는 Cloud Tasks를 바로 도입하지 않으면 장애 복구 wake-up은 별도 phase에서 보강해야 한다.
- 이미 생성된 asset이 손상된 경우 기본 skip 정책만으로는 복구할 수 없고, 추후 force 재생성 옵션이 필요할 수 있다.

재검토 조건:

- `queued`, `processing`, `pending` job이 반복적으로 장시간 남으면 Cloud Scheduler polling recovery 또는 Cloud Tasks 기반 큐를 도입한다.
- 중복 worker 실행이 Firestore write 충돌이나 중복 Storage upload를 만들면 job lease, generation, idempotency key 정책을 강화한다.
- asset 파일 손상이나 잘못된 thumb/detail 경로가 확인되면 force resync 옵션을 추가한다.
- import job과 season candidate 문서가 과도하게 쌓이면 TTL 또는 완료 후 정리 정책을 도입한다.
- worker 운영 비용, cold start, 처리 latency가 사용자 경험에 영향을 주면 min instances, batch size, 동시성, Cloud Tasks 전환을 재검토한다.
