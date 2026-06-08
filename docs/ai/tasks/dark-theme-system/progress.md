# Dark Theme System Progress

## 1. 최종 목표

OutPick을 다크 모드 전용 앱으로 전환하고, 형광 포인트 색상 한 가지와 무채색 스케일을 중심으로 UIKit/SwiftUI 화면의 시각 시스템을 정리한다.

성공 기준:

- 앱이 시스템 설정과 무관하게 다크 모드로 표시된다.
- 공통 색상 토큰이 UIKit/SwiftUI 양쪽에서 재사용된다.
- 포인트 색은 CTA/선택/focus/진행 상태에 제한적으로 사용된다.
- 오류/삭제/차단/신고/좋아요 등 의미색 예외가 일관되게 적용된다.
- 룩북 이미지는 Neutral Frame/Soft Matte/Focus Ring 정책으로 읽기 좋게 표시된다.
- 채팅 말풍선은 무채색 위계로 정리된다.
- 주요 화면에서 라이트 배경/검정 텍스트 누수가 없다.

## 2. 완료한 작업

- 기존 문서 확인:
  - `docs/ai/PRD.md`
  - `docs/ai/SCREEN_SPEC.md`
  - `docs/ai/FLOW.md`
  - `docs/ai/CODE_ARCHITECTURE.md`
  - `docs/ai/ENTRYPOINTS.md`
  - `docs/ai/ADR.md`
  - `HANDOFF.md`
  - `docs/ai/tasks/active.md`
- 현재 코드 색상 상태 확인:
  - `AppDelegate`에서 라이트 모드 강제 확인.
  - `AccentColor`가 비어 있음을 확인.
  - UIKit/SwiftUI 전반에 `.white`, `.black`, `.gray`, `.systemBlue`, `.red`, 베이지 계열 직접 지정이 많음을 확인.
- 사용자와 초기 결정 정리:
  - 포인트 컬러는 형광색 계열을 선호.
  - 초기 추천이던 Electric Lime `#B7FF2A`는 너무 밝을 수 있어 더 어두운 Signal Lime `#8FEA00`을 1순위 추천으로 조정.
  - 최종 포인트 컬러는 Signal Lime보다 조금 더 어둡고 안정적인 Volt Green `#7FDB1E`로 확정.
  - 의미색 예외는 허용.
  - 화면 우선순위는 공통 토큰/appearance, 탭/네비게이션, 룩북, 채팅, 프로필/마이페이지, 로그인/부트 순서로 진행.
  - active task 포인터는 `dark-theme-system`으로 전환하기로 결정.
  - 테마 파일 위치는 `OutPick/DesignSystem/OutPickTheme.swift`로 결정.
  - 다음 구현은 Phase 2만 진행하기로 결정.
  - 다크 전용 디자인 시스템 결정은 Phase 2 전 ADR에 기록하기로 결정.
  - 룩북 이미지 배경은 가독성 우선 추천안을 문서화.
  - 채팅 말풍선은 무채색 위계로 정리.
  - 접근성은 WCAG AA 수준을 목표로 진행.
- 설계 문서 생성:
  - `docs/ai/tasks/dark-theme-system/design.md`
  - `docs/ai/tasks/dark-theme-system/decisions.md`
  - `docs/ai/tasks/dark-theme-system/plan.md`
  - `docs/ai/tasks/dark-theme-system/progress.md`
- active 포인터와 ADR 반영:
  - `HANDOFF.md`와 `docs/ai/tasks/active.md`를 `dark-theme-system` 기준으로 전환.
  - `docs/ai/ADR.md`에 ADR-010 다크 전용 디자인 시스템 결정을 추가.
- Phase 2 공통 테마 토큰과 앱 appearance 전환:
  - `OutPick/DesignSystem/OutPickTheme.swift`를 추가해 UIKit/SwiftUI 공통 역할 색상 토큰을 정의했다.
  - 브랜드 포인트 색상을 Volt Green `#7FDB1E`로 정의했다.
  - `OutPick/Assets.xcassets/AccentColor.colorset/Contents.json`에 Volt Green 값을 설정했다.
  - `OutPick/App/AppDelegate.swift`의 라이트 강제 설정을 `OutPickTheme.applyAppAppearance()` 호출로 대체했다.
  - `OutPick/Info.plist`에 `UIUserInterfaceStyle = Dark`를 추가했다.
  - `UINavigationBar`/`UITabBar` 기본 appearance와 앱 tint를 다크 토큰 기준으로 설정했다.
- Phase 3 탭바, 네비게이션, 공통 컴포넌트 정리:
  - `CustomTabBarView`의 배경, 활성 tab, 비활성 tab 색상을 테마 토큰으로 교체했다.
  - `CustomTabBarViewController` root 배경을 `backgroundBase`로 교체했다.
  - `NavigationBarManager` 기본 back button tint를 Volt Green accent로 교체했다.
  - `CustomNavigationBarView`의 검색 아이콘, 검색 입력창, 취소 버튼, nav 버튼, title/subtitle, 배경 색상을 테마 토큰으로 교체했다.
  - `AppToastView`의 icon/text/background/border/shadow 색상을 SwiftUI 테마 토큰으로 교체했다.
  - `CircularProgressHUD`, `LoadingIndicator`, `BackgroundDecorationView`의 공통 진행/배경 색상을 테마 토큰으로 교체했다.
  - Phase 3 대상 경로에서 `.white`, `.black`, `.gray`, `systemBackground`, `secondarySystemBackground` 등 직접 색상 검색을 수행했고, 남은 결과는 문자열 처리나 `label` 변수명 같은 false positive로 확인했다.
- Phase 4 구현 전 결정 정리:
  - Phase 4는 4A/4B/4C로 나누어 진행한다.
  - Phase 4A는 룩북 홈, 좋아요 탭, 공통 이미지 컴포넌트를 대상으로 한다.
  - 의미색은 `OutPickTheme` semantic token으로 추가한다.
  - 전체 화면 이미지 preview의 black 배경은 media viewer 예외로 둔다.
  - 생성 플로우의 베이지/크림 계열은 다크 무채색 토큰으로 대체한다.
- Phase 4A 룩북 홈, 좋아요 탭, 공통 이미지 컴포넌트 정리:
  - `OutPickTheme`에 `like`, `destructive`, `warning`, `success` semantic token을 추가했다.
  - `LookbookAssetImageView`의 placeholder/loading/failure/border 색상을 테마 토큰으로 교체했다.
  - `BrandRowView`의 카드 표면, border, title, 좋아요 chip, 이미지 fallback 색상을 테마 토큰으로 교체했다.
  - `LookbookHomeView`의 loading/failure/navigation/list/background 색상을 테마 토큰으로 교체했다.
  - `LikedView`와 좋아요 카드 3종의 background, menu chip, loading/failure/empty/header/status 색상을 테마 토큰으로 교체했다.
  - iOS 15.6 호환성을 위해 `scrollContentBackground(.hidden)`은 iOS 16 이상에서만 적용되도록 로컬 View extension으로 감쌌다.
  - Phase 4A 대상 경로에서 직접 색상 검색을 수행했고, 남은 결과는 테마 토큰 사용 또는 `primaryPath`/`secondaryPath` 같은 변수명 false positive로 확인했다.
- Phase 4Nav 룩북 SwiftUI 공통 네비게이션 바 적용:
  - `LookbookNavigationBar`, `LookbookNavigationIconButton`, `LookbookNavigationTextButton`을 추가했다.
  - 공통 바는 `safeAreaInset(edge: .top)`으로 표시하고 native navigation bar는 숨긴다.
  - 홈 화면은 `OutPick` title과 `+ 브랜드` action을 공통 바로 옮겼다.
  - 좋아요 탭은 `좋아요` title을 공통 바로 옮겼다.
  - 브랜드 상세는 back button과 브랜드 관리 menu를 공통 바로 옮겼다.
  - 시즌 상세와 포스트 상세는 back button을 공통 바로 옮겼다.
  - 룩북 공통 바 title typography는 채팅 `CustomNavigationBarView`와 시각적으로 맞도록 18pt semibold, `textPrimary`로 보정했다.
  - 좋아요 탭의 상단 title은 탭 이름 대신 `OutPick` 브랜드 title로 통일했다.
  - 채팅방 추가 버튼과 브랜드 추가 버튼은 심볼 렌더링 차이를 피하기 위해 icon 없이 텍스트 전용 CTA로 통일했다.
  - 두 생성 CTA의 title size/weight, height, horizontal inset, accent 색상을 같은 수치 기준으로 맞췄다.
  - 생성 플로우, 댓글 sheet, import 관리 sheet의 native toolbar는 Phase 4C 대상이라 유지했다.
- Phase 4B 룩북 상세 화면군 색상 토큰화:
  - 브랜드 상세, 시즌 상세, 포스트 상세의 본문 화면을 `OutPickTheme` 토큰 기준으로 정리했다.
  - 브랜드 상세 header/list/grid의 배경, title, 설명, loading, empty/error, border, 공식 사이트 CTA 색상을 다크 무채색과 accent 토큰으로 교체했다.
  - 브랜드/시즌 좋아요 상태는 semantic `like` 토큰을 사용하고, 비활성 상태는 neutral icon/text 토큰을 사용하도록 맞췄다.
  - 시즌 상세와 포스트 상세의 기존 크림/베이지 gradient 배경을 제거하고 `backgroundBase` 중심의 다크 표면으로 통일했다.
  - 포스트 상세 metric card는 좋아요 `like`, 저장 `accent`, 댓글 neutral 정책으로 정리했다.
  - 이미지 overlay의 black/white와 전체 화면 zoom preview의 black 배경은 이미지 가독성/media viewer 예외로 유지했다.
- Phase 4Nav/4B 후속 보정:
  - 브랜드 상세, 시즌 상세, 포스트 상세의 공통 navigation title을 제거하고 back/action 중심의 상단 바로 정리했다.
  - 룩북 공통 navigation icon button의 기본 foreground를 accent로 맞춰 브랜드 추가 CTA, 뒤로가기, 브랜드 관리 action의 버튼 색상 위계를 통일했다.
  - 브랜드 관리 menu label은 공통 `LookbookNavigationIconLabel`을 사용하도록 정리했다.
  - 홈 브랜드 row의 좋아요 수는 상세 좋아요 변경에 즉시 동기화하지 않고, pull-to-refresh 또는 앱 재시작 시 서버 snapshot 기준으로 최신화하는 정책으로 정했다.
- Phase 4C 구현 전 결정 정리:
  - 댓글/sheet/생성/import 화면은 native `NavigationView`/`Form` 구조를 유지하고 색상만 다크 토큰화한다.
  - 댓글 sheet 닫기 버튼은 룩북 공통 navigation icon button과 같은 `accent on surfaceBase` 규칙을 따른다.
  - 댓글 카드 배경은 `surfaceBase`/`surfaceElevated`, border는 `borderSubtle`, text는 `textPrimary`/`textSecondary` 위계로 정리한다.
  - 댓글 좋아요도 semantic `like` 토큰을 사용한다.
  - 신고/삭제/차단 실행 CTA는 semantic `destructive`, 실패/부분 실패/주의 상태는 `warning`을 사용한다.
  - import job 상태색은 완료 `success`, 일부 실패/실패 `warning`, 취소 `textSecondary`, 대기/처리 중 `accent`로 정리한다.
  - 생성 플로우의 베이지/크림 gradient는 제거하고 `backgroundBase`/`surfaceBase`/`surfaceElevated` 중심으로 전환한다.
  - 시즌 import 진행 중에는 “가져올 시즌 선택” 문구를 숨기고 “시즌을 불러오는 중입니다”와 전체 진행률/완료/실패 count를 중심으로 표시한다.
  - 포스트 저장 기능은 Phase 4C에서 UI만 제거하고, 내부 도메인/서버 save cleanup은 별도 phase로 미룬다.
- Phase 4B 수동 QA:
  - 사용자가 브랜드 상세, 시즌 상세, 포스트 상세의 Phase 4B 수동 QA를 완료했다.
- Phase 4C 댓글, sheet, 생성/import 플로우 적용:
  - 댓글 sheet, 답글 sheet, 댓글 카드, 댓글 입력창을 `OutPickTheme` 토큰 기준으로 정리했다.
  - 댓글 좋아요는 semantic `like`, 댓글 sheet sort 선택은 accent, 일반/보조 텍스트는 neutral 토큰을 사용하도록 맞췄다.
  - 신고/삭제/차단 confirmation sheet의 destructive CTA, neutral 취소 버튼, 입력/설명 영역을 다크 토큰으로 정리했다.
  - 브랜드 생성 플로우의 베이지/크림 배경과 검정 CTA를 `backgroundBase`, `surfaceBase`, `surfaceElevated`, `accent` 중심으로 교체했다.
  - 시즌 후보 선택/가져오기 진행 화면은 상태별 header 문구를 분리해, import 진행 중에는 “시즌을 불러오는 중입니다”와 전체 진행률을 중심으로 표시한다.
  - 시즌 추가 Form, URL import Form, import 관리 화면의 tint/background/status color를 다크 토큰으로 정리했다.
  - 포스트 상세 metric card에서 저장 버튼 UI를 제거했다. 내부 save 도메인/서버 cleanup은 후속 phase 대상으로 남긴다.

## 3. 아직 남은 작업

1. Phase 3 수동 QA

   - 실제 시뮬레이터에서 로그인/메인 탭 진입 후 탭바 활성/비활성 색상을 확인한다.
   - 커스텀 네비게이션 바가 있는 채팅/마이페이지/검색 화면에서 icon/title/input 가독성을 확인한다.
   - toast/loading/progress가 다크 표면에서 잘 보이는지 확인한다.

2. Phase 4A 수동 QA

   - 룩북 홈의 list 배경, brand row 카드, 이미지 placeholder/failure, 좋아요 chip 대비를 확인한다.
   - 좋아요 탭의 brand/season/post 카드와 filter/menu chip의 다크 표면 대비를 확인한다.
   - 이미지 로딩 중/실패/비어 있음 상태가 Soft Matte 정책대로 튀지 않고 읽히는지 확인한다.

3. Phase 4Nav 수동 QA

   - 룩북 홈/좋아요 탭의 title과 상단 여백이 채팅 탭 custom navigation bar와 어색하지 않은지 확인한다.
   - 홈의 `브랜드 추가` action이 정상 동작하는지 확인한다.
   - 브랜드/시즌/포스트 상세 push 후 title 없이 back button만 표시되고, 가능한 경우 swipe back 동작도 확인한다.
   - 브랜드 관리자 계정에서 브랜드 관리 menu가 accent icon button으로 표시되고, `시즌 추가`/`가져오기 현황`이 정상 동작하는지 확인한다.

4. Git 추적 상태 정리

   - `OutPick/App/AppDelegate.swift`, `OutPick/Info.plist`, `HANDOFF.md`, `docs/ai/tasks/*`는 현재 ignore/exclude 대상이라 `git status`에 기본 노출되지 않는다.
   - 커밋 시 실제 포함 범위를 사용자가 명시해야 한다.

5. Phase 4C 수동 QA

   - 댓글 sheet/답글 sheet의 header, 닫기 버튼, sort control, 댓글 카드, 입력창 대비를 확인한다.
   - 댓글 작성, 댓글 좋아요, 답글 열기, profile sheet 열기/닫기가 기존대로 동작하는지 확인한다.
   - 신고/삭제/차단 sheet의 destructive CTA와 취소 버튼 위계가 명확한지 확인한다.
   - 브랜드 생성 플로우의 form, logo picker, 생성 중/완료/시즌 탐색/후보 선택/가져오기 진행 화면이 다크 표면으로 자연스럽게 이어지는지 확인한다.
   - 시즌 추가 Form, URL import Form, import 관리 화면의 Form/List 배경과 status color가 어색하지 않은지 확인한다.
   - 포스트 상세 metric card에 저장 버튼이 보이지 않고, 좋아요/댓글만 남는지 확인한다.

## 4. 변경한 파일 목록

```text
docs/ai/tasks/dark-theme-system/design.md
docs/ai/tasks/dark-theme-system/decisions.md
docs/ai/tasks/dark-theme-system/plan.md
docs/ai/tasks/dark-theme-system/progress.md
docs/ai/tasks/active.md
HANDOFF.md
docs/ai/ADR.md
OutPick/DesignSystem/OutPickTheme.swift
OutPick/Assets.xcassets/AccentColor.colorset/Contents.json
OutPick/App/AppDelegate.swift
OutPick/Info.plist
OutPick/App/TabBarController/MainTab/CustomTabBarView.swift
OutPick/App/TabBarController/MainTab/CustomTabBarViewController.swift
OutPick/UINavigationControllerManager/NavigationBarManager.swift
OutPick/Infra/ShareView/CustomNavigationBar/CustomNavigationBarView.swift
OutPick/Infra/Toast/AppToastView.swift
OutPick/Infra/ShareView/CircularProgressView/CircularProgressView.swift
OutPick/Infra/ShareView/LoadingIndicator/LoadingIndicator.swift
OutPick/Infra/ShareView/BackgroundDeco/BackgroundDecorationView.swift
OutPick/Features/Lookbook/Views/Shared/LookbookAssetImageView.swift
OutPick/Features/Lookbook/Views/LookbookHome/BrandRowView.swift
OutPick/Features/Lookbook/Views/LookbookHome/LookbookHomeView.swift
OutPick/Features/Lookbook/Views/Liked/LikedView.swift
OutPick/Features/Lookbook/Views/Liked/LikedBrandCardView.swift
OutPick/Features/Lookbook/Views/Liked/LikedSeasonCardView.swift
OutPick/Features/Lookbook/Views/Liked/LikedPostCardView.swift
OutPick/Features/Lookbook/Views/Shared/LookbookNavigationBar.swift
OutPick/Features/Lookbook/Views/BrandDetail/BrandDetailView.swift
OutPick/Features/Lookbook/Views/BrandDetail/BrandDetailHeaderView.swift
OutPick/Features/Lookbook/Views/BrandDetail/BrandDetailSeasonsGridView.swift
OutPick/Features/Lookbook/Views/BrandDetail/BrandDetailSeasonGridItemView.swift
OutPick/Features/Lookbook/Views/SeasonDetail/SeasonDetailView.swift
OutPick/Features/Lookbook/Views/SeasonDetail/SeasonDetailHeaderCardView.swift
OutPick/Features/Lookbook/Views/PostDetail/PostDetailView.swift
OutPick/Features/Lookbook/Views/PostDetail/PostDetailMetricsCardView.swift
OutPick/Features/Lookbook/Views/PostDetail/PostCommentsSheetView.swift
OutPick/Features/Lookbook/Views/PostDetail/PostCommentRepliesSheetView.swift
OutPick/Features/Lookbook/Views/PostDetail/PostCommentCardView.swift
OutPick/Features/Lookbook/Views/PostDetail/PostCommentInputBarView.swift
OutPick/Features/Lookbook/Views/PostDetail/CommentReportSheetView.swift
OutPick/Features/Lookbook/Views/PostDetail/CommentDeleteConfirmationSheetView.swift
OutPick/Features/Lookbook/Views/PostDetail/CommentBlockConfirmationSheetView.swift
OutPick/Features/Lookbook/Views/PostDetail/CommentSafetyAvatarView.swift
OutPick/Features/Lookbook/Views/CreateBrand/brand/CreateBrandFlowView.swift
OutPick/Features/Lookbook/Views/CreateBrand/brand/CreateBrandView.swift
OutPick/Features/Lookbook/Views/CreateBrand/brand/CreateBrandFinishingView.swift
OutPick/Features/Lookbook/Views/CreateBrand/brand/CreateBrandCompletedView.swift
OutPick/Features/Lookbook/Views/CreateBrand/brand/CreateBrandDiscoveringView.swift
OutPick/Features/Lookbook/Views/CreateBrand/brand/CreateBrandCandidateSelectionView.swift
OutPick/Features/Lookbook/Views/CreateBrand/brand/SeasonCandidateCoverView.swift
OutPick/Features/Lookbook/Views/CreateBrand/season/CreateSeasonView.swift
OutPick/Features/Lookbook/Views/CreateBrand/season/CreateSeasonFromURLView.swift
OutPick/Features/Lookbook/Views/BrandDetail/SeasonImportManagementView.swift
```

## 5. 검증 상태

- `jq empty OutPick/Assets.xcassets/AccentColor.colorset/Contents.json` 통과.
- `plutil -lint OutPick/Info.plist` 통과.
- `xcodebuild -scheme OutPick -destination 'generic/platform=iOS Simulator' build` 통과.
- `git diff --check` 통과.
- Phase 3 대상 경로 색상 검색 통과:
  - `OutPick/App/TabBarController/MainTab`
  - `OutPick/UINavigationControllerManager`
  - `OutPick/Infra/ShareView`
  - `OutPick/Infra/Toast`
- Phase 4A 대상 경로 색상 검색 통과:
  - `OutPick/Features/Lookbook/Views/LookbookHome`
  - `OutPick/Features/Lookbook/Views/Liked`
  - `OutPick/Features/Lookbook/Views/Shared`
- Phase 4Nav 대상 화면 native toolbar 검색:
  - 홈/좋아요/브랜드 상세/시즌 상세/포스트 상세의 native title/toolbar는 공통 바로 대체했다.
  - 생성 플로우, 댓글 sheet, import 관리 sheet의 native toolbar와 직접 색상은 Phase 4C 대상으로 남아 있다.
- Phase 4B 대상 경로 색상 검색 통과:
  - 브랜드 상세, 시즌 상세, 포스트 상세 본문 화면에서 라이트 배경/검정 텍스트 직접 지정 누수를 정리했다.
  - 남은 `Color.black`, `.white`, `Color.clear`는 이미지 overlay, media viewer, 투명 placeholder 예외로 확인했다.
- Phase 4C 대상 경로 색상 검색 통과:
  - 댓글 sheet/card/input/safety sheet, 생성 플로우, 시즌 추가/URL import/import 관리 화면에서 라이트 배경/검정 텍스트 직접 지정 누수를 정리했다.
  - 남은 `Color.black`, `.white`는 `PostImagePreviewView` media viewer 예외로 확인했다.
  - `whitespacesAndNewlines` 검색 결과는 문자열 처리 false positive로 확인했다.
- Phase 4C 수동 QA 후속 수정:
  - 시즌 import 진행 화면에서 헤더와 진행 카드에 유사한 안내 문구가 중복 노출되던 문제를 정리했다.
  - 시즌 import 진행 화면의 제목, 설명, 진행률을 중앙 정렬 상태 블록으로 모아 진행 중 맥락과 진행 상황이 한 번에 읽히도록 조정했다.
  - 사용자 차단 확인 sheet에서 프로필 아바타가 상단 drag indicator와 겹치지 않도록 sheet 높이, 상단 여백, 아바타 크기, 텍스트 줄바꿈을 조정했다.
  - 댓글 삭제 확인 sheet에서 일부 기기에서 안내 문구가 잘리는 문제를 줄이기 위해 sheet 높이, 내부 간격, 아바타 크기, 텍스트 영역 우선순위를 조정했다.
- 빌드 중 기존 경고가 남아 있다:
  - `LoadChatRoomParticipantsUseCase` Swift 6 actor-isolation 경고.
  - 일부 `contentEdgeInsets`/`windows` deprecation 경고.
  - `functions/node_modules/@unrs/resolver-binding-darwin-arm64` search path 누락 경고.
  - 위 경고들은 이번 Phase 2 변경으로 새로 만든 오류는 아니며, 빌드는 성공했다.

## 6. 불확실한 부분

- 확실하지 않음: Volt Green `#7FDB1E`이 실제 룩북 이미지 데이터와 모든 화면에서 가장 적합한지는 수동 QA 전까지 확정할 수 없다.
- 확실하지 않음: 일부 레거시 채팅 화면은 하드코딩 색상이 많아 phase 5에서 예상보다 변경 범위가 커질 수 있다.
- 추측입니다: 형광 포인트 색은 룩북/패션 맥락에서 브랜드 기억점을 만들 가능성이 높다. 다만 과도하게 쓰면 앱이 가벼워 보일 수 있어 사용 범위를 좁게 유지해야 한다.

## 7. 다음 단계

1. Phase 4C 수동 QA로 댓글 sheet, 답글 sheet, 신고/삭제/차단 sheet, 생성/import 플로우, 포스트 metric 저장 버튼 제거를 확인한다.
2. Phase 5 채팅 화면군 토큰화 전 의사결정 사항을 점검한다.
3. 별도 후속 phase에서 포스트 저장 기능의 도메인/서버 cleanup 여부를 점검한다.
