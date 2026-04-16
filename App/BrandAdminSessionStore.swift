//
//  BrandAdminSessionStore.swift
//  OutPick
//
//  Created by OpenAI Codex on 4/16/26.
//

import Foundation
import Combine

@MainActor
final class BrandAdminSessionStore: ObservableObject {
    @Published private(set) var canCreateBrand: Bool = false
    @Published private(set) var roles: [String] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var isLoaded: Bool = false

    private let cloudFunctionsManager: CloudFunctionsManager
    private var loadedIdentityKey: String?

    init(cloudFunctionsManager: CloudFunctionsManager = .shared) {
        self.cloudFunctionsManager = cloudFunctionsManager
    }

    func refreshCurrentSession(force: Bool = false) async {
        let identityKey = LoginManager.shared.getAuthIdentityKey
        await refresh(identityKey: identityKey, force: force)
    }

    func refresh(identityKey rawIdentityKey: String, force: Bool = false) async {
        let identityKey = rawIdentityKey.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !identityKey.isEmpty else {
            reset()
            print("[BrandAdminSessionStore] skip refresh: empty auth identity")
            return
        }

        guard !isLoading else { return }

        if !force,
           isLoaded,
           loadedIdentityKey == identityKey {
            return
        }

        if loadedIdentityKey != identityKey {
            clearCapabilities()
            isLoaded = false
            loadedIdentityKey = nil
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let capabilities = try await loadCapabilitiesWithRetry()
            canCreateBrand = capabilities.canCreateBrands
            roles = capabilities.roles
            loadedIdentityKey = identityKey
            isLoaded = true
            print(
                """
                [BrandAdminSessionStore] refreshed identity=\(identityKey) \
                canCreateBrand=\(capabilities.canCreateBrands) \
                roles=\(capabilities.roles)
                """
            )
        } catch {
            clearCapabilities()
            isLoaded = false
            loadedIdentityKey = nil

            let nsError = error as NSError
            print(
                """
                [BrandAdminSessionStore] refresh failed identity=\(identityKey) \
                domain=\(nsError.domain) code=\(nsError.code) \
                description=\(nsError.localizedDescription)
                """
            )
        }
    }

    func reset() {
        clearCapabilities()
        isLoaded = false
        isLoading = false
        loadedIdentityKey = nil
    }

    private func clearCapabilities() {
        canCreateBrand = false
        roles = []
    }

    private func loadCapabilitiesWithRetry() async throws -> BrandAdminCapabilitiesResponse {
        do {
            return try await cloudFunctionsManager.getBrandAdminCapabilities()
        } catch {
            let nsError = error as NSError
            print(
                """
                [BrandAdminSessionStore] retry scheduled domain=\(nsError.domain) \
                code=\(nsError.code) description=\(nsError.localizedDescription)
                """
            )
            try? await Task.sleep(nanoseconds: 500_000_000)
            return try await cloudFunctionsManager.getBrandAdminCapabilities()
        }
    }
}
