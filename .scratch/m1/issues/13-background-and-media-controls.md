# 13: 背景播放與系統媒體控制

Status: ready-for-agent
Blocked by: 07、09
讀: brief §6；事實 I2、I5、K18、M10、R4；architecture〈主要依賴〉〈風險與回寫點〉；`scripts/experiments/macos-now-playing/`；spec〈共同規則〉

## What to build

App 在背景時繼續播放（Android 前景服務與通知、iOS 背景音訊模式、桌面最小化），系統媒體控制接上：Android、iOS、macOS 用 audio_service，Windows 用 runner 裡自己接的 SMTC（2026-11-19 擁有者同意，原本是 smtc_windows；Dart 端只有 `platform/` 碰 `fmp/media` 頻道）。Now Playing 顯示曲名、作者、封面、長度與位置；系統的播放、暫停、上一首、下一首、拖動進度控制 App。App 要出過聲才會成為 Now Playing App（事實 M10），重啟後先在 App 按播放。

iOS 的中斷與 Now Playing 模擬器驗不到的部分記在 Comments（事實 I2、I5），留給使用者試。audio_service 在 macOS 壞了就照〈風險與回寫點〉改用自己的 platform channel。

## 驗收

- [ ] 四平台：App 在背景時繼續播放，讀回 log 或畫面。
- [ ] Now Playing 的資訊與系統的播放、暫停、上一首、下一首、拖動進度有作用（macOS 控制中心、Windows 媒體浮層、Android 通知用模擬器讀回；iOS 模擬器做得到的部分）。
- [ ] 換曲、暫停、seek 時 Now Playing 的資訊跟著更新，有測試（fake 的媒體控制）。
- [ ] audio_service 的版本與 Windows 的做法寫進 ARCHITECTURE〈主要依賴〉；需要的平台設定（manifest、Info.plist、entitlements）寫進 `docs/development.md`〈平台〉。
- [ ] 模擬器驗不到的項目列在 Comments。
- [ ] 全部檢查綠燈（`dart run tool/check.dart` 完整版）。

## Comments

決定：Windows 的系統媒體控制不用 smtc_windows（和 fjs 的 flutter_rust_bridge 版本衝突，事實 W7），改在 runner 用 C++ 接 SMTC、經 `fmp/media` 頻道；brief §6、ARCHITECTURE〈主要依賴〉、spec 照草稿改（使用者同意）
