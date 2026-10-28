// 真的滑鼠事件（CGEvent，送到 HID 層）：`orca computer` 的合成點擊到不了系統的標題區，拖曳與雙擊標題列要用它。
// 座標是全域點（左上原點），用 System Events 讀視窗位置再加上視窗內座標。目標 App 要先在最前面，
// 否則點到的是擋在前面的別的 App。
//
//   xcrun swiftc -O mouse.swift -o <暫存目錄>/mouse
//   mouse move X Y ｜ mouse click X Y ｜ mouse dbl X Y ｜ mouse drag X1 Y1 X2 Y2
import CoreGraphics
import Foundation

let a = CommandLine.arguments
func post(_ type: CGEventType, _ p: CGPoint, clicks: Int64 = 1) {
  let e = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: p, mouseButton: .left)!
  e.setIntegerValueField(.mouseEventClickState, value: clicks)
  e.post(tap: .cghidEventTap)
}
let n = a.dropFirst(2).compactMap { Double($0) }
switch a[1] {
case "drag":
  let p1 = CGPoint(x: n[0], y: n[1]), p2 = CGPoint(x: n[2], y: n[3])
  post(.mouseMoved, p1); usleep(100_000)
  post(.leftMouseDown, p1); usleep(100_000)
  for i in 1...20 {
    let t = Double(i) / 20
    post(.leftMouseDragged, CGPoint(x: p1.x + (p2.x - p1.x) * t, y: p1.y + (p2.y - p1.y) * t))
    usleep(20_000)
  }
  post(.leftMouseUp, p2)
case "dbl":
  let p = CGPoint(x: n[0], y: n[1])
  post(.mouseMoved, p); usleep(100_000)
  post(.leftMouseDown, p, clicks: 1); post(.leftMouseUp, p, clicks: 1); usleep(80_000)
  post(.leftMouseDown, p, clicks: 2); post(.leftMouseUp, p, clicks: 2)
case "move":
  post(.mouseMoved, CGPoint(x: n[0], y: n[1]))
default:
  let p = CGPoint(x: n[0], y: n[1])
  post(.mouseMoved, p); usleep(100_000); post(.leftMouseDown, p); post(.leftMouseUp, p)
}
