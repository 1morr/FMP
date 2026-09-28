# 設計：UI／UX 設計系統、響應式與桌面播放頁（階段二第 5 項）

## 目標

為 `app/` 定下設計 token（間距、字級、圓角、色彩）、各視窗寬度的版面與導覽、桌面播放頁版面、i18n、無障礙與鍵盤操作、使用者指南的去留。產出 ADR 0024。技術設計見 `design.md`，執行步驟見 `implement.md`。

依據：parent `prd.md` 階段二第 5 項；`docs/audit/questions.md` U1–U8（擁有者全部勾「重寫時處理」；U7 右側「正在播放」面板保留常駐；U8 大斷點實作）、E20（不確定）；
`docs/audit/ui.md`；`phase2-plan.md` §5（E20 傾向刪除改連 docs）、§8（CJK 字型依平台 fallback）；ADR 0009（平台層）、0011（設定分組）、0021（歌詞 widget 共用、逐字高亮）、0023（Toast 位置）。

## 現況（`research/current-state.md`＋`docs/audit/ui.md`，關鍵項已核對）

- **主題**：`ColorScheme.fromSeed`（預設紫色 seed＋9 組 preset），沒有 dynamic color；深淺色與系統三態；8 個 sub-theme；`textTheme` 沒有自訂字級。
- **token**：只有 `AppRadius` 與版面常數；`EdgeInsets` 約 250 處、`SizedBox` 約 500 處字面數字，29 處 `fontSize:` 繞過主題（U1）。事實標準是 4 的倍數。
- **字型**：Windows fallback `Microsoft YaHei UI`、`Microsoft YaHei`（**都是簡體字形，沒有繁中**），其他平台 `Noto Sans SC`；使用者主要用繁中。
- **斷點**：`WindowClass` 與 M3 同值（600／840／1200／1600）；`large`、`extraLarge` 沒有對應版面（U8）。
- **導覽**：手機底部導覽列、桌面 NavigationRail；右側「正在播放」面板（`TrackDetailPanel`，預設 412dp、可拖寬度）在寬度 ≥ 840 的所有頁面常駐（U7）。
  迷你播放器 5 顆控制＋桌面 2 顆（輸出裝置、音量），窄桌面視窗時標題只剩 2 個字（U4）。
- **播放頁**：四種版面 `narrow`／`wideSingle`／`wideSplit`（左封面＋控制 5：右歌詞 7）／`shortSplit`；背景是模糊封面（sigma 48）＋ 60% 表面色；
  寬版沒有佇列欄，佇列要另開。
- **i18n**：slang，38 檔 × 3 語言（zh-CN、zh-TW、en）＝ 1176 key，**base locale 是 zh-CN**；`formatCount` 強制一位小數造成「4600.0萬」「46.0M」，英文沒有複數（「1 tracks」）（U6）。
- **鍵盤**：App 內 `Shortcuts`／`Actions` 0 處，Esc 離不開播放頁，深色主題焦點指示幾乎看不見，Tab 要穿過整個清單（U2）；全域熱鍵（`hotkey_manager`）有設定頁。
- **無障礙**：大播放鍵沒有名稱、迷你播放器是按鈕包按鈕（U3）；沒有 golden 測試、沒有對比度測試。
- **搜尋頁**：來源篩選列被排序鈕蓋住、沒有可捲動提示（U5）。
- **使用者指南（E20）**：7 段可展開卡片、每語言約 40 條目。

## 研究結論（`research/prior-art.md`、`research/packages-and-platform.md`）

- **M3**：寬度 class 與 FMP 同值；導覽列只到 medium，rail 從 medium 起；canonical layouts 有 list-detail、supporting pane、feed。
  Material 3 Expressive 在 Flutter 端官方表示目前不開發（#168813）。spacing token 以 4／8dp 為基礎。
- **桌面播放頁先例**：
  - 歌詞在右側：Apple Music 全螢幕播放器、Feishin（左 50% 封面，右側分頁：佇列／歌詞／相關）。
  - 右欄分頁（歌詞與佇列互斥、記住選擇）：Namida 寬版播放頁（左右各半）。
  - 沉浸式歌詞佔滿、底部控制列帶小封面、網格漸層背景：Harmonoid。
  - Spotify 以右側 Now Playing 面板與底部播放列為主，佇列、歌詞是獨立頁。
  - 佇列在多數產品是獨立頁或側滑面板；背景主流是模糊封面或封面取色。
- **快捷鍵**：Spotify 官方表（Space 播放暫停、Ctrl+F／Ctrl+K 搜尋、Ctrl+S 隨機、Ctrl+R 循環、Alt+Shift+Q 佇列）；Apple Music（Space、左右鍵上下一首、Cmd+↑↓ 音量）。
- **使用者指南**：Spotube、Namida、Finamp、Feishin 只有 About 頁並連到 GitHub 或網站；NewPipe、LocalSend 有 About 加 FAQ 連結。沒有大量內建說明頁的先例。
- **Flutter**：`WindowSizeClass` 不在 framework；`flutter_adaptive_scaffold` 已停止維護且無官方替代；Material 正拆出為 `material_ui`（1.4.0，舊版已間接依賴 1.1.1），舊路徑移除時程不明。
  `intl` 的 `NumberFormat.compact`：en `46M`、zh_TW `4600萬`、zh_CN `4600万`（本機實測）。slang 4.19.2 支援複數與參數。
  `SemanticsRole`（dart:ui）、`meetsGuideline(textContrastGuideline)` 可用；golden 測試可用 `alchemist` 解決跨平台字型差異。

## 已確定的方向

- U1–U8 都在重寫時處理；U7 右側面板保留常駐；U8 實作大斷點版面。
- Toast 位置照 ADR 0023；播放頁與桌面視窗的歌詞共用一套 widget（ADR 0021）。

## 已決定

1. **桌面播放頁用方案 B（2026-09-28，按建議）**：示意頁 https://claude.ai/artifact/WbYKvNKgS2XpJbCuGr9xTZ（私人）。
   ≥ 840dp：左右各半，左為封面、曲名、進度、控制；右欄分頁「歌詞｜佇列｜詳細」並記住上次的分頁；「詳細」放現行右側面板的內容。
   ≥ 1600dp：三欄——封面與控制｜歌詞｜佇列（分頁剩「佇列｜詳細」）。< 840dp 用手機版播放頁。Esc 關閉；背景為模糊封面。
   否決：A 左右分割（看佇列會蓋住歌詞、超寬空間用不上）、C 沉浸式歌詞（無歌詞曲目畫面空、佇列需另叫出）。

2. **三種語言保留、base locale 改為 zh-TW（2026-09-28，按建議）**：新字串先寫繁中；缺字退回繁中；測試要求三語言 key 完全一致。
   字型 fallback 依語言分開（繁中先微軟正黑體／Noto Sans TC，簡中微軟雅黑／Noto Sans SC）；數字用 `NumberFormat.compact`、英文複數用 slang 複數。
   否決：只留繁中與英文（簡中使用者只能看英文）、簡中由 OpenCC 自動轉換（用詞不道地、要維護修正清單）。

3. **App 內鍵盤快捷鍵（2026-09-28，按建議）**：固定一組、不可自訂，只在 FMP 為前景視窗且焦點不在輸入框時有效：
   空白鍵播放暫停、Ctrl+←／→ 上下一首、Shift+←／→ 倒轉快轉 5 秒、Ctrl+↑／↓ 音量、Ctrl+S 隨機、Ctrl+R 循環、Ctrl+F 搜尋、
   Ctrl+L／Ctrl+Q 播放頁右欄切歌詞／佇列、Esc 關閉播放頁與對話框、F6 在導覽列／內容／播放列之間跳、Ctrl+, 設定。
   提示文字附按鍵，設定頁有完整清單；兩種主題都有明顯焦點框，Tab 只在同一區內移動。
   全域快捷鍵照舊（可自訂、預設關、預設 Ctrl+Alt+…），同一組按鍵時全域優先；錄製全域快捷鍵時若與 App 內相同就提示。
   擁有者問「只有全域不行嗎」：全域會攔走所有 App 的按鍵，只能用罕用組合，且 Esc、搜尋、焦點移動只在 App 內有意義（U2）。
   否決：App 內只做畫面操作（在 App 內按空白鍵不能暫停）、App 內快捷鍵可自訂（要衝突檢查與錄製介面）。

## 待決定

1. 窄桌面視窗的迷你播放器保留哪些控制。
2. 使用者指南（E20）去留。

## 不在範圍

- dynamic color（Material You 取色）：舊版沒有，屬新功能。
- Debug 頁的版面（第 4 項）。

## 驗收條件

- [ ] ADR 0024 記錄：token 與主題、字型 fallback、斷點與導覽、右側面板、桌面與手機播放頁、迷你播放器、i18n 與數字格式、無障礙、鍵盤與焦點、使用者指南、閘門（lint、對比度、golden）。
- [ ] U1–U8、E20 各自對到決定。
- [ ] `phase2-plan.md` §3 第 5 項標 ✅ 與 ADR 編號。
