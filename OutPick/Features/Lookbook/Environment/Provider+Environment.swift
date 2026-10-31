//
//  Provider+Environment.swift
//  OutPick
//
//  Created by 김가윤 on 1/9/26.
//

import SwiftUI

private struct LookbookRepositoryProviderKey: EnvironmentKey {
    static var defaultValue: LookbookRepositoryProvider {
        #if DEBUG && (targetEnvironment(simulator) || OUTPICK_BRAND_LOCAL_DEVICE)
        if BrandLocalIntegrationMode.isEnabled {
            do { return try BrandLocalRepositoryEnvironment.shared.installedProvider() }
            catch { preconditionFailure("로컬 화면 Provider를 먼저 주입해야 합니다.") }
        }
        #endif
        return .shared
    }
}

#if DEBUG && (targetEnvironment(simulator) || OUTPICK_BRAND_LOCAL_DEVICE)
// SwiftUI는 명시 환경값을 쓰기 전에도 기본값을 읽는다. 로컬 모드에서 기본 SDK 생성을 막는다.
final class BrandLocalRepositoryEnvironment: @unchecked Sendable {
    static let shared = BrandLocalRepositoryEnvironment()
    private let lock = NSLock()
    private var provider: LookbookRepositoryProvider?

    func install(_ provider: LookbookRepositoryProvider) {
        lock.lock()
        defer { lock.unlock() }
        self.provider = provider
    }

    func installedProvider() throws -> LookbookRepositoryProvider {
        lock.lock()
        defer { lock.unlock() }
        guard let provider else { throw BrandLocalIntegrationError.unavailableConfiguration }
        return provider
    }
}
#endif

extension EnvironmentValues {
    var repositoryProvider: LookbookRepositoryProvider {
        get { self[LookbookRepositoryProviderKey.self] }
        set { self[LookbookRepositoryProviderKey.self] = newValue }
    }
}
