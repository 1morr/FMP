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
    // Experiment (M0 ticket 05b): Settings > Accessibility > Display & Text Size
    // > Reduce Transparency.
    let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "FmpxA11y")!
    FlutterMethodChannel(name: "fmpx/a11y", binaryMessenger: registrar.messenger())
      .setMethodCallHandler { call, result in
        if call.method == "reduceTransparency" {
          result(UIAccessibility.isReduceTransparencyEnabled)
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
  }
}
