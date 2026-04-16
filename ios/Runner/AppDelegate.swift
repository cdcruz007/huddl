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

        // 1. Register Flutter plugins (FlutterFire calls FirebaseApp.configure() here)
        GeneratedPluginRegistrant.register(with: self)

        // 2. Set up the method channel for native phone auth AFTER plugins are registered
        if let controller = window?.rootViewController as? FlutterViewController {
            let channel = FlutterMethodChannel(
                name: "com.huddlconnect/phone_auth",
                binaryMessenger: controller.binaryMessenger
            )
            channel.setMethodCallHandler { [weak self] call, result in
                guard let self = self else { return }
                if call.method == "sendOtp" {
                    guard let args = call.arguments as? [String: Any],
                          let phoneNumber = args["phoneNumber"] as? String else {
                        result(FlutterError(code: "INVALID_ARGS", message: "Missing phoneNumber", details: nil))
                        return
                    }
                    self.sendOtp(phoneNumber: phoneNumber, result: result)
                } else {
                    result(FlutterMethodNotImplemented)
                }
            }
        }

        // 3. Request APNs authorisation early
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

    // MARK: - Native phone auth via signInWithPhoneNumber (avoids verifyPhoneNumber SIGTRAP)

    private func sendOtp(phoneNumber: String, result: @escaping FlutterResult) {
        guard let viewController = window?.rootViewController else {
            result(FlutterError(code: "NO_VC", message: "No root view controller", details: nil))
            return
        }

        // Use the ObjC Firebase Auth API directly to avoid the Swift assertionFailure
        // that occurs in verifyPhoneNumber when APNs token isn't ready.
        // FIRPhoneAuthProvider.provider().verifyPhoneNumber uses reCAPTCHA when
        // called with a UIDelegate, which does NOT require APNs.
        let authProvider = FIRPhoneAuthProvider.provider()
        authProvider.verifyPhoneNumber(
            phoneNumber,
            uiDelegate: viewController as? FIRAuthUIDelegate
        ) { verificationID, error in
            if let error = error {
                result(FlutterError(
                    code: "AUTH_ERROR",
                    message: error.localizedDescription,
                    details: nil
                ))
                return
            }
            result(verificationID ?? "")
        }
    }
}
