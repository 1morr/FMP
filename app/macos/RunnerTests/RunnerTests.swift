import Cocoa
import XCTest

@testable import FMP_Dev

/// 測試跑在 FMP Dev 裡（TEST_HOST），讀的是 App 真的那個視窗。
class TrafficLightsTests: XCTestCase {
  /// 細欄的外框離視窗左邊 8 到 80（docs/design/DESIGN.md：細欄 left 8、外框寬 72）。寬級
  /// 側欄更寬，排得進細欄就排得進側欄。
  private let railMinX: CGFloat = 8
  private let railMaxX: CGFloat = 80
  /// 燈的上緣離視窗頂 22：細欄頂 8 加上燈的上內距 14（docs/design/assets/fmp.css 的
  /// `.rail .lights`）。
  private let lightsTop: CGFloat = 22

  /// App 啟動後、還沒有測試動過視窗時的按鈕位置。
  private static var framesAtLaunch: [NSRect] = []

  override class func setUp() {
    super.setUp()
    framesAtLaunch = buttonFrames()
  }

  private static var window: NSWindow {
    NSApp.windows.first { $0 is MainFlutterWindow }!
  }

  /// 三顆按鈕的框，y 從視窗頂往下量。
  private static func buttonFrames() -> [NSRect] {
    return [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].map { type in
      let button = window.standardWindowButton(type)!
      let rect = button.convert(button.bounds, to: nil)
      return NSRect(
        x: rect.minX, y: window.frame.height - rect.maxY, width: rect.width, height: rect.height)
    }
  }

  /// 燈位：三顆排成一列、上緣在 [lightsTop]，整列在細欄外框裡水平置中。
  private func assertLightsAtSpot(
    _ frames: [NSRect] = buttonFrames(), file: StaticString = #filePath, line: UInt = #line
  ) {
    for frame in frames {
      XCTAssertEqual(frame.minY, lightsTop, "top of the row", file: file, line: line)
    }
    let left = frames[0].minX - railMinX
    let right = railMaxX - frames[2].maxX
    XCTAssertGreaterThan(left, 0, "inside the rail's left edge", file: file, line: line)
    XCTAssertGreaterThan(right, 0, "inside the rail's right edge", file: file, line: line)
    XCTAssertEqual(left, right, "centred in the rail", file: file, line: line)
  }

  /// 每個測試從燈位開始：改一下尺寸再改回來（縮放一直都會重排），測試只看
  /// 它自己的事件會不會把燈放回原位。
  override func setUp() {
    super.setUp()
    let window = Self.window
    let frame = window.frame
    window.setFrame(frame.insetBy(dx: 1, dy: 0), display: true)
    window.setFrame(frame, display: true)
    settle()
  }

  /// 讓 run loop 跑完這一輪，系統的標題列重排與 App 排回燈位都做完。
  private func settle() {
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.2))
  }

  func testLightsSitAtTheirSpotAfterLaunch() {
    assertLightsAtSpot(Self.framesAtLaunch)
  }

  func testLightsStayAfterTitleChange() {
    let window = Self.window
    let title = window.title
    defer { window.title = title }
    window.title = "Another title"
    settle()
    assertLightsAtSpot()
  }

  func testLightsStayAfterAppearanceChange() {
    let window = Self.window
    defer { window.appearance = nil }
    for name in [NSAppearance.Name.darkAqua, .aqua] {
      window.appearance = NSAppearance(named: name)
      settle()
      assertLightsAtSpot()
    }
  }

  func testLightsStayAfterResize() {
    let window = Self.window
    let frame = window.frame
    defer { window.setFrame(frame, display: true) }
    for width in [1280.0, 760.0] {
      window.setFrame(NSRect(x: frame.minX, y: frame.minY, width: width, height: 640), display: true)
      settle()
      assertLightsAtSpot()
    }
  }
}
