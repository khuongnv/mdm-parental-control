import Flutter
import UIKit
import UserNotifications
#if canImport(FirebaseCore)
import FirebaseCore
#endif

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    #if canImport(FirebaseCore)
    if Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil,
       FirebaseApp.app() == nil {
      FirebaseApp.configure()
    }
    #endif
    UNUserNotificationCenter.current().delegate = self
    application.registerForRemoteNotifications()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let updaterChannel = FlutterMethodChannel(
      name: "vn.hanoi.khuongnv.vfam.admin/updater",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    updaterChannel.setMethodCallHandler { (call: FlutterMethodCall, result: @escaping FlutterResult) in
      if call.method == "getAppVersion" {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.5.5"
        result(version)
      } else if call.method == "getAppBuildNumber" {
        let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "14"
        result(buildNumber)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
  }
}

