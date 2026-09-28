# 設計：UI／UX 設計系統、響應式與桌面播放頁

## 1. 主題與 token（U1）

- 色彩：沿用 `ColorScheme.fromSeed`（預設紫色 seed＋preset）、淺色／深色／跟隨系統；不做 dynamic color（新功能）。
- `AppTokens`（`ThemeExtension`，放在 `lib/ui/theme/`）：
  - 間距：`s4`、`s8`、`s12`、`s16`、`s20`、`s24`、`s32`、`s40`、`s48`，沿用現有 4 的倍數慣例；
  - 圓角：`xs 4`、`sm 8`、`md 12`、`lg 16`、`xl 28`（M3 shape scale）；
  - 語意色：成功、警告，其餘用 `ColorScheme` 角色；
  - 焦點框：2dp、`primary`、外擴 2dp。
- 字級只用 M3 `textTheme` 角色（`titleLarge`、`bodyMedium`…），不寫 `fontSize:`；元件的固定尺寸（封面上限、面板寬度）放 `AppLayout` 常數，同樣在 theme 目錄。
- 新 lint `fmp_design_tokens`（加入 ADR 0015 的 `fmp_lints`）：`lib/ui/`（theme 目錄除外）不得在 `EdgeInsets.*`、`SizedBox` 的寬高、`BorderRadius.circular`、`fontSize:` 使用數字字面值，
  也不得寫 `Color(0x…)`、`Colors.*`；允許 `0`。依 ADR 0015 寫雙向變異測試。
- Material 正拆出為 `material_ui` 套件：建立 `app/` 時依當時 stable 的官方建議決定 import 路徑，不提前遷移。

## 2. 字型（i18n 決定的一部分）

- 不指定主字型時用各平台預設（Windows 為 Segoe UI），`fontFamilyFallback` 依目前語言排序：
  - 繁中：Windows `Microsoft JhengHei UI`、`Microsoft JhengHei`，其他平台 `Noto Sans TC`；
  - 簡中：Windows `Microsoft YaHei UI`、`Microsoft YaHei`，其他平台 `Noto Sans SC`；
  - 英文：繁中清單在前，確保混排的中文字形正確。
- 清單由平台層提供（ADR 0009）；Linux 是否內建 Noto CJK 由 Linux 平台任務決定。

## 3. 斷點與導覽（U7、U8）

- 自有 `WindowClass`：compact < 600、medium 600–839、expanded 840–1199、large 1200–1599、extraLarge ≥ 1600（與 M3 同值）。不用已停止維護的 `flutter_adaptive_scaffold`。

| 寬度 | 導覽 | 右側「正在播放」面板 | 播放列 | 播放頁 |
|---|---|---|---|---|
| compact | 底部導覽列 | 無 | 手機迷你播放列 | 手機版 |
| medium | NavigationRail | 無 | 桌面播放列（中） | 手機版 |
| expanded | NavigationRail | 常駐、可收起、可拖寬（U7） | 桌面播放列（寬） | 方案 B 兩欄 |
| large | 常駐導覽抽屜（圖示＋文字） | 同上 | 同上 | 方案 B 兩欄 |
| extraLarge | 常駐導覽抽屜 | 同上，預設寬度較大 | 同上 | 方案 B 三欄 |

- 播放列的寬度分段依「內容區寬度」而不是視窗寬度：≥ 840、600–839、< 600（已決定 4）。compact 的桌面視窗也用 < 600 的樣子。

## 4. 播放頁（已決定 1）

- 桌面（≥ 840）：左右各半。左邊是封面（上限 420dp）、曲名、歌手、進度、五個播放控制；右欄分頁「歌詞｜佇列｜詳細」，記住上次的分頁（per-device 設定）。
- extraLarge：三欄，比例約 1：1.15：0.9，封面與控制｜歌詞｜分頁「佇列｜詳細」。
- 手機與 medium：現行 narrow 版面（封面與歌詞切換），佇列以底部面板開啟，詳細在「⋯」。
- 背景：模糊封面＋表面色遮罩（沿用）。頂列：收起、加入歌單、輸出裝置（桌面）、音量（桌面）、⋯。
- 「詳細」分頁與右側面板共用同一個內容 widget。

## 5. 其他版面問題

- 搜尋頁（U5）：來源篩選 chip 列可橫向捲動，兩端有漸層提示；排序按鈕在捲動區之外。
- 設定頁：依 ADR 0011 的分組；expanded 以上用 list-detail（左分組、右內容），compact 為單欄。
- 數字與複數（U6）：`intl` 的 `NumberFormat.compact`（依 locale：`4600萬`、`46M`），英文複數用 slang 的複數語法。

## 6. i18n（已決定 2）

- slang，`base_locale: zh-TW`，三語言；測試要求三語言 key 集合完全相同（缺一條即紅）。
- 桌面歌詞子視窗、Android 懸浮窗的字串經型別化訊息傳入（ADR 0021），不再自帶簡體預設值。

## 7. 無障礙與鍵盤（U2、U3，已決定 3）

- 所有只有圖示的按鈕都有 tooltip 與語意標籤；大播放鍵、播放列控制都有名稱；播放列點擊區與按鈕分開，不再是按鈕包按鈕。
- `Shortcuts`／`Actions` 掛在 App 根部，`Intent` 對到 `PlaybackController` 與路由；輸入框有焦點時不觸發（以 widget test 驗證空白鍵在搜尋框內只輸入空格）。
- `FocusTraversalGroup` 分三區（導覽、內容、播放列），F6 依序切換；焦點框用 `AppTokens` 的樣式，兩種主題都清楚。
- 設定頁「鍵盤快捷鍵」列出 App 內與全域兩組；錄製全域快捷鍵時若與 App 內相同就提示。

## 8. 使用者指南（已決定 5）

- 刪除 `user_guide_page` 與 `userGuide` 字串。新增 `docs/user-guide.md`（繁中），隨 `app/` 功能完成時撰寫。
- 「設定 → 關於」：版本、使用說明、CHANGELOG、回報問題（ADR 0023 的 GitHub 流程）、原始碼、授權；網址放在 `fmp_url_literal` 允許的端點檔。

## 9. 閘門

- lint `fmp_design_tokens`（§1）。
- widget 測試：
  - 主要頁面（首頁、搜尋、歌單、播放頁、設定）在淺色與深色主題下通過 `meetsGuideline(labeledTapTargetGuideline)` 與 `textContrastGuideline`；
  - 快捷鍵與焦點（空白鍵、Esc、F6、輸入框內不觸發）；
  - 播放列三段寬度的控制項集合；曲名寬度不小於 160dp。
- golden（`alchemist`，CI 用色塊字型避開平台差異）：播放頁 B 在 1000、1400、1800 寬；播放列三段寬度。只守版面結構，數量保持少。
- i18n：三語言 key 集合相同。

## 10. 相關 ADR 的指向

- 0011：設定頁 list-detail 版面、「鍵盤快捷鍵」與「關於」頁見 0024。
- 0015：後續 ADR 新增的規則加 `fmp_design_tokens`。
- 0021：播放頁歌詞所在位置（右欄分頁或 extraLarge 的中欄）見 0024。
