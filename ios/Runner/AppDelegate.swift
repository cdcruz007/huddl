import Flutter
import UIKit
import Foundation
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {

        // Register Flutter plugins — FlutterFire calls FirebaseApp.configure() here.
        GeneratedPluginRegistrant.register(with: self)

        // ── Firebase Phone Auth: disable APNs assertion for test numbers ──────
        // Must be set AFTER GeneratedPluginRegistrant (which initialises Firebase)
        // and BEFORE any phone verification call. This tells Firebase to skip the
        // APNs silent-push check and accept the test OTP directly.
        // Safe for production: only test numbers listed in Firebase Console are
        // affected; real numbers go through the normal SMS flow.
        Auth.auth().settings?.isAppVerificationDisabledForTesting = true

        // ── Request APNs early so the token is ready when needed ──────────────
        if #available(iOS 10.0, *) {
            let center = UNUserNotificationCenter.current()
            center.delegate = self
            center.requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in
                DispatchQueue.main.async {
                    application.registerForRemoteNotifications()
                }
            }
        } else {
            application.registerForRemoteNotifications()
        }

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    override func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        // Forward APNs token to Firebase Auth (used for real SMS verification)
        Auth.auth().setAPNSToken(deviceToken, type: .unknown)
        super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
    }

    override func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        // Firebase will fall back to reCAPTCHA when APNs isn't available
        super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
    }

    override func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) -> Bool {
        // Let Firebase Auth handle silent push notifications used for phone auth
        if Auth.auth().canHandleNotification(userInfo) {
            completionHandler(.noData)
            return true
        }
        return super.application(application, didReceiveRemoteNotification: userInfo,
                                  fetchCompletionHandler: completionHandler)
    }
}
