# UI 基礎：主題、字串、提示（M1 PR 12a）

父任務：`../09-28-m1-skeleton-tracer`（implement「12.」的前半；擁有者決定 2）。PR 12 拆成 12a（基礎）與 12b（外殼與頁面），各自一個 PR。

依據：
- ADR 0024：§決定 1–3、7、8 的無障礙部分；
- ADR 0023：§決定 1–3、5；
- ADR 0013：錯誤對應表、`messageKey`；
- ADR 0011：外觀設定；
- ADR 0009：字型 fallback 由平台層提供。

## 做什麼

1. **主題**：放在 `lib/ui/theme/`。
   - Material 3，seed 色；淺色、深色、跟隨系統。
   - `AppTokens`（`ThemeExtension`）：
     - 間距 4、8、12、16、20、24、32、40、48；
     - 圓角 4、8、12、16、28；
     - 語意色：成功、警告；
     - 焦點框：2dp `primary`，外擴 2dp。
   - 元件固定尺寸放 `AppLayout`；字級只用 M3 的 `textTheme` 角色。
   - `fmp_design_tokens` 已經守著 `lib/ui/`（theme 目錄除外），這次讓它真的有東西可守。
2. **`WindowClass`**：compact、medium、expanded、large、extraLarge，與 M3 同值（< 600、600–839、840–1199、1200–1599、≥ 1600）。
   - 以內容區寬度判斷，由一個 provider 或 `InheritedWidget` 提供。
3. **字型**：主題的 `fontFamilyFallback` 取自平台層（PR 4 已提供），依目前介面語言排序。
   - `MaterialApp.locale` 帶 script 的形式，例如 `zh-Hant-TW`。
   - 做完後實測兩件事：
     - Windows 的繁中是不是由正黑體顯示；
     - Android 英文介面時，漢字會不會落到簡中字形。

     結論寫進研究檔；需要的話在漢字文字上指定 `zh-Hant`。
4. **i18n**：slang。
   - `base_locale: zh-TW`，三語言：zh-TW、zh-CN、en；缺字退回繁中。
   - 測試：三語言的 key 集合相同，少一條就紅。
   - 外觀設定的「語言」控制 App locale：跟隨系統，或指定三者之一。
   - **錯誤訊息**：`ErrorMessageKey` 對到 slang 字串。
   - 同時收窄 `AppError.messageArgs`：只收數字，與已知的具名值（例如秒數、插件名稱），不讓插件把伺服器原文送上畫面。這是 PR 7 審查時發現的。
5. **提示**：`Toaster` 與 `ToastHost`，照 ADR 0023 §決定 1–3、5。
   - `success`、`info`、`warning` 收 i18n 字串；`error(AppError, {operation})` 只收 `AppError`。
   - SnackBar 使用 floating 樣式，四種語意色加圖示。
   - 一次一則，新的取代舊的。時長：成功與資訊 4 秒，錯誤與警告 6 秒。開啟無障礙導覽時停留到手動關閉。
   - 5 秒內去重。
   - 放在 `MaterialApp.builder`，全螢幕頁、對話框、底部面板之上都看得到。
   - 外殼要發佈「底部被佔用的高度」。12a 先提供介面，12b 的外殼再接上。
   - 錯誤一律經 log 門面寫進錯誤歷史。
   - **M1 不做**：ADR 0023 §決定 4 的詳細頁、`ErrorReport`、「回報」按鈕。移到 M3，和 Debug 頁的錯誤歷史一起做，因為兩者共用同一頁。
6. **外觀設定能清回「跟隨系統」**：`AppearanceSettingsRepository.write` 補上把欄位清成 `null` 的方式，並加測試。這是 PR 6 審查時發現的。
7. `MaterialApp` 接上主題、locale 與 `ToastHost`。現有的身分頁保留，12b 才換成外殼。

## 驗收

- [ ] `app/` 驗證清單全過。
- [ ] 測試：
  - token 與 `WindowClass` 的邊界值；
  - 三語言 key 集合相同；
  - 每個 `ErrorMessageKey` 在三語言都有字串；
  - `messageArgs` 收窄後，插件送來的字串不會出現在畫面上；
  - Toast 的去重、取代、時長；
  - 全螢幕路由與對話框開著時，提示仍然可見；
  - 外觀設定可以清回跟隨系統；
  - 淺色與深色主題下，示範畫面通過點擊區與對比度 guideline。
- [ ] 實機，照 `verify-on-device`，Android 與 Windows 各一次：
  - 切換主題、語言後身分頁正常；
  - Windows 繁中是正黑體（截字形，避開個人資訊）；
  - Android 英文介面的漢字字形。

  身分頁目前不需要提示；Toast 的實機可見性在 12b 驗。
