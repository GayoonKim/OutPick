//
//  AppDelegate.swift
//  OutPick
//
//  Created by 김가윤 on 7/11/24.
//
import UIKit
import KakaoSDKCommon
import KakaoSDKAuth
import KakaoSDKUser
import FirebaseCore
import FirebaseAuth
import FirebaseStorage
import GoogleSignIn

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
      return GIDSignIn.sharedInstance.handle(url)
    }
    

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {

        KakaoSDK.initSDK(appKey: "a2b20f7bedfb9582147f572ef004d0f0")
        configureFirebaseApp()
        warmUpFirebaseStorage()
//        runLookbookImageABTestIfNeeded()

        // GoogleSignIn configuration (prevents "No active configuration" crash)
        if let clientID = FirebaseApp.app()?.options.clientID {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        } else if isRunningTestFirebaseUITest() {
            // 테스트 Firebase plist는 Google Sign-In OAuth client를 포함하지 않는다.
            // 실제 Firebase UITest는 --uitest-authenticated 경로를 사용하므로 GoogleSignIn 설정을 건너뛴다.
            print("[AppDelegate] Skip GoogleSignIn configuration for test Firebase UITest.")
        } else {
            assertionFailure("Firebase clientID 없음: GoogleService-Info.plist 타겟 포함 여부 확인")
        }

        OutPickTheme.applyAppAppearance()
        return true
    }

    private func configureFirebaseApp(processInfo: ProcessInfo = .processInfo) {
        #if DEBUG
        if processInfo.environment["UITESTS"] == "1",
           processInfo.arguments.contains("--uitest-test-firebase") {
            guard let plistPath = processInfo.environment["OUTPICK_TEST_FIREBASE_PLIST_PATH"],
                  plistPath.isEmpty == false,
                  let options = FirebaseOptions(contentsOfFile: plistPath) else {
                fatalError("OUTPICK_TEST_FIREBASE_PLIST_PATH로 유효한 테스트 Firebase plist 경로를 전달해야 합니다.")
            }

            FirebaseApp.configure(options: options)
            return
        }
        #endif

        FirebaseApp.configure()
    }

    private func isRunningTestFirebaseUITest(processInfo: ProcessInfo = .processInfo) -> Bool {
        #if DEBUG
        return processInfo.environment["UITESTS"] == "1" &&
            processInfo.arguments.contains("--uitest-test-firebase")
        #else
        return false
        #endif
    }
    
    // MARK: UISceneSession Lifecycle
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // Called when a new scene session is being created.
        // Use this method to select a configuration to create the new scene with.
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }
    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
        // Called when the user discards a scene session.
        // If any sessions were discarded while the application was not running, this will be called shortly after application:didFinishLaunchingWithOptions.
        // Use this method to release any resources that were specific to the discarded scenes, as they will not return.
        
    }

    private func warmUpFirebaseStorage() {
        _ = Storage.storage().reference()

        Task.detached(priority: .utility) {
            guard Auth.auth().currentUser != nil else { return }
            let storage = Storage.storage()
            let warmupRef = storage.reference().child("warmup/ping.txt")
            _ = try? await warmupRef.getMetadata()
        }
    }

    private func runLookbookImageABTestIfNeeded() {
        guard let configuration = LookbookImageABTestConfiguration.make() else {
            return
        }

        Task.detached(priority: .utility) {
            let runner = LookbookImageABTestRunner(storage: Storage.storage())
            await runner.run(configuration: configuration)
        }
    }
}

private struct LookbookImageABTestConfiguration {
    let path: String
    let maxBytes: Int

    static func make() -> Self? {
        let processInfo = ProcessInfo.processInfo
        let arguments = processInfo.arguments

        let pathFromArguments: String? = {
            guard let flagIndex = arguments.firstIndex(of: "-LookbookImageABPath"),
                  flagIndex + 1 < arguments.count else {
                return nil
            }
            return arguments[flagIndex + 1]
        }()

        let path = processInfo.environment["LOOKBOOK_IMAGE_AB_PATH"]
            ?? pathFromArguments

        guard let rawPath = path?.trimmingCharacters(in: .whitespacesAndNewlines),
              rawPath.isEmpty == false else {
            return nil
        }

        let maxBytesFromArguments: Int? = {
            guard let flagIndex = arguments.firstIndex(of: "-LookbookImageABMaxBytes"),
                  flagIndex + 1 < arguments.count else {
                return nil
            }
            return Int(arguments[flagIndex + 1])
        }()

        let maxBytes = Int(processInfo.environment["LOOKBOOK_IMAGE_AB_MAX_BYTES"] ?? "")
            ?? maxBytesFromArguments
            ?? 1_500_000

        return .init(path: rawPath, maxBytes: max(1, maxBytes))
    }
}

private struct LookbookImageABTestResult {
    let label: String
    let bytes: Int
    let fetchMilliseconds: Double
    let decodeMilliseconds: Double
    let totalMilliseconds: Double
}

private actor LookbookImageABTestRunner {
    private let storage: Storage

    init(storage: Storage) {
        self.storage = storage
    }

    func run(configuration: LookbookImageABTestConfiguration) async {
        print("[LookbookImageAB] start path=\(configuration.path) maxBytes=\(configuration.maxBytes)")

        do {
            let dataResult = try await measureStorageDataLoad(
                path: configuration.path,
                maxBytes: configuration.maxBytes
            )
            print(
                "[LookbookImageAB] ref.data result total=\(format(dataResult.totalMilliseconds)) fetch=\(format(dataResult.fetchMilliseconds)) decode=\(format(dataResult.decodeMilliseconds)) bytes=\(dataResult.bytes)"
            )
        } catch {
            print("[LookbookImageAB] ref.data failed error=\(error.localizedDescription)")
        }

        do {
            let urlSessionResult = try await measureDownloadURLAndURLSessionLoad(
                path: configuration.path
            )
            print(
                "[LookbookImageAB] downloadURL+URLSession result total=\(format(urlSessionResult.totalMilliseconds)) fetch=\(format(urlSessionResult.fetchMilliseconds)) decode=\(format(urlSessionResult.decodeMilliseconds)) bytes=\(urlSessionResult.bytes)"
            )
        } catch {
            print("[LookbookImageAB] downloadURL+URLSession failed error=\(error.localizedDescription)")
        }
    }

    private func measureStorageDataLoad(
        path: String,
        maxBytes: Int
    ) async throws -> LookbookImageABTestResult {
        let reference = storage.reference(withPath: path)
        let totalStartedAt = CFAbsoluteTimeGetCurrent()

        let fetchStartedAt = CFAbsoluteTimeGetCurrent()
        let data = try await reference.data(maxSize: Int64(maxBytes))
        let fetchMilliseconds = elapsedMilliseconds(since: fetchStartedAt)

        let decodeStartedAt = CFAbsoluteTimeGetCurrent()
        guard UIImage(data: data) != nil else {
            throw NSError(
                domain: "LookbookImageABTestRunner",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "ref.data 결과를 UIImage로 디코딩하지 못했습니다."]
            )
        }
        let decodeMilliseconds = elapsedMilliseconds(since: decodeStartedAt)

        return LookbookImageABTestResult(
            label: "ref.data",
            bytes: data.count,
            fetchMilliseconds: fetchMilliseconds,
            decodeMilliseconds: decodeMilliseconds,
            totalMilliseconds: elapsedMilliseconds(since: totalStartedAt)
        )
    }

    private func measureDownloadURLAndURLSessionLoad(
        path: String
    ) async throws -> LookbookImageABTestResult {
        let reference = storage.reference(withPath: path)
        let totalStartedAt = CFAbsoluteTimeGetCurrent()

        let downloadURLStartedAt = CFAbsoluteTimeGetCurrent()
        let url = try await reference.downloadURL()
        let downloadURLMilliseconds = elapsedMilliseconds(since: downloadURLStartedAt)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60

        let request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 30
        )

        let fetchStartedAt = CFAbsoluteTimeGetCurrent()
        let (data, _) = try await URLSession(configuration: configuration).data(for: request)
        let fetchMilliseconds = elapsedMilliseconds(since: fetchStartedAt)

        let decodeStartedAt = CFAbsoluteTimeGetCurrent()
        guard UIImage(data: data) != nil else {
            throw NSError(
                domain: "LookbookImageABTestRunner",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "downloadURL 경로 결과를 UIImage로 디코딩하지 못했습니다."]
            )
        }
        let decodeMilliseconds = elapsedMilliseconds(since: decodeStartedAt)

        return LookbookImageABTestResult(
            label: "downloadURL+URLSession(\(format(downloadURLMilliseconds)) + \(format(fetchMilliseconds)))",
            bytes: data.count,
            fetchMilliseconds: downloadURLMilliseconds + fetchMilliseconds,
            decodeMilliseconds: decodeMilliseconds,
            totalMilliseconds: elapsedMilliseconds(since: totalStartedAt)
        )
    }

    private func elapsedMilliseconds(since startedAt: CFAbsoluteTime) -> Double {
        (CFAbsoluteTimeGetCurrent() - startedAt) * 1000
    }

    private func format(_ milliseconds: Double) -> String {
        String(format: "%.0fms", milliseconds)
    }
}
