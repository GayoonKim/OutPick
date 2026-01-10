//
//  Provider+Environment.swift
//  OutPick
//
//  Created by 김가윤 on 1/9/26.
//

import SwiftUI

private struct RepositoryProviderKey: EnvironmentKey {
    static let defaultValue: RepositoryProvider = .shared
}

extension EnvironmentValues {
    var repositoryProvider: RepositoryProvider {
        get { self[RepositoryProviderKey.self] }
        set { self[RepositoryProviderKey.self] = newValue }
    }
}
