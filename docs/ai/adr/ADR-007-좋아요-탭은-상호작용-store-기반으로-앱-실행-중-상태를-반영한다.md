# ADR-007: 좋아요 탭은 상호작용 Store 기반으로 앱 실행 중 상태를 반영한다


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

