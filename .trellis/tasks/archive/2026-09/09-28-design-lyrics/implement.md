# 執行計畫：第 15 項（設計任務，只產出文件）

1. [x] 核准後寫 `docs/adr/0021-lyrics.md`（依 `docs/adr/template.md`），內容取自 `design.md` §2–§11；被否決的方案：
   三個歌詞源各自寫死在 Dart、宿主內建 QRC／KRC 解析器、AI 只留標題解析、App 內建 AI 客戶端（擁有者指出做成插件只需更新插件）、
   只承諾 Windows 的桌面歌詞、只有 hover 工具列沒有鎖定、同步掛在 UI 元件上、以字串 map 推子視窗、逐 tick 推送位置、
   Flutter 官方多視窗 API（仍在 `main` channel）、Android 狀態列歌詞（列待辦）、iOS 系統級懸浮（平台不允許）。
2. [x] 其他 ADR 各加一句指向 ADR 0021：0009（`desktopLyrics` 細分 `clickThrough`／`alwaysOnTop`、`overlayLyrics`、`liveActivityLyrics`）、
   0014（能力加 `aiAssist`；`lyrics` 介面與歌詞文件）、0015（後續 ADR 新增的規則：`fmp_periodic_timer_owner` 允許桌面歌詞查游標）、
   0016（AI 標題解析快取在 `cache.db`）、0017（同上的計時器擁有者）、0020（`PermissionGateway` 加懸浮窗權限）。
3. [x] `phase2-plan.md`：§3 第 15 項標 ✅（ADR 0021）；第 20 項待辦加 Android 狀態列歌詞、本機歌詞檔匯入；
   §8 延後實測加入：桌面歌詞在 macOS／Linux X11／Wayland 的穿透、置頂、定位；`window_manager` 在子 engine 設穿透作用在子視窗；
   `flutter_overlay_window` 的記憶體與 Android 15 前景服務限制；iOS Live Activity 本機逐行更新；`flutter_lyric` 直接用或自寫；
   §10 交接段更新，下一項 19 發版與更新，下一份 ADR 0022。
4. [x] 驗證：Mermaid 以 mermaid-cli 渲染；`git grep` 確認 ADR 間引用。
5. [x] `task.py finish`、`task.py archive design-lyrics --no-commit --skip-branch-validation`；分開提交 ADR 與歸檔，推上 `docs/audit`。

回退：全部是文件，revert 對應 commit 即可。
