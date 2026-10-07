# 0024 — UI／UX：Material 3 加 token、五段寬度版面、右欄分頁的桌面播放頁、繁中為主的 i18n、App 內快捷鍵

- 狀態：已採納
- 日期：2026-09-28
- 影響範圍：`app/lib/ui/` 的主題與 token、字型 fallback、斷點與導覽殼、播放頁、播放列、搜尋頁篩選列、設定頁版面、i18n、無障礙、鍵盤與焦點、使用者指南、`fmp_lints`

## 背景

舊專案（`.trellis/tasks/archive/2026-09/09-28-design-ui-ux/research/current-state.md`、`docs/audit/ui.md`，已以程式碼核對）：

- 主題為 `ColorScheme.fromSeed`，沒有間距、字級 token：`EdgeInsets` 約 250 處、`SizedBox` 約 500 處字面數字，29 處 `fontSize:`（U1）。
- 字型 fallback 只有簡體字形（Windows `Microsoft YaHei`、其他 `Noto Sans SC`），i18n 的 base locale 是 zh-CN；擁有者主要用繁中。
- `large`、`extraLarge` 沒有版面（U8）；右側「正在播放」面板在寬度 ≥ 840 常駐（U7）。
- 播放頁寬版是左封面＋右歌詞（5：7），沒有佇列；播放列固定 7 個控制，窄視窗時曲名只剩 2 字（U4）。
- App 內沒有快捷鍵、Esc 離不開播放頁、焦點看不見（U2）；大播放鍵沒有名稱、播放列是按鈕包按鈕（U3）；搜尋篩選列被蓋住（U5）；「4600.0萬」「1 tracks」（U6）。
- 使用者指南是 7 段、每語言約 40 條的 App 內頁（E20）。

擁有者：U1–U8 全部重寫時處理，U7 面板保留常駐、U8 實作大斷點；parent prd 第 5 項要求桌面播放頁提供 2–3 個方案選擇。
2026-09-28 選定：
- 播放頁方案 B（示意頁 https://claude.ai/artifact/WbYKvNKgS2XpJbCuGr9xTZ ，僅擁有者可見）；
- 三語言、base 改 zh-TW；
- App 內快捷鍵的清單；
- 播放列三段；
- 刪除 App 內指南；
- Material 3 加播放頁局部毛玻璃。

## 考慮過的選項

- **播放頁 A 左右分割**：否決，看佇列會蓋住歌詞，超寬空間用不上。
- **播放頁 C 沉浸式歌詞**：否決。B 站、YouTube 曲目常沒有歌詞，畫面會空；佇列要另外叫出。
- **只留繁中與英文**：否決，簡中使用者只能看英文。
- **簡中由 OpenCC 自動轉換**：否決，用詞不道地，要另外維護修正清單。
- **App 內只做畫面操作的快捷鍵、播放靠全域**：否決，在 App 內按空白鍵不能暫停。
  擁有者問過「只有全域不行嗎」：全域快捷鍵會攔走所有 App 的按鍵，只能用罕用組合；Esc、搜尋、焦點移動只在 App 內有意義（U2）。
- **App 內快捷鍵可自訂**：否決，要做衝突檢查與錄製介面。
- **中寬度播放列保留五個播放控制**：否決，曲名只剩 6–7 字。
- **保留 App 內使用者指南**：否決，三語言各一份、容易過時。
- **整套液態玻璃**：否決。
  - Flutter 官方 2025-06-11 表示不在 Cupertino 開發 Apple '26 設計（#170310）；
  - `liquid_glass_renderer` 實驗性，只支援 Impeller，不支援 Windows、Linux、Web；
  - `liquid_glass_easy` 真折射只在 Impeller，Skia 上退化為毛玻璃，每片玻璃都要讀背景重算；
  - 在 Android、Windows 上風格不合，也要自己做元件與無障礙。
- **全 App 毛玻璃**：否決。內容在其下捲動時每幀重算模糊，對比度也難守。
- **各平台原生風格（Fluent、Material、Cupertino）**：否決，要做三套 UI。
- **`flutter_adaptive_scaffold`**：否決，已停止維護，官方沒有替代。
- **dynamic color（Material You 取色）**：不做，舊版沒有，屬新功能。

## 決定

1. **風格與 token**：
   - Material 3 元件；沿用 seed 色、preset、淺色／深色／跟隨系統。
   - `AppTokens`（`ThemeExtension`）：
     - 間距 4、8、12、16、20、24、32、40、48；
     - 圓角 4、8、12、16、28（M3 shape scale）；
     - 語意色：成功、警告；
     - 焦點框：2dp `primary`、外擴 2dp。
   - 字級只用 M3 `textTheme` 角色；元件固定尺寸（封面上限、面板寬度）放 theme 目錄的 `AppLayout`。
   - 播放頁在模糊封面背景上，以半透明表面色（約 60–72%）＋一般模糊做右欄、佇列、控制區，不做折射；系統「減少透明度」或高對比時改為不透明。
   - `material_ui` 的 import 路徑在建立 `app/` 時依當時 stable 的官方建議決定。
2. **字型**：`fontFamilyFallback` 依目前語言排序，由平台層提供（ADR 0009）；Linux 是否內建 Noto CJK 由 Linux 平台任務決定。
   - 繁中：Windows `Microsoft JhengHei UI`、`Microsoft JhengHei`，其他平台 `Noto Sans TC`；
   - 簡中：Windows `Microsoft YaHei UI`、`Microsoft YaHei`，其他平台 `Noto Sans SC`；
   - 英文：繁中清單在前。
3. **斷點與導覽**：自有 `WindowClass`，與 M3 同值。

   | 寬度 | 導覽 | 右側「正在播放」面板 | 播放頁 |
   |---|---|---|---|
   | compact（< 600） | 底部導覽列 | 無 | 手機版 |
   | medium（600–839） | NavigationRail | 無 | 手機版 |
   | expanded（840–1199） | NavigationRail | 常駐、可收起、可拖寬（U7） | B 兩欄 |
   | large（1200–1599） | 常駐導覽抽屜（圖示＋文字） | 同上 | B 兩欄 |
   | extraLarge（≥ 1600） | 常駐導覽抽屜 | 同上，預設較寬 | B 三欄（U8） |

4. **播放頁（方案 B）**：
   - ≥ 840：左右各半。
     - 左：封面（上限 420dp）、曲名、歌手、進度、五個播放控制；
     - 右欄：分頁「歌詞｜佇列｜詳細」，依裝置記住上次的分頁。「詳細」與右側面板共用同一個內容 widget。
   - extraLarge：三欄（約 1：1.15：0.9），依序為封面與控制｜歌詞｜分頁「佇列｜詳細」。
   - 手機與 medium：封面與歌詞切換，佇列以底部面板開啟。
   - 共通：Esc 關閉；背景為模糊封面＋遮罩。
5. **播放列**（依內容區寬度，曲名至少約 160dp）：
   - ≥ 840：隨機、上一首、播放、下一首、循環、輸出裝置、音量滑桿；
   - 600–839：上一首、播放、下一首、音量圖示（點開滑桿）、「⋯」（隨機、循環、輸出裝置）；
   - < 600：播放、下一首。
   
   點空白處開播放頁，點擊區與按鈕分開（U3、U4）。
6. **其他版面**：
   - 搜尋頁的來源 chip 列可橫向捲動、兩端有漸層提示，排序按鈕在捲動區外（U5）；
   - 設定頁依 ADR 0011 的分組，expanded 以上用 list-detail（左分組、右內容）；
   - 數字用 `intl` 的 `NumberFormat.compact`（`4600萬`、`46M`），英文複數用 slang 的複數語法（U6）。
7. **i18n**：
   - slang，`base_locale: zh-TW`，三語言（zh-TW、zh-CN、en）；新字串先寫繁中，缺字退回繁中。
   - 子視窗與懸浮窗的字串經型別化訊息傳入（ADR 0021）。
8. **無障礙與鍵盤**（U2、U3）：
   - 只有圖示的按鈕都有 tooltip 與語意標籤。
   - App 內快捷鍵固定、不可自訂，只在 FMP 為前景且焦點不在輸入框時有效：

     | 按鍵 | 動作 |
     |---|---|
     | 空白鍵 | 播放暫停 |
     | Ctrl+←／→ | 上一首／下一首 |
     | Shift+←／→ | 倒轉／快轉 5 秒 |
     | Ctrl+↑／↓ | 音量 |
     | Ctrl+S | 隨機 |
     | Ctrl+R | 循環 |
     | Ctrl+F | 搜尋 |
     | Ctrl+L／Ctrl+Q | 播放頁右欄切到歌詞／佇列 |
     | Esc | 關閉播放頁與對話框 |
     | F6 | 在導覽／內容／播放列三區之間移動焦點 |
     | Ctrl+, | 設定 |

   - 提示文字附按鍵；設定頁「鍵盤快捷鍵」列出 App 內與全域兩組。
   - 全域快捷鍵照舊：可自訂、預設關、預設 Ctrl+Alt+…。同一組按鍵時全域優先；錄製全域快捷鍵時若與 App 內相同就提示。
   - `FocusTraversalGroup` 分三區，Tab 只在區內移動。
9. **使用者指南**（E20）：
   - 刪除 App 內指南頁與其字串，改為 repo 的 `docs/user-guide.md`（繁中，隨 `app/` 功能撰寫）。
   - 「設定 → 關於」列版本、使用說明、CHANGELOG、回報問題（ADR 0023）、原始碼、授權；網址放在 `fmp_url_literal` 允許的端點檔。
   - 容易卡住處就地說明：首次引導、權限說明、快捷鍵清單。

採用的慣例：
- Material 3 的 window size class、導覽元件切換、canonical layouts；
- Namida 寬版播放頁的右欄分頁與記住選擇；
- Feishin 的左右分割全螢幕播放器；
- Spotify、Apple Music 官方快捷鍵表；
- Spotube、Namida、Finamp 的「關於頁連到 GitHub 文件」；
- CLDR 的數字縮寫（`intl`）。

## 後果

- 好的：
  - 間距、字級、顏色有一致來源並由 lint 守住；
  - 繁中字形正確；
  - 大螢幕空間用上；
  - 看佇列不必離開播放畫面；
  - 窄視窗曲名可讀；
  - 鍵盤可完整操作；
  - 說明文件跟著程式碼更新。
- 壞的：
  - 多一種三欄播放頁；
  - 每改一條字串仍要動三個檔；
  - App 內快捷鍵不能自訂；
  - 看說明要連網；
  - 播放頁毛玻璃要守對比度。
- 之後要注意：
  - Material 拆成 `material_ui` 的遷移時程；
  - Flutter 若提供官方 window size class 或液態玻璃支援時再評估；
  - Linux 的 CJK 字型內建由平台任務決定。
- 更正（2026-09-29）：§決定 2 的 `Noto Sans TC`／`Noto Sans SC` 在 Android 無效。系統的 Noto CJK 在 `fonts.xml` 是沒有名稱的 fallback family，引擎以名稱找不到，所以 Android 不指名字型，繁簡字形交給文字的 locale；模擬器實測 `zh-Hant` 的 locale 拿到繁中字形（來源與實測見 `.trellis/tasks/archive/2026-09/09-29-platform-layer/research/notes.md`，M1 PR 4）。
- 更正（2026-10-07，M2 PR 18a）：§決定 1 的「系統『減少透明度』時改為不透明」目前偵測不到：Flutter 3.47.5 的 `AccessibilityFeatures` 沒有這一項（有 `accessibleNavigation`、`invertColors`、`disableAnimations`、`boldText`、`reduceMotion`、`highContrast`），所以只照 `highContrast` 改成不透明。

## 如何確認

- lint `fmp_design_tokens`（加入 ADR 0015 的 `fmp_lints`）：`lib/ui/`（theme 目錄除外）不得在 `EdgeInsets.*`、`SizedBox` 寬高、`BorderRadius.circular`、`fontSize:` 使用數字字面值（`0` 除外），
  也不得寫 `Color(0x…)`、`Colors.*`；依 ADR 0015 寫雙向變異測試。
- widget 測試：
  - 首頁、搜尋、歌單、播放頁、設定在淺色與深色主題下通過 `meetsGuideline(labeledTapTargetGuideline)` 與 `textContrastGuideline`；播放頁以最淺與最深的測試封面各測一次。
  - 快捷鍵與焦點：空白鍵、Esc、F6，以及輸入框內空白鍵只輸入空格。
  - 播放列三段寬度的控制項集合，曲名寬度不小於 160dp。
- golden（`alchemist`，色塊字型）：播放頁 B 在 1000、1400、1800 寬，播放列三段寬度；只守版面結構，數量保持少。
- i18n：三語言 key 集合相同（缺一條即紅）。
- 第一個里程碑實測：輸入框內空白鍵不觸發播放；F6 焦點切換；Windows 繁中字形由正黑體顯示。
