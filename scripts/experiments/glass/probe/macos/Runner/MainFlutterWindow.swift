import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    // Experiment (M0 ticket 05b): phone-ish window so the dock layout fits.
    self.setFrame(NSRect(x: windowFrame.minX, y: windowFrame.minY, width: 600, height: 860), display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // Experiment (M0 ticket 05b): System Settings > Accessibility > Display >
    // Reduce transparency.
    FlutterMethodChannel(name: "fmpx/a11y", binaryMessenger: flutterViewController.engine.binaryMessenger)
      .setMethodCallHandler { call, result in
        if call.method == "reduceTransparency" {
          result(NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency)
        } else {
          result(FlutterMethodNotImplemented)
        }
      }

    super.awakeFromNib()
  }
}
