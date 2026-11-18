import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
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
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.5.4"
        result(version)
      } else if call.method == "getAppBuildNumber" {
        let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "13"
        result(buildNumber)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
  }
}

