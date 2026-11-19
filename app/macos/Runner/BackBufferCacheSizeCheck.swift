import Cocoa
import ObjectiveC

/// 補上 Flutter 引擎少的一道尺寸檢查（事實 M17）：視窗尺寸在很短的時間內 A→B→A 來回，
/// 而 A 的畫布還被 WindowServer 佔著時，`FlutterBackBufferCache.removeSurfaceForSize:` 會把
/// B 尺寸的畫布交給要 A 的請求；Impeller 包材質時發現尺寸不合，默默丟掉顏色附件，接著在
/// `Canvas::SetupRenderPass` 讀到空指標，App 閃退。上游 issue 是 flutter/flutter#185394，
/// 修正是 flutter/flutter#192522。
///
/// 做法：在取出端檢查，拿到的尺寸不對就丟掉、回 nil，引擎的 `surfaceForSize:` 會新建一張。
/// 靠的是引擎內部的類別、方法與屬性名，升 Flutter 時改了就不裝（`installed` 是 false，
/// `RunnerTests` 的 `WindowResizeTests` 會紅）；上游收錄修正後連同那組測試一起刪掉。
enum BackBufferCacheSizeCheck {
  /// 有沒有裝上。
  private(set) static var installed = false

  private typealias RemoveSurface = @convention(c) (AnyObject, Selector, CGSize) -> AnyObject?

  /// 在引擎建第一張畫布之前呼叫一次。
  static func install() {
    // 讀尺寸用 KVC，`FlutterSurface` 沒有 `size` 時會丟例外，所以先確認再裝。
    guard let cacheClass = NSClassFromString("FlutterBackBufferCache"),
      let method = class_getInstanceMethod(
        cacheClass, NSSelectorFromString("removeSurfaceForSize:")),
      let surfaceClass = NSClassFromString("FlutterSurface") as? NSObject.Type,
      surfaceClass.instancesRespond(to: NSSelectorFromString("size"))
    else { return }
    let selector = method_getName(method)
    let original = unsafeBitCast(method_getImplementation(method), to: RemoveSurface.self)
    let checked: @convention(block) (AnyObject, CGSize) -> AnyObject? = { cache, size in
      guard let surface = original(cache, selector, size) else { return nil }
      // FlutterSurface 的 `size` 是唯讀屬性，經 KVC 讀成 NSValue。
      guard (surface.value(forKey: "size") as? NSValue)?.sizeValue == size else { return nil }
      return surface
    }
    method_setImplementation(method, imp_implementationWithBlock(checked))
    installed = true
  }
}
