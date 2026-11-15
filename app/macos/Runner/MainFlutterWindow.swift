import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  /// 紅綠燈第一顆按鈕的左上角，從視窗左上角量（docs/design/assets/fmp.css 的
  /// `.rail .lights`：細欄離邊 8、內距 6、燈再內縮 7；頂 8 加上燈的上內距 14）。
  /// 寬級的側欄稿上是 24，差 3pt；細欄比較窄，照它排三顆才不會超出。
  private let trafficLightOrigin = NSPoint(x: 21, y: 22)

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // 標題列透明、內容延伸到它底下：紅綠燈疊在側欄頂端，側欄讓出位置
    // （lib/platform/window_chrome.dart）。標題列的點擊照樣進 Flutter，所以
    // 拖動視窗由 Flutter 經 fmp/window 頻道叫回來（lib/platform/window_drag.dart）。
    self.titlebarAppearsTransparent = true
    self.titleVisibility = .hidden
    self.styleMask.insert(.fullSizeContentView)
    // 桌面視窗最小 720×560（brief〈介面〉）。
    self.contentMinSize = NSSize(width: 720, height: 560)

    let channel = FlutterMethodChannel(
      name: "fmp/window",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "startDrag":
        if let event = NSApp.currentEvent { self?.performDrag(with: event) }
        result(nil)
      case "zoom":
        self?.performZoom(nil)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    // 系統會在縮放與離開全螢幕時把按鈕放回原位，每次都重排。
    for name in [NSWindow.didResizeNotification, NSWindow.didExitFullScreenNotification] {
      NotificationCenter.default.addObserver(forName: name, object: self, queue: .main) {
        [weak self] _ in self?.layoutTrafficLights()
      }
    }

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
    layoutTrafficLights()
  }

  /// 把紅綠燈移到 [trafficLightOrigin]：先把裝按鈕的標題列加高到放得下，再排
  /// 三顆按鈕（Electron 的 trafficLightPosition 也是這樣做）。
  private func layoutTrafficLights() {
    guard !styleMask.contains(.fullScreen),
      let close = standardWindowButton(.closeButton),
      let mini = standardWindowButton(.miniaturizeButton),
      let zoom = standardWindowButton(.zoomButton),
      let container = close.superview?.superview
    else { return }
    let height = close.frame.height
    let barHeight = height + trafficLightOrigin.y * 2
    var frame = container.frame
    frame.size.height = barHeight
    frame.origin.y = self.frame.height - barHeight
    container.frame = frame
    let spacing = mini.frame.minX - close.frame.minX
    for (i, button) in [close, mini, zoom].enumerated() {
      button.setFrameOrigin(
        NSPoint(
          x: trafficLightOrigin.x + CGFloat(i) * spacing,
          y: (barHeight - height) / 2))
    }
  }
}
