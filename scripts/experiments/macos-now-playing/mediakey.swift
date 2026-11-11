// 實驗用：模擬鍵盤的媒體鍵（F7 上一首、F8 播放／暫停、F9 下一首），跟實體鍵送出同一種
// NSSystemDefined（subtype 8）事件，系統再轉成 MPRemoteCommand 給 Now Playing 的 App。
//
//   swift mediakey.swift <play|next|previous>
//
// 執行者要有「輔助使用」權限，否則 CGEvent.post 靜默失敗。
import AppKit

let keys: [String: Int32] = ["play": 16, "next": 17, "previous": 18]  // NX_KEYTYPE_*
guard CommandLine.arguments.count == 2, let key = keys[CommandLine.arguments[1]] else {
  FileHandle.standardError.write("usage: mediakey.swift <play|next|previous>\n".data(using: .utf8)!)
  exit(2)
}
guard AXIsProcessTrusted() else {
  FileHandle.standardError.write("沒有輔助使用權限，事件送不出去\n".data(using: .utf8)!)
  exit(1)
}

func post(down: Bool) {
  let flags: Int32 = down ? 0xa00 : 0xb00  // NX_KEYDOWN／NX_KEYUP 放在 bit 8–15
  let data1 = Int((key << 16) | flags)
  let event = NSEvent.otherEvent(
    with: .systemDefined, location: .zero, modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(flags)),
    timestamp: 0, windowNumber: 0, context: nil, subtype: 8, data1: data1, data2: -1)
  event?.cgEvent?.post(tap: .cghidEventTap)
}

post(down: true)
usleep(50_000)
post(down: false)
print("posted \(CommandLine.arguments[1])")
