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

        // Register Flutter plugins first — FlutterFire initialises Firebase here.
        GeneratedPluginRegistrant.register(with: self)

        // Request APNs authorisation early so a device token is available
        // before the user reaches the phone verification screen.
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
        super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
    }

    override func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
    }
}
