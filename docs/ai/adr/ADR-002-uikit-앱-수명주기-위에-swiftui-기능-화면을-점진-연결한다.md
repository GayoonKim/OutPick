# ADR-002: UIKit 앱 수명주기 위에 SwiftUI 기능 화면을 점진 연결한다


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

