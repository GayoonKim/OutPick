//
//  MainTabBuilding.swift
//  OutPick
//
//  Created by 김가윤 on 2/3/26.
//

import UIKit

// MARK: - Tab Building (DI 포인트)

/// CustomTabBarViewController가 각 탭의 화면을 직접 생성하지 않도록 분리한 빌더 프로토콜
/// - Note: 나중에 OpenChat/Profile/Lookbook 등 기능별 CompositionRoot + Coordinator를 붙일 때
///         이 빌더 구현만 교체하면 됩니다.
@MainActor
protocol MainTabBuilding: AnyObject {
    func makeViewController(for index: Int) -> UIViewController
}
