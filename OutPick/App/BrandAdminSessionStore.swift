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
    @Published private(set) var isTotalAdmin: Bool = false
    @Published private(set) var roles: [String] = []
    @Published private(set) var ownedBrandIDs: Set<BrandID> = []
    @Published private(set) var adminBrandIDs: Set<BrandID> = []
    @Published private(set) var writableBrandIDs: Set<BrandID> = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var isLoaded: Bool = false
    @Published private(set) var isWritableBrandsLoading: Bool = false
    @Published private(set) var isWritableBrandsLoaded: Bool = false

    private let cloudFunctionsManager: CloudFunctionsManager
    private var loadedIdentityKey: String?
    private var loadedWritableBrandsIdentityKey: String?

    init(
        cloudFunctionsManager: CloudFunctionsManager = .shared
    ) {
        self.cloudFunctionsManager = cloudFunctionsManager
    }

    func refreshCurrentSession(force: Bool = false) async {
        let identityKey = LoginManager.shared.canonicalUserID
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

        handleIdentityChangeIfNeeded(identityKey)

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
            apply(capabilities)
            loadedIdentityKey = identityKey
            loadedWritableBrandsIdentityKey = identityKey
            isLoaded = true
            isWritableBrandsLoaded = true
            print(
                """
                [BrandAdminSessionStore] refreshed identity=\(identityKey) \
                isTotalAdmin=\(capabilities.isTotalAdmin) \
                roles=\(capabilities.roles) \
                ownerCount=\(capabilities.ownedBrandIDs.count) \
                adminCount=\(capabilities.adminBrandIDs.count)
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

    func refreshWritableBrands(force: Bool = false) async {
        let identityKey = LoginManager.shared.canonicalUserID
        let normalizedIdentityKey = identityKey.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedIdentityKey.isEmpty else {
            reset()
            print("[BrandAdminSessionStore] skip writable brand refresh: empty auth identity")
            return
        }

        guard !isWritableBrandsLoading else { return }

        handleIdentityChangeIfNeeded(normalizedIdentityKey)

        if !force,
           isWritableBrandsLoaded,
           loadedWritableBrandsIdentityKey == normalizedIdentityKey {
            return
        }

        isWritableBrandsLoading = true
        defer { isWritableBrandsLoading = false }

        do {
            let capabilities = try await loadCapabilitiesWithRetry()
            apply(capabilities)
            loadedIdentityKey = normalizedIdentityKey
            loadedWritableBrandsIdentityKey = normalizedIdentityKey
            isLoaded = true
            isWritableBrandsLoaded = true
            print(
                """
                [BrandAdminSessionStore] writable brands refreshed identity=\(normalizedIdentityKey) \
                ownerCount=\(capabilities.ownedBrandIDs.count) \
                adminCount=\(capabilities.adminBrandIDs.count)
                """
            )
        } catch {
            clearWritableBrandIDs()
            loadedWritableBrandsIdentityKey = nil
            isWritableBrandsLoaded = false

            let nsError = error as NSError
            print(
                """
                [BrandAdminSessionStore] writable brand refresh failed identity=\(normalizedIdentityKey) \
                domain=\(nsError.domain) code=\(nsError.code) \
                description=\(nsError.localizedDescription)
                """
            )
        }
    }

    func ensureWritableBrandsLoaded() async {
        let identityKey = LoginManager.shared.canonicalUserID
        let normalizedIdentityKey = identityKey.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedIdentityKey.isEmpty else {
            reset()
            print("[BrandAdminSessionStore] skip writable brand ensure: empty auth identity")
            return
        }

        handleIdentityChangeIfNeeded(normalizedIdentityKey)

        if isWritableBrandsLoaded,
           loadedWritableBrandsIdentityKey == normalizedIdentityKey {
            return
        }

        await refreshWritableBrands()
    }

    func canWrite(brandID: BrandID) -> Bool {
        isTotalAdmin || writableBrandIDs.contains(brandID)
    }

    func canManageBrandManagers(brandID: BrandID) -> Bool {
        isTotalAdmin || ownedBrandIDs.contains(brandID)
    }

    var canOpenAdminConsole: Bool {
        isTotalAdmin || writableBrandIDs.isEmpty == false
    }

    #if DEBUG
    func applyUITestWritableBrands(_ brandIDs: Set<BrandID>) {
        ownedBrandIDs = brandIDs
        adminBrandIDs = []
        writableBrandIDs = brandIDs
        loadedWritableBrandsIdentityKey = LoginManager.shared.canonicalUserID
        isWritableBrandsLoaded = true
    }
    #endif

    func reset() {
        clearCapabilities()
        clearWritableBrandIDs()
        isLoaded = false
        isLoading = false
        isWritableBrandsLoading = false
        isWritableBrandsLoaded = false
        loadedIdentityKey = nil
        loadedWritableBrandsIdentityKey = nil
    }

    private func clearCapabilities() {
        isTotalAdmin = false
        roles = []
    }

    private func clearWritableBrandIDs() {
        ownedBrandIDs = []
        adminBrandIDs = []
        writableBrandIDs = []
    }

    private func apply(_ capabilities: BrandAdminCapabilitiesResponse) {
        isTotalAdmin = capabilities.isTotalAdmin
        roles = capabilities.roles
        ownedBrandIDs = Set(capabilities.ownedBrandIDs.map { BrandID(value: $0) })
        adminBrandIDs = Set(capabilities.adminBrandIDs.map { BrandID(value: $0) })
        writableBrandIDs = ownedBrandIDs.union(adminBrandIDs)
    }

    private func handleIdentityChangeIfNeeded(_ identityKey: String) {
        let didGlobalIdentityChange =
            loadedIdentityKey.map { $0 != identityKey } ?? false
        let didWritableIdentityChange =
            loadedWritableBrandsIdentityKey.map { $0 != identityKey } ?? false

        guard didGlobalIdentityChange || didWritableIdentityChange else { return }

        clearCapabilities()
        clearWritableBrandIDs()
        isLoaded = false
        isWritableBrandsLoaded = false
        loadedIdentityKey = nil
        loadedWritableBrandsIdentityKey = nil
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
