# Main Tab Shell Standardization Design

## 목적

메인 탭 shell을 `CustomTabBarViewController`가 child 위에 커스텀 탭 바를 직접 얹는 구조에서 UIKit 표준 구조로 전환한다.

목표 구조는 `UITabBarController + 각 탭 UINavigationController + hidesBottomBarWhenPushed`다. UIKit navigation bar는 계속 숨기고, 화면에 보이는 navigation chrome은 OutPick 커스텀 navigation bar가 담당한다.

## 배경

`navigation-swipe-back` 작업에서 Chat과 Lookbook/Liked 상세 화면을 UIKit push 기반으로 전환했다. 그 결과 상세 화면의 back button과 edge swipe pop 자체는 UIKit navigation stack에 맞출 수 있었지만, 앱의 메인 탭 shell이 표준 `UITabBarController`가 아니어서 다음 문제가 드러났다.

- 상세 push 화면에서 메인 탭 바가 남아 보일 수 있다.
- `hidesBottomBarWhenPushed`를 사용할 수 없다.
- `CustomTabBarViewController`가 child `UINavigationController`의 stack depth를 관찰해 탭 바 숨김/표시를 흉내 내야 한다.
- interactive pop 취소/완료 타이밍과 커스텀 탭 바 애니메이션 타이밍이 어긋날 수 있다.
- child bottom constraint를 탭 바 top 또는 safe area bottom으로 직접 바꿔야 해서 layout 책임이 shell에 과도하게 들어간다.

따라서 swipe-back 보정으로 끝내지 않고, 배포 전 앱 shell을 실무적인 UIKit 탭 구조로 정리한다.

## 확정 방향

### 표준 shell 구조

- 메인 탭 root는 `UITabBarController` 기반 controller로 전환한다.
- 각 탭은 독립 `UINavigationController`를 가진다.
- 탭별 root 화면은 각 navigation controller의 root view controller가 된다.
- UIKit navigation bar는 모든 탭 navigation controller에서 숨긴다.
- 상세 화면 push 시 대상 view controller의 `hidesBottomBarWhenPushed = true`를 사용한다.
- 화면 상단 chrome은 기존 OutPick 커스텀 navigation bar가 계속 담당한다.

### 탭 바 외형

- 기존 `CustomTabBarView` 외형은 `UITabBarAppearance`로 근사한다.
- 현재처럼 60pt 성격의 탭 바 높이는 유지한다.
- `UITabBarAppearance`만으로 높이와 hit area 요구사항이 부족하면 `UITabBar` subclass를 도입한다.
- 초기 목표는 디자인 픽셀 완전 복제가 아니라 표준 container 구조 전환이다.

### 탭 재선택 동작

- 같은 탭을 다시 눌러도 아무 동작도 하지 않는다.
- root 화면에서 사용자가 열심히 스크롤한 위치를 실수로 잃지 않도록 `scroll-to-top`, refresh, pop-to-root 같은 특수 동작은 이번 작업 범위에서 제외한다.
- 상세 화면에서는 탭 바가 숨겨지므로 같은 탭 재선택 자체가 불가능하다.

### 탭 바 숨김 범위

- Chat 검색 화면은 탭 바를 숨긴다.
- Chat 방 생성 화면은 탭 바를 숨긴다.
- Chat 방 본문 화면은 탭 바를 숨긴다.
- Lookbook 브랜드 상세 화면은 탭 바를 숨긴다.
- Lookbook 시즌 상세 화면은 탭 바를 숨긴다.
- Lookbook 포스트 상세 화면은 탭 바를 숨긴다.
- 각 탭 root 화면에서만 탭 바를 표시한다.

## 현재 구조

- `MainTabCompositionRoot`가 `CustomTabBarViewController`를 생성한다.
- `DefaultMainTabBuilder`가 탭 index별 root view controller를 생성한다.
- `CustomTabBarViewController`는 child view controller를 직접 add/remove하고 `CustomTabBarView`를 하단에 붙인다.
- 탭 전환은 `switchScreen(_:)`가 담당한다.
- cross-feature route는 `DefaultAppContentRouter`가 `CustomTabBarViewController.switchScreen(_:)`와 `activeContentViewController`에 의존한다.

## 목표 구조

- `MainTabCompositionRoot`는 `MainTabBarController`를 생성한다.
- `MainTabBarController`는 `UITabBarController` subclass다.
- `DefaultMainTabBuilder`는 탭별 root content를 만들고, composition root 또는 shell이 이를 `UINavigationController`로 감싼다.
- `DefaultAppContentRouter`는 `UITabBarController.selectedIndex`와 selected navigation controller를 기준으로 route한다.
- Chat/Lookbook Coordinator push 대상은 같은 탭의 navigation controller다.
- 상세 view controller 또는 hosting controller는 push 전 `hidesBottomBarWhenPushed = true`를 가진다.

## 구현 가능성

가능하다.

근거:

- 현재 각 탭 root는 이미 대부분 `UINavigationController` 기반이거나 UIKit navigation stack에 붙을 수 있는 형태다.
- Chat/Lookbook push 전환이 완료되어 상세 화면은 modal이 아니라 navigation push 경로를 탄다.
- iOS 15.6에서도 `UITabBarController`, `UINavigationController`, `hidesBottomBarWhenPushed`, `UITabBarAppearance`를 사용할 수 있다.

확실하지 않음:

- 기존 custom 탭 바의 60pt 높이를 시스템 tab bar와 완전히 동일한 터치/레이아웃 감각으로 맞추려면 `UITabBar` subclass가 필요할 수 있다.
- safe area, keyboard, custom tab bar height 조합은 시뮬레이터/실기기 QA가 필요하다.

## 제외 범위

- iOS deployment target 상향.
- SwiftUI `NavigationStack` 전환.
- 화면 상단 navigation chrome을 UIKit navigation bar로 되돌리는 작업.
- 탭 root 화면의 scroll-to-top 또는 refresh 재선택 동작.
- 탭 디자인 전면 개편.
- Chat/Lookbook 내부 도메인 로직 변경.
