# Main Tab Shell Standardization Progress

## 현재 상태

- Phase 0 설계/task 문서 생성 완료.
- Phase 1 `MainTabBarController` 도입과 탭 root 조립 전환 완료.
- Phase 2 `DefaultAppContentRouter`와 cross-feature route 전환 완료.
- Phase 3 Chat/Lookbook 상세 `hidesBottomBarWhenPushed` 정리 완료.
- Phase 4 기존 custom child overlay shell 제거와 문서 갱신 완료.
- Phase 5 정적 검증과 Swift build 완료.
- 수동 QA 완료.

## 확정된 기준

- 메인 탭 shell은 `UITabBarController + 각 탭 UINavigationController` 구조로 전환한다.
- 상세 push 화면의 탭 바 숨김은 `hidesBottomBarWhenPushed`를 기준으로 처리한다.
- UIKit navigation bar는 계속 숨긴다.
- 화면 상단 chrome은 OutPick 커스텀 navigation bar가 담당한다.
- 기존 `CustomTabBarView` 외형은 `UITabBarAppearance`로 근사한다.
- 탭 바는 현재처럼 60pt 성격을 유지한다.
- 필요하면 `UITabBar` subclass를 도입한다.
- 같은 탭 재선택은 아무 동작도 하지 않는다.
- Chat 검색/방 생성/방 본문과 Lookbook 브랜드/시즌/포스트 상세에서는 탭 바를 숨긴다.

## 조사 내용

- 현재 `MainTabCompositionRoot`는 `CustomTabBarViewController`를 생성한다.
- `CustomTabBarViewController`는 child view controller를 직접 add/remove하고 `CustomTabBarView`를 하단에 붙인다.
- 현재 custom shell에서는 `hidesBottomBarWhenPushed`를 사용할 수 없다.
- `navigation-swipe-back` 작업에서 stack depth 관찰 기반 탭 바 숨김 보정을 추가했지만, 이는 표준 shell 전환 전 임시 안정화에 가깝다.
- `DefaultAppContentRouter`는 현재 `CustomTabBarViewController.switchScreen(_:)`와 `activeContentViewController`에 의존한다.

## 완료 내용

- `MainTabBarController`를 추가해 메인 탭 root를 `UITabBarController` 기반으로 전환했다.
- `OutPickTabBar`를 추가해 60pt 성격의 탭 바 높이를 유지했다.
- `MainTabCompositionRoot`가 `MainTabBarController`를 만들고 `OutPickTabBar`를 주입하도록 바꿨다.
- `DefaultMainTabBuilder`가 5개 탭 root와 tab bar item을 생성하도록 확장했다.
- 같은 탭 재선택은 `MainTabBarController` delegate에서 no-op으로 처리한다.
- `AppCoordinator`의 메인 탭 참조를 `MainTabBarController`로 전환했다.
- notification route는 `selectTab(1)`과 active presenter를 사용한다.
- `DefaultAppContentRouter`는 `MainTabBarController.selectTab(_:)`와 selected navigation controller 기준으로 route한다.
- Chat 검색/방 생성/방 본문 push 대상에 `hidesBottomBarWhenPushed = true`를 적용했다.
- 생성 완료 후 `RoomCreateViewController`가 직접 push하는 `ChatViewController`도 `makeChatRoomViewController`에서 탭 바 숨김을 보장한다.
- Lookbook 브랜드/시즌/포스트 상세 hosting controller에 `hidesBottomBarWhenPushed = true`를 적용했다.
- cross-feature Lookbook shared content hosting controller에도 `hidesBottomBarWhenPushed = true`를 적용했다.
- 기존 `CustomTabBarViewController.swift`와 `CustomTabBarView.swift`를 제거했다.

## 남은 작업

- 없음.

## 검증 상태

- `git diff --check -- OutPick/App ...` 통과.
- 전체 `git diff --check` 통과.
- `rg "CustomTabBarViewController|CustomTabBarView|switchScreen\\(" OutPick` 결과 앱 코드 잔여 참조 없음.
- `xcodebuild -scheme OutPick -destination 'generic/platform=iOS Simulator' build` 성공.
- 수동 QA 완료:
  - 탭 전환과 탭 바 표시 정상 확인.
  - Chat 검색/방 생성/방 본문, Lookbook/Liked 상세 이동과 탭 바 숨김 정상 확인.
  - 탭 바 초기 표시/터치 영역과 Lookbook/Liked 전환 후 높이 유지 정상 확인.
