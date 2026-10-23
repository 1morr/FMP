# U UI 對齊舊版

## Goal

擁有者試用 M5 的 dev 版後認為新版 UI「連舊版都完全比不過」（例：匯入 1195 首的歌單時看不到進度）。在 M6 之前插入這個里程碑，把新版 UI 做成和舊版一樣，之後的功能疊在對齊後的 UI 上。

## 已知事實

- 擁有者決定（2026-10-24）：「插，UI 幫我做成和舊版一樣」。
- 現行規範是 ADR 0024（UI／UX）與 ADR 0033（首頁與導覽）。其中幾處是擁有者 2026-09-28 選定、刻意和舊版不同的：
  - 播放頁方案 B：右欄有「歌詞｜佇列｜詳細」分頁。舊版寬版是左封面加右歌詞，佇列是獨立頁。
  - 佇列不再是導覽項。
  - 播放列依寬度分三段。
  - 設定頁 expanded 以上用 list-detail。
  - App 內快捷鍵、繁中字形、token。
- 舊版 UI 的審計在 `docs/audit/ui.md`、`docs/audit/features.md` §0，截圖在 `docs/audit/screenshots/`（個人資料已模糊）。舊版程式在根目錄 `lib/ui/`（凍結）。
- 匯入進度：帳號頁匯入歌單的進度條按「歌單數」算（`app/lib/ui/accounts/account_playlists_page.dart:231`）；URL 匯入對話框只有不定進度條（`app/lib/ui/library/import_dialog.dart:238`）。舊版按曲目數顯示。

## 待擁有者決定

- 「和舊版一樣」的範圍：只對齊外觀與手感，還是連 ADR 0024 選過的不同之處也退回舊版。

## Requirements

- TBD（範圍定了再寫）

## Acceptance Criteria

- [ ] TBD

## Out of Scope

- TBD
