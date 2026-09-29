# Flutter 怎麼選 CJK 字形（Android、Windows）

查證日期 2026-09-29，對照 Flutter 3.47.5（engine `af7e796e16`）與 flutter/flutter、google/skia 的 main。
這個環境沒有 context7／tavily，來源都是直接抓官方原始碼與文件。

## 結論

| 平台 | `fontFamilyFallback` 寫系統字型名 | 依 locale 選字形 | 本 PR 的做法 |
|---|---|---|---|
| Windows | 有效（DirectWrite 對得到系統字型名） | 只影響沒被指名字型涵蓋的字元 | 照 ADR 0024 指名正黑體／雅黑（`fonts_windows.dart`） |
| Android | **無效**：`Noto Sans TC`／`SC` 在系統裡不是有名稱的 family | 有效：模擬器實測 `zh-Hant` 的 locale 拿到繁中字形（見「實機結果」） | 不指名（`FontFallback.none`，`fonts_android.dart`）；ADR 0024 補更正 |

## 引擎的路徑（原始碼）

1. 文字的 locale：`RichText.createRenderObject` 傳 `locale ?? Localizations.maybeLocaleOf(context)` 給
   `RenderParagraph`（`packages/flutter/lib/src/widgets/basic.dart`）。`TextStyle.locale` 的 dartdoc：
   「The locale used to select region-specific glyphs … Typically … defined by … `Localizations.localeOf(context)`」
   （`packages/flutter/lib/src/painting/text_style.dart`）。
2. dart:ui 把 locale 編成字串：`_encodeLocale(Locale? locale) => locale?.toString() ?? ''`
   （`engine/src/flutter/lib/ui/text.dart`），`Locale.toString()` 是 `_rawToString('_')`，也就是
   **底線**格式 `zh_Hant_TW`（`lib/ui/platform_dispatcher.dart`；`toLanguageTag()` 才是 `-`）。
3. engine 原樣傳給 SkParagraph：`paragraph_builder.cc` 的 `style.locale = locale`，
   `paragraph_builder_skia.cc` 的 `setLocale(SkString(txt.locale.c_str()))`。
4. SkParagraph 缺字時 `FontCollection::defaultFallback(unicode, families, style, locale)` 呼叫
   `matchFamilyStyleCharacter(familyName, style, {locale}, …)`（`skia/modules/skparagraph/src/FontCollection.cpp`）。
5. 各平台的字型管理器（`engine/src/flutter/txt/src/txt/platform_*.cc`）：
   - Android：`SkFontMgr_New_Android`，預設 family `sans-serif`；
   - Windows：`SkFontMgr_New_DirectWrite`，預設 family `Segoe UI`、`Arial`。

## Android

- 系統字型設定 `data/fonts/fonts.xml`（AOSP，android14-release 與 main 都一樣）：Noto Sans CJK 是
  `<family lang="zh-Hans">`、`<family lang="zh-Hant,zh-Bopo">`、`<family lang="ja">`、`<family lang="ko">`，
  **沒有 `name`**，指向同一個 `NotoSansCJK-Regular.ttc` 的不同 index；`zh-Hans` 排在 `zh-Hant` 前。
  來源：https://github.com/aosp-mirror/platform_frameworks_base/blob/android14-release/data/fonts/fonts.xml
- Skia `src/ports/SkFontMgr_android.cpp`：
  - 沒有名稱的 fallback family 只會有自動產生的名稱 `"%.2x##fallback"`（`addFamily`）；
  - `onMatchFamily(name)` 只比對 `fNameToFamilyMap`／`fFallbackNameToFamilyMap` 的名稱。
  - 所以 `fontFamilyFallback: ['Noto Sans TC']` 找不到字型，會被略過，**寫了等於沒寫**。
- 同一檔的 `onMatchFamilyStyleCharacter`（下方「原先的推論」的依據，實機結果與它不符）：以 locale 選 fallback family 時，條件是字型的 `lang`
  `startsWith(要求的 tag)`；找不到就 `SkLanguage::getParent()`，以最右邊的 **`-`** 截掉一段再試
  （`SkFontMgr_android_parser.cpp`）；全部落空才不看語言，依 fonts.xml 的順序取第一個有該字的
  family，也就是 `zh-Hans`。
- 官方文件對中文 locale 的建議：`supportedLocales` 寫 `Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant', countryCode: 'TW')`
  等帶 script 的形式（https://docs.flutter.dev/ui/internationalization §「Chinese」）。

### 實機結果（2026-09-29，主對話）：推論不成立

Android 模擬器（Medium_Phone）以臨時探測頁顯示「骨直這說」，`Locale` 依序為 `zh-Hant-TW`、`zh-Hant-HK`、`zh_TW`、`zh-Hans-CN`、`ja_JP`：前三列是繁中字形（「骨」下半為台灣寫法），`zh-Hans-CN` 是簡中字形，`ja_JP` 是日文字形。locale 能選到繁中字形，下面這段原始碼推論與實際不符，保留作紀錄；PR 12 只要讓文字帶正確的 locale（例如 `MaterialApp.locale`）。

### 原先的推論（不成立）

把 2–4 與上一段合起來：Flutter 送進 Skia 的是 `zh_Hant_TW`、`zh_Hant`、`zh_TW`（底線），
`getParent` 找不到 `-` 就直接變空，永遠比對不到 fonts.xml 的 `zh-Hant`；只有純語言碼
（`zh`、`ja`）比對得到，而 `zh` 會先比對到 `zh-Hans`。照原始碼推，**Android 上不論 locale 怎麼設，
漢字都拿到簡中字形**，繁中介面也一樣。

- 這是讀原始碼推出來的，還沒實機驗證。驗法：在 Android 模擬器用 `Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant', countryCode: 'TW')`
  顯示「骨、直、這、說」，跟系統 TextView（例如設定頁）的繁中字形比。
- 若屬實，靠官方 API 做不到；可能的對策（PR 12 由擁有者決定）：
  - 接受 Android 用簡中字形；
  - 內建 Noto Sans TC 子集或全字型（ADR 0024「CJK 字型不內建」要改）；
  - 向 Flutter 回報 locale 應以 BCP 47（`toLanguageTag()`）傳給 Skia。
- 沒找到直接回報這件事的 issue（搜尋 `zh_Hant`、`Traditional Chinese glyph Android`、`Locale toString underscore`）。
  相關的舊 issue：#12576（2017，Android 日文字形，當時的修法是「把 locale 傳進文字渲染」）、
  #16870（2018，Android 永遠是 CN 字形，併入 #12576）、#41138（CJK 選錯字形的追蹤 issue，2019 關閉）。
  當時的引擎用 minikin，不是現在的 SkParagraph。

## Windows

- `SkFontMgr_New_DirectWrite` 以 DirectWrite 的系統字型集合解析名稱，`Microsoft JhengHei UI`、
  `Microsoft YaHei UI` 這類系統 family 名稱對得到。
- flutter/flutter#103811（Windows 中文顯示異常，open）：預設字型 `Segoe UI` 沒有中文，引擎自己做的
  fallback 會混到 `Yu Gothic UI` 與 `Microsoft JhengHei UI`，字重也不一致；jason-simmons 的分析在
  https://github.com/flutter/flutter/issues/103811 （2022-06-01）。社群的解法是
  `TextStyle(fontFamilyFallback: ['Microsoft YaHei'])`
  （https://github.com/flutter/flutter/issues/103811#issuecomment-2708024718 ），舊專案
  `lib/ui/theme/app_theme.dart` 也用 `Microsoft YaHei UI`，Windows 上實際有效。
- 所以 Windows 照 ADR 0024 指名。英文介面繁中在前：出現漢字時先用正黑體。

## 對 ADR 0024 的更正

§決定 2 的「其他平台 `Noto Sans TC`／`Noto Sans SC`」在 Android 無效，改為不指名、交給 locale。
Linux／macOS／iOS 在各自的平台任務再查（Linux 的 fontconfig 通常認得 `Noto Sans CJK TC` 這類名稱，
但那時再驗）。
