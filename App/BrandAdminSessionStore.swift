//
//  BrandAdminSessionStore.swift
//  OutPick
//
//  Created by OpenAI Codex on 4/16/26.
//

import Foundation
import Combine
import FirebaseFirestore

@MainActor
final class BrandAdminSessionStore: ObservableObject {
    @Published private(set) var canCreateBrand: Bool = false
    @Published private(set) var roles: [String] = []
    @Published private(set) var writableBrandIDs: Set<BrandID> = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var isLoaded: Bool = false

    private let cloudFunctionsManager: CloudFunctionsManager
    private let db: Firestore
    private var loadedIdentityKey: String?
    private var loadedWritableBrandsIdentityKey: String?
    private var isLoadingWritableBrands: Bool = false

    init(
        cloudFunctionsManager: CloudFunctionsManager = .shared,
        db: Firestore = Firestore.firestore()
    ) {
        self.cloudFunctionsManager = cloudFunctionsManager
        self.db = db
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

    func refreshWritableBrands(force: Bool = false) async {
        let identityKey = LoginManager.shared.getAuthIdentityKey
        let normalizedIdentityKey = identityKey.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedIdentityKey.isEmpty else {
            reset()
            print("[BrandAdminSessionStore] skip writable brand refresh: empty auth identity")
            return
        }

        guard !isLoadingWritableBrands else { return }

        handleIdentityChangeIfNeeded(normalizedIdentityKey)

        if !force,
           loadedWritableBrandsIdentityKey == normalizedIdentityKey {
            return
        }

        isLoadingWritableBrands = true
        defer { isLoadingWritableBrands = false }

        do {
            let brandIDs = try await loadWritableBrandIDsWithRetry(identityKey: normalizedIdentityKey)
            writableBrandIDs = brandIDs
            loadedWritableBrandsIdentityKey = normalizedIdentityKey
            print(
                """
                [BrandAdminSessionStore] writable brands refreshed identity=\(normalizedIdentityKey) \
                count=\(brandIDs.count)
                """
            )
        } catch {
            clearWritableBrandIDs()
            loadedWritableBrandsIdentityKey = nil

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

    func canWrite(brandID: BrandID) -> Bool {
        writableBrandIDs.contains(brandID)
    }

    func reset() {
        clearCapabilities()
        clearWritableBrandIDs()
        isLoaded = false
        isLoading = false
        isLoadingWritableBrands = false
        loadedIdentityKey = nil
        loadedWritableBrandsIdentityKey = nil
    }

    private func clearCapabilities() {
        canCreateBrand = false
        roles = []
    }

    private func clearWritableBrandIDs() {
        writableBrandIDs = []
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

    private func loadWritableBrandIDsWithRetry(identityKey: String) async throws -> Set<BrandID> {
        do {
            return try await fetchWritableBrandIDs(identityKey: identityKey)
        } catch {
            let nsError = error as NSError
            print(
                """
                [BrandAdminSessionStore] writable brand retry scheduled domain=\(nsError.domain) \
                code=\(nsError.code) description=\(nsError.localizedDescription)
                """
            )
            try? await Task.sleep(nanoseconds: 500_000_000)
            return try await fetchWritableBrandIDs(identityKey: identityKey)
        }
    }

    private func fetchWritableBrandIDs(identityKey: String) async throws -> Set<BrandID> {
        let brandsCollection = db.collection("brands")

        async let ownerQuery = brandsCollection
            .whereField("ownerUIDs", arrayContains: identityKey)
            .getDocuments()
        async let adminQuery = brandsCollection
            .whereField("adminUIDs", arrayContains: identityKey)
            .getDocuments()

        let (ownerSnapshot, adminSnapshot) = try await (ownerQuery, adminQuery)
        let allDocuments = ownerSnapshot.documents + adminSnapshot.documents

        return Set(allDocuments.map { BrandID(value: $0.documentID) })
    }
}
