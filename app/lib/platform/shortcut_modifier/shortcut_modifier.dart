/// 快捷鍵的主修飾鍵（ADR 0035 §決定 7）：Windows、Android 外接鍵盤是 Ctrl，Apple 平台是 ⌘。
///
/// UI 不判斷平台，快捷鍵表依平台宣告的這個值組出（`PlatformCapabilities.shortcutModifier`）。
enum ShortcutModifier { control, meta }

/// Apple 平台（macOS、iOS）的值。App 目前在 Apple 平台還不啟動（宣告是
/// `PlatformCapabilities.none`），macOS／iOS 平台任務接上時宣告這個。
const appleShortcutModifier = ShortcutModifier.meta;
