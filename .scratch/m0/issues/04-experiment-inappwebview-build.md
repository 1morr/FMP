# 04: 實驗：flutter_inappwebview 6.1.5 四平台建置

**What to build:** 確認登入 WebView 要用的 `flutter_inappwebview` 6.1.5 在目前的工具鏈（Flutter 3.47.5、Xcode 27.1、AGP 9、VS 2026）上四平台都建得起來並能開一個網頁，讓 M2 的登入票不用再踩建置問題。只驗建置與開頁，不做登入。

讀：plan §1.4、§2、§7；brief 事實 A4、W8、M8、K8、R1、T1；spec〈共同規則〉的實驗規則

**Blocked by:** None (can start immediately)

**Status:** done

- [x] 實驗專案在 `scripts/experiments/` 底下，可重跑，附怎麼跑的說明。
- [x] 四平台各自建置成功並開出一個公開網頁，讀回畫面為證。
- [x] 重驗事實 A4、W8、M8、K8：要加的旗標、編譯選項與 lock 檔的坑，逐條寫明是否仍需要；更新 brief §18 的寫法與【待重驗】標記。
- [x] 某平台建不起來時，記下錯誤與試過的做法，結論寫進 brief，不改用 beta 版（要用 beta 先問擁有者）。

## Comments

- 結論：flutter_inappwebview 6.1.5 在 Flutter 3.47.5、Xcode 27.2、AGP 9.1.0、VS 2026（MSVC 14.51）上四平台都建得起來並開出 example.com（macOS、iOS 模擬器 debug；Android、Windows debug 與 release），每個平台都讀回畫面。結果表、13 次 Windows 建置的明細與怎麼重跑在 `scripts/experiments/inappwebview/README.md`，結果檔在同目錄 `results/*.json`。沒有平台建不起來，沒用 beta 版（beta 只在 `lockfile-repro.sh` 的暫存副本裡用來重現 K8）。
- 重驗的事實（brief §18 已改寫）：A4 仍需要（AGP 9 下 debug 也在 Gradle 設定階段失敗）；W8 的 define 仍需要，`/FS` 沒重現出需要但留著當保險，`/utf-8` 不需要（插件刻意不開 `/WX`，C4819 只是警告；舊版 `windows/` 其實也沒加 `/utf-8`）；M8 穩定版在 Xcode 27.2 不加設定就過，27.1 沒試（本機已更新，T1 補一句）；K8 仍成立，`flutter pub upgrade --unlock-transitive flutter_inappwebview` 才清得掉殘留。四條的【待重驗】都拿掉。
- 順手重驗：M3 的 WKWebView 那半句（沙盒缺 `network.client` 時靜默失敗）實測成立，M3 補註但保留【待重驗】（其餘幾句沒驗）。R1 補「2026-11-11 再查仍是」。
- 新事實 K17：6.1.5 的 Apple 端沒有 SwiftPM 支援，Flutter 退回 CocoaPods 並警告將來會變成錯誤。`app/` 目前只用 SwiftPM，所以 M2 的登入票加這個套件時，iOS、macOS 會多出 Podfile、`Podfile.lock`、`Pods/`，建置機器要裝 CocoaPods，plan §2、§4 的前置條件也要跟著改。這是給登入票（或擁有者）決定的事，這張票只記事實、沒改 plan 的前置條件。
- 給 M2 登入票的設定清單：Android `gradle.properties` 加 `android.r8.proguardAndroidTxt.disallowed=false`；macOS 兩個 entitlements 加 `com.apple.security.network.client`；Windows `windows/CMakeLists.txt` 對 `flutter_inappwebview_windows_plugin` 加 `_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS` 與 `/FS`（寫法照 `scripts/experiments/inappwebview/probe/`）；Android 加 INTERNET 權限（`flutter create` 只放在 debug manifest）。
- plan §7 的風險註記補上這次的實驗參照，「登入票先實測四個平台」維持原樣（審查指出改寫會縮小登入票的承諾，已還原）。
- `winpc` 實驗目錄是 `C:\fmpx\inappwebview`（跑完已清掉），經 `run-windows.sh` 持共用裝置鎖；建置要的 CMake 開關用使用者環境變數 `FMPX_WIN_PATCH` 傳給排程工作，腳本結束時（含失敗）清掉。Windows 建置途中遇到 4 次 `flutter_assemble` 的 MSB8066 與 1 次 `CL.exe` 0xC0000409，都是 plan §2 記的 `winpc` 環境問題，重跑就過。
- code-review（c3dfd856 起）已處理：M3 被引用卻沒重驗 → 補實測；`run.sh` 開跑前不清舊結果、逾時時印不出「no result」、release 結果會蓋掉 debug → 先刪結果檔、release 另存 `<平台>-release.json`、Android 改從 log 取結果不再 `run-as`；`run-windows.sh` 失敗時環境變數留在 `winpc` → 改在 EXIT trap 清；`lockfile-repro.sh` 沒重現「一般 `pub upgrade` 清不掉」→ 補這一步；README 補 `orca computer` 前置條件；M8 的 beta 那半句與 W8 的「`/FS` 在 VS 2022 無害」標明沒實測；A4、W8 補上游完整網址；CMake 補丁註解改繁中；`flutter create` 寫進 iOS 專案檔的 Apple Team ID 已在 commit 前移除。
- code-review 未處理（不做，理由）：`run.sh` 讓 macOS 也能 `MODE=release`（Speculative Generality）：成本是一行，換版本重量時可能用到。

