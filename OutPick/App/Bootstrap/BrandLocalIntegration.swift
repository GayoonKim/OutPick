#if DEBUG && (targetEnvironment(simulator) || OUTPICK_BRAND_LOCAL_DEVICE)
import Foundation
import FirebaseCore
import FirebaseAuth
import FirebaseFunctions
import FirebaseFirestore
import FirebaseAppCheck

enum BrandLocalIntegrationMode {
    static var showsLocalUI: Bool {
        #if OUTPICK_BRAND_LOCAL_DEVICE && !targetEnvironment(simulator)
        return true
        #else
        return ProcessInfo.processInfo.environment["OUTPICK_BRAND_LOCAL_UI"] == "1"
        #endif
    }

    static var isEnabled: Bool {
        #if (OUTPICK_BRAND_LOCAL_INTEGRATION && targetEnvironment(simulator)) || (OUTPICK_BRAND_LOCAL_DEVICE && !targetEnvironment(simulator))
        return true
        #else
        return false
        #endif
    }
}

enum BrandLocalIntegrationError: LocalizedError {
    case invalidTarget, isolatedModeRequired, unavailableConfiguration
    var errorDescription: String? { "로컬 브랜드 검사 설정을 확인하지 못했습니다." }
}

struct BrandLocalIntegrationTarget {
    struct Endpoint: Equatable {
        let host: String
        let port: Int
        init(_ raw: String) throws {
            let parts = raw.split(separator: ":", omittingEmptySubsequences: false)
            guard parts.count == 2, parts[0] == "127.0.0.1", let port = Int(parts[1]),
                  (1024...65535).contains(port), String(port) == parts[1] else {
                throw BrandLocalIntegrationError.invalidTarget
            }
            host = "127.0.0.1"
            self.port = port
        }
        var authority: String { "\(host):\(port)" }

        // 승인된 실기기 중계 어댑터만 사용한다. 기본 파서는 loopback 전용이다.
        fileprivate init(deviceRelay raw: String) throws {
            let parts = raw.split(separator: ":", omittingEmptySubsequences: false)
            guard parts.count == 2, parts[0] == "192.168.123.110",
                  let port = Int(parts[1]), (1024...65535).contains(port), String(port) == parts[1] else {
                throw BrandLocalIntegrationError.invalidTarget
            }
            host = String(parts[0])
            self.port = port
        }
    }

    let auth: Endpoint
    let functions: Endpoint
    let firestore: Endpoint
    let roundID: String
    let functionsBaseURL: String?

    private init(auth: Endpoint, functions: Endpoint, firestore: Endpoint, roundID: String, functionsBaseURL: String) {
        self.auth = auth
        self.functions = functions
        self.firestore = firestore
        self.roundID = roundID
        self.functionsBaseURL = functionsBaseURL
    }

    static func deviceRelay(canonical: Self, endpoints: [String: String], functionsBaseURL: String) throws -> (Self, Endpoint) {
        guard Set(endpoints.keys) == Set(["auth", "functions", "firestore", "storage"]) else {
            throw BrandLocalIntegrationError.invalidTarget
        }
        let auth = try Endpoint(deviceRelay: endpoints["auth"]!)
        let functions = try Endpoint(deviceRelay: endpoints["functions"]!)
        let firestore = try Endpoint(deviceRelay: endpoints["firestore"]!)
        let storage = try Endpoint(deviceRelay: endpoints["storage"]!)
        guard Set([auth.port, functions.port, firestore.port, storage.port]).count == 4,
              functionsBaseURL == "https://\(functions.authority)/outpick-test/asia-northeast3" else {
            throw BrandLocalIntegrationError.invalidTarget
        }
        return (.init(auth: auth, functions: functions, firestore: firestore, roundID: canonical.roundID,
            functionsBaseURL: functionsBaseURL), storage)
    }

    init(data: Data) throws {
        struct Wire: Decodable {
            let projectID: String
            let region: String
            let authHost: String
            let functionsHost: String
            let firestoreHost: String
            let allRequiredServicesLocal: Bool
            let inheritedCredentials: Bool
            let directory: String
            let functionNames: [String]
        }
        let wire = try JSONDecoder().decode(Wire.self, from: data)
        let round = URL(fileURLWithPath: wire.directory).lastPathComponent
        guard wire.projectID == "outpick-test", wire.region == "asia-northeast3",
              wire.allRequiredServicesLocal, !wire.inheritedCredentials,
              UUID(uuidString: round) != nil,
              Set(["submitBrandRequest", "listMyBrandRequests", "searchBrands"]).isSubset(of: Set(wire.functionNames)) else {
            throw BrandLocalIntegrationError.invalidTarget
        }
        auth = try Endpoint(wire.authHost)
        functions = try Endpoint(wire.functionsHost)
        firestore = try Endpoint(wire.firestoreHost)
        guard Set([auth.port, functions.port, firestore.port]).count == 3 else {
            throw BrandLocalIntegrationError.invalidTarget
        }
        roundID = round
        functionsBaseURL = nil
    }
}

@MainActor
final class BrandLocalIntegrationContext {
    let app: FirebaseApp
    let auth: Auth
    let db: Firestore
    let requests: CloudFunctionsBrandRequestRepository
    let brands: FirestoreBrandRepository
    let search: CloudFunctionsBrandSearchRepository
    let transport: FirebaseCloudFunctionsTransport

    fileprivate init(target: BrandLocalIntegrationTarget) throws {
        guard BrandLocalIntegrationMode.isEnabled, FirebaseApp.app() == nil else {
            throw BrandLocalIntegrationError.isolatedModeRequired
        }
        // 실제 plist/기본 앱/실계정·AppCheck provider를 초기화하지 않는다.
        let options = FirebaseOptions(googleAppID: "1:1234567890:ios:00000000000000000000000000000000", gcmSenderID: "1234567890")
        options.projectID = "outpick-test"
        // SDK의 형식 검사만 만족하는 가상 값이며 실제 키를 읽지 않는다.
        options.apiKey = "A" + String(repeating: "0", count: 38)
        let name = "brand-local-" + UUID().uuidString
        // SDK 기본 Simulator provider의 원격 App Check 교환도 차단한다.
        AppCheck.setAppCheckProviderFactory(nil)
        FirebaseApp.configure(name: name, options: options)
        guard let app = FirebaseApp.app(name: name) else { throw BrandLocalIntegrationError.unavailableConfiguration }
        guard AppCheck.appCheck(app: app) == nil else { throw BrandLocalIntegrationError.isolatedModeRequired }
        app.isDataCollectionDefaultEnabled = false
        self.app = app
        auth = Auth.auth(app: app)
        auth.useEmulator(withHost: target.auth.host, port: target.auth.port)
        guard auth.tenantID == nil else { throw BrandLocalIntegrationError.invalidTarget }
        let functions: Functions
        if let baseURL = target.functionsBaseURL {
            // 공식 HTTPS customDomain 경로를 사용하고 emulator 설정으로 덮어쓰지 않는다.
            functions = Functions.functions(app: app, customDomain: baseURL)
        } else {
            functions = Functions.functions(app: app, region: "asia-northeast3")
            functions.useEmulator(withHost: target.functions.host, port: target.functions.port)
        }
        db = Firestore.firestore(app: app)
        let settings = FirestoreSettings()
        settings.host = target.firestore.authority
        settings.isSSLEnabled = false
        settings.cacheSettings = MemoryCacheSettings()
        db.settings = settings
        transport = FirebaseCloudFunctionsTransport(functions: functions,
            preservingErrorDetailsForCalls: ["submitBrandRequest", "listMyBrandRequests"])
        requests = CloudFunctionsBrandRequestRepository(transport: transport)
        brands = FirestoreBrandRepository(db: db)
        search = CloudFunctionsBrandSearchRepository(transport: transport)
    }
}

extension AppCompositionRoot {
    static func makeBrandLocalIntegration(target: BrandLocalIntegrationTarget) throws -> BrandLocalIntegrationContext {
        try BrandLocalIntegrationContext(target: target)
    }
}
#endif
