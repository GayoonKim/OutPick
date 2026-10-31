#if DEBUG && (targetEnvironment(simulator) || OUTPICK_BRAND_LOCAL_DEVICE)
import Foundation
import CryptoKit
import UIKit
import SwiftUI
import FirebaseCore
import FirebaseStorage

struct BrandLocalUIConfiguration {
    let target: BrandLocalIntegrationTarget
    let storageEndpoint: BrandLocalIntegrationTarget.Endpoint
    let targetSHA256: String
    let publicRootSHA256: String?

    // canonical loopback 원본과 Storage 원본을 먼저 검증하고 LAN 중계만 치환한다.
    init(targetData: Data, storageData: Data, deviceData: Data, expectedDeviceSHA256: String,
         publicRootData: Data, now: Date = Date()) throws {
        let canonical = try Self(targetData: targetData, storageData: storageData)
        guard expectedDeviceSHA256.count == 64,
              SHA256.hash(data: deviceData).map({ String(format: "%02x", $0) }).joined() == expectedDeviceSHA256,
              let wire = try JSONSerialization.jsonObject(with: deviceData) as? [String: Any],
              wire["status"] as? String == "ready", wire["scope"] as? String == "ios-single-device-read-relay",
              wire["projectID"] as? String == "outpick-test", wire["region"] as? String == "asia-northeast3",
              wire["tenantID"] is NSNull, wire["timeLimit"] is NSNull,
              wire["allowedPeerIP"] as? String == "192.168.123.169",
              wire["roundID"] as? String == canonical.target.roundID,
              wire["roundID"] as? String == "49fd2792-eca0-45b8-b711-e72b9124add4",
              wire["targetSHA256"] as? String == canonical.targetSHA256,
              wire["userUID"] as? String == "fixture-user",
              wire["groupID"] as? String == "ba0b02d1d3f1c0a889226d2060165c63",
              wire["brandID"] as? String == "668fefda94c3ac1055720b1823256703a38a3966de214f5a7989683c199d189c",
              wire["seasonID"] as? String == "local-l159-first-season",
              wire["credentialsIncluded"] as? Bool == false,
              wire["automaticallyRestarts"] as? Bool == false,
              wire["expiresOnUSBDisconnect"] as? Bool == false,
              wire["stopsOnQAComplete"] as? Bool == true,
              let endpoints = wire["endpoints"] as? [String: String],
              wire["connectionVersion"] as? Int == 2,
              let functionsBaseURL = wire["functionsBaseURL"] as? String,
              let tls = wire["functionsTLS"] as? [String: Any],
              !publicRootData.isEmpty,
              let rootSHA = tls["publicRootSHA256"] as? String,
              rootSHA == SHA256.hash(data: publicRootData).map({ String(format: "%02x", $0) }).joined(),
              let rootFingerprint = tls["rootFingerprint256"] as? String,
              rootFingerprint.replacingOccurrences(of: ":", with: "").lowercased() == rootSHA,
              let serverFingerprint = tls["serverFingerprint256"] as? String,
              serverFingerprint.range(of: "^([A-F0-9]{2}:){31}[A-F0-9]{2}$", options: .regularExpression) != nil,
              let validUntil = tls["validUntil"] as? String,
              let expiry = Self.tlsDate(validUntil), expiry > now,
              expiry.timeIntervalSince(now) <= 31 * 24 * 60 * 60 else {
            throw BrandLocalIntegrationError.invalidTarget
        }
        (target, storageEndpoint) = try BrandLocalIntegrationTarget.deviceRelay(canonical: canonical.target,
            endpoints: endpoints, functionsBaseURL: functionsBaseURL)
        targetSHA256 = canonical.targetSHA256
        publicRootSHA256 = rootSHA
    }

    init(targetData: Data, storageData: Data) throws {
        struct StorageWire: Decodable {
            let projectID: String
            let roundID: String
            let storageHost: String
            let firestoreHost: String
            let targetSHA256: String
        }
        target = try BrandLocalIntegrationTarget(data: targetData)
        publicRootSHA256 = nil
        let wire = try JSONDecoder().decode(StorageWire.self, from: storageData)
        targetSHA256 = SHA256.hash(data: targetData).map { String(format: "%02x", $0) }.joined()
        guard wire.projectID == "outpick-test", wire.roundID == target.roundID,
              wire.firestoreHost == target.firestore.authority, wire.targetSHA256 == targetSHA256 else {
            throw BrandLocalIntegrationError.invalidTarget
        }
        storageEndpoint = try .init(wire.storageHost)
        guard ![target.auth.port, target.functions.port, target.firestore.port].contains(storageEndpoint.port) else {
            throw BrandLocalIntegrationError.invalidTarget
        }
    }

    private static func tlsDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)
    }
}

// 인증/SDK 오류 원문은 기록하지 않는다. 화면·이미지의 로컬 진단만 보존한다.
final class BrandLocalUIEvidence: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [[String: Any]] = []
    private let url: URL
    init(url: URL) { self.url = url }
    func record(_ kind: String, _ fields: [String: Any] = [:]) {
        lock.lock()
        defer { lock.unlock() }
        var event = fields
        event["kind"] = kind
        event["at"] = ISO8601DateFormatter().string(from: Date())
        events.append(event)
        guard let data = try? JSONSerialization.data(withJSONObject: ["events": events,
            "credentialsIncluded": false], options: [.prettyPrinted, .sortedKeys]) else { return }
        try? data.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

struct BrandLocalReadOnlyTransport: CloudFunctionsTransporting {
    let base: any CloudFunctionsTransporting
    var evidence: BrandLocalUIEvidence?
    func call(_ name: String, data: [String: Any]) async throws -> [String: Any] {
        guard name == "listMyBrandRequests" else {
            evidence?.record("callable.blocked", ["name": name])
            throw BrandLocalIntegrationError.isolatedModeRequired
        }
        evidence?.record("callable.started", ["name": name])
        let value: [String: Any]
        do {
            value = try await base.call(name, data: data)
        } catch {
            // 응답/메시지/userInfo는 인증 정보가 섞일 수 있으므로 기록하지 않는다.
            let failure = error as NSError
            evidence?.record("callable.failed", ["name": name, "domain": failure.domain, "code": failure.code])
            throw error
        }
        let rows = (value["requests"] as? [[String: Any]]) ?? []
        evidence?.record("requests.received", ["scope": value["scope"] ?? NSNull(),
            "rows": rows.count, "states": rows.compactMap { $0["status"] as? String },
            "resolvedBrandIDs": rows.compactMap { $0["resolvedBrandID"] as? String }])
        return value
    }
}

private struct BrandLocalBlockedTransfers: FirebaseStorageTransferRepositoryProtocol {
    func setDataFallbackLimitMB(_ mb: Int) {}
    func uploadWithRetry(data: Data, to path: String, contentType: String, uploadFailure: Error,
        cacheControl: String?, retries: Int, backoff: Double, progress: ((Int64, Int64) -> Void)?) async throws -> String {
        throw BrandLocalIntegrationError.isolatedModeRequired
    }
    func uploadFileWithRetry(from fileURL: URL, to path: String, contentType: String, uploadFailure: Error,
        cacheControl: String?, retries: Int, backoff: Double, progress: ((Int64, Int64) -> Void)?) async throws -> String {
        throw BrandLocalIntegrationError.isolatedModeRequired
    }
    func uploadFileWithRetryAndDataFallback(from fileURL: URL, to path: String, contentType: String,
        uploadFailure: Error, cacheControl: String?, retries: Int, backoff: Double,
        progress: ((Int64, Int64) -> Void)?) async throws -> String {
        throw BrandLocalIntegrationError.isolatedModeRequired
    }
}

// 이미지를 성공으로 대체하지 않고 기존 Storage 다운로드만 통과시킨다.
private struct BrandLocalReadOnlyStorage: StorageServiceProtocol {
    let base: LookbookStorageService
    let evidence: BrandLocalUIEvidence
    private func check(_ path: String) throws {
        guard path.hasPrefix("brands/"), !path.contains("://"), !path.contains("..") else {
            throw BrandLocalIntegrationError.invalidTarget
        }
    }
    func downloadData(from path: String, maxSize: Int) async throws -> Data {
        try check(path)
        do {
            let data = try await base.downloadData(from: path, maxSize: maxSize)
            evidence.record("storage.download", ["path": path, "bytes": data.count,
                "sha256": SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()])
            return data
        } catch {
            evidence.record("storage.failed", ["path": path, "domain": (error as NSError).domain,
                "code": (error as NSError).code])
            throw error
        }
    }
    func downloadImage(from path: String, maxSize: Int) async throws -> Data {
        try await downloadData(from: path, maxSize: maxSize)
    }
    func downloadImages(_ paths: [String], maxSize: Int) async throws -> [Data] {
        var results: [Data] = []
        for path in paths { results.append(try await downloadData(from: path, maxSize: maxSize)) }
        return results
    }
    func downloadFile(from path: String, to localURL: URL) async throws {
        try check(path)
        try await base.downloadFile(from: path, to: localURL)
    }
    func downloadImageFile(from path: String, to localURL: URL, maxBytes: Int) async throws {
        try check(path)
        do {
            try await base.downloadImageFile(from: path, to: localURL, maxBytes: maxBytes)
            let data = try Data(contentsOf: localURL)
            evidence.record("storage.downloadFile", ["path": path, "bytes": data.count,
                "sha256": SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()])
        } catch {
            evidence.record("storage.failed", ["path": path, "domain": (error as NSError).domain,
                "code": (error as NSError).code])
            throw error
        }
    }
    func uploadImage(data: Data, to path: String) async throws -> String { throw BrandLocalIntegrationError.isolatedModeRequired }
    func uploadImageFileWithRetryAndDataFallback(from fileURL: URL, to path: String, contentType: String) async throws -> String { throw BrandLocalIntegrationError.isolatedModeRequired }
    func uploadVideo(fileURL: URL, to path: String) async throws -> String { throw BrandLocalIntegrationError.isolatedModeRequired }
    func uploadImages(_ datas: [Data], to folderPath: String) async throws -> [String] { throw BrandLocalIntegrationError.isolatedModeRequired }
    func deleteFile(at path: String) async throws { throw BrandLocalIntegrationError.isolatedModeRequired }
    func updateFile(data: Data, at path: String) async throws -> String { throw BrandLocalIntegrationError.isolatedModeRequired }
    func updateMetadata(for path: String, metadata: StorageMetadata) async throws -> StorageMetadata { throw BrandLocalIntegrationError.isolatedModeRequired }
}

private struct BrandLocalCurrentUser: CurrentUserProviding {
    let canonicalUserID: String
    var email: String { "" }
    var nickname: String? { nil }
    var avatarPath: String? { nil }
    var profile: UserPublicProfile? { nil }
}

@MainActor
final class BrandLocalUIBootstrap: NSObject, UINavigationControllerDelegate {
    private weak var window: UIWindow?
    private var context: BrandLocalIntegrationContext?
    private var container: LookbookContainer?
    private var coordinator: LookbookCoordinator?
    private var evidence: BrandLocalUIEvidence?
    init(window: UIWindow) { self.window = window }

    func start() async {
        do {
            guard BrandLocalIntegrationMode.isEnabled else { throw BrandLocalIntegrationError.isolatedModeRequired }
            let environment = ProcessInfo.processInfo.environment
            let output = environment["OUTPICK_BRAND_LOCAL_OUTPUT"].map { URL(fileURLWithPath: $0) }
                ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("brand-local-ui-evidence.json")
            let evidence = BrandLocalUIEvidence(url: output)
            self.evidence = evidence
            evidence.record("bootstrap.started")
            let config: BrandLocalUIConfiguration
            let loginPath: String
            #if OUTPICK_BRAND_LOCAL_DEVICE && !targetEnvironment(simulator)
            guard Bundle.main.object(forInfoDictionaryKey: "OutPickBrandLocalDeviceBuild") as? Bool == true else {
                throw BrandLocalIntegrationError.isolatedModeRequired
            }
            let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("BrandLocalDevice", isDirectory: true)
            config = try BrandLocalUIConfiguration(
                targetData: Data(contentsOf: directory.appendingPathComponent("target.json")),
                storageData: Data(contentsOf: directory.appendingPathComponent("storage-target.json")),
                deviceData: Data(contentsOf: directory.appendingPathComponent("device-target.json")),
                expectedDeviceSHA256: String(contentsOf: directory.appendingPathComponent("accepted-relay-sha256.txt"), encoding: .utf8)
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                publicRootData: Data(contentsOf: directory.appendingPathComponent("public-root.cer")))
            loginPath = directory.appendingPathComponent("login.private.json").path
            #else
            guard let targetPath = environment["OUTPICK_BRAND_LOCAL_TARGET"],
                  let storagePath = environment["OUTPICK_BRAND_LOCAL_STORAGE_TARGET"],
                  let environmentLoginPath = environment["OUTPICK_BRAND_LOCAL_LOGIN"] else {
                throw BrandLocalIntegrationError.unavailableConfiguration
            }
            config = try BrandLocalUIConfiguration(targetData: Data(contentsOf: URL(fileURLWithPath: targetPath)),
                storageData: Data(contentsOf: URL(fileURLWithPath: storagePath)))
            loginPath = environmentLoginPath
            #endif
            evidence.record("bootstrap.local-targets", ["roundID": config.target.roundID,
                "auth": config.target.auth.authority, "functions": config.target.functions.authority,
                "firestore": config.target.firestore.authority, "storage": config.storageEndpoint.authority,
                "targetSHA256": config.targetSHA256])
            if let baseURL = config.target.functionsBaseURL {
                evidence.record("bootstrap.functions-https", ["baseURL": baseURL,
                    "publicRootSHA256": config.publicRootSHA256 ?? "", "connectionVersion": 2])
            }
            let context = try AppCompositionRoot.makeBrandLocalIntegration(target: config.target)
            self.context = context
            let storage = Storage.storage(app: context.app, url: "gs://outpick-test.appspot.com")
            storage.useEmulator(withHost: config.storageEndpoint.host, port: config.storageEndpoint.port)
            storage.maxDownloadRetryTime = 10
            struct Login: Decodable {
                struct User: Decodable { let uid: String; let email: String }
                let projectID: String
                let syntheticLocalOnly: Bool
                let user: User
                let password: String
            }
            let login = try JSONDecoder().decode(Login.self, from: Data(contentsOf: URL(fileURLWithPath: loginPath)))
            guard login.syntheticLocalOnly, login.projectID == "outpick-test" else { throw BrandLocalIntegrationError.invalidTarget }
            #if OUTPICK_BRAND_LOCAL_DEVICE && !targetEnvironment(simulator)
            let loginWire = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: loginPath))) as? [String: Any]
            guard login.user.uid == "fixture-user", loginWire?["tenantID"] is NSNull,
                  Set(loginWire?.keys.map { $0 } ?? []) == Set(["projectID", "user", "password", "tenantID", "syntheticLocalOnly"]) else {
                throw BrandLocalIntegrationError.invalidTarget
            }
            try FileManager.default.setAttributes([.posixPermissions: 0o600, .protectionKey: FileProtectionType.complete], ofItemAtPath: loginPath)
            #endif
            let result = try await context.auth.signIn(withEmail: login.user.email, password: login.password)
            guard result.user.uid == login.user.uid, context.auth.tenantID == nil else { throw BrandLocalIntegrationError.invalidTarget }
            evidence.record("auth.general-local", ["defaultAppCreated": FirebaseApp.app() != nil,
                "appCheckProviderDisabled": true, "tenant": NSNull()])
            let provider = makeProvider(context: context, storage: storage, evidence: evidence, round: config.target.roundID)
            BrandLocalRepositoryEnvironment.shared.install(provider)
            evidence.record("environment.local-provider", [
                "sameInjectedProvider": EnvironmentValues().repositoryProvider === provider,
                "defaultAppCreated": FirebaseApp.app() != nil])
            let blocked = BrandLocalReadOnlyTransport(base: context.transport, evidence: evidence)
            let imageRepository = FirebaseImageStorageRepository(transferService: BrandLocalBlockedTransfers(), db: context.db, storage: storage)
            let firebase = FirebaseRepositoryProvider(userProfileRepository: UserProfileRepository(db: context.db),
                chatRoomRepository: FirebaseChatRoomRepository(db: context.db), imageStorageRepository: imageRepository,
                videoStorageRepository: FirebaseVideoStorageRepository(transferService: BrandLocalBlockedTransfers(), storage: storage),
                messageRepository: FirebaseMessageRepository(db: context.db),
                mediaIndexRepository: FirebaseChatRoomMediaIndexRepository(db: context.db),
                announcementRepository: FirebaseAnnouncementRepository(db: context.db))
            let currentUser = BrandLocalCurrentUser(canonicalUserID: result.user.uid)
            let container = LookbookContainer(provider: provider,
                brandAdminSessionStore: BrandAdminSessionStore(capabilitiesClient: BrandAdminCapabilitiesCloudFunctionsClient(transport: blocked),
                    currentUserProvider: currentUser),
                currentUserProvider: currentUser,
                stylePreferenceStore: CurrentUserStylePreferenceStore(), firebaseRepositories: firebase,
                publicProfileRepository: FirestoreUserPublicProfileRepository(db: context.db),
                avatarImageManager: AvatarImageService(imageStorageRepository: imageRepository, pipeline: provider.imageCachePipeline))
            self.container = container
            let coordinator = LookbookCoordinator(container: container)
            self.coordinator = coordinator
            let navigation = LookbookNavigationController()
            navigation.loadViewIfNeeded()
            navigation.delegate = self
            coordinator.attach(navigationController: navigation)
            window?.rootViewController = navigation
            coordinator.pushMyBrandRequests(initialScope: .history)
            evidence.record("ui.history.opened")
        } catch {
            evidence?.record("bootstrap.failed", ["domain": (error as NSError).domain, "code": (error as NSError).code])
            let controller = UIViewController()
            controller.view.backgroundColor = .black
            let label = UILabel()
            label.text = "로컬 화면 검사 연결을 확인하지 못했어요."
            label.textColor = .white
            label.numberOfLines = 0
            label.frame = CGRect(x: 24, y: 180, width: 320, height: 100)
            controller.view.addSubview(label)
            window?.rootViewController = controller
        }
    }

    func navigationController(_ navigationController: UINavigationController, didShow viewController: UIViewController, animated: Bool) {
        (navigationController as? LookbookNavigationController)?.refreshInteractivePopAvailability()
        evidence?.record("ui.didShow", ["controller": String(reflecting: type(of: viewController)),
            "depth": navigationController.viewControllers.count])
    }

    private func makeProvider(context: BrandLocalIntegrationContext, storage: Storage,
        evidence: BrandLocalUIEvidence, round: String) -> LookbookRepositoryProvider {
        let db = context.db
        let transport = BrandLocalReadOnlyTransport(base: context.transport, evidence: evidence)
        let readStorage = BrandLocalReadOnlyStorage(base: LookbookStorageService(storage: storage,
            transferService: BrandLocalBlockedTransfers()), evidence: evidence)
        let folder = "BrandLocalUI-" + round + "-" + UUID().uuidString
        let pipeline = ImageCachePipeline(fetcher: { path, max in
            try await readStorage.downloadImage(from: path, maxSize: max)
        }, fileFetcher: { path, max, url in
            try await readStorage.downloadImageFile(from: path, to: url, maxBytes: max)
        }, disk: ImageCacheDiskStore(folderName: folder), decoder: { data in
            let image = ImageFileDecoding.image(data)
            evidence.record("image.decoded", ["bytes": data.count, "success": image != nil,
                "width": image?.size.width ?? 0, "height": image?.size.height ?? 0])
            return image
        }, fileDecoder: { url in
            let image = ImageFileDecoding.image(url)
            evidence.record("image.fileDecoded", ["success": image != nil,
                "width": image?.size.width ?? 0, "height": image?.size.height ?? 0])
            return image
        })
        let cacheDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent(folder + "-http")
        let http = LookbookHTTPImageCache(directory: cacheDirectory, fetch: { request, _ in
            evidence.record("image.externalHTTPBlocked", ["host": request.url?.host ?? "unknown"])
            throw BrandLocalIntegrationError.isolatedModeRequired
        })
        let imageCache = BrandImageCache(storage: readStorage, pipeline: pipeline, httpCache: http)
        evidence.record("image.cold-cache", ["folder": folder])
        return LookbookRepositoryProvider(currentUserUIDProvider: { context.auth.currentUser?.uid ?? "" },
            brandRepository: context.brands, brandSearchRepository: CloudFunctionsBrandSearchRepository(transport: transport),
            brandRequestRepository: CloudFunctionsBrandRequestRepository(transport: transport),
            lookbookDeletionRepository: CloudFunctionsLookbookDeletionRepository(transport: transport),
            brandEngagementRepository: CloudFunctionsBrandEngagementRepository(transport: transport),
            brandStore: CloudFunctionsBrandStore(transport: transport), styleMoodRepository: FirestoreStyleMoodRepository(db: db),
            styleMoodAdminRepository: CloudFunctionsStyleMoodAdminRepository(transport: transport),
            seasonMoodAdminRepository: CloudFunctionsSeasonMoodAdminRepository(transport: transport),
            seasonRepository: FirestoreSeasonRepository(db: db), seasonEngagementRepository: CloudFunctionsSeasonEngagementRepository(transport: transport),
            seasonUserStateRepository: FirestoreSeasonUserStateRepository(db: db),
            postRepository: FirestorePostRepository(db: db), postEngagementRepository: CloudFunctionsPostEngagementRepository(transport: transport),
            tagRepository: FirestoreTagRepository(db: db), commentRepository: FirestoreCommentRepository(db: db),
            commentWritingRepository: CloudFunctionsCommentWritingRepository(transport: transport),
            commentEngagementRepository: CloudFunctionsCommentEngagementRepository(transport: transport),
            commentSafetyRepository: CloudFunctionsCommentSafetyRepository(transport: transport),
            userBlockRepository: CloudFunctionsUserBlockRepository(transport: transport, db: db),
            replacementRepository: FirestoreReplacementRepository(db: db),
            postUserStateRepository: FirestorePostUserStateRepository(db: db), brandUserStateRepository: FirestoreBrandUserStateRepository(db: db),
            commentUserStateRepository: FirestoreCommentUserStateRepository(db: db), brandImageCache: imageCache,
            imageCachePipeline: pipeline, storageService: readStorage)
    }
}
#endif
