# 05b: Windows 自繪標題列

Status: ready-for-agent
Blocked by: 05
讀: `docs/design/DESIGN.md` §5.2（Windows 那一點）；`docs/design/shell.html`、`docs/design/system.html`；票 05 的 Comments；architecture〈依賴規則〉〈主要依賴〉；spec〈共同規則〉

2026-11-15 協調者插票：票 05 做外殼時發現 Windows 用的是系統原生標題列，和 `DESIGN.md` §5.2 不符；擁有者定 05 先留原生標題列，自繪另開這張、排在 06 之前（M1 驗收要外殼截圖對得上設計稿）。

## What to build

Windows 照 `DESIGN.md` §5.2 改成沒有原生標題列的視窗：最小化、最大化（還原）、關閉三顆鈕（各 46×32，圖示 16）畫在視窗右上，內容頂列右端讓出 138px。視窗仍要像一般 Windows 視窗：可以拖曳頂列移動、雙擊頂列最大化與還原、滑鼠停在最大化鈕上出 Snap Layouts、邊緣可以拉大小、高 DPI 下按鈕與拖曳區位置正確，最小 720×560 照舊。

- 視窗相關的 Windows 差異收在 `platform/`，畫面只拿「要不要畫視窗鈕、讓出多少寬度」（依賴規則：`platform/` 以外不判斷平台）。
- 要加依賴（例如 `window_manager` 或 `bitsdojo_window`）時照〈事實與查證〉查當前 stable 與 Snap Layouts 的支援，版本寫進 ARCHITECTURE〈主要依賴〉；用到的平台行為補成事實。
- macOS、iOS、Android 不受影響。

## 驗收

- [ ] Windows 沒有原生標題列，三顆視窗鈕的位置與大小照 `DESIGN.md` §5.2，內容頂列右端讓出 138px；截圖和設計稿對得上（深淺色）。
- [ ] 拖曳頂列移動、雙擊最大化與還原、停在最大化鈕出 Snap Layouts、邊緣拉大小、最小 720×560，在 `winpc` 實跑讀回。
- [ ] 讓出寬度與是否畫視窗鈕由 `platform/` 提供，有測試。
- [ ] 新依賴的版本在 ARCHITECTURE〈主要依賴〉。
- [ ] 其他三平台實跑外殼照常。
- [ ] 全部檢查綠燈（`dart run tool/check.dart` 完整版）。

## Comments
