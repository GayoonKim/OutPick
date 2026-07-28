//
//  CurrentUserSessionStore.swift
//  OutPick
//
//  Created by Codex on 7/2/26.
//

import Foundation

final class CurrentUserSessionStore {
    private(set) var currentProfile: UserPublicProfile?

    func replaceProfile(_ profile: UserPublicProfile?) {
        currentProfile = profile
    }

    func updateProfile(_ mutate: (inout UserPublicProfile) -> Void) {
        guard var profile = currentProfile else { return }
        mutate(&profile)
        currentProfile = profile
    }

    func clear() {
        currentProfile = nil
    }
}
