import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  // 關掉最後一個視窗就結束 App，同 Windows；「關閉後留在背景」跟托盤一起在 M8 做（ADR 0036 §決定 6）。
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  // 單一實例（ADR 0036 §決定 4）：Info.plist 的 LSMultipleInstancesProhibited 讓再次開啟回到這個行程，
  // 系統接著呼叫這裡。沒有可見的視窗（例如最小化到 Dock）時把主視窗帶回前景。
  override func applicationShouldHandleReopen(
    _ sender: NSApplication, hasVisibleWindows flag: Bool
  ) -> Bool {
    if !flag {
      mainFlutterWindow?.makeKeyAndOrderFront(nil)
    }
    return true
  }
}
