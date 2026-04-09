//
//  PushNotificationManager.swift
//  OutPick
//
//  Created by Codex on 4/10/26.
//

import UIKit
import UserNotifications
import FirebaseMessaging

@MainActor
final class PushNotificationManager: NSObject {
    static let shared = PushNotificationManager()

    private let notificationCenter = UNUserNotificationCenter.current()
    private var latestFCMToken: String?
    private var lastKnownPushEnabled = false
    private var didConfigure = false

    private override init() {
        super.init()
    }

    func configure(application: UIApplication) {
        guard !didConfigure else { return }
        didConfigure = true

        notificationCenter.delegate = self
        Messaging.messaging().delegate = self

        // Ensure we learn about the current token even if the delegate callback
        // happened before login finished.
        refreshFCMToken()

        if application.isRegisteredForRemoteNotifications {
            refreshAuthorizationState()
        }
    }

    func startForAuthenticatedUser() async {
        let application = UIApplication.shared
        configure(application: application)
        await syncAuthorizationState(application: application)
        refreshFCMToken()
        await PresenceManager.shared.refreshCurrentDeviceState(
            pushEnabledOverride: lastKnownPushEnabled,
            fcmTokenOverride: latestFCMToken
        )
    }

    func didRegisterForRemoteNotifications(deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
    }

    func didFailToRegisterForRemoteNotifications(error: Error) {
        print("[PushNotificationManager] APNs registration failed: \(error.localizedDescription)")
    }

    private func refreshAuthorizationState() {
        Task { @MainActor in
            await self.syncAuthorizationState(application: .shared)
        }
    }

    private func syncAuthorizationState(application: UIApplication) async {
        let settings = await notificationCenter.notificationSettings()
        let pushEnabled = isPushEnabled(status: settings.authorizationStatus)
        lastKnownPushEnabled = pushEnabled

        if settings.authorizationStatus == .notDetermined {
            do {
                let granted = try await notificationCenter.requestAuthorization(options: [.alert, .badge, .sound])
                lastKnownPushEnabled = granted
                if granted {
                    application.registerForRemoteNotifications()
                }
            } catch {
                print("[PushNotificationManager] notification authorization failed: \(error.localizedDescription)")
            }
        } else if pushEnabled {
            application.registerForRemoteNotifications()
        }

        await PresenceManager.shared.updatePushPermission(
            granted: lastKnownPushEnabled,
            fcmToken: latestFCMToken
        )
    }

    private func isPushEnabled(status: UNAuthorizationStatus) -> Bool {
        switch status {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied, .notDetermined:
            return false
        @unknown default:
            return false
        }
    }

    private func refreshFCMToken() {
        Messaging.messaging().token { [weak self] token, error in
            guard let self else { return }

            if let error {
                print("[PushNotificationManager] FCM token fetch failed: \(error.localizedDescription)")
                return
            }

            guard let token, !token.isEmpty else { return }

            Task { @MainActor in
                self.latestFCMToken = token
                await PresenceManager.shared.updatePushPermission(
                    granted: self.lastKnownPushEnabled,
                    fcmToken: token
                )
            }
        }
    }
}

@MainActor
extension PushNotificationManager: MessagingDelegate {
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        Task { @MainActor in
            self.latestFCMToken = fcmToken
            await PresenceManager.shared.updatePushPermission(
                granted: self.lastKnownPushEnabled,
                fcmToken: fcmToken
            )
        }
    }
}

@MainActor
extension PushNotificationManager: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let userInfo = notification.request.content.userInfo
        if let route = PushNotificationRoute.from(userInfo: userInfo),
           (route.messageType?.lowercased() == "chat" || userInfo["type"] as? String == "chat") {
            completionHandler([])
            return
        }

        if #available(iOS 14.0, *) {
            completionHandler([.banner, .list, .sound, .badge])
        } else {
            completionHandler([.alert, .sound, .badge])
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        NotificationRouter.shared.storePendingRoute(from: response.notification.request.content.userInfo)
        AppCoordinator.activeCoordinator?.consumePendingNotificationRouteIfPossible()
        completionHandler()
    }
}
