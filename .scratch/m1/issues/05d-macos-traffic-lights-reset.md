# 05d: macOS 紅綠燈跑回系統原位、壓到側欄頂邊

Status: ready-for-agent
Blocked by: None
讀: `docs/design/DESIGN.md` §5.2（側欄、細欄的 macOS 紅綠燈）；`docs/design/shell.html`；票 05 的 Comments（紅綠燈那幾行）；`docs/development.md`〈macOS〉的紅綠燈檢查方法；事實 M12；spec〈共同規則〉

2026-11-17 協調者插票（擁有者同意）：擁有者在票 07 實跑時看到 macOS 的紅綠燈貼著側欄頂邊、壓到圓角，像停在系統原位，沒有排到稿上的燈位（離視窗左上 (21,22)，也就是側欄頂邊往下 14）。票 05 與 05b 收尾的 macOS 截圖是對的，所以是某些情況下才發生。`app/macos/Runner/MainFlutterWindow.swift` 只在 `awakeFromNib`、`didResize`、`didExitFullScreen` 重排紅綠燈；系統在其他時機（視窗變成 key／main、失去焦點、切深淺色、改標題、顯示時……）可能把按鈕放回原位。修復票的驗收包含回頭補勾被它卡住的票：沒有。

協調者實測（2026-11-17，票 07 分支建的 Debug 版，視窗 800×600 啟動、不拉大小）：一啟動紅綠燈就在系統原位（第一顆中心約 (16,16)，壓在細欄頂邊上），失去焦點時一樣；用 System Events 把視窗改成 820×600 後立刻排到燈位。所以至少「啟動後沒排到」這條必現。票 05、05b 的截圖都是先把視窗拉到指定大小再拍，`didResize` 剛好把它排好，蓋掉了這個問題；`docs/development.md`〈macOS〉的檢查方法（先拉到 1280×800、960×720 再截圖）也一樣抓不到，要一起改成「啟動後不動視窗先截一張」。

## What to build

先寫出失效條件：找出紅綠燈會跑回原位的情況，做成能重現的 repro（例如腳本開 App、做某個動作、讀三顆按鈕在視窗裡的位置），修之前會紅。懷疑對象至少查上面列的系統事件，以及 App 剛啟動、第一幀畫完、從 Dock 叫回、在別的 App 之間切換。查成熟做法（Electron 的 `trafficLightPosition`、其他自訂紅綠燈位置的 macOS App）怎麼保證按鈕不被系統放回去，說明採用了誰的做法。

- 修根因，不靠計時器反覆重排。
- 查到的系統行為補成事實；`docs/development.md`〈macOS〉的檢查方法照實改。
- Windows、iOS、Android 不受影響。

## 驗收

- [ ] 有 repro，修之前紅、修之後綠；根因寫在 Comments（或寫明為什麼查不到）。
- [ ] 啟動後不動視窗、失去與取回焦點、切深淺色、縮放、全螢幕進出、寬級與細欄兩種寬度下，紅綠燈都在燈位；截圖和 `shell.html` 對過（深淺色）。
- [ ] 全部檢查綠燈（`dart run tool/check.dart` 完整版）。

## Comments
