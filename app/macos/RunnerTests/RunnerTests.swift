import Cocoa
import XCTest

@testable import FMP_Dev

/// 測試跑在 FMP Dev 裡（TEST_HOST），讀的是 App 真的那個視窗；燈位由 Dart 排完版面後
/// 經 `fmp/window` 送來，所以動了視窗寬度要等它。
class TrafficLightsTests: XCTestCase {
  /// 燈的上緣離視窗頂 22：側欄與細欄頂 8 加上燈的上內距 14（docs/design/assets/fmp.css
  /// 的 `.side .lights`、`.rail .lights`）。
  private static let lightsTop: CGFloat = 22
  /// 側欄與細欄的內框，從視窗左緣量（docs/design/DESIGN.md：側欄 left 8、外框寬 248、
  /// 內距 8；細欄 left 8、外框寬 72、內距 6）。
  private static let sidebarBox: ClosedRange<CGFloat> = 16...248
  private static let railBox: ClosedRange<CGFloat> = 14...74
  /// 寬級照稿：第一顆離視窗左 24（側欄內框 16 加 `.side .lights` 的內縮 8）。
  private static let sidebarLightsX: CGFloat = 24
  /// 寬級是視窗寬 1200 以上，細欄是 600–1199（docs/design/DESIGN.md〈中寬度〉）。
  private static let wideSize = NSSize(width: 1280, height: 800)
  private static let railSize = NSSize(width: 960, height: 720)

  /// App 啟動後、還沒有測試動過視窗時的按鈕位置（啟動時是 800 寬的細欄）。
  private static var framesAtLaunch: [NSRect] = []

  override class func setUp() {
    super.setUp()
    waitUntil { !window.standardWindowButton(.closeButton)!.isHidden }
    framesAtLaunch = buttonFrames()
  }

  fileprivate static var window: NSWindow {
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

  private static func isInside(_ box: ClosedRange<CGFloat>) -> Bool {
    buttonFrames().allSatisfy {
      box.contains($0.minX) && box.contains($0.maxX) && $0.minY == lightsTop
    }
  }

  /// 讓 run loop 跑到 [condition] 成立（Dart 重排版面、送來燈位、原生端排好），最多
  /// 5 秒；沒成立就交給後面的斷言報錯。
  fileprivate static func waitUntil(_ condition: () -> Bool) {
    let deadline = Date(timeIntervalSinceNow: 5)
    while !condition() && Date() < deadline {
      RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
    }
  }

  /// 讓 run loop 跑完這一輪：系統的標題列重排與 App 排回燈位都做完。
  private static func settle() {
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.2))
  }

  fileprivate static func resize(to size: NSSize) {
    let frame = window.frame
    window.setFrame(
      NSRect(x: frame.minX, y: frame.maxY - size.height, width: size.width, height: size.height),
      display: true)
  }

  private func assertInside(
    _ box: ClosedRange<CGFloat>, _ frames: [NSRect] = buttonFrames(),
    file: StaticString = #filePath, line: UInt = #line
  ) {
    for frame in frames {
      XCTAssertEqual(frame.minY, Self.lightsTop, "top of the row", file: file, line: line)
      XCTAssertTrue(
        box.contains(frame.minX) && box.contains(frame.maxX),
        "\(frame) inside \(box)", file: file, line: line)
    }
  }

  /// 每個測試從細欄的燈位開始。
  override func setUp() {
    super.setUp()
    Self.resize(to: Self.railSize)
    Self.waitUntil { Self.isInside(Self.railBox) }
  }

  func testLightsSitInTheRailAfterLaunch() {
    assertInside(Self.railBox, Self.framesAtLaunch)
  }

  func testLightsFollowTheDesignInTheWideLayout() {
    Self.resize(to: Self.wideSize)
    Self.waitUntil { Self.buttonFrames()[0].minX == Self.sidebarLightsX }
    assertInside(Self.sidebarBox)
    XCTAssertEqual(
      Self.buttonFrames()[0].origin, NSPoint(x: Self.sidebarLightsX, y: Self.lightsTop))
  }

  func testLightsFitInTheRailAfterTheWideLayout() {
    Self.resize(to: Self.wideSize)
    Self.waitUntil { Self.buttonFrames()[0].minX == Self.sidebarLightsX }
    Self.resize(to: Self.railSize)
    Self.waitUntil { Self.isInside(Self.railBox) }
    assertInside(Self.railBox)
  }

  func testLightsStayAfterTitleChange() {
    let window = Self.window
    let title = window.title
    defer { window.title = title }
    window.title = "Another title"
    Self.settle()
    assertInside(Self.railBox)
  }

  func testLightsStayAfterAppearanceChange() {
    let window = Self.window
    defer { window.appearance = nil }
    for name in [NSAppearance.Name.darkAqua, .aqua] {
      window.appearance = NSAppearance(named: name)
      Self.settle()
      assertInside(Self.railBox)
    }
  }

  /// 沒有側欄或細欄的畫面，Dart 送「沒有燈位」：三顆看得到，回到系統原位（macOS 27 是
  /// (9,9)，事實 M13）。
  func testLightsShowInTheSystemSpotWithoutASidebarOrRail() {
    let window = Self.window as! MainFlutterWindow
    let spot = window.trafficLightsSpot
    defer { window.setTrafficLights(spot) }
    window.setTrafficLights(nil)
    Self.settle()
    for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
      XCTAssertFalse(window.standardWindowButton(type)!.isHidden, "\(type) visible")
    }
    XCTAssertEqual(Self.buttonFrames()[0].origin, NSPoint(x: 9, y: 9))
  }
}

/// 視窗尺寸在很短的時間內 A→B→A 來回時，Flutter 的 `FlutterBackBufferCache` 會把 B 的畫布
/// 交給要 A 的請求，Impeller 接著在 `Canvas::SetupRenderPass` 讀到空指標、App 閃退（事實
/// M17）。App 啟動時裝的 `BackBufferCacheSizeCheck` 擋住它；Flutter 收錄上游修正後連同這組
/// 測試一起刪掉。
class WindowResizeTests: XCTestCase {
  /// Flutter 畫出第一幀之前縮放不會等它畫新尺寸，碰不到這條路；等紅綠燈露出來（Dart 排完版面、
  /// 送來燈位）再開始。
  override class func setUp() {
    super.setUp()
    TrafficLightsTests.waitUntil {
      !TrafficLightsTests.window.standardWindowButton(.closeButton)!.isHidden
    }
  }

  /// 裝不上代表 Flutter 改了內部的類別或方法名，檢查已經失效，App 又會在縮放時閃退。
  func testBackBufferCacheSizeCheckIsInstalled() {
    XCTAssertTrue(
      BackBufferCacheSizeCheck.installed,
      "FlutterBackBufferCache.removeSurfaceForSize: not found; see fact M17")
  }

  /// 沒有檢查時，連續 1000 次來回每次都閃退（XCTest 報 `Crash: FMP Dev`）；停在細欄的尺寸，
  /// 給後面的測試一樣的起點。
  func testRapidBackAndForthResizesDoNotCrash() {
    let rail = NSSize(width: 960, height: 720)
    let wide = NSSize(width: 1280, height: 800)
    for i in 0..<1000 {
      TrafficLightsTests.resize(to: i % 2 == 0 ? wide : rail)
    }
    XCTAssertEqual(TrafficLightsTests.window.frame.size, rail)
  }
}

