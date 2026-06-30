# Main Tab Shell Standardization Decisions

## 결정 인덱스

| ID | 상태 | 결정 |
| --- | --- | --- |
| MTS-D001 | Accepted | 메인 탭 shell은 `UITabBarController + 각 탭 UINavigationController` 구조로 전환한다. |
| MTS-D002 | Accepted | 상세 push 화면의 탭 바 숨김은 `hidesBottomBarWhenPushed`를 기준으로 처리한다. |
| MTS-D003 | Accepted | UIKit navigation bar는 계속 숨기고 OutPick 커스텀 navigation bar가 화면 chrome을 담당한다. |
| MTS-D004 | Accepted | 기존 custom tab bar 외형은 `UITabBarAppearance`로 근사한다. |
| MTS-D005 | Accepted | 탭 바는 현재처럼 60pt 성격을 유지하고, 필요하면 `UITabBar` subclass를 사용한다. |
| MTS-D006 | Accepted | 같은 탭 재선택은 아무 동작도 하지 않는다. |
| MTS-D007 | Accepted | Chat 검색/방 생성/방 본문과 Lookbook 브랜드/시즌/포스트 상세에서는 탭 바를 숨긴다. |

## MTS-D001: 표준 UITabBarController shell

결정:

- 기존 `CustomTabBarViewController + CustomTabBarView` child overlay 구조를 표준 `UITabBarController` 기반 shell로 대체한다.
- 각 탭은 독립 `UINavigationController`를 가진다.

이유:

- UIKit이 탭별 navigation stack, tab bar safe area, `hidesBottomBarWhenPushed`, interactive pop 전환 타이밍을 직접 관리하게 하기 위해서다.
- 기존 구조는 child 위에 custom view를 직접 올리고 stack depth를 관찰해 탭 바 숨김을 흉내 내므로 push/pop transition과 어긋날 위험이 크다.

## MTS-D002: hidesBottomBarWhenPushed 기준 탭 바 숨김

결정:

- root가 아닌 상세 push 화면은 push 전 `hidesBottomBarWhenPushed = true`를 설정한다.
- shell이 navigation controller delegate로 stack depth를 관찰해 탭 바를 숨기는 임시 보정은 제거 대상이다.

이유:

- `hidesBottomBarWhenPushed`는 `UITabBarController`와 `UINavigationController` 조합에서 UIKit이 제공하는 표준 동작이다.
- interactive pop 취소/완료 시점의 탭 바 표시 복구를 UIKit에게 맡길 수 있다.

## MTS-D003: UIKit navigation bar 숨김 유지

결정:

- 각 탭 navigation controller의 UIKit navigation bar는 계속 숨긴다.
- visible navigation chrome은 기존 OutPick 커스텀 navigation bar가 담당한다.

이유:

- 이전 push 구조의 문제는 표준 push 자체보다 UIKit navigation bar, SwiftUI navigation bar, OutPick custom bar의 표시 책임이 섞인 데 있었다.
- stack owner와 visible chrome owner를 분리한다.

## MTS-D004: UITabBarAppearance 우선

결정:

- 기존 `CustomTabBarView` 외형은 `UITabBarAppearance`로 근사한다.
- 디자인 픽셀 완전 복제보다 표준 shell 구조 전환을 우선한다.

이유:

- 배포 전 구조 안정화가 현재 핵심 목표다.
- 탭 UI는 이후 원하는 방향으로 빠르게 조정 가능하다.

## MTS-D005: 60pt 탭 바 성격 유지

결정:

- 현재 custom tab bar의 60pt 성격은 유지한다.
- `UITabBarAppearance`만으로 부족하면 `UITabBar` subclass를 도입한다.

이유:

- 기존 앱의 하단 chrome 밀도와 터치 영역 감각을 크게 바꾸지 않기 위해서다.

## MTS-D006: 같은 탭 재선택은 no-op

결정:

- 이미 선택된 탭을 다시 눌러도 아무 동작도 하지 않는다.
- root scroll-to-top, refresh, pop-to-root는 이번 작업 범위에서 제외한다.

이유:

- 상세 화면에서는 탭 바가 숨겨져 같은 탭 재선택이 불가능하다.
- root 화면에서 사용자가 스크롤한 위치를 실수 탭으로 잃는 UX를 피한다.

## MTS-D007: 상세 화면 탭 바 숨김 범위

결정:

- Chat 검색, 방 생성, 방 본문은 탭 바를 숨긴다.
- Lookbook 브랜드, 시즌, 포스트 상세는 탭 바를 숨긴다.
- 각 탭 root 화면에서만 탭 바를 표시한다.

이유:

- 상세 화면은 OutPick 커스텀 navigation bar와 content에 집중하게 하고, back button/edge swipe로 root로 돌아오게 하는 흐름이 명확하다.
