import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // 標題列透明、內容延伸到它底下：紅綠燈疊在側欄頂端，側欄讓出位置
    // （docs/design/DESIGN.md〈桌面〉、lib/platform/window_chrome.dart）。
    self.titlebarAppearsTransparent = true
    self.titleVisibility = .hidden
    self.styleMask.insert(.fullSizeContentView)
    // 桌面視窗最小 720×560（brief〈介面〉）。
    self.contentMinSize = NSSize(width: 720, height: 560)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
