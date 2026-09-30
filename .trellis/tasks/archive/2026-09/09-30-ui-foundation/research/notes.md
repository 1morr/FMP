# UI 基礎（M1 PR 12a）：查證與選擇

查證日期 2026-09-30，對照 Flutter 3.47.5（engine `af7e796e16`）、`material_ui` 1.5.0、slang 4.19.2。
這個環境沒有 context7／tavily，來源是 pub-cache 裡的套件原始碼與 README、pub.dev API（版本）。

## 1. 套件

| 套件 | 版本 | 用途 | 決定 |
|---|---|---|---|
| `slang` | ^4.19.2（pub.dev 最新，2026-09-12） | 介面字串 | 採用；ADR 0024 §決定 7 指定 |
| `slang_build_runner` | ^4.19.0（最新；它釘 `slang >=4.19.0 <4.20.0`） | 讓 `dart run build_runner build` 一併產生翻譯 | dev 依賴；CI 既有的「Check generated code is up to date」就涵蓋 slang，不另加步驟 |
| `slang_flutter` | — | `TranslationProvider`、`context.t`、`LocaleSettings` 的 Flutter 部分 | **不用**：翻譯以 Riverpod 注入（§3） |
| `clock` | ^1.1.3（原本就是 fake_async／flutter_test 的傳遞依賴） | Toast 去重讀時間 | 採用：`fake_async` 的 `run` 以 `withClock` 包住，`clock.now()` 跟著假時間走 |
| `intl` | ^0.20.2（跟 `material_ui` 的限制） | slang 產生檔的 import；之後 ADR 0024 §決定 6 的數字縮寫 | 直接依賴：產生檔一律 import 它，不宣告就是 import 沒宣告的套件（check agent 改） |
| `alchemist` | — | golden | 12a 不做 golden（ADR 0024 的 golden 是播放頁與播放列，12b 以後） |
| `flutter_localizations` | — | — | **不直接用**：見 §2 |

## 2. Material 的內建字串與 locale

- `material_ui` README「Step 2: Migrate localizations」：用 `material_ui` 自己的
  `GlobalMaterialLocalizations.delegates`（內含 `cupertino_ui` 的 Cupertino 與
  `flutter_localizations` 的 Widgets）。`flutter_localizations` 的 `GlobalMaterialLocalizations`
  提供的是凍結的 `package:flutter/material.dart` 的 `MaterialLocalizations` 型別，
  `material_ui` 的元件查不到。
- `material_ui-1.5.0/lib/src/l10n/generated_material_localizations.dart` 的
  `getMaterialTranslation`：`zh` 先看 `scriptCode`（`Hans` → `ZhHans`；`Hant` 再看
  `HK`／`TW`），沒有 script 才看 `countryCode`。`isSupported` 只看 `languageCode`。
- `WidgetsApp` 即使給了 `locale` 也會拿它對 `supportedLocales` 做
  `basicLocaleListResolution`；`supportedLocales` 放同樣帶 script 的三個 locale，完全比對。
- 測試（`test/ui/i18n/ui_locale_test.dart`）：`zh-Hant-TW` 的 `okButtonLabel` 是「確定」、
  `zh-Hans-CN` 是「确定」、`en` 是「OK」。

## 3. slang 的 locale 與注入方式

- 檔名 `<locale>.i18n.json`；`zh-TW`、`zh-CN`、`en` 產生 `AppLocale.zhTw`（`languageCode: 'zh',
  countryCode: 'TW'`）等。slang 的 locale 也可以帶 script（`zh-Hant-TW`），但 ADR 0024 定
  `base_locale: zh-TW`，所以 slang 用 `zh-TW`／`zh-CN`，給 Flutter 的帶 script 的 locale 由
  `lib/ui/i18n/ui_locale.dart` 的 `flutterLocaleOf` 從 `LocaleSetting` 對出來。slang 的
  `AppLocale.flutterLocale` 不用（`flutter_integration: false` 時也不產生）。
- README「Dependency Injection」：`locale_handling: false`（不產生全域 `t`、`LocaleSettings`）＋
  `translation_class_visibility: public`，以 `AppLocale.x.buildSync()` 建實例，文件的例子就是
  Riverpod。採用：`translationsProvider` 由 `uiLocaleProvider` 算出。理由：語言的來源已經是
  外觀設定的 Notifier（ADR 0011），再有 slang 的全域 `LocaleSettings` 會變成兩份狀態；
  `Toaster` 不用 `BuildContext` 也拿得到翻譯；測試不用重設全域。
- `fallback_strategy: base_locale`：缺字退回繁中（PRD「缺字退回繁中」）。代價是漏翻照樣編譯，
  所以 `test/i18n/translations_test.dart` 比對三個 JSON 的 key 與參數。
- `lazy: false`：Android、Windows 沒有 deferred loading，延遲載入換不到任何東西（舊專案同樣設定）。
- `string_interpolation: braces`（`{source}`）、`timestamp: false`（產生檔穩定，CI 才比得了）、
  `flat_map: false`（不用字串 key 查翻譯）、`format.enabled: true, width: 80`（產生檔通過
  `dart format --set-exit-if-changed`）。
- 產生檔提交（`lib/i18n/*.g.dart`），比照 drift：拉下來不用先跑 codegen；CI 重跑 build_runner
  後有 diff 就紅。

## 4. Toast 的層級（ADR 0023 §決定 3）

- `MaterialApp` 自己在 `builder` 之上建了一個根 `ScaffoldMessenger`；`ToastHost` 在 `builder`
  裡再建一個，包住 Navigator。頁面的 `Scaffold` 都是宿主 `Scaffold` 的子孫，
  `ScaffoldMessengerState` 只把 SnackBar 放在「根」的 Scaffold（不是其他已登記 Scaffold 的
  子孫者），所以只出現在宿主這一層，畫在所有路由之上。
- SnackBar 的計時器只在 `ModalRoute.of(messenger 的 context)` 為 null 或是目前路由時啟動
  （`scaffold.dart` 的 `ScaffoldMessengerState.build`）；宿主在 Navigator 之上，`ModalRoute` 是
  null，全螢幕頁開著時照樣計時。
- `SnackBar.persist` 預設 `action != null`：帶動作的預設不消失。ADR 要照時長消失，所以明確給
  `persist: accessibleNavigation`。
- floating 的 SnackBar 已由 `Scaffold` 放在底部安全區（`minViewPadding.bottom`）之上；外殼發佈
  的高度從視窗底邊算，所以宿主只補 `max(0, 發佈高度 − viewPadding.bottom)`。
- **無障礙導覽時的關閉鈕需要 Overlay**：`IconButton` 的 tooltip 找最近的 Overlay，宿主在
  Navigator 之上找不到而拋錯（widget 測試抓到）。宿主以 `Overlay.wrap` 包住自己。
- 宿主 `Scaffold` 設 `resizeToAvoidBottomInset: false`：否則鍵盤出現時整個 Navigator 被縮，
  頁面的 Scaffold 也拿不到 `viewInsets`。

## 5. 採用的慣例

- 間距以 4dp 為單位、名稱是倍數（`x4` = 16）：Tailwind 的 spacing scale 與 M3 的 4dp grid。
- 圓角名稱：M3 shape scale（extraSmall 4、small 8、medium 12、large 16、extraLarge 28）。
- 語意色：M3「custom colors」的做法，以固定 seed 產生同一組四個色調（color／on／container／
  onContainer）；沒做 harmonize（要直接依賴 `material_color_utilities`）。
- 資訊類提示用 M3 snackbar 預設的 `inverseSurface`；成功、警告、錯誤用各自的 container 色。
- 語言選單的名稱用各語言自己的寫法（endonym）：Android、iOS 語言設定的慣例；每個名稱帶自己的
  locale，繁簡字形不隨介面語言變。
- `WindowClass` 的值與名稱：M3 window size classes。
- 翻譯注入：slang 文件的 Dependency Injection 一節（Riverpod 例子）。

## 6. 實機驗證（主對話做，結論補在這裡）

- Windows 繁中是不是正黑體（2026-09-30，Windows dev build，身分頁依序切 繁體中文 → English →
  简体中文）：繁中與英文介面的「UI」列與 zh-Hant 參照列（正黑體）相同，簡中介面與 zh-Hans
  參照列（雅黑）相同。
  - 同一輪發現 `UI locale applied` 的 `fontFallback` 記成上一個語言的清單（簡中記成英文的四個
    字型）；畫面本身正確。原因：listener 在 `uiLocaleProvider` 的 listener 裡 `ref.read`
    `fontFamilyFallbackProvider`，而 Riverpod 依訂閱順序通知，`fontFamilyFallbackProvider`
    重建一次後重新訂閱、排到 listener 後面，被讀的時候還沒收到「相依變了」，回傳舊值。改成
    以 listener 拿到的語言呼叫 `fontFamilyFallbackOf`；`fmp_app_test.dart` 來回切換四次斷言
    每筆 log。
- Android 英文介面的漢字字形（2026-09-30，Android 17 模擬器，系統語言 en、App 語言跟隨系統，
  log `{locale: en, fontFallback: []}`）：「UI」列是簡中字形（「骨」裡面是直的「月」、「令」
  末筆是點），與 zh-Hans 參照列相同。也就是英文介面的文字 locale 是 `en`，引擎依
  fonts.xml 的順序取到 `zh-Hans` 那個 family。
  - 對策：`buildAppTheme` 把 `textLocaleOf` 的 locale 放進每個 `TextTheme` 角色（英文介面是
    `zh-Hant-TW`，中文介面同介面語言）。Material 元件（文字、輸入框、按鈕、分段按鈕、
    ListTile、AppBar）的樣式都從主題繼承到它（`app_theme_test.dart`）；英文字由主字型顯示，
    不受影響；Material 內建字串仍看 `MaterialApp.locale` 的 `en`。
  - 代價：樣式的 locale 蓋過 `Text.locale`，所以語言選單的名稱改在樣式上給 locale。
  - 修正後的實機複驗（2026-09-30，主對話）：Android 模擬器（系統語言 en）英文介面的漢字與 zh-Hant 對照列相同（「骨」內為台灣寫法、「令」末筆非點），切到简体中文後與 zh-Hans 列相同；Windows 切 繁中 → English → 简中 → 繁中，四筆 `UI locale applied` 的 `fontFallback` 都對應當下語言，字形與修正前相同（繁中／English 正黑體、简中雅黑）。
