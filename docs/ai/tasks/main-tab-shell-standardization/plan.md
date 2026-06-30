# Main Tab Shell Standardization Plan

## 목적

메인 탭 shell을 표준 UIKit container 구조로 전환해 push 상세 화면의 탭 바 숨김, edge swipe pop, safe area 처리를 UIKit 기본 동작에 맞춘다.

## Phase 지도

| Phase | 목표 | 상태 |
| --- | --- | --- |
| Phase 0 | 설계/task 문서 생성 | 완료 |
| Phase 1 | MainTabBarController 도입과 탭 root 조립 전환 | 완료 |
| Phase 2 | AppContentRouter와 cross-feature route 전환 | 완료 |
| Phase 3 | Chat/Lookbook 상세 `hidesBottomBarWhenPushed` 정리 | 완료 |
| Phase 4 | 기존 custom tab shell 제거/문서 갱신 | 완료 |
| Phase 5 | 최종 검증/QA 정리 | 완료 |

## 완료 기준

- 메인 탭 root가 `UITabBarController` 기반이다.
- 각 탭은 독립 `UINavigationController`를 가진다.
- UIKit navigation bar는 모든 탭에서 숨겨져 있다.
- Chat 검색/방 생성/방 본문 push 화면에서 탭 바가 보이지 않는다.
- Lookbook 브랜드/시즌/포스트 상세 push 화면에서 탭 바가 보이지 않는다.
- 상세 화면에서 back button과 edge swipe pop이 같은 결과를 낸다.
- root 복귀 시 탭 바가 늦게 올라오는 느낌 없이 UIKit transition과 함께 복구된다.
- 같은 탭 재선택은 아무 동작도 하지 않는다.
- 기존 child overlay 방식의 탭 바 숨김 보정 코드는 제거된다.

## Phase 1: MainTabBarController 도입과 탭 root 조립 전환

### 목표

`CustomTabBarViewController` 대신 `UITabBarController` 기반 `MainTabBarController`를 도입하고, 각 탭을 `UINavigationController`로 구성한다.

### 변경 범위 후보

- `OutPick/App/TabBarController/MainTab/MainTabBarController.swift`
- `OutPick/App/TabBarController/MainTab/OutPickTabBar.swift`
- `OutPick/App/TabBarController/Composition/MainTabCompositionRoot.swift`
- `OutPick/App/TabBarController/Composition/DefaultMainTabBuilder.swift`
- `OutPick/App/TabBarController/Composition/MainTabBuilding.swift`
- `OutPick/App/AppCoordinator.swift`

### 완료 기준

- 앱 루트로 `MainTabBarController`가 설정된다.
- 5개 탭 순서는 기존과 동일하다.
- 각 탭 root는 독립 navigation controller 안에 있다.
- navigation bar는 숨김 상태다.
- tab bar item icon/title/selected color는 기존 외형에 가깝게 표시된다.
- 탭 바 높이는 60pt 성격을 유지한다.
- 같은 탭 재선택은 no-op이다.

### 검증 방법

- 코드 inspection.
- 수동 QA: 앱 진입, 5개 탭 전환, 같은 탭 재선택 no-op.
- 가능하면 `git diff --check`.

## Phase 2: AppContentRouter와 cross-feature route 전환

### 목표

`DefaultAppContentRouter`가 `CustomTabBarViewController.switchScreen(_:)`와 `activeContentViewController`에 의존하지 않고, 표준 `UITabBarController.selectedIndex`와 selected navigation controller를 사용하도록 전환한다.

### 변경 범위 후보

- `OutPick/App/Routing/DefaultAppContentRouter.swift`
- `OutPick/App/TabBarController/Composition/MainTabBuilding.swift`
- `OutPick/App/TabBarController/Composition/DefaultMainTabBuilder.swift`
- 필요 시 `OutPick/App/AppCoordinator.swift`

### 완료 기준

- 공유 카드에서 룩북 상세로 이동할 때 Lookbook 탭 navigation controller에 push된다.
- 룩북 공유 완료 후 채팅방 이동 시 Joined Rooms 탭 navigation controller에 push된다.
- route 전환 전 visible modal/sheet dismiss 정책은 유지된다.

### 검증 방법

- 코드 inspection.
- 수동 QA: Lookbook shared content open, joined chat room open.

## Phase 3: Chat/Lookbook 상세 hidesBottomBarWhenPushed 정리

### 목표

상세 push 대상 view controller 또는 hosting controller에 `hidesBottomBarWhenPushed = true`를 명시하고, root 화면에서는 탭 바가 표시되도록 정리한다.

### 변경 범위 후보

- `OutPick/Features/Chat/ChatCoordinator.swift`
- `OutPick/Features/Chat/Controllers/RoomSearchViewController.swift`
- `OutPick/Features/Chat/Controllers/RoomCreateViewController.swift`
- `OutPick/Features/Chat/Controllers/ChatViewController.swift`
- `OutPick/Features/Lookbook/Coordinators/LookbookCoordinator.swift`
- `OutPick/App/Routing/DefaultAppContentRouter.swift`

### 완료 기준

- Chat 검색/방 생성/방 본문에서 탭 바가 숨겨진다.
- Lookbook 브랜드/시즌/포스트 상세에서 탭 바가 숨겨진다.
- root로 pop되면 탭 바가 UIKit transition에 맞춰 즉시 복구된다.
- UIKit navigation bar는 노출되지 않는다.

### 검증 방법

- 수동 QA: Chat/Lookbook push, back button, edge swipe 완료/취소.
- 가능하면 `git diff --check`.

## Phase 4: 기존 custom tab shell 제거/문서 갱신

### 목표

`CustomTabBarViewController`와 `CustomTabBarView` 기반 child overlay 구조를 제거하거나 미사용 상태로 정리하고, entrypoint 문서를 갱신한다.

### 변경 범위 후보

- `OutPick/App/TabBarController/MainTab/CustomTabBarViewController.swift`
- `OutPick/App/TabBarController/MainTab/CustomTabBarView.swift`
- `docs/ai/entrypoints/APP.md`
- `docs/ai/tasks/main-tab-shell-standardization/progress.md`
- `docs/ai/tasks/main-tab-shell-standardization/qa-checklist.md`
- 필요 시 `docs/ai/tasks/navigation-swipe-back/progress.md`

### 완료 기준

- 앱 실행 경로에서 custom child overlay tab shell을 사용하지 않는다.
- 문서에 새 shell 구조와 route owner가 반영된다.
- `navigation-swipe-back`에서 남은 custom tab bar 임시 보정은 후속 제거 완료로 기록된다.

### 검증 방법

- `rg "CustomTabBarViewController|CustomTabBarView"`로 사용처 확인.
- 문서 inspection.

## Phase 5: 최종 검증/QA 정리

### 목표

전체 변경의 기본 검증과 남은 위험을 정리한다.

### 완료 기준

- `git diff --check`가 통과한다.
- 가능한 경우 Swift build가 성공한다.
- 수동 QA 체크리스트가 갱신된다.
- 남은 위험과 후속 후보가 정리된다.

### 검증 방법

- `git diff --check`
- `xcodebuild -scheme OutPick -destination 'generic/platform=iOS Simulator' build`
- 수동 QA 체크리스트

## 테스트 설계

- 테스트 대상: Main tab shell, 탭별 navigation stack, `hidesBottomBarWhenPushed`, cross-feature route.
- 필요한 테스트: 우선 자동 테스트 추가 없이 build와 수동 QA 중심으로 검증한다.
- 수동 QA 항목: 앱 진입, 5개 탭 전환, 같은 탭 재선택 no-op, Chat 검색/방 생성/방 본문 push/back/swipe, Lookbook 상세 push/back/swipe, cross-feature route.
- 보류할 테스트와 이유: 시각/gesture transition 타이밍은 unit test 효용이 낮고 수동 QA가 더 정확하다.
- 테스트 실행 여부: 구현 후 `git diff --check`, 가능하면 Swift build를 수행한다.
