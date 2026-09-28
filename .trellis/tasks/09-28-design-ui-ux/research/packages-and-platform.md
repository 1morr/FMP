# packages-and-platform.md — 套件、framework 與平台事實（Flutter 3.47 世代）

- **查證日**：2026-09-28
- **查證方式**：
  - **本機 primary source**：Flutter SDK `D:\Development\SDK\flutter`（3.47.1 stable / Dart 3.13.1，framework revision `6655482ec06e547f90abf8ae7590466f4415978d`，2026-08-19）、FMP 的 `pubspec.yaml` / `pubspec.lock` / `.dart_tool/package_config.json`。
  - **實測**：以 `dart --packages=".dart_tool/package_config.json"` 跑 FMP 自己解析出的 `intl 0.20.3`，量測 `NumberFormat.compact` 的實際輸出（**非推測**）。`dart pub deps` 讀依賴樹。
  - **外部**：pub.dev API（`https://pub.dev/api/packages/<name>`）、`gh api`、`raw.githubusercontent.com`、context7（slang 官方 README）、api.flutter.dev / docs.flutter.dev。
  - **未執行 FMP App**、**未打任何音樂平台 API**。
- **標記慣例**：`逐字` = 官方原文；`推測` = 推論；`查不到` = 本輪找不到可靠出處；`實測` = 本機跑出來的。

---

## 0. Flutter 3.47 世代最重要的一件事：Material / Cupertino 正在從 SDK 拆出去

這條不在原題目清單裡，但它直接影響 FMP 的重寫，因此記在最前面。

- **現況是「並存」**：本機 3.47.1 SDK 的 `packages/flutter/lib/material.dart` 仍存在，`packages/flutter/lib/src/material/` 下有 **184** 個檔案（`typography.dart`、`color_scheme.dart` 等都在）。所以 `package:flutter/material.dart` 在 3.47.1 **照常可用**。
- **同時**，`flutter/packages` 已新增兩個獨立套件（`gh api` 列 `packages/` 目錄可見 `material_ui`、`cupertino_ui`）：
  - `material_ui` latest **1.4.0**（2026-09-22），`environment: {sdk: ^3.13.0, flutter: ">=3.47.0"}`，description 逐字「The official Flutter Material UI Library, implementing Google's Material Design design system.」
  - `cupertino_ui` latest **1.1.1**（2026-09-21）
- **官方 README 逐字**（<https://github.com/flutter/packages/blob/main/packages/material_ui/README.md>，本輪抓 `main`；**非固定 SHA permalink**）：「The standalone `material_ui` package was previously built directly into the core Flutter framework as `package:flutter/material.dart`. It has been decoupled from the flutter/flutter repository into its new home here in flutter/packages.」
- **官方遷移三步**（README 逐字）：
  1. `dart fix --apply --code=migrate_design_widgets` —— 效果等同於加入 `material_ui` 依賴並把 `package:flutter/material.dart` 的 import 改成 `package:material_ui/material_ui.dart`
  2. localizations：改用 `material_ui` / `cupertino_ui` 版的 `GlobalMaterialLocalizations` / `GlobalCupertinoLocalizations`（README 範例：`localizationsDelegates: GlobalMaterialLocalizations.delegates`）
  3. 第三方套件仍 import `package:flutter/material.dart` 時，用 `MaterialUiCompatibilityBridge` 橋接 `ThemeData` 與 `MaterialLocalizations`
- **FMP 的依賴樹已經踩到這條路**（實測 `dart pub deps --style=compact`）：FMP **沒有**直接依賴 `material_ui`，但 `pubspec.lock` 已經解析出 **`material_ui 1.1.1`** 與 **`cupertino_ui 1.0.2`**（皆 `dependency: transitive`）。拉進來的是兩個直接依賴：
  - `go_router 18.0.1` → `[collection cupertino_ui flutter flutter_web_plugins logging material_ui meta]`
  - `cached_network_image 4.0.0` → `[... material_ui]`（`cached_network_image_platform_interface 5.0.0`、`cached_network_image_web 2.0.0` 同）
- **官方部落格**（Flutter 3.47 what's-new）稱 `flutter_localizations` 也一併 unbundle → <https://flutter.dev/blog/whats-new-in-flutter-3-47>（本輪未逐字核對該頁）。FMP 目前仍以 `flutter_localizations: sdk: flutter` 直接依賴（`pubspec.yaml`，`pubspec.lock:457-460` 為 `dependency: "direct main"`, `source: sdk`）。
- **版本落差警告**：`docs.flutter.dev` 多數頁面仍標「reflects Flutter 3.44.7」，與本機 3.47.1 有落差，讀官方文檔時需留意。

---

## 1. Flutter framework 的響應式／自適應 API

### 1.1 `WindowSizeClass` **不在** Flutter framework

- 本機 SDK 實測：`grep -rn "class WindowSizeClass" packages/flutter/lib/` → **無命中**；`grep -rln "AdaptiveScaffold" packages/flutter/lib/` → **無命中**。
- 外部交叉查證（子代理）：`api.flutter.dev/flutter/widgets/WindowSizeClass-class.html` → **HTTP 404**；flutter/flutter code search `WindowSizeClass` total_count = **0**、`windowSizeClass` = **0**；`packages/flutter/lib/src/widgets/window_size_class.dart` 在 master → **404**；Flutter 3.47.0 release notes 未提 window size class。
- 官方 adaptive 總覽頁（<https://docs.flutter.dev/ui/adaptive-responsive>）只點名 `SafeArea` 與 `MediaQuery`；子頁 `large-screens` 逐字提「use `MediaQuery` to get the app window size rather than the physical device size」，另提 `ui.Display` API、`SliverGridDelegateWithMaxCrossAxisExtent`、`BoxConstraints.maxWidth`、`NavigationRail` vs `BottomNavigationBar`。
- **結論**：framework 內沒有 window size class API，官方路線是 `MediaQuery` + 自訂 breakpoint。`WindowSizeClass` 這個名字來自下面的套件與 Material 設計層，不是 Flutter API。

### 1.2 `flutter_adaptive_scaffold` **已 discontinued，且沒有官方替代品**

實測 pub.dev API（`https://pub.dev/api/packages/flutter_adaptive_scaffold`）：

| 欄位 | 值 |
|---|---|
| latest | **0.3.3+1** |
| published | **2025-05-06** |
| `isDiscontinued` | **true** |
| `replacedBy` | **null**（官方未指名替代品） |
| pubspec `repository` | `https://github.com/flutter/packages/tree/main/packages/flutter_adaptive_scaffold`（**該目錄現在 404**，`gh api` 實測 Not Found） |

- pub.dev 頁面逐字：「This project has been discontinued, and will not receive further updates.」未指名替代品，只導向 GitHub issue **flutter/flutter #162965** 供社群討論 fork。
- `#162965`「flutter_adaptive_scaffold planned to be discontinued」（2025-02-10 開，已 closed）目的是協調社群 fork，**沒有任何官方替代或框架層替代計畫**。上層統籌 issue 為 **#162960**「Packages planned to be discontinued」（同樣涵蓋 css_colors、flutter_image、flutter_markdown 等）。
- **即：這個套件不能作為長期方案。**

### 1.3 Material 3 Expressive：官方**尚未實作**，且目前**不開發**

- 統籌 issue **flutter/flutter#168813**「☂️ Bring Material 3 Expressive to Flutter」：本機 `gh api` 實測 state = **open**、created 2025-05-14、updated **2026-08-17**、comments **84** → <https://github.com/flutter/flutter/issues/168813>
- 2025-07-29 更新逐字：「The material and cupertino libraries are being decoupled into standalone packages to accelerate feature development. All new work for Material 3 Expressive will happen in the new packages once established in flutter/packages.」
- 但 issue 正文同時逐字寫：「As of writing, this work is **not planned**。」後續狀態（多方引用）為「Currently, we are **not actively developing** Material 3 Expressive, and we will not be accepting contributions for Expressive features or updates at this time.」
- **Flutter 3.47.0 release notes 完全未提 M3 Expressive**；Material 段只有 VPAT/a11y 工具、阿拉伯數字修正、lint 清理。
- **本機 SDK 的直接證據**：`packages/flutter/lib/src/material/page_transitions_theme.dart:468` 註解逐字寫「Android is using Material 3 Expressive springs that are not currently …」—— framework 自己承認尚未支援 M3E 的動態曲線。
- 已 merge 的相關 PR：`flutter/packages#12093`「[material_ui] Add Material 3 Expressive IconButton」→ 本輪 `gh api` 查得 state = **closed**、`merged: false`（closed_at 2026-09-10）。
- 第三方套件 `material_3_expressive`（pub.dev，**非官方**）提供 44 個 M3E widget。**framework 內沒有官方 flag。**
- **但是**：Flutter 的 `DynamicSchemeVariant` **有** `expressive`（本機 `color_scheme.dart:51` 為 `expressive,`，`:2217` 為 `DynamicSchemeVariant.expressive => SchemeExpressive(...)`）—— 即**取色方案**層面已支援 M3E 的色調，元件與動態層面沒有。

### 1.4 `dynamic_color`

實測 pub.dev API（`https://pub.dev/api/packages/dynamic_color`）：

| 欄位 | 值 |
|---|---|
| latest | **2.1.0** |
| published | **2026-08-20** |
| `isDiscontinued` | false |
| pubspec env | `sdk: >=2.16.0 <4.0.0`, `flutter: >=3.4.0-17.0.pre` |
| 依賴 | `material_color_utilities ^0.13.0`、`material_ui ^1.0.0` |

- pubspec 的 `flutter.plugin.platforms` 明確列出 **android, linux, macos, windows**（Windows 走 `DynamicColorPluginCApi`）→ **Android 12+ 與 Windows、macOS、Linux 皆支援**。
- **FMP 現況（事實）**：`pubspec.yaml` **沒有** `dynamic_color` 依賴；主題走 `ColorScheme.fromSeed`（見 `current-state.md` §1）。

---

## 2. i18n

### 2.1 `slang`

實測 pub.dev API（`https://pub.dev/api/packages/slang`）：latest **4.19.2**，published **2026-09-12**，`isDiscontinued` false，env `sdk: >=3.3.0 <4.0.0`。repo 已遷至 `codeberg.org/Tienisto/slang`；依賴 `intl >=0.18.1 <2.0.0`。

**功能**（context7 取官方 README <https://github.com/slang-i18n/slang/blob/main/slang/README.md>）：

- **Type safety**：逐字「Type-safe i18n solution using JSON, YAML, CSV, or ARB files.」「no typos or missing arguments possible due to compile-time checking.」
- **Plural**：用 Unicode CLDR plural rules，關鍵字 `zero/one/two/few/many/other`，支援 **cardinal 與 ordinal**；設定 `pluralization.auto`（`off` / `cardinal` / `ordinal`）與逐 key 清單。未支援的語言可用 `LocaleSettings.setPluralResolver(...)` 自訂。
- **Linked translations**：`"sentence": "I have @:apples and @:bananas"`，可讓一句話裡有多個 plural 參數（README 範例 `t.sentence(appleCount: 1, bananaCount: 2)`）。
- **參數 / placeholders**：三種插值模式 `dart` / `braces` / `double_braces`；參數預設型別 `Object`；RichText 用 `(rich)` modifier。
- **Lazy loading**：`lazy: true`（**預設**）；逐字「translations for secondary locales are loaded lazily if Deferred loading is supported (Web).」
- **Namespaces**：逐字「You can split the translations into multiple files. Each file represents a namespace.」（`namespaces: true`）；檔名格式 `<namespace>_<locale>.<extension>`，可用目錄分（`i18n/en/widgets/welcomeCard.json`）；根命名空間用 `_default`。取用語法 `t.<namespace>.<path>`。
- **Fallback locale**：`fallback_strategy` ∈ `none`（**預設**）/ `base_locale` / `base_locale_empty_string`；逐字「Missing translations will fall back to base locale.」（**只在 `base_locale` 時**）。`dart run slang analyze` 可找 missing / unused（missing 只在 `fallback_strategy: base_locale` 時才報）。
- **Locale handling**：`locale_handling: true`（預設）；`TranslationProvider` 會監聽裝置 locale 變化。另有 `setLocale` / `setLocaleRaw` / `useDeviceLocale`。
- **其他 config key**（README 配置表）：`translate_var`（預設 `t`）、`enum_name`（`AppLocale`）、`class_name`（`Translations`）、`key_case`（`snake`）、`param_case`（`pascal`）、`maps`、`contexts`（自訂 `GenderContext` 等）、`interfaces`、`obfuscation`、`format`、`autodoc`、`imports`、`generate_enum`、`timestamp`、`statistics`。
- 文件：<https://pub.dev/documentation/slang/latest/>

**FMP 現況（事實，`slang.yaml` 全文）**：`base_locale: zh-CN`、`namespaces: true`、`input_directory: lib/i18n`、`input_file_pattern: .i18n.json`、`output_directory: lib/i18n`、`output_file_name: strings.g.dart`、`lazy: false`（附中文註解說明理由：只出 Android 與 Windows，兩者都不支援 deferred loading）。**未設定** `fallback_strategy`（即預設 `none`）。
規模實測：`lib/i18n/` 下 **38** 個 `*.i18n.json` × 3 locale（`en` / `zh-CN` / `zh-TW`）= **114** 檔；`enum AppLocale` 順序為 `zhCn` → `en` → `zhTw`（`lib/i18n/strings.g.dart:31-34`）。i18n 走 `dart run slang` 獨立 CLI，**不經 build_runner**（`slang_build_runner` 在 `dev_dependencies` 被刻意排除，附理由註解）。

### 2.2 官方 `gen-l10n`（ARB）vs slang

官方 i18n 文件 <https://docs.flutter.dev/ui/accessibility-and-internationalization/internationalization>：

- **產物**：由 `l10n.yaml` 驅動，`flutter gen-l10n`（或 `flutter run` / `pub get` 自動觸發），產生 `AppLocalizations` 類別 + delegate + 自動 `supportedLocales`。逐字：「Alternatively, you can also run `flutter gen-l10n` to generate the same files without running the app.」
- **型別安全**：ARB key 變成有型別的 getter / method；逐字「A placeholder... becomes a positional parameter in the generated method」。
- **Plural / ICU**：完整支援 ICU message syntax，含 `plural`、`select`、`=0/=1/other`；逐字「Only the more general `messageOther` field is required.」`num` placeholder 可帶 `"format": "compact"`；`DateTime` placeholder 用 `DateFormat`（41 種 variation）。
- **官方文檔完全不提 slang 或任何第三方 codegen 套件**；只把「手寫 class」與「`intl_translation` 原始工具」列為 alternative workflow。
- **兩者差異（事實對照）**：官方 gen-l10n 的 plural 走 ICU message 字串；slang 走 JSON 巢狀物件 + CLDR 規則。官方 gen-l10n 需要 ICU literal 的語法知識；slang 不需要。官方工具 shipped with SDK，無第三方依賴。**官方沒有任何文件建議或反對用 slang。**

### 2.3 `intl` 的 `NumberFormat.compact` —— 實測輸出

方法：在本機以 FMP 自己解析出的 **intl 0.20.3**（`C:\Users\Roxy\AppData\Local\Pub\Cache\hosted\pub.dev\intl-0.20.3`）+ Dart 3.13.1 實際執行（`dart --packages=".dart_tool/package_config.json"`）。

| locale | 1 | 999 | 1000 | 1500 | 46000 | **46000000** | 1234567890 |
|---|---|---|---|---|---|---|---|
| `en` | 1 | 999 | **1K** | **1.5K** | 46K | **46M** | **1.23B** |
| `zh` | 1 | 999 | 1000 | 1500 | **4.6万** | **4600万** | **12.3亿** |
| `zh_TW` | 1 | 999 | 1000 | 1500 | **4.6萬** | **4600萬** | **12.3億** |
| `zh_CN` | 1 | 999 | 1000 | 1500 | **4.6万** | **4600万** | **12.3亿** |
| `ja` | 1 | 999 | 1000 | 1500 | **4.6万** | **4600万** | **12.3億** |

**三個要點**：

1. **中文在 10000 以下不壓縮**：`1000 → "1000"`、`1500 → "1500"`（不是 `1K`）。與 FMP 自家 `formatCount` 相同（FMP 也是 `<10000` 直接回原數字）。
2. **整數時不加小數點**：`46000000 → "46M"`（不是 `46.0M`）；`4600萬`（不是 `4600.0萬`）。
3. **有效位數是 3 位**：`1234567890 → "1.23B"`。

**與 FMP 自家實作的差異**（`lib/core/utils/number_format_utils.dart`，38 行全文已讀）：

| | FMP `formatCount` | `intl` `NumberFormat.compact` |
|---|---|---|
| en 1e9 帶 | `${(c/1e9).toStringAsFixed(1)}B` → `1.2B` | `1.23B` |
| en 整數 | 一律一位小數 → **`46.0M`** | 去尾 → **`46M`** |
| zh 1e8 帶 | `${(c/1e8).toStringAsFixed(1)}亿` → `4.6亿` | `12.3亿`（3 位有效） |
| zh 整數 | 一律一位小數 → **`4600.0萬`** | 去尾 → **`4600萬`** |
| 千分位 | 無 | 無（compact 不帶千分位） |
| 低於 1e3 / 1e4 門檻 | 直接回原數字 | 同 |

即這兩個 audit 抓到的症狀（`46.0M`、`4600.0萬`）正是「自家實作強制一位小數」造成的，`intl` 的 `compact` 不會有這個尾巴。

**子代理補充（僅一項，需注意）**：`zh_Hant`（**只有 script、無 region**）實測落回**簡體「万」**，`zh_Hant_TW` 才是繁體「萬」。成因**未查證**（推測 locale resolution 掉到 `zh`）。FMP 走 `AppLocale.zhTw`（`languageCode: 'zh', countryCode: 'TW'`），不經這條路徑。
**CLDR 來源**（子代理）：`cldr-json/cldr-numbers-full/main/<loc>/numbers.json` 的 `decimalFormats-numberSystem-latn.short`；zh / zh-Hant 的 `10000000-count-other` = `"0000萬"`、`100000000-count-other` = `"0億"`；en 的 `1000000-count-other` = `"0M"`。→ 46,000,000 落在 10^7 帶，除以 10^4 得 4600。→ <https://raw.githubusercontent.com/unicode-org/cldr-json/main/cldr-json/cldr-numbers-full/main/zh/numbers.json>

---

## 3. 無障礙與鍵盤

### 3.1 `Shortcuts` / `Actions` / `Intent` 三者角色

- **`Intent`**：逐字「An abstract class representing a particular configuration of an Action.」是 `Shortcuts.shortcuts` map 的 value，由 `ActionDispatcher` 查表並 invoke。`@immutable`。→ <https://api.flutter.dev/flutter/widgets/Intent-class.html>
- **`Shortcuts`**：逐字「A widget that creates key bindings to specific actions for its descendants.」建立 `ShortcutManager`，把按鍵組合對應到 `Intent`；官方強調它「**separates key bindings and their implementations**」。→ <https://api.flutter.dev/flutter/widgets/Shortcuts-class.html>
- **`Actions`**：逐字「A widget that maps Intents to Actions to be used by its descendants when invoking an Action.」「Actions are typically invoked using `Shortcuts`。」靜態 `Actions.invoke(context, intent)`。→ <https://api.flutter.dev/flutter/widgets/Actions-class.html>

### 3.2 `FocusTraversalGroup`

- 逐字：「grouping them into a separate traversal group」；「Within the group, it will use the given policy to order the elements」；「The group itself will be ordered using the parent group's policy」；預設「traverses in reading order using `ReadingOrderTraversalPolicy`」。`policy` 逐字：「The policy used to move the focus from one focus node to another when traversing them using a keyboard」。→ <https://api.flutter.dev/flutter/widgets/FocusTraversalGroup-class.html>
- `FocusScope` vs `FocusTraversalGroup` 的差別（逐字，<https://api.flutter.dev/flutter/widgets/FocusScope-class.html>）：「If you just want to group widgets together in a group so that they are traversed in a particular order, **but the focus can still leave the group**, use a `FocusTraversalGroup`.」
- **FMP 現況（事實）**：`current-state.md` §5 記錄了 FMP 目前的 `Shortcuts`/`Actions`/`FocusTraversalGroup` 使用位置與全域熱鍵清單。
- 社群分組實例見 `prior-art.md` §4.5（Fladder、flutter-adaptive-demo、Arna）。

### 3.3 `SemanticsRole`（**是新 API**）

- 定義位置：**`dart:ui`（engine）**，本機路徑 `bin/cache/pkg/sky_engine/lib/ui/semantics.dart:361`（**不是** `packages/flutter`）。dartdoc 首段逐字：「An enum to describe the role for a semantics node.」「The roles are translated into native accessibility roles in each platform.」
- **加入版本：Flutter 3.29.0**。證據（子代理）：3.29.0 release notes 有「add semantics role and tab by @chunhtai in **161260**」（PR #161260）；framework `semantics.dart` 對 `SemanticsRole` 的引用數在 3.27.0 = 0、3.29.0 = 17、3.32.0 = 68。
- **本機實測 3.47.1 的完整 enum 值（33 個，`semantics.dart:361-556`）**：

  `none, tab, tabBar, tabPanel, dialog, alertDialog, table, cell, row, columnHeader, dragHandle, spinButton, comboBox, menuBar, menu, menuItem, menuItemCheckbox, menuItemRadio, list, listItem, form, tooltip, loadingSpinner, progressBar, hotKey, radioGroup, status, alert, complementary, contentInfo, main, navigation, region`

  其中與播放器版面直接相關的：`main`、`navigation`、`region`、`complementary`、`list` / `listItem`、`hotKey`、`status`、`alert`、`tooltip`、`progressBar`、`loadingSpinner`。
- 3.47.0 相關 PR（子代理）：「Adds semantics role check to `isSemantics` and `matchesSemantics`」(#188825)、「Keep scrollable semantics role stable」(#187963)、「Map some framework semantics roles to android classes」(#185217)。
- → <https://api.flutter.dev/flutter/dart-ui/SemanticsRole.html>

### 3.4 widget test 的 `meetsGuideline`

- 本機 `packages/flutter_test/lib/src/accessibility.dart` 與 `matchers.dart:1300` 實測：`AsyncMatcher meetsGuideline(AccessibilityGuideline guideline)`。
- **可用 guideline 常數**（本機 `accessibility.dart` 實測行號）：
  - `androidTapTargetGuideline`（`:785`）
  - `iOSTapTargetGuideline`（`:800`）
  - `textContrastGuideline`（`:818`）
  - `labeledTapTargetGuideline`（`:825`）
- **限制**：需先 `tester.ensureSemantics()` 且結果要 `await`（官方範例逐字：`await expectLater(tester, meetsGuideline(textContrastGuideline));`）。→ <https://api.flutter.dev/flutter/flutter_test/meetsGuideline.html>
- **FMP 現況（事實，取自 `current-state.md` §7）**：只有 2 個測試檔用到 `meetsGuideline`（`comment_pager_test.dart:33-34`、`mini_player_accessibility_test.dart:117-118`），用的是 `androidTapTargetGuideline` 與 `labeledTapTargetGuideline`；**`textContrastGuideline` 全 repo 零使用**。

### 3.5 Windows 焦點指示（focus highlight）已知 issue

全部本輪以 `gh api` 實測 state：

- **#120425「Material 3 focus rings & keyboard behavior on web/desktop」— OPEN**，P3，labels `a: accessibility` / `a: desktop` / `c: new feature` / `p: material_ui` / `team-design`。逐字：「placeholder issue for a project to draw outlined indicators ("focus rings") around focused M3 elements」，理由「improve a11y and ease of use」。**即 M3 元件目前缺 focus ring。** → <https://github.com/flutter/flutter/issues/120425>
- **#172438「[Windows][Accessibility] Text can't be focused when navigating using a keyboard」— OPEN**，P2，`platform-windows`。→ <https://github.com/flutter/flutter/issues/172438>
- **#151457「Windows desktop app completely losing keyboard focus」— OPEN**。→ <https://github.com/flutter/flutter/issues/151457>
- **#119531「Allow `MenuBar` menus to be focused via keyboard without accelerators」— OPEN**，`f: focus`，P2。
- **#103811「[Desktop-Windows] Chinese characters are incorrectly rendered in flutter 3」— OPEN**，P2，`c: regression` / `a: typography` / `a: internationalization` / `platform-windows`：回報 3.0.0 Windows 桌面渲染錯誤、2.10.5 正常、web 正常。
- 官方焦點文件提到切換機制：`FocusManager.instance.highlightMode` 與 `highlightStrategy`，用於 touch 與 mouse/keyboard 兩種模式間切換焦點高亮（逐字：「the focus highlight is usually hidden」於 touch 時）→ <https://docs.flutter.dev/ui/interactivity/focus>
- **查不到**專門講「深色主題下 `focusColor` 不明顯」的 open issue（搜尋未命中 `focusColor` 相關標題）。→ **查不到**

---

## 4. 視覺回歸（golden test）

### 4.1 FMP 現況（事實）

FMP `pubspec.yaml` / `pubspec.lock` **沒有** `alchemist`、`golden_toolkit`、`golden_test` 任一依賴；repo 內**零個 golden 測試**（見 `current-state.md` §7）。

### 4.2 官方 `matchesGoldenFile` 的跨平台字型問題

- 逐字：「The term **golden file** refers to a master image that is considered the true rendering of a given widget, state, application...」
- 更新方式逐字：「The master golden image files that are tested against can be created or updated by running `flutter test --update-goldens`」。
- **字型警示（逐字）**：「Custom fonts may render differently across different platforms, or between different versions of Flutter.」「a golden file generated on **Windows** with fonts will likely differ from the one produced by another operating system.」「Even on the same platform, if the generated golden is tested with a different Flutter version, the test may fail and require an updated image.」
- **預設字型是 Ahem（方塊）**，逐字：「the Flutter framework uses a font called '**Ahem**' which shows squares instead of characters」；要載自訂字型可用 `FontLoader`，或全域放進 `flutter_test_config.dart`。
- → <https://api.flutter.dev/flutter/flutter_test/matchesGoldenFile.html>
- **`flutter test --platform` 不是 3.47.1 的旗標**（子代理在本機專案目錄實跑 `flutter test --help`）：有 **`--update-goldens`**，但**沒有** `--platform`（`--platform` 是 `dart test` 的旗標：vm / chrome / node）。官方 CLI 參考頁亦未記載 → <https://docs.flutter.dev/reference/flutter-cli>

### 4.3 `alchemist`

實測 pub.dev API（`https://pub.dev/api/packages/alchemist`）：

| 欄位 | 值 |
|---|---|
| latest | **0.14.0** |
| published | **2026-03-13** |
| `isDiscontinued` | false |
| pubspec env | `sdk: >=3.8.0 <4.0.0`, `flutter: >=3.32.0` |
| repo | `https://github.com/Betterment/alchemist` |

- **解決什麼**：跨平台字型渲染差異導致 golden 在 CI 失敗。做法是把 CI golden 的文字換成有色方塊（逐字：「the text blocks are replaced with colored squares」），且「always run using the **Ahem** font family」，使輸出與平台無關。
- **API**：宣告式 `goldenTest`，搭配 `GoldenTestGroup`（表格）與 `GoldenTestScenario`（name + child）；生成用 `flutter test --update-goldens`；測試帶 `"golden"` tag 可用 `--tags golden` 過濾。
- **設定**：`AlchemistConfig`（`forceUpdateGoldenFiles`、themes、`PlatformGoldensConfig` / `CiGoldensConfig`，含 `obscureText`、`renderShadows`、`diffThreshold`），常放在 `flutter_test_config.dart`；支援 `merge` / `copyWith`。
- **目錄慣例**：CI golden 進 `goldens/ci/`，可讀的平台 golden 進 `goldens/<platform>`（macos / linux / windows）。
- → <https://pub.dev/packages/alchemist>

### 4.4 其他工具

- **`golden_toolkit` — 已 discontinued**：latest **0.15.0**，published **2023-02-21**，pub.dev `isDiscontinued: true`；repo eBay/flutter_glove_box。alchemist 即受它啟發。
- **`patrol`**：latest **4.10.0**；是「multiplatform E2E UI testing framework... overcoming the limitations of `integration_test`」，處理 native 互動（**非** golden 工具）。
- 另有第三方 `golden_test`（pub.dev）與商業的 Widgetbook Cloud（雲端跑 golden 以消平台差異）。→ **本輪未逐一核對這兩個的版本與成熟度。**

---

## 5. 字型與 CJK fallback

### 5.1 `fontFamilyFallback` 的官方語意

本機 `packages/flutter/lib/src/painting/text_style.dart` 實測：

- `:394-408` dartdoc：fallback 是 ordered list；`:403` 逐字「`fontFamilyFallback` in order of **first to last**」；`:397` 逐字「The fonts in `fontFamilyFallback` will be used **only if the requested glyph is** [not found in the higher priority families]」。
- **關鍵語意（本機 `:566-567`、`:588`）**：當 `fontFamily` 為 null 或未提供時，**`fontFamilyFallback` 的第一個值就成為主要字型**（逐字：「When `fontFamily` is null or not provided, the first value in `fontFamilyFallback` acts as the preferred/first font」）。
- `:585-594`：若所有 font family 都用盡仍無 match，就畫方塊；`:594` 逐字「in `fontFamilyFallback` will be searched in order until it is found」。
- → <https://api.flutter.dev/flutter/painting/TextStyle/fontFamilyFallback.html>（dartdoc 逐字：「ordered list of font families to fall back on when a glyph cannot be found in a higher priority font family」）

### 5.2 Flutter 各平台 Typography 的預設字型（本機 SDK 實測）

- `packages/flutter/lib/src/material/theme_data.dart:399`：`platform ??= defaultTargetPlatform;`
- `:505-506`：`typography ??= useMaterial3 ? Typography.material2021(platform: platform, colorScheme: colorScheme) : ...`
- `packages/flutter/lib/src/material/typography.dart:219-224`（`material2021` 的平台分派）：
  - `TargetPlatform.iOS` → `blackCupertino` / `whiteCupertino`
  - `TargetPlatform.fuchsia`、`android` → `blackMountainView` / `whiteMountainView`
  - **`TargetPlatform.windows` → `blackRedmond` / `whiteRedmond`**
  - `TargetPlatform.linux` → `blackHelsinki` / `whiteHelsinki`
- **`blackRedmond` 的 fontFamily 實測（`:568` 起）**：**`'Segoe UI'`**（15 個 style 全部）。
- `Typography-class` 官方頁（子代理）列：Android = **Roboto**；iOS = San Francisco；macOS = San Francisco；**Windows = Segoe UI**；Linux = Roboto，fallback「DejaVu Sans, Liberation Sans and Arial」。→ <https://api.flutter.dev/flutter/material/Typography-class.html>

**推論（本檔最關鍵的一條，標明為推測）**：FMP 的 `ThemeData(useMaterial3: true, ...)` **沒有**傳 `platform:`，因此 Windows 上文字預設 family 是 **Segoe UI**、Android 上是 **Roboto**。**兩者都沒有 CJK 字符**。所以 FMP 的 CJK 顯示完全依賴它自己加的 `fontFamilyFallback` 與 engine 的系統 fallback。

### 5.3 FMP 現況（事實，`lib/ui/theme/app_theme.dart`）

- `:203-205`：`return base.copyWith(textTheme: base.textTheme.apply(fontFamilyFallback: fallback));` —— **只設 `fontFamilyFallback`，不覆寫 `fontFamily`**（除了使用者自選字型時，見下）。
- `:96-105` `_buildFontFallback`：
  - Windows：使用者選了字型 → `[fontFamily, 'Microsoft YaHei UI', 'Microsoft YaHei']`；未選 → `['Microsoft YaHei UI', 'Microsoft YaHei']`
  - 其他（Android）→ `['Noto Sans SC']`
- `:70-93` `availableFonts`：Windows 8 個選項（系統預設、Microsoft YaHei UI、SimSun、SimHei、KaiTi、FangSong、Yu Gothic UI、Meiryo）；Android 7 個（系統預設、sans-serif、serif、sans-serif-medium、sans-serif-light、sans-serif-condensed、monospace）。
- `:129-130`：使用者選了字型時 `fontFamily: (fontFamily != null && fontFamily.isNotEmpty) ? fontFamily : ...` —— 即**只有自選時才覆寫 `fontFamily`**。
- **`pubspec.yaml` 沒有 `fonts:` 區段**（實測），即 FMP **不內嵌任何字型檔**。
- **兩個值得注意的事實**：
  1. **繁體中文沒有列入**：Windows fallback 清單是 `Microsoft YaHei UI`（**簡體**字型），**沒有 `Microsoft JhengHei UI`**（Windows 的繁中字型）。`availableFonts` 的 Windows 清單同樣沒有繁中字型。FMP 的 `base_locale` 是 `zh-CN`，但 UI 支援 `zh-TW`（`AppLocale.zhTw`）。→ 繁中字形實際由哪個字型提供，**本輪查不到官方或程式碼層的說明**；`Microsoft YaHei UI` 內含部分繁中字形，但這點**未查證**。
  2. **Android 清單有日文字型**：`Yu Gothic UI` / `Meiryo` 在 Windows 清單裡，但 Windows 8 個選項中 **沒有** 韓文字型。

### 5.4 各平台內建 CJK 字型名稱（子代理查證）

- **Windows**（Microsoft 官方 Windows 11 font list → <https://learn.microsoft.com/en-us/typography/fonts/windows_11_font_list>）：
  - 簡體：**Microsoft YaHei / Microsoft YaHei UI**（`Msyh.ttc`）、SimSun / NSimSun（`Simsun.ttc`）、SimHei、DengXian、FangSong、KaiTi
  - 繁體：**Microsoft JhengHei / Microsoft JhengHei UI**（`Msjh.ttc`）、MingLiU / PMingLiU、DFKai-SB
  - 日文：Yu Gothic / Yu Gothic UI（`YuGoth*.ttc`）、Meiryo / Meiryo UI、MS Gothic、MS Mincho
  - 韓文：Malgun Gothic（`Malgun.ttf`）、Batang、Gulim、Dotum
- **Android**：`NotoSansCJK-Regular.ttc`（`/system/fonts`），於 `fonts.xml` 以 `index` 區分語境：`zh-Hans` index 2、`zh-Hant` index 3、`ja` index 0、`ko` index 1。（子代理標記：index 值來自社群貼出的 `fonts.xml`，**未逐字對上 AOSP 該檔**——googlesource 回 503；AOSP 官方頁只確認檔案位置與機制，未列 index。）→ <https://source.android.com/docs/core/fonts/custom-font-fallback>
- **Linux**：走 fontconfig 比對；社群證據顯示常見為 Noto Sans CJK / Source Han Sans。Ubuntu 自 2016（language-selector 0.154）起，簡中預設由 Droid Sans Fallback 改為 **Noto Sans CJK**（Launchpad bug #1468027）。
- **`fontFamilyFallback` 未命中時的落地機制**：官方 dartdoc 只說「the default platform font family will be used instead」。**Flutter 官方沒有文件明確描述 Windows/Linux 上「未宣告 fallback 的 CJK 字元會落到哪個系統字型」的機制** → **查不到**。相關 open issue 為 #103811（見 §3.5）。

---

## 本檔最不確定的 5 件事

1. **`material_ui` / `cupertino_ui` 的遷移時間表與對 FMP 的強制性**：官方 README 與部落格都說「decoupled」，3.47.1 SDK 仍內建 `package:flutter/material.dart`，但**沒有任何官方文件說明舊路徑何時移除**。FMP 已在依賴樹裡拿到 `material_ui 1.1.1`（transitive），卻還沒直接依賴它。
2. **`SemanticsRole` 的加入版本（3.29.0）**：engine 在 3.27 之前是獨立 repo，`raw.githubusercontent.com/flutter/flutter/<tag>/engine/...` 在 3.27.0 是 404，所以無法逐版比對 `dart:ui` 檔；結論由 framework 引用數（3.27=0 / 3.29=17）加 3.29 release notes 的 PR #161260 交叉推得，**非逐版確認 enum 定義**。enum 值本身是本機 3.47.1 實測，無疑。
3. **FMP 的繁體中文字形實際由哪個字型提供**：`_buildFontFallback` 的 Windows 清單只有簡體 `Microsoft YaHei UI` / `Microsoft YaHei`，沒有 `Microsoft JhengHei UI`；但 `zh-TW` 是支援的 locale。`Microsoft YaHei UI` 是否足以覆蓋繁中字形、以及未覆蓋時 engine 落到哪裡，**兩者都查不到**。這是本檔我認為最可能出錯的一條。
4. **`zh_Hant`（無 region）落回簡體「万」的成因**：實測輸出確定（intl 0.20.3），但成因未查證（推測 locale resolution 掉到 `zh`）。FMP 走 `AppLocale.zhTw`（有 countryCode），不經這條路徑，所以**這條不影響 FMP**，但若日後有人用 script-only locale 就會踩到。
5. **Windows 焦點指示的實際嚴重度**：#120425（M3 缺 focus ring）是 placeholder issue、P3；#172438（鍵盤無法聚焦文字）與 #151457（完全失去鍵盤焦點）都是 OPEN 但**我沒有實際重現**。官方文件只描述 `highlightMode` / `highlightStrategy` 機制，未說 Windows 上有已知破損。FMP 是否會踩到，**需在裝置上實測**。
