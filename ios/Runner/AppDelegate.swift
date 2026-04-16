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

        // 2. Set up method channel for native phone auth AFTER plugins registered
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
                        result(FlutterError(code: "INVALID_ARGS",
                                           message: "Missing phoneNumber", details: nil))
                        return
                    }
                    self.sendOtpViaObjC(phoneNumber: phoneNumber, result: result)
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

    // MARK: - ObjC-level phone auth (bypasses Swift PhoneAuthProvider assertionFailure)
    //
    // Firebase Auth 5.x Swift overlay for PhoneAuthProvider.verifyPhoneNumber()
    // unconditionally calls assertionFailure() on iOS 18 when APNs token isn't
    // available yet, crashing with SIGTRAP. The underlying ObjC FIRPhoneAuthProvider
    // does NOT have this assertion — we call it directly via NSClassFromString to
    // bypass the Swift wrapper entirely.

    private func sendOtpViaObjC(phoneNumber: String, result: @escaping FlutterResult) {
        guard let viewController = window?.rootViewController else {
            result(FlutterError(code: "NO_VC",
                               message: "No root view controller", details: nil))
            return
        }

        // Get FIRPhoneAuthProvider class via ObjC runtime (avoids Swift wrapper crash)
        guard let providerClass = NSClassFromString("FIRPhoneAuthProvider") as? NSObject.Type else {
            result(FlutterError(code: "NO_PROVIDER",
                               message: "FIRPhoneAuthProvider not found", details: nil))
            return
        }

        // FIRPhoneAuthProvider.provider() -> FIRPhoneAuthProvider instance
        guard let provider = providerClass.perform(NSSelectorFromString("provider"))?.takeUnretainedValue() as? NSObject else {
            result(FlutterError(code: "NO_INSTANCE",
                               message: "Could not create FIRPhoneAuthProvider", details: nil))
            return
        }

        // Call verifyPhoneNumber:UIDelegate:completion: via ObjC messaging
        // This is the ObjC method — no Swift assertion, no APNs requirement
        let selector = NSSelectorFromString("verifyPhoneNumber:UIDelegate:completion:")

        guard provider.responds(to: selector) else {
            result(FlutterError(code: "NO_METHOD",
                               message: "verifyPhoneNumber:UIDelegate:completion: not found",
                               details: nil))
            return
        }

        // Use a block-based ObjC call via NSInvocation workaround:
        // Cast to AnyObject and use objc_msgSend pattern via a typed function pointer
        typealias VerifyFunc = @convention(c) (AnyObject, Selector, NSString, AnyObject?, (@escaping (NSString?, NSError?) -> Void)) -> Void
        let impl = unsafeBitCast(
            class_getMethodImplementation(type(of: provider), selector),
            to: VerifyFunc.self
        )

        impl(provider, selector, phoneNumber as NSString, viewController) { verificationID, error in
            DispatchQueue.main.async {
                if let error = error {
                    result(FlutterError(
                        code: "AUTH_ERROR",
                        message: error.localizedDescription,
                        details: nil
                    ))
                    return
                }
                result(verificationID as String? ?? "")
            }
        }
    }
}
