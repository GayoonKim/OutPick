//
//  LookbookCompositionRoot.swift
//  OutPick
//
//  Created by 김가윤 on 2/3/26.
//

import UIKit
import SwiftUI

/// 룩북 탭 조립 전담 CompositionRoot
/// - Note: UIKit(CustomTabBarViewController)은 Lookbook을 전혀 몰라도 되도록
///         룩북 관련 의존성/SwiftUI Hosting 조립을 여기로 모읍니다.
@MainActor
enum LookbookCompositionRoot {

    /// 룩북 탭의 Root VC를 생성합니다.
    /// - Returns: UINavigationController(루트: UIHostingController)
    static func makeRoot(container: LookbookContainer) -> UIViewController {
        // 한국어 주석: SwiftUI View 조립
        let lookbookView =
            LookbookHomeView(
                viewModel: container.lookbookHomeViewModel,
                provider: container.provider
            )
            .environment(\.repositoryProvider, container.provider)

        // 한국어 주석: SwiftUI -> UIKit 브릿지
        let hostingVC = UIHostingController(rootView: lookbookView)

        // 한국어 주석: 탭 내부 push 흐름 확장을 위해 UINavigationController로 감싸둠
        let nav = UINavigationController(rootViewController: hostingVC)
        nav.isNavigationBarHidden = true
        return nav
    }
}
