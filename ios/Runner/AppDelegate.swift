import Flutter
import UIKit
import UserNotifications
import FirebaseCore
import FirebaseAuth

@main
@objc class AppDelegate: FlutterAppDelegate {

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // Register Flutter plugins — this calls FirebaseApp.configure() internally.
        GeneratedPluginRegistrant.register(with: self)

        // Set appVerificationDisabledForTesting synchronously RIGHT HERE, immediately
        // after FirebaseApp.configure() has run (via plugin registration above).
        // Firebase docs require this to be set before calling verifyPhoneNumber.
        // Setting it here in native Swift (not async from Dart) guarantees it is
        // active before ANY call to verifyPhoneNumber, regardless of Dart timing.
        // This allows the registered test phone number (+447575888452, code 123456)
        // to work without APNs. For real numbers on real devices this has no effect.
        Auth.auth().settings?.isAppVerificationDisabledForTesting = true

        // Request APNs permission — needed for real-number verification on real devices.
        if #available(iOS 10.0, *) {
            UNUserNotificationCenter.current().delegate = self
            UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .badge, .sound]) { _, _ in
                DispatchQueue.main.async {
                    application.registerForRemoteNotifications()
                }
            }
        } else {
            application.registerForRemoteNotifications()
        }

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    // Forward APNs device token to Firebase Auth (needed for real-number verification).
    override func application(_ application: UIApplication,
                              didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Auth.auth().setAPNSToken(deviceToken, type: .unknown)
        super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
    }

    // Let Firebase Auth handle its own silent push notifications.
    override func application(_ application: UIApplication,
                              didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                              fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        if Auth.auth().canHandleNotification(userInfo) {
            completionHandler(.noData)
            return
        }
        super.application(application, didReceiveRemoteNotification: userInfo,
                          fetchCompletionHandler: completionHandler)
    }

    // Let Firebase Auth handle reCAPTCHA redirect URLs.
    override func application(_ app: UIApplication, open url: URL,
                              options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        if Auth.auth().canHandle(url) {
            return true
        }
        return super.application(app, open: url, options: options)
    }
}
