# Dark Theme System Plan

## Phase 1. 디자인 시스템 하네스 정리

목표:

- 다크 전용 앱 전환의 요구사항, 색상 정책, 화면 우선순위, 검증 기준을 문서화한다.

상태:

- 진행 중.

변경 범위:

- `docs/ai/tasks/dark-theme-system/design.md`
- `docs/ai/tasks/dark-theme-system/decisions.md`
- `docs/ai/tasks/dark-theme-system/plan.md`
- `docs/ai/tasks/dark-theme-system/progress.md`

완료 기준:

- 포인트 색상 후보와 추천안이 정리되어 있다.
- 무채색 토큰 스케일이 역할 기반으로 정리되어 있다.
- 룩북 이미지 배경 정책이 정리되어 있다.
- 채팅 말풍선 정책이 정리되어 있다.
- phase별 구현 순서와 검증 방법이 정리되어 있다.

검증 방법:

- 문서 검토.
- 코드 수정 없음.

논의 필요 사항:

- 없음.
- 최종 포인트 색상은 Volt Green `#7FDB1E`로 확정.

## Phase 2. 공통 테마 토큰과 앱 appearance 전환

목표:

- 앱을 다크 전용으로 고정하고 UIKit/SwiftUI 공통 색상 토큰을 추가한다.

변경 후보:

- `OutPick/App/AppDelegate.swift`
- `OutPick/Info.plist`
- `OutPick/Assets.xcassets/AccentColor.colorset/Contents.json`
- `OutPick/DesignSystem/OutPickTheme.swift`
- 앱 전역 navigation/tab appearance 진입점

완료 기준:

- 앱이 시스템 설정과 무관하게 다크로 표시된다.
- AccentColor가 최종 포인트 색상으로 설정된다.
- UIKit/SwiftUI 양쪽에서 사용할 수 있는 역할 기반 색상 토큰이 있다.
- 라이트 강제 코드가 다크 정책으로 대체된다.

검증 방법:

- `xcodebuild -scheme OutPick -destination 'generic/platform=iOS Simulator' build`
- 주요 root 화면 수동 실행 확인.

논의 필요 사항:

- 없음.
- 최종 포인트 색상은 Volt Green `#7FDB1E`.
- 테마 파일 위치는 `OutPick/DesignSystem/OutPickTheme.swift`.

## Phase 3. 탭바, 네비게이션, 공통 컴포넌트 정리

목표:

- 앱의 첫 인상과 반복 노출되는 chrome 영역에서 다크 시스템을 안정화한다.

변경 후보:

- `OutPick/App/TabBarController/MainTab/CustomTabBarView.swift`
- `OutPick/App/TabBarController/MainTab/CustomTabBarViewController.swift`
- `OutPick/UINavigationControllerManager/NavigationBarManager.swift`
- `OutPick/Infra/ShareView/CustomNavigationBar/CustomNavigationBarView.swift`
- `OutPick/Infra/Toast/AppToastView.swift`
- 공통 loading/progress/alert view

완료 기준:

- 활성 tab은 포인트 색, 비활성 tab은 보조 무채색으로 표시된다.
- 네비게이션 back/settings/search icon이 다크 배경에서 잘 보인다.
- 공통 toast/loading/alert가 다크 표면과 맞는다.
- `.white`, `.black`, `.gray` 직접 지정이 공통 chrome 영역에서 제거되거나 의도적 예외로 남는다.

검증 방법:

- 로그인 후 하단 탭 전환 수동 QA.
- 네비게이션 push/back 수동 QA.
- 토스트/로딩 표시 수동 QA.

## Phase 4A. 룩북 홈, 좋아요 탭, 공통 이미지 컴포넌트 적용

목표:

- 룩북 홈, 좋아요 탭, 공통 이미지 컴포넌트에 다크 시스템을 적용한다.
- Neutral Frame/Soft Matte/Focus Ring 이미지 정책을 가장 작은 범위에서 검증한다.

변경 후보:

- `OutPick/Features/Lookbook/Views/LookbookHome`
- `OutPick/Features/Lookbook/Views/Liked`
- `OutPick/Features/Lookbook/Views/Shared/LookbookAssetImageView.swift`

완료 기준:

- 룩북 홈과 좋아요 탭 배경, 카드, 텍스트, loading/empty/error 상태가 테마 토큰을 사용한다.
- 공통 이미지 placeholder/loading/failure 상태가 Soft Matte 정책을 따른다.
- 이미지 카드 주변은 Neutral Frame 정책을 따른다.
- 좋아요 메뉴와 좋아요 count는 semantic `like` 토큰을 사용한다.
- 포인트 색은 CTA, 선택, focus, loading/progress에만 제한적으로 사용된다.

검증 방법:

- 룩북 탭 진입, 브랜드 목록 스크롤, 브랜드 카드 tap 수동 QA.
- 좋아요 탭 진입, 브랜드/시즌 가로 카드, 포스트 grid 수동 QA.
- 이미지 로딩/실패/빈 상태는 가능한 범위에서 수동 QA.
- `xcodebuild -scheme OutPick -destination 'generic/platform=iOS Simulator' build`

## Phase 4Nav. 룩북 SwiftUI 공통 네비게이션 바 적용

목표:

- 룩북 SwiftUI 화면군의 native toolbar/Liquid Glass 느낌을 줄이고 채팅 탭의 커스텀 네비게이션 바와 같은 제품 언어로 통일한다.

변경 후보:

- `OutPick/Features/Lookbook/Views/Shared/LookbookNavigationBar.swift`
- `OutPick/Features/Lookbook/Views/LookbookHome/LookbookHomeView.swift`
- `OutPick/Features/Lookbook/Views/Liked/LikedView.swift`
- `OutPick/Features/Lookbook/Views/BrandDetail/BrandDetailView.swift`
- `OutPick/Features/Lookbook/Views/SeasonDetail/SeasonDetailView.swift`
- `OutPick/Features/Lookbook/Views/PostDetail/PostDetailView.swift`

완료 기준:

- 홈/좋아요/브랜드 상세/시즌 상세/포스트 상세가 같은 SwiftUI 공통 네비게이션 바를 사용한다.
- 공통 바의 배경, 버튼 표면, 아이콘, title, 주요 액션은 `OutPickTheme` 토큰을 사용한다.
- 상세 화면의 back action은 `dismiss()`로 연결된다.
- 브랜드 상세의 관리 메뉴는 공통 바 trailing 영역에서 유지된다.
- 생성 플로우, 댓글 sheet, import 관리 sheet의 native toolbar는 Phase 4C 적용 대상으로 남긴다.

검증 방법:

- 홈/좋아요 title과 홈 브랜드 추가 action 수동 QA.
- 브랜드/시즌/포스트 상세 push 후 back button, 가능한 경우 swipe back 수동 QA.
- 브랜드 관리자 계정에서 브랜드 관리 메뉴 수동 QA.
- `xcodebuild -scheme OutPick -destination 'generic/platform=iOS Simulator' build`

## Phase 4B. 룩북 상세 화면 적용

목표:

- 브랜드 상세, 시즌 상세, 포스트 상세 화면에 다크 시스템을 적용한다.

변경 후보:

- `OutPick/Features/Lookbook/Views/BrandDetail`
- `OutPick/Features/Lookbook/Views/SeasonDetail`
- `OutPick/Features/Lookbook/Views/PostDetail`

완료 기준:

- 이미지 카드는 Neutral Frame/Soft Matte/Focus Ring 정책을 따른다.
- 포인트 색은 CTA, 선택, focus, 진행 상태에만 제한적으로 사용된다.
- 좋아요/metrics action은 semantic token을 사용한다.
- 전체 화면 이미지 preview의 black 배경은 media viewer 예외로 유지한다.

검증 방법:

- 룩북 탭 진입, 리스트 스크롤, 브랜드 상세 push, 시즌 상세 push, 포스트 상세 push 수동 QA.
- 밝은 이미지/어두운 이미지/로딩 실패 이미지 수동 QA.

## Phase 4C. 댓글, sheet, 생성 플로우 적용

목표:

- 댓글/대댓글 sheet, 신고/삭제/차단 sheet, 브랜드/시즌 생성 흐름에 다크 시스템을 적용한다.

변경 후보:

- `OutPick/Features/Lookbook/Views/PostDetail/*Comment*`
- `OutPick/Features/Lookbook/Views/PostDetail/CommentReportSheetView.swift`
- `OutPick/Features/Lookbook/Views/PostDetail/CommentDeleteConfirmationSheetView.swift`
- `OutPick/Features/Lookbook/Views/PostDetail/CommentBlockConfirmationSheetView.swift`
- `OutPick/Features/Lookbook/Views/CreateBrand`

완료 기준:

- 댓글/대댓글 sheet, 입력창, sort control이 다크 표면 위계와 맞는다.
- 신고/삭제/차단 의미색이 semantic token으로 명확하게 구분된다.
- 생성 플로우의 베이지/크림 계열 배경은 다크 무채색 토큰으로 대체된다.

검증 방법:

- 댓글 sheet, 답글 sheet, 입력창, 삭제/차단/신고 확인 sheet 수동 QA.
- 브랜드/시즌 생성 플로우 수동 QA.

## Phase 5. 채팅 화면군 적용

목표:

- 채팅 목록, 참여 채팅방, 채팅방, 방 생성/편집/검색/설정, 미디어 갤러리에 다크 시스템을 적용한다.

변경 후보:

- `OutPick/Features/Chat/Controllers`
- `OutPick/Features/Chat/Views`
- `OutPick/Features/Chat/Views/Cell`

완료 기준:

- 말풍선은 무채색 위계로 구분된다.
- 전송/검색/focus/선택 상태만 포인트 색을 사용한다.
- 이미지/비디오 preview overlay는 기존 의미를 유지하되 토큰화된다.
- 방 생성/편집 입력창 텍스트와 placeholder가 다크 배경에서 읽힌다.

검증 방법:

- 채팅 목록/참여 채팅방 탭 수동 QA.
- 채팅방 진입, 메시지 표시, 이미지/비디오 preview, 검색, 설정 화면 수동 QA.
- 긴 메시지, 답장 preview, 업로드 실패/재시도 UI 수동 QA.

## Phase 6. 프로필, 마이페이지, 로그인/부트 적용

목표:

- 나머지 주요 화면의 라이트 색상 누수를 제거한다.

변경 후보:

- `OutPick/Features/Login/Presentation`
- `OutPick/Features/Profile`
- `OutPick/Features/MyPage`

완료 기준:

- 로그인, 부트 로딩, 프로필 생성/상세, 마이페이지가 다크 시스템과 일관된다.
- 마이페이지의 기존 `systemBlue` hero/button은 포인트 색 정책으로 대체된다.
- 프로필 이미지 placeholder와 border가 다크 표면에서 자연스럽다.

검증 방법:

- 로그아웃 후 로그인 화면 수동 QA.
- 프로필 플로우 진입 가능 시 수동 QA.
- 마이페이지 진입, 설정 메뉴, 로그아웃 메뉴 수동 QA.

## Phase 7. 최종 QA와 하드코딩 색상 정리

목표:

- 색상 하드코딩 잔여분, 대비 문제, 라이트 모드 누수를 점검한다.

변경 후보:

- `rg`로 색상 직접 사용 검색 후 필요한 범위 수정.
- 수동 QA 체크리스트 업데이트.
- 반복 재사용될 결정은 `docs/ai/ADR.md` 승격 후보로 제안.

완료 기준:

- 앱 주요 흐름에서 라이트 배경/검정 텍스트 누수가 없다.
- 포인트 색 사용이 과하지 않다.
- 의미색 예외가 일관된다.
- 빌드가 통과한다.

검증 방법:

- `rg` 색상 검색.
- `xcodebuild -scheme OutPick -destination 'generic/platform=iOS Simulator' build`
- 핵심 화면 수동 QA.

## 테스트 설계

변경 유형:

- View 렌더링 변경.
- 앱 appearance 변경.
- 디자인 시스템 토큰 추가.

필요한 테스트:

- 토큰이 순수 계산/변환 로직을 갖지 않는다면 별도 unit test는 우선순위가 낮다.
- 향후 색상 대비 계산 helper를 코드에 넣는 경우에는 해당 helper unit test를 검토한다.

수동 QA 항목:

- 다크 고정 여부.
- 탭바/네비게이션 가독성.
- 룩북 이미지 밝기별 카드 판독성.
- 채팅 말풍선과 입력창 가독성.
- 로그인/프로필/마이페이지 라이트 색 누수.
- 오류/삭제/좋아요 의미색 인지성.

보류할 테스트와 이유:

- 시각 완성도와 화면 감각은 자동 테스트보다 실제 시뮬레이터/기기 수동 QA가 적합하다.
- 데이터/서버/상태 전이 로직 변경이 아니므로 fake repository 기반 테스트는 현재 범위에 필요하지 않다.

테스트 실행 여부:

- 구현 phase에서는 Swift 빌드 검증을 우선 수행한다.
- 수동 QA는 phase별 화면 적용 후 수행한다.
