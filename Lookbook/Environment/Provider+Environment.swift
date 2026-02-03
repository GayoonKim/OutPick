//
//  Provider+Environment.swift
//  OutPick
//
//  Created by 김가윤 on 1/9/26.
//

import SwiftUI

private struct LookbookRepositoryProviderKey: EnvironmentKey {
    static let defaultValue: LookbookRepositoryProvider = .shared
}

extension EnvironmentValues {
    var repositoryProvider: LookbookRepositoryProvider {
        get { self[LookbookRepositoryProviderKey.self] }
        set { self[LookbookRepositoryProviderKey.self] = newValue }
    }
}
