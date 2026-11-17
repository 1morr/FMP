import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  /// Dart 給的燈位（lib/platform/traffic_lights.dart）：第一顆按鈕照稿的左上角，從視窗
  /// 左上量，以及燈所在那一列的左右緣。版面是寬級還是細欄由 Dart 決定，這裡不重抄斷點。
  private struct TrafficLightsSpot {
    let origin: NSPoint
    let minX: CGFloat
    let maxX: CGFloat
  }
  private var trafficLightsSpot: TrafficLightsSpot?

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
      case "setTrafficLights":
        if let args = call.arguments as? [String: Double],
          let x = args["x"], let y = args["y"], let minX = args["minX"], let maxX = args["maxX"]
        {
          self?.trafficLightsSpot = TrafficLightsSpot(
            origin: NSPoint(x: x, y: y), minX: minX, maxX: maxX)
          self?.layoutTrafficLights()
        }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
    // Dart 畫完第一幀、給了燈位才露出來，別先在系統原位閃一下。
    for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
      standardWindowButton(type)?.isHidden = true
    }
  }

  private var observedTitlebarViews: [NSView] = []
  private var titlebarFrameObservers: [NSObjectProtocol] = []
  private var trafficLightsLayoutPending = false

  /// 系統排標題列（`NSThemeFrame` 的 `_tileTitlebarAndRedisplay:`）時會把標題列容器
  /// 與三顆按鈕放回原位：改標題（Flutter 在 applicationWillFinishLaunching 設一次）、
  /// 縮放、切深淺色……都會走到這裡。與其像 Electron 一個個事件追，直接看著它們的
  /// frame，一被移動就排回去（事實 M13）。
  private func observeTitlebarFrames(_ views: [NSView]) {
    guard !views.elementsEqual(observedTitlebarViews, by: ===) else { return }
    titlebarFrameObservers.forEach(NotificationCenter.default.removeObserver)
    observedTitlebarViews = views
    titlebarFrameObservers = views.map { view in
      view.postsFrameChangedNotifications = true
      return NotificationCenter.default.addObserver(
        forName: NSView.frameDidChangeNotification, object: view, queue: nil
      ) { [weak self] _ in self?.scheduleTrafficLightsLayout() }
    }
  }

  /// 通知是系統移動按鈕的當下發的，這時設正在移動的那顆會被它的重入保護吃掉
  /// （`_NSThemeWidget setFrameOrigin:ignoreRentry:`），所以等這一輪 run loop 把
  /// 標題列排完、畫面更新之前再排；同一輪的多個通知合成一次。common modes 讓拖拉
  /// 縮放（event tracking mode）時也照排。
  private func scheduleTrafficLightsLayout() {
    guard !trafficLightsLayoutPending else { return }
    trafficLightsLayoutPending = true
    RunLoop.main.perform(inModes: [.common]) { [weak self] in
      self?.trafficLightsLayoutPending = false
      self?.layoutTrafficLights()
    }
  }

  /// 排紅綠燈：先把裝按鈕的標題列加高到放得下，再排三顆按鈕（Electron 的
  /// trafficLightPosition 也是這樣做）。原生按鈕比稿上的燈大，照稿放會比在那一列裡
  /// 置中還靠右（右邊放不下）時改成置中。已經在位置上的不再設（容許系統對齊像素的
  /// 誤差），自己發出的 frame 通知才不會一直排下去。
  private func layoutTrafficLights() {
    // 全螢幕時按鈕在系統的工具列視窗裡，不動；離開時系統重排標題列，frame 監看會排回來。
    guard !styleMask.contains(.fullScreen),
      let spot = trafficLightsSpot,
      let close = standardWindowButton(.closeButton),
      let mini = standardWindowButton(.miniaturizeButton),
      let zoom = standardWindowButton(.zoomButton),
      let container = close.superview?.superview
    else { return }
    observeTitlebarFrames([container, close, mini, zoom])
    let size = close.frame.size
    let barHeight = size.height + spot.origin.y * 2
    var frame = container.frame
    frame.size.height = barHeight
    frame.origin.y = self.frame.height - barHeight
    if !container.frame.isClose(to: frame) { container.frame = frame }
    let spacing = mini.frame.minX - close.frame.minX
    let rowWidth = spacing * 2 + size.width
    let left = min(spot.origin.x, (spot.minX + spot.maxX - rowWidth) / 2)
    for (i, button) in [close, mini, zoom].enumerated() {
      let origin = NSPoint(x: left + CGFloat(i) * spacing, y: (barHeight - size.height) / 2)
      if !button.frame.origin.isClose(to: origin) { button.setFrameOrigin(origin) }
      if button.isHidden { button.isHidden = false }
    }
  }
}

extension NSPoint {
  fileprivate func isClose(to other: NSPoint) -> Bool {
    abs(x - other.x) < 0.5 && abs(y - other.y) < 0.5
  }
}

extension NSRect {
  fileprivate func isClose(to other: NSRect) -> Bool {
    origin.isClose(to: other.origin) && abs(width - other.width) < 0.5
      && abs(height - other.height) < 0.5
  }
}
