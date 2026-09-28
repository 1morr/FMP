# current-state.md — UI／UX 現況（補 `docs/audit/ui.md` 未載者）

> 查證日 2026-09-28。查證方式：先讀 `docs/audit/ui.md` 全文（審計日 2026-09-26，HEAD `6d78fe23`），
> 本檔**只寫它沒有的事實**；`ui.md` 已完整記載者以一行指回，不重複。
> 證據全部來自靜態讀源碼（`檔案:行號`，branch `docs/audit`）；**未執行 App、未用 VM Service、未看截圖**。
> 工具版本：Flutter 3.47.1 stable、Dart 3.13.1（`flutter --version`）。
> 標「推測」者為未實測的程式碼推論。

---

## 1. 主題來源（`lib/ui/theme/`）

`lib/ui/theme/` 只有兩個檔：`app_theme.dart`（223 行）、`theme_preset_colors.dart`（45 行）。

**色彩是 seed，不是 dynamic color。** `dynamic_color` 既不在 `pubspec.yaml` 也不在 `pubspec.lock`；
`lib/` 內只有兩處 `ColorScheme.fromSeed`（`lib/ui/theme/app_theme.dart:28`、`lib/ui/startup_failure_app.dart:37`）。
Material You 取色未實作，`lib/` 內也沒有 `DynamicColorBuilder`。

- seed 色預設 `Color(0xFF6750A4)`（`theme_preset_colors.dart:15`），另有 9 組 preset（`:17-31`）。
- 若使用者選的是 preset 色，`colorScheme.copyWith` 只覆寫 5 個 role：`primary`、`onPrimary`、
  `primaryContainer`、`onPrimaryContainer`、`surfaceTint`（`app_theme.dart:44-50`）；其餘 role 全由
  `ColorScheme.fromSeed` 決定。`primaryContainer` 用 `Color.alphaBlend`（light 0.18 / dark 0.32，
  `:53-60`），`onPrimary` / `onPrimaryContainer` 用 luminance 比對挑黑或白（`:62-67`）。
  未選色（`primaryColor == null`）時直接用 `fromSeed` 的結果（`:33-35`）。
- 深／淺色只差一個 `Brightness`；`lightTheme` / `darkTheme`（`:209-222`）都走同一個 `_theme`（`:113-206`），
  `useMaterial3: true`（`:126`）。`themeMode` 有 system / light / dark 三態（`lib/providers/settings/theme_provider.dart:17`、
  `:104-107` 的循環切換），在 `lib/app.dart:151` 傳進 `MaterialApp`。
- 只有 8 個 sub-theme：`appBarTheme`、`cardTheme`、`listTileTheme`、`navigationBarTheme`、
  `navigationRailTheme`、`navigationDrawerTheme`、`inputDecorationTheme`、`sliderTheme`
  （`app_theme.dart:134-200`）。檔內註解（`:107-112`）明說八個 sub-theme 全部只讀 `colorScheme` 與 `AppRadius`、
  沒有一處看亮度。
- `theme_preset_colors.dart` 的 `storesAsDefault` 只用在 `themePresetColorFor`：`color == null` 時回傳預設項
  （`:33-45`）。

### 字型與 CJK fallback

- `fontFamily` 來自使用者設定，未設時為 `null`（`app_theme.dart:129-131`）。
  `textTheme` **只套 `fontFamilyFallback`，沒有自訂字級**（`:203-205`）。
- fallback 由 `_buildFontFallback` 產生（`:96-105`），只有兩個分支：
  - Windows：使用者選了具體字型時 `[選的字型, 'Microsoft YaHei UI', 'Microsoft YaHei']`（`:99-101`）；
    否則 `['Microsoft YaHei UI', 'Microsoft YaHei']`（`:102`）。
  - **其餘所有平台**（含 Android、Linux、macOS）：`['Noto Sans SC']`（`:104`）。
- 這是硬編碼在 `lib/` 的清單，沒有平台條件以外的 fallback 鏈；
  `app_theme.dart:1` 只 import `dart:io` 的 `Platform`，`Platform.isAndroid` / `isLinux` 沒有被檢查過。
- 可選字型清單（`:70-93`）：Windows 8 項（系統預設 + Microsoft YaHei UI / SimSun / SimHei / KaiTi /
  FangSong / Yu Gothic UI / Meiryo）；Android 7 項（系統預設 + `sans-serif` / `serif` /
  `sans-serif-medium` / `sans-serif-light` / `sans-serif-condensed` / `monospace`）。

---

## 2. 播放頁版面結構

兩個全螢幕播放頁：`PlayerPage`（`lib/ui/pages/player/player_page.dart`，1220 行）與
`RadioPlayerPage`（`lib/ui/pages/radio/radio_player_page.dart`）。相關元件檔：

| 檔案 | 內容 |
|------|------|
| `lib/ui/pages/player/player_page.dart` | `PlayerPage` + `PlayerLayoutMode` + `resolvePlayerLayout` + `PlayerShortSplitContent` + `_DetailContent` 等私有類別 |
| `lib/ui/widgets/layout/immersive_player_scaffold.dart` | 共用沉浸式外殼（背景 Stack + 透明 AppBar + overlay alpha 常數） |
| `lib/ui/widgets/player/blurred_cover_backdrop.dart` | `TrackBlurredBackdrop` / `RadioBlurredBackdrop` / `BlurredCoverBackdrop` |
| `lib/ui/widgets/player/cover_art_container.dart` | 封面容器 |
| `lib/ui/widgets/player/player_play_pause_button.dart` | 大播放鍵（`ui.md` §5.2 的無障礙問題就在這） |
| `lib/ui/widgets/player/compact_volume_control.dart` | 播放頁頂列的音量（含靜音） |
| `lib/ui/widgets/player/fmp_audio_device_selector.dart` | 音訊輸出裝置選擇器（播放頁與迷你播放器共用） |
| `lib/ui/widgets/player/audio_stream_info_section.dart` | 詳情面板底部的音訊串流資訊 |
| `lib/ui/widgets/lyrics/lyrics_display.dart:23` | `LyricsDisplay`（`_buildLyricsPanel` 用的歌詞欄）；同目錄另有 `lyrics_offset_bar.dart`、`lyrics_styled_text.dart`、`lyrics_style_dialog.dart`。獨立浮動視窗在 `lib/ui/windows/lyrics_window.dart`（`ui.md` §1.1） |

兩者共用外殼 `ImmersivePlayerScaffold`（`lib/ui/widgets/layout/immersive_player_scaffold.dart:17`），
它的 dartdoc（`:9-15`）說明：背景由全頁 `Stack` 統一繪製、AppBar 透明且置於同一 Stack、不用 `Scaffold.appBar`。

### 版面決策

`enum PlayerLayoutMode { narrow, wideSingle, wideSplit, shortSplit }`（`player_page.dart:44-59`），
由純函式 `resolvePlayerLayout(Size size, {required bool hasLyrics})` 決定（`:74-83`）：

| 條件 | 結果 |
|------|------|
| 寬 `atLeast(WindowClass.expanded)`（≥ 840dp）**且** 高 ≥ `AppLayout.playerWideMinHeight`（520dp），有歌詞 | `wideSplit` |
| 同上，無歌詞 | `wideSingle` |
| 高 < 520dp **且** 寬 > 高 | `shortSplit` |
| 其餘 | `narrow` |

`WindowClass.of(size.width).atLeast(...)` 在 `:77`。`hasLyrics` 來自 `lyricsPaneHasContentProvider`（`:162`）。

> **未記載的來源**：`player_page.dart:65` 與 `app_layout.dart:61` 的註解引用「**六個對照專案**」與 Auxio 的
> `layout-h520dp` / `layout-land`，但 repo 內沒有任何文件列出那六個專案是誰
> （`grep -riE "auxio|namida|harmonoid|spotube|finamp|feishin|cider"` 全 repo 只命中：
> `player_page.dart:65`、`app_layout.dart:61`、`.trellis/tasks/09-26-fmp-rewrite/prd.md:105-106` 的競品清單、
> 以及 `09-27-design-background-tasks` 的背景任務研究）。相關 commit：
> `044889e1`（封面與控制列在矮視窗左右並排）、`4a23ae86`（高度下限 520dp 抄 Auxio，
> 見 `00-bootstrap-guidelines/research/providers-ui.md:148`）。

### 背景（模糊封面）

播放頁傳給 `TrackBlurredBackdrop` 的兩層 overlay alpha **都是 0**（`player_page.dart:374-375`），
電台頁也是 0（`radio_player_page.dart:94-95`）。真正上色的 overlay 在
`ImmersivePlayerScaffold`：

- body 區：`surface` alpha **0.60** + `surfaceContainerHighest` alpha **0.08**
  （`immersive_player_scaffold.dart:34-35`，套用點 `:88-95`）。
- AppBar 區：`surface` alpha **0.50** + `surfaceContainerHighest` alpha **0.06**（`:36-37`，套用點 `:71-75`）。

底圖 `BlurredCoverBackdrop`（`lib/ui/widgets/player/blurred_cover_backdrop.dart:110-176`）三層：
`ColoredBox(surface)` → `ImageFiltered(ImageFilter.blur(sigmaX: 48, sigmaY: 48))` 包 `Image(fit: BoxFit.cover)`
（`:139-151`）→ 兩層 overlay。圖來源是 `TrackBlurredBackdrop` 用 `TrackCover.imageProviderCandidates`
（`variant: TrackCoverVariant.backdrop`，`blurred_cover_backdrop.dart:44-49`）。

→ 事實上的播放頁背景 = **封面模糊（sigma 48）再蓋 60% surface 色**。
`ui.md` §6.2 觀察 7「背景模糊色塊在右半部偏灰」是這個機制的視覺結果（**推測**，未實測）。

### 各版面內容

- **`narrow`**（`_buildNarrowPlayerContent`，`:385-404`）：`Padding(all: 24)` 內 `Column` →
  `Expanded(_buildNarrowMediaSection)` + `SizedBox(32)` + 控制區。
  `_buildNarrowMediaSection`（`:490-519`）是 `AnimatedSwitcher`，`_showLyrics` 為 true 時顯示
  `LyricsDisplay`，否則顯示封面（`ConstrainedBox(maxWidth: AppLayout.playerCoverMax = 420)`，
  長按切換；`:503-516`）。
- **`wideSingle`**（`:225-232`）：同一份 narrow 內容置中，`ConstrainedBox(maxWidth:
  AppLayout.playerContentMaxWide = 720)`。
- **`wideSplit`**（`_buildDesktopPlayerContent`，`:406-442`）：`Padding(all: 24)` 內 `Row` →
  左 `Expanded(flex: 5)` = `Column`〔`Expanded(Center(封面, max 420))` + `SizedBox(24)` + 控制區〕；
  `SizedBox(width: 32)`；右 `Expanded(flex: 7)` = `LyricsDisplay` 佔滿高度。
  **這個版面沒有佇列欄、沒有右側資訊面板、沒有標題列**；flex 5:7 是寫死的（`:430`、`:440`）。
- **`shortSplit`**（`PlayerShortSplitContent`，`:90-118`）：`Padding(all: 24)` 內 `Row` →
  左 `Expanded(媒體)`、中 `SizedBox(32)`、右 `Expanded(Center(SingleChildScrollView(控制區)))`。
- **控制區**（`_buildControlSection`，`:444-489`）由上而下：`_buildTrackInfo`（標題／作者）→
  gap 20（narrow 為 32）→ `_buildProgressBar` → gap 16（narrow 為 24）→ `_buildPlaybackControls`。
  gap 值由 `useCompactGaps = layoutMode != PlayerLayoutMode.narrow`（`:167`）決定。
- **播放控制列**（`_buildPlaybackControls`，`:661-763`）：`Row(mainAxisAlignment: spaceEvenly)`，
  5 顆依序為 隨機／亂序（`Icons.shuffle`）、上一首（`Icons.skip_previous`，`iconSize: 40`）、
  `PlayerPlayPauseButton`、下一首（`Icons.skip_next`，`iconSize: 40`）、循環（`_getLoopModeIcon`）。
- **頂列**（`ImmersivePlayerScaffold` 提供 chrome）：`leading` 固定是
  `IconButton(Icons.keyboard_arrow_down, tooltip: t.player.collapse)`（`immersive_player_scaffold.dart:47-51`）；
  `player_page.dart` 傳入的 `appBarActions`（`:240-364`）依序為：加入歌單 `PopupMenuButton`
  （只有 `currentTrack != null` 時，`:242-271`）、`FmpAudioDeviceSelector`
  （`isDesktopPlatform && hasSelectableDevices`，`:276-282`）、`CompactVolumeControl`（`isDesktopPlatform`，`:283-288`）、
  `IconButton(Icons.info_outline)`（`:292`）、`PopupMenuButton(Icons.more_vert)` 溢出選單（`:298`）。
  Windows 另有 `DragToMoveArea`（`immersive_player_scaffold.dart:76`）。

---

## 3. 導航殼與迷你播放器（UI 元件清單）

`ui.md` §1.2 已載三種版面、導航軌寬度與 MiniPlayer 掛載位置。以下補控制項清單與右側面板細節。

### MiniPlayer（`lib/ui/widgets/player/mini_player.dart`，474 行）

- 標題區：曲名 + 作者（`:345-380`）。
- 控制群（`_buildControls` 尾段，`:420-467`）共 5 顆，順序：隨機（`Icons.shuffle`，size 20）、
  上一首（`Icons.skip_previous`，24）、`MiniPlayerPlayPauseButton`、下一首（`Icons.skip_next`，24）、
  循環（`Icons.repeat` / `Icons.repeat_one`，20）。
- 桌面尾隨群 `MiniPlayerDesktopControls`（`lib/ui/widgets/player/mini_player_desktop_controls.dart:46-56`）：
  `SizedBox(width: 8)` + 音訊輸出裝置選擇器（僅 `hasSelectableDevices` 時）+ 音量控制。
  該檔 dartdoc（`:9-13`）說明音樂與電台迷你播放器共用這一份。
- 插入條件 `isDesktopPlatform`（`mini_player.dart:96`）。
- 合計桌面寬版 5 + 2 = **7 顆**（與 `ui.md` U4 的「7 顆鈕」一致）。

### 右側「正在播放」面板 `TrackDetailPanel`

- 檔案 `lib/ui/widgets/panels/track_detail_panel.dart`（1347 行）。
- 寬度 token 在 `lib/core/constants/app_layout.dart`：預設 `detailPanelDefault = 412`、
  下限 `detailPanelMin = 320`、比例上限 `detailPanelMaxFraction = 0.4`（`:19-25`）；
  實際上限 `max(320, windowWidth * 0.4)`（`detailPanelMaxFor`，`:60-61`）；
  存進 DB 的上限 `detailPanelStoredMax = 1600`（`:31`）。收起條寬 36dp／hover 54dp（`:33-36`）。
- 掛載點 `ResponsiveScaffold._ExpandedLayout`（`lib/ui/layouts/responsive_scaffold.dart:457-577`），
  spacer + 真實面板「始終在 widget tree 中」（`:457` 註解），拖曳結束時 commit 寬度（`:577`）。
- 內容（`_DetailContent`，`:703-1043`）由上而下：可點封面（`_ClickableCover`，`:1048`）、
  owner 頭像 + 名稱 + 發布日期列（`:860-886`）、`_buildSimpleStats`、下一首（有 upcoming 才顯示，`:985-1046`）、
  簡介（`ExpandableTextSection`）、熱門評論（`CommentPager`）、音訊串流資訊（`AudioStreamInfoSection`，最下方）。
- `_buildSimpleStats`（`:945-983`）分兩種：歌曲來源顯示專輯名 + 留言數；影片來源顯示播放數 + 點讚數
  （部分音源再加收藏數）。
- header 有「正在播放」標題與收起鈕（`:440-470`）。
- 電台變體 `_RadioDetailContent`：直播公告、簡介、標籤（`:1142-1213`）。

---

## 4. i18n

`ui.md` §4 已載三語言、38 namespace、每語言 1176 key、`slang.yaml` 的 `base_locale: zh-CN`、
缺漏 0、同值檢查、語言選擇四選一、複數與數字格式問題。以下補結構與慣例。

- 目錄結構 `lib/i18n/<locale>/<namespace>.i18n.json`；本檔重數確認三語言各 **38 檔、1176 葉節點**
  （Python 遞迴數 JSON 葉）。
- `lib/i18n/` 內另有產物 `strings.g.dart` 與 `strings_<locale>.g.dart`（已 gitignore，`ui.md` 已載）。
- `slang.yaml` 完整鍵值：`base_locale: zh-CN`、`namespaces: true`、`input_directory: lib/i18n`、
  `input_file_pattern: .i18n.json`、`output_directory: lib/i18n`、`output_file_name: strings.g.dart`、
  `lazy: false`（檔內註解：slang 4 預設 `lazy: true` 為 web deferred loading，Android／Windows 不支援，
  且 lazy 會讓 `LocaleSettings` 的同步版 API 拿不到未載入的語言）。
- 命名慣例：namespace = 檔名（`player.i18n.json` → `t.player.*`），key 為 camelCase，
  值皆為**純字串**（無 ICU 巢狀、無 plural 形式）。巢狀只用到兩層以內，例如
  `t.userGuide.quickStart.title`、`t.settings.font.microsoftYaHei`、`t.audioSettings.qualityLevel.high`。
- **全樹沒有用 slang 的 plural**：1176 個 key 沒有一個是 plural 形式；英文複數靠字串內插
  `"$n tracks"`（`ui.md` §4 已載的 `1 tracks`）。
- locale 執行期管理在 `lib/providers/settings/locale_provider.dart`：`LocaleNotifier extends Notifier<AppLocale?>`
  （`:6-60`），state 為 `AppLocale?`，`null` 代表跟隨系統（走 `LocaleSettings.instance.useDeviceLocaleSync()`，
  `:24-26`）；持久化字串是 `'zh_CN'` / `'zh_TW'` / `'en'`（`:46-57`）。
- `MaterialApp` 的 localizations delegates 是 `GlobalMaterialLocalizations.delegates`
  （`lib/app.dart:48`、`:140`）。
- 數字格式 `formatCount(int)`（`lib/core/utils/number_format_utils.dart:6-38`）：看
  `LocaleSettings.currentLocale`；`en` 走 B / M / K（`:17-26`），其餘走 億 / 万
  （繁 `億`／`萬`，簡 `亿`／`万`，`:28-37`）；**兩條路徑都 `toStringAsFixed(1)`**，沒有千分位，
  10000（中文）／1000（英文）以下回原數字。

---

## 5. 鍵盤（補計數與位置）

`ui.md` §5.3 已載「快捷鍵框架完全沒用」、全域熱鍵清單與預設值、實測結果。以下補本檔重數的計數與確切位置。

本檔 `grep -rn` 於 `lib/`（`--include=*.dart`）：

| API | 命中 | 說明 |
|-----|-----:|------|
| `Shortcuts(` | 0 | — |
| `Actions(` | 18 | **全部是誤配**：方法名 `_radioMenuActions()` / `_stationMenuActions()` 等與具名參數 `actions:`（`change_download_path_dialog.dart:48`）。真正的 Flutter `Actions` widget = 0 |
| `FocusTraversalGroup` | 0 | — |
| `CallbackShortcuts` / `SingleActivator` | 0 / 0 | — |
| `RawKeyboardListener` / `HardwareKeyboard` | 0 / 0 | — |
| `KeyboardListener` | 1 | `lib/ui/pages/settings/widgets/settings_desktop.dart:439`（快捷鍵錄製對話框） |
| `Focus(` / `FocusNode(` | 2 / 2 | `FocusNode` 用於錄製對話框（`settings_desktop.dart:425`）；另 `windows_desktop_service.dart:496` 是 `onWindowFocus()` 方法名，非 widget |
| `autofocus` | 7 | 全在對話框或搜尋框 |
| `LogicalKeyboardKey` | 79 | 只出現在 `lib/data/models/hotkey_config.dart` 與 `settings_desktop.dart` |

全域熱鍵：`hotkey_manager`，`HotKeyScope.system`（`hotkey_config.dart:78`），預設值在
`HotkeyConfig.defaults()`（`:212`）；清單與實測結果見 `ui.md` §5.3。

---

## 6. 使用者指南頁（E20）

- 檔案 `lib/ui/pages/settings/user_guide_page.dart`（492 行）。`UserGuidePage` 是 `StatelessWidget`（`:7`），
  `AppBar(title: t.settings.userGuide.title)`（`:15`）。
- body 是 7 個可展開卡片 `_buildExpandableSection`（`:318` 起），每段內放 `_buildInfoItem`
  或 `_buildStepItem`（後者有序號）。
- 7 段（依 i18n key 與行號）：
  1. `quickStart`（`:19-49`）— 3 個步驟（匯入歌單、加入佇列、開始播放）
  2. `externalImport`（`:50-100`）— 7 個條目（支援平台、智慧配對、預覽、YouTube Mix 快捷、無限播放、授權匯入、匯入自動更新）
  3. `search`（`:101-145`）— 音源、排序與篩選、直播篩選、多選等
  4. `playbackControl`（`:146-202`）— 播放控制、音訊設定指南、授權播放
  5. `tips.lyricsTitle` 歌詞（`:203-241`）— 5 個條目
  6. `download`（`:242-280`）— 5 個條目（設定路徑、下載歌曲、離線、下載同步、備份）
  7. `tips.desktopAndMaintenanceTitle` 桌面與維護（`:281-317`）— 4 個條目（桌面熱鍵、托盤開機、歷史、App 更新）
- 內容量（Python 數 JSON 葉節點）：`lib/i18n/<locale>/userGuide.i18n.json` 每語言 **83 個葉節點**
  （title + description 成對，約 40 個條目）；總字元數 **zh-TW 1358、zh-CN 1349、en 3830**。
- `userGuide` namespace 另有 `liveRadio`、`explore`、`history`、`audioSettingsGuide`、`ytMix`、
  `appUpdate` 等群組，它們是**被塞在既有 section 內的條目標題**，不是獨立 section
  （例如 `t.userGuide.liveRadio.title` 當作 search 段的一項，`:134`）。
- 入口：設定頁 → 使用者指南，路由 `/settings/user-guide`（`ui.md` §1.1 的路由表；`questions.md` E20 標「不確定」）。

---

## 7. UI static-rule 一覽

`AGENTS.md` § Boundaries 記載規則的**性質**；以下是原始檔與它們守的東西（`test/ui/static_rules/` 4 檔 +
`test/services/static_rules/` 1 檔 + `test/support/` 與 `test/data/static_rules/` 各 1 檔）。

| 檔案 | 守的性質 |
|------|----------|
| `test/ui/static_rules/ui_consistency_static_rule_test.dart` | (a) 只有 `lib/ui/widgets/images/` 的語意 widget 可以呼叫底層 image API 或指名 `ImageTargetSizes` tier——比對**集合** `_imageApiOwners`（定義在 `:101` 起，比對點 `:20-31`）；偵測器認得 `Image.network`、`loadImage`、`ImageTargetSizes`、`CachedNetworkImage` 等（`:56-66`）。(b) `ListTile` 的 `leading` 不可直接用 `Row`（`:33-44`） |
| `test/ui/static_rules/slider_overlay_static_rule_test.dart` | `lib/` 內除 `lib/ui/widgets/controls/scoped_slider.dart` 外，不可直接建 Material `Slider` / `RangeSlider`（含 `.adaptive`）——比對**集合**，理由：數值指示器落進 Navigator Overlay 會讓 Windows 無障礙樹停住（檔頭註解） |
| `test/ui/static_rules/error_presentation_static_rule_test.dart` | 三條：(a) async error 分支不可渲染成空（要 `ErrorDisplay(compact: true)` + retry，掃整個 `lib/ui`）；(b) i18n error template 不可塞原始 exception（掃整個 `lib/`，`t.x.loadFailed(error: e.toString())` 違規，要 `userMessageFor(e)`）；(c) 不可把原始 exception 交給使用者可見的 widget（要 `userMessageFor` / `ToastService.failure`）。偵測器有雙向變異測試（`:70-118`） |
| `test/ui/static_rules/watch_scope_static_rule_test.dart` | 5 個「寬且高頻」provider 不可整包 `ref.watch`（要 `.select(...)`）：`audioControllerProvider`、`rankingCacheServiceProvider`、`searchSelectionProvider`、`playlistDetailSelectionProvider`、`downloadProgressStateProvider`（`:24-32`） |
| `test/services/static_rules/lyrics_window_strings_static_rule_test.dart` | 歌詞子視窗（獨立 engine）讀的每個翻譯字串都必須有人從主 isolate 推過去；漏推只會顯示簡體 fallback，不會壞掉（檔頭註解） |

相鄰的邊界規則（非 UI 專屬，但影響 UI 程式碼的寫法）：`test/support/layer_boundary_static_rule_test.dart`
（`lib/core/`、`lib/data/` 不 import `lib/services/`、`lib/providers/`）、
`test/data/static_rules/isar_boundary_static_rule_test.dart`（`isar.` 只出現在 `lib/data/repositories/`）。
`AGENTS.md` § Boundaries 另載「Test waits」（`pumpUntil` / `drainEventQueue`）與
「Static rules 命名與位置」兩條規則，各由 `test/support/` 下的對應檔守。

**目前沒有任何規則守「間距／字級 token」**：`grep -rn AppSpacing lib` 為 0，`lib/core/constants/ui_constants.dart`
沒有間距常數類別（`ui.md` §3.1 已載）；`fontSize:` 字面值 29 處也沒有規則擋。

### 相關測試覆蓋（無障礙與視覺回歸）

- **沒有任何 golden test**：`grep -rln "matchesGoldenFile|goldenTest|alchemist"` 於 `test/`、`tool/` 命中 0。
- 觸及語意的測試 9 檔，其中 2 檔用 `meetsGuideline`：
  `test/ui/widgets/comment_pager_test.dart:33-34` 與 `test/ui/widgets/mini_player_accessibility_test.dart:117-118`，
  都只斷言 `androidTapTargetGuideline` 與 `labeledTapTargetGuideline`；
  **`textContrastGuideline` 全 repo 沒有使用**。
- 其餘語意測試（`test/ui/layouts/nav_rail_semantics_test.dart`、
  `test/ui/windows/lyrics_window_semantics_test.dart`、`test/ui/widgets/app_bars/custom_title_bar_test.dart`、
  `test/app_content_wrapper_test.dart`、`test/ui/windows/lyrics/lyrics_title_bar_test.dart`）
  斷言的是語意樹節點內容，不是 guideline helper。

---

## 8. 本檔與 `ui.md` 的差異更正

- `ui.md` §6.2 觀察 7 對播放頁背景的「**推測**是封面取色的漸層」→ 實際是
  模糊封面（`sigma 48`）+ `ImmersivePlayerScaffold` 的 0.60 / 0.08 overlay，**不是取色漸層**
  （`immersive_player_scaffold.dart:34-37`、`blurred_cover_backdrop.dart:139-151`）。
- `ui.md` §3.1 說 `app_theme.dart`「從種子色產生 `ColorScheme`」，未提 dynamic color 有無
  → 確認**沒有** `dynamic_color` 依賴，只有 seed。
- `ui.md` §5.3 說 `Actions(` 為 0「排除類別名尾碼的誤配後」→ 本檔重數 18 個命中，逐一確認為
  `*Actions()` 方法名與 `actions:` 具名參數，真 widget 使用為 0，與 `ui.md` 結論一致。
