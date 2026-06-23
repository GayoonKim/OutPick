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

## ADR-009: 앱 미배포 기간에는 불필요한 하위 호환성을 유지하지 않는다

상태: accepted

결정:

- OutPick 앱이 실제 사용자에게 배포되기 전까지는 기존 개발 중 상태 enum, DTO, API payload, Firestore 필드를 새 설계와 병행 지원하지 않는다.
- 더 명확한 데이터 모델과 상태 전이가 확정되면 앱, Functions, worker를 같은 변경 단위에서 전환하고 필요 없는 호환 분기를 제거한다.
- 호환 계층은 실제 배포 앱, 보존할 운영 데이터, 외부 API 소비자, 단계적 rollout 같은 구체적 근거가 있을 때만 추가한다.
- 운영 데이터 삭제나 일괄 마이그레이션은 별도 승인 대상으로 유지한다.

이유:

- 아직 사용자가 의존하는 구버전 앱이 없으므로 가상의 호환성을 유지하면 상태 모델이 이중화되고 분기와 테스트 비용만 늘어난다.
- 출시 전에 앱과 서버 계약을 명확하게 정리하는 편이 이후 운영과 장애 복구에 유리하다.

트레이드오프:

- 개발 중 만들어진 테스트 데이터나 이전 smoke job은 새 DTO로 읽히지 않을 수 있다.
- 실제 배포가 시작되면 동일한 방식으로 즉시 enum이나 필드를 교체할 수 없다.

재검토 조건:

- TestFlight, App Store, 사내 배포 등으로 실제 사용자가 구버전 앱을 사용한다.
- 외부 시스템이나 별도 운영 도구가 OutPick API 또는 Firestore schema를 소비한다.

## ADR-010: OutPick은 다크 전용 디자인 시스템을 사용한다

상태: accepted

결정:

- OutPick 앱은 시스템 라이트/다크 설정을 따르지 않고 다크 appearance로 고정한다.
- 브랜드 포인트 색상은 Volt Green `#7FDB1E` 한 가지로 둔다.
- 포인트 색은 CTA, 활성 tab, 선택 상태, focus ring, 진행 상태처럼 사용자 행동과 현재 상태를 안내하는 곳에 제한적으로 사용한다.
- 기본 UI는 역할 기반 무채색 토큰을 사용한다.
- 테마 토큰은 `OutPick/DesignSystem/OutPickTheme.swift`에 둔다.
- 오류, 삭제, 차단, 신고, 위험 액션, 좋아요처럼 의미가 강한 상태색은 포인트 색의 예외로 허용한다.
- 채팅 말풍선은 포인트 색 fill을 피하고 무채색 표면 위계로 구분한다.
- 룩북 이미지는 Neutral Frame, Soft Matte, Focus Ring 정책을 우선한다.

이유:

- 앱 전반의 색상이 화면별 하드코딩으로 흩어지면 다크 전용 전환 후에도 라이트 색상 누수와 대비 문제가 반복된다.
- Volt Green은 형광 라임 계열의 브랜드 기억점을 유지하면서 Electric Lime `#B7FF2A`나 Signal Lime `#8FEA00`보다 눈부심과 피로감이 낮을 가능성이 높다.
- OutPick은 룩북 이미지가 핵심 콘텐츠이므로 포인트 색은 이미지와 경쟁하지 않고 행동 유도와 상태 표시 역할에 집중해야 한다.
- UIKit과 SwiftUI가 섞인 앱이므로 공통 역할 토큰을 두어 같은 시각 언어를 공유해야 한다.

트레이드오프:

- 사용자가 시스템 라이트 모드를 쓰더라도 앱은 다크로 표시된다.
- Phase 2 직후에는 기존 화면의 하드코딩 색상 때문에 일부 라이트 색상 누수가 남을 수 있다.
- 형광 포인트 색은 넓은 면적에 쓰면 피로감이 생길 수 있어 사용 범위를 계속 제한해야 한다.
- 새 `DesignSystem` 최상위 디렉터리가 생기지만, UI 토큰의 소유권이 명확해진다.

재검토 조건:

- 실제 기기 QA에서 Volt Green의 대비나 피로도가 기대와 다르게 나타난다.
- 룩북 이미지와 포인트 색이 경쟁해 콘텐츠 판독성이 떨어진다.
- App Store 출시 이후 사용자가 시스템 appearance 연동을 강하게 요구한다.
- 채팅/룩북/마이페이지 등 주요 화면군에서 의미색과 포인트 색의 충돌이 반복적으로 확인된다.

## ADR-011: 룩북 채팅 공유는 snapshot 렌더링과 상세 비동기 최신화를 분리한다

상태: accepted

결정:

- 룩북 브랜드/시즌/포스트를 내부 참여 채팅방에 공유할 때 채팅 메시지는 snapshot + reference 구조로 저장한다.
- 채팅방 카드 렌더링은 `sharedContent` snapshot만 사용하고, 브랜드/시즌/포스트 원본을 조회하지 않는다.
- 공유 카드 탭 후 기존 룩북 상세 화면에서 원본을 비동기로 조회해 최신 데이터로 갱신한다.
- 원본 삭제, 권한 없음, 접근 불가 상태는 상세 화면에서 `볼 수 없는 콘텐츠예요` 계열 상태로 처리한다.

이유:

- 채팅의 1차 가치는 실시간 메시징 속도와 안정성이다.
- 룩북 원본 최신성 확인을 채팅방 렌더링 경로에 넣으면 채팅 스크롤/진입 성능과 실패 독립성이 나빠진다.
- 사용자가 채팅방에서 원하는 것은 정확한 최신 브랜드명이 아니라, 대화 맥락 안에서 무엇이 공유됐는지 빠르게 이해하는 것이다.

트레이드오프:

- 채팅 카드의 제목/이미지는 전송 당시 snapshot이라 원본 수정이 즉시 반영되지 않는다.
- 대신 상세 진입 후에는 최신 원본을 표시한다.

핵심 문장:

- 채팅은 채팅답게 빠르게, 룩북은 들어갔을 때 정확하게.

## ADR-012: 룩북 공유 메시지는 새 소켓 이벤트로 전송하고 기존 메시지 스트림으로 수신한다

상태: accepted

결정:

- 공유 전송은 새 소켓 이벤트 `chat:lookbookShare`를 사용한다.
- 서버 broadcast는 기존 `chat message` 이벤트를 유지한다.
- 저장 메시지는 `messageType = lookbookShare`, `sharedContent` map, 선택적 `msg` 텍스트를 가진다.
- 클라이언트 전송 payload의 `msg`는 공유와 함께 보낸 사용자 입력 텍스트이며, 텍스트가 없으면 nil 또는 빈 문자열을 허용한다.
- 서버 저장 문서의 `msg`는 항상 문자열로 채운다. 사용자 텍스트가 없으면 generic 공유 문구를 저장한다.
  - `브랜드를 공유했어요`
  - `시즌을 공유했어요`
  - `포스트를 공유했어요`
- 브랜드명, 시즌명, 썸네일은 `sharedContent` snapshot에만 저장하고 공유 카드 렌더링에서 사용한다.
- 과거 generic preview가 `msg`에 저장된 메시지도 호환성 때문에 정상 표시한다.
- 서버는 `Rooms/{roomID}`를 조회해 방 존재, `isClosed == false`, sender 참여 여부, socket room join 상태, payload shape/size, rate limit을 검증한다.
- 서버는 브랜드/시즌/포스트 원본 존재 여부를 검증하지 않는다. 이는 상세 조회 책임이다.

이유:

- 기존 `chat message`는 텍스트 메시지 검증과 `msg` 중심 preview 흐름을 가진다.
- 구조화 공유 payload를 텍스트 이벤트에 억지로 넣으면 검증과 유지보수 분기가 커진다.
- 수신은 기존 메시지 스트림을 재사용하면 클라이언트의 실시간 수신/저장/정렬 흐름을 크게 바꾸지 않아도 된다.
- `msg`를 generic preview로 고정하면 추후 공유와 함께 보낼 텍스트를 자연스럽게 담기 어렵다.
- 서버 저장 시 `msg`를 비워두지 않으면 기존 배너, 푸시, 참여방 목록, 답장 preview 경로를 단순하게 유지할 수 있다.
- legacy/로컬 실패 메시지처럼 `msg`가 비어 있는 예외에서는 클라이언트가 `sharedContent.contentType` 기반 fallback preview를 계산한다.

트레이드오프:

- 소켓 서버에 새 이벤트와 검증 로직을 추가해야 한다.
- 운영 소켓 서버 배포 경로와 secret 주입 방식은 구현 전 확인해야 한다.

## ADR-013: 룩북 채팅 공유는 Chat 접합부를 먼저 만들고 거대 ViewController에 직접 붙이지 않는다

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

## ADR-014: 운영 소켓 서버의 Firebase Admin 키는 커밋하지 않는다

상태: accepted

결정:

- `Socket/*firebase-adminsdk*.json` 같은 Firebase Admin 서비스 계정 키는 커밋하지 않는다.
- `.gitignore`에 `**/*firebase-adminsdk*.json`, `Socket/node_modules/`를 보강한다.
- 소켓 서버는 서비스 계정 JSON 파일명을 직접 require하지 않고 `FIREBASE_SERVICE_ACCOUNT_JSON` env secret 또는 Application Default Credentials로 초기화한다.
- 로컬 실행은 `GOOGLE_APPLICATION_CREDENTIALS`가 가리키는 ignored local secret 파일을 사용한다.

이유:

- Firebase Admin 서비스 계정 JSON에는 private key가 포함된다.
- 키가 저장소에 올라가면 운영 데이터 접근 권한이 노출될 수 있다.

트레이드오프:

- 로컬 실행과 배포 환경 설정이 별도로 필요하다.
- 대신 저장소에서 비밀정보를 제거해 보안 리스크를 낮춘다.

## ADR-015: 여러 Phase 작업은 병렬 조사와 충돌 기준 구현 분기를 사용한다

상태: accepted

결정:

- 새 기능, 큰 수정, 리팩토링처럼 여러 phase로 나뉘는 작업은 메인 스레드를 총괄 컨텍스트로 유지한다.
- 메인 스레드는 phase 상태, 설계 쟁점, 사용자 결정, 통합 검증, 문서 갱신 기준을 관리한다.
- 구현 전에는 다음 phase들의 예상 변경 파일, 의존성, DI/Container/Coordinator 영향, 데이터/API 계약, 충돌 가능성을 먼저 점검한다.
- 코드 수정이 필요 없는 조사, 중복 지점 탐색, 설계 쟁점 후보 발굴, 테스트 범위 조사는 서브 에이전트로 병렬화할 수 있다.
- 설계 쟁점의 최종 결정은 메인 스레드에서 사용자와 논의해 확정한다.
- 구현은 파일 충돌 가능성, service/protocol 경계 변경, 데이터/API 계약 의존성, DI/Container/Coordinator 영향 범위를 기준으로 순차 진행 또는 별도 스레드 병렬 진행을 결정한다.
- 같은 파일, 같은 service/protocol 경계, 같은 DI 조립부를 건드릴 가능성이 있거나 한 phase 결과가 다른 phase의 전제 조건이면 병렬 구현하지 않고 메인 스레드에서 순차 진행한다.
- 별도 스레드에서 구현한 작업은 메인 스레드에서 최종 통합, 검증, 문서 갱신 기준을 관리한다.

이유:

- 여러 phase를 무조건 순차 진행하면 조사와 설계 쟁점 발굴 시간이 길어진다.
- 반대로 구현까지 무조건 병렬화하면 같은 파일이나 DI 조립부를 동시에 수정해 merge 충돌, 설계 중복, 책임 경계 불일치가 생기기 쉽다.
- 조사와 설계 쟁점 발굴은 병렬화하고, 구현은 충돌 가능성과 의존성 기준으로 분기하면 속도와 안정성의 균형을 잡을 수 있다.

트레이드오프:

- 메인 스레드가 조사 결과를 통합하고 구현 분기 여부를 판단해야 하므로 운영 절차가 조금 늘어난다.
- 별도 스레드 구현은 최종 통합 검증 비용이 추가된다.
- 대신 큰 리팩토링에서 설계 결정의 단일 출처를 유지하면서 독립적인 조사와 구현을 병렬화할 수 있다.

재검토 조건:

- 서브 에이전트 조사 결과가 자주 중복되거나 품질이 낮아 메인 스레드 통합 비용이 더 커진다.
- 별도 스레드 구현의 충돌 해결 비용이 순차 진행보다 반복적으로 커진다.
- phase 간 의존성이 낮은 작업이 많아져 더 공격적인 병렬 구현 기준이 필요해진다.
