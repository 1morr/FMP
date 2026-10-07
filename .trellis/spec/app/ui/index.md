# 介面（`app/lib/ui/`、`app/lib/i18n/`）

寫畫面、加字串、跳提示、加快捷鍵時適用。規則（token、字串來源、提示入口、快捷鍵、焦點三區）
與閘門見 `app/AGENTS.md` § 介面；為什麼是這些選擇，見 ADR 0023、ADR 0024 與
`.trellis/tasks/archive/2026-09/09-30-ui-foundation/research/notes.md`。這裡只寫怎麼做。

## 目錄

```
lib/i18n/
  zh-TW.i18n.json      # base locale；新字串先寫這裡
  zh-CN.i18n.json
  en.i18n.json
  strings*.g.dart      # slang 產生，提交
lib/ui/
  theme/               # AppTokens、AppLayout、buildAppTheme；fmp_design_tokens 豁免
  layout/              # WindowClass、WindowClassScope
  i18n/ui_locale.dart  # LocaleSetting → Flutter locale／slang／字型；translationsProvider
  errors/              # AppError → 訊息
  empty_state/         # EmptyState：置中的圖示、標題、說明與動作
  offline/             # OfflineBanner（外殼）、OfflineMessage（頁面的離線空狀態）
  toast/               # Toaster、ToastHost；fmp_toast_entry 的允許目錄
  shell/               # AppShell（導覽、內容、播放列三區）、快捷鍵表
  search/              # 搜尋頁、searchProvider、音源 chip 列
  history/             # 歷史頁（播放歷史，分頁讀、依日分組）、historyProvider
  settings/            # 設定頁（分組、list-detail）與外觀、網路的控制項
  player/              # 播放列（讀佇列項目的 TrackInfo；隨機、循環、medium 的「⋯」）
  artwork/             # 封面縮圖（CachedNetworkImage）與 pickArtwork；cached_network_image 只准在這裡
  format/              # 時長與位元組數的文字
lib/app/app_material.dart  # 三個 App 根元件共用的 MaterialApp 設定
```

## 間距、圓角、顏色

```dart
final tokens = AppTokens.of(context);
Padding(padding: EdgeInsets.all(tokens.spacing.x4));        // 16
SizedBox(height: tokens.spacing.x2);                         // 8
BorderRadius.circular(tokens.radius.medium);                 // 12
Container(color: tokens.success.container);                  // 語意色
Text('…', style: Theme.of(context).textTheme.titleMedium);   // 字級只用角色
```

- 間距只有 ADR 0024 的九個值：`x1 x2 x3 x4 x5 x6 x8 x10 x12`（×4dp）。要的值不在裡面時先
  想是不是元件的固定尺寸；是就加進 `AppLayout`，不是就改用最接近的 token。
- 顏色：`Theme.of(context).colorScheme` 的角色，或 `AppTokens` 的 `success`／`warning`。
  語意色成對用（`container` 配 `onContainer`、`color` 配 `onColor`），對比度才有保證。
- 元件的固定尺寸（封面上限、面板寬度）放 `AppLayout`，隨元件出現時加。
- `lib/ui/theme/` 可以寫數字與 `Color(0x…)`；其他地方寫了 `fmp_design_tokens` 會報。真的
  不是設計值的（宿主的透明底）以 `// ignore: fmp_lints/fmp_design_tokens — 理由` 標出。

## 寬度

```dart
switch (WindowClass.of(context)) {
  WindowClass.compact || WindowClass.medium => …,
  WindowClass.expanded || WindowClass.large || WindowClass.extraLarge => …,
}
```

- `WindowClass.of` 讀最近的 `WindowClassScope`；App 根放了一個（量整個視窗，外殼用它選導覽
  元件），外殼在內容區與播放列各放一個，頁面與播放列讀到的是自己那一塊的等級（視窗 900 寬時
  內容區扣掉 rail 是 medium）。
- 只在等級改變時重建。要精確寬度的版面仍用 `LayoutBuilder`。

## 字串

加一條字串：

1. 三個 JSON 都加同一個 key，先寫繁中。參數寫 `{name}`，三個語言的參數要一樣。
2. `dart run slang`（設定在 `slang.yaml`），提交 `lib/i18n/*.g.dart`。
3. widget 裡 `final t = ref.watch(translationsProvider);`，`t.section.key` 或
   `t.section.key(name: …)`。沒有 slang 的全域 `t`、`context.t`。

- 缺某個語言也編譯得過（`fallback_strategy: base_locale`，退回繁中），擋住漏翻的是
  `test/i18n/translations_test.dart`。
- 簡中寫大陸用語（登录、网络、粘贴），不是繁中逐字轉換。英文句子裡的參數放在句中，
  音源名稱沒有時代入的是小寫的 `the source`。
- 不翻的字（語言選單上各語言的名稱）不放 JSON，寫在程式碼並註明理由（`localeEndonym`）。
- 漢字的繁簡字形看文字樣式的 `locale`：`buildAppTheme` 把 `textLocaleOf` 放進每個
  `TextTheme` 角色（英文介面是繁中），Android 這類不指名字型的平台只看它。顯示中文但不跟
  介面語言的文字（語言名稱、之後的曲名）在**樣式**上給 locale
  （`style: TextStyle(locale: …)`）；`Text.locale` 會被主題樣式的 locale 蓋過，沒有作用。

## 錯誤訊息

- `errorMessage(t, error, sourceName: …)`（`lib/ui/errors/error_message.dart`）以
  exhaustive `switch` 把 `ErrorMessageKey` 對到 `t.errors.<同名>`。加 key 時編譯器會指出這裡；
  JSON 三個都要加（測試逐一檢查每個 `ErrorMessageKey`、`UnavailableReason`）。
- 音源名稱由呈現層以 `pluginId` 查 manifest 的 `name`；查不到（未安裝）時用 `pluginId`
  本身（manifest 驗過格式：小寫英數與 `-`），錯誤沒有 `pluginId` 才用 `errors.unknownSource`。

## 提示

```dart
final toaster = ref.read(toasterProvider);
toaster.success(t.library.added);
toaster.info(t.share.copied, action: ToastAction(label: t.common.undo, onPressed: undo));
try {
  await search(query);
} on AppError catch (error) {
  toaster.error(error, operation: 'Search failed', tag: 'search');
}
```

- 只給使用者動作的回饋。背景工作不呼叫 `Toaster`：`log.report` 後更新畫面上的狀態。
- `error` 自己呼叫 `log.report`，呼叫端不要再 report 一次。
- 錯誤訊息要放進一句話（「已跳過「歌名」：原因」）時給 `sentence: (message) => t.x(reason:
  message)`：`message` 是依類別表翻譯好的訊息，去重仍是「類別＋音源」。
- 每則最多一個動作；帶動作的也照時長消失（成功與資訊 4 秒、警告與錯誤 6 秒）。
- 去重 5 秒：訊息以「種類＋文字」，錯誤以「類別＋音源」。
- 外殼的 `_BottomInsetReporter` 量底部那一塊（compact 是播放列加底部導覽列，更寬是播放列）
  的高度，排版後以 `toastBottomInsetProvider` 發佈；頁面不用管。M2 的全螢幕播放頁蓋住外殼時
  要設回 0。
- 要看狀態變化或事件跳提示（播放控制器的 `events`），在 `ref.listen` 的 callback 裡呼叫
  `Toaster`，不在 `build` 裡：`Toaster` 同步送出，`ToastHost` 當場 `showSnackBar`。
- M1 沒有「詳細」與「回報」（ADR 0023 §決定 4 延到 M3，和 Debug 頁的錯誤歷史一起做）。

## 外殼、快捷鍵與焦點

- 導覽項只有 `ShellDestination` 的兩個；頁面放在內容區的 `IndexedStack`（換頁不丟狀態，沒選的
  頁面焦點被排除）。
- 加一個 App 內快捷鍵（ADR 0024 §決定 8 的表）：
  1. `shell_shortcuts.dart` 加一個 `Intent` 與 `shellShortcuts` 的一列；
  2. `AppShell` 的 `Actions` 接上。按鍵同時是文字編輯鍵（空白鍵、方向鍵、Home／End、
     Ctrl+A 之類）的，用 `TextInputAwareAction`，焦點在輸入框時停用、交給輸入框；
  3. 有對應按鈕的，翻譯檔的 `*Tooltip` 字串寫上按鍵（`播放（空白鍵）`），按鈕的語意標籤
     （`Icon.semanticLabel`）不帶按鍵；
  4. `test/ui/shell/app_shell_test.dart` 加案例，文字編輯鍵另外在輸入框裡按一次確認沒作用。
- 焦點三區（導覽、內容、播放列）各是一個 `FocusScope` 加 `FocusTraversalGroup`：Tab 只在區內
  循環；F6 回到那一區上次的焦點，沒有就是它的第一個可聚焦項目。新的可聚焦元件放在對的那一區裡。

## 離線

- 外殼已經放了 `OfflineBanner`，頁面不另外提示離線，也不用 toast。
- 頁面的內容要網路時：
  - 使用者的操作在 `noInterface`、`unreachable` 都照常送出，不在 Notifier 擋（系統的
    回報可能是錯的，見 `app/AGENTS.md` § 網路）。
  - 失敗而狀態不是 `online` 時，內容區換成 `OfflineMessage(status: 目前狀態, action: 重試)`；
    在 `online` 時失敗照一般的失敗畫面。已有的內容照常顯示。
  - 背景請求（M3 起）在不是 `online` 時不發。
  - 本機資料（設定、之後的音樂庫）照常顯示。
- 空狀態與失敗用 `EmptyState`，離線的那一個樣子才一致。
- 測試：`ShellHarness.setNetwork(tester, NetworkStatus.x)`；新頁面的離線狀態加進
  guideline 測試。

## 歷史頁

規則與閘門見 `app/AGENTS.md` § 介面。

- 資料：`historyProvider`（`history_state.dart`）是 `AsyncNotifier`，載入的是「最新的前 N 筆」（N 從 50 起，
  `loadMore` 每次加 50）；`PlayHistoryRepository.changes()` 一發出就重讀已載入的那麼多筆，每次重讀換一代、過時的重讀丟掉。
  `loadMore` 的位移是照開始時的清單算的：讀的期間換了一代，或清單已經被別的結果換掉（開始時已有一次重讀在路上），
  那一頁就丟掉，不接在新清單後面（接上會重複或漏列；`a page read while a reload is in flight…` 守著）。頁面是 `ListView.builder`，最後一列（還有下一頁時）在 build 時排一個 post-frame 去 `loadMore`。
- 讀取失敗在 notifier 的 `_fail` 包成 `AppError` 並 `log.report` 一次，頁面的 `AsyncError` 分支顯示錯誤圖示與
  `errorMessage` 的文字，不是空狀態；不要把這個報告搬進 build。
- 分組在 `groupByDay`（純函數，以裝置本地日界）與 `dayKindOf`（今天、昨天用日期運算，不減 24 小時；現在讀
  `clock.now()`，測試用 `withClock(Clock.fixed(...))`）。日期標題用 `MaterialLocalizations` 的
  `formatMediumDate`（同年）與 `formatShortDate`（跨年），時刻用 `formatTimeOfDay(alwaysUse24HourFormat: true)`，
  不自己拼格式。測試的資料用本地時間造（`DateTime(2026, 10, 7, 14, 5)`），不依賴機器的時區。
- 一列的選單與搜尋結果列同一個寫法（`MenuAnchor`、右鍵 `excludeFromSemantics`、「⋯」下方開）；兩處沒有共用
  元件，改一邊時看另一邊。
- 測試：`h.pumpApp(tester, const HistoryPage())`（要離線橫幅就 `pumpShell` 後點「History」）；寫歷史用
  `container.read(playHistoryRepositoryProvider).record(...)`，要包 `tester.runAsync`，之後 `h.loadSettings`
  讓變動的串流與重讀跑完。

## 播放列與封面

- 開始播放與加入佇列都直接呼叫 `PlaybackController`（`playTemporary`、`playNext`、`addToQueue`，
  曲目是 `TrackSummary.toTrackInfo()`）。播放列讀 `QueueState.current`（`TrackInfo`）的顯示資料。
- 一首曲目的選單（搜尋頁的寫法）：`MenuAnchor` 包住整列，右鍵（`GestureDetector` 的
  `onSecondaryTapUp`，`excludeFromSemantics: true`）在點的位置開、長按與尾端「⋯」在「⋯」下方開，
  三處同一份選單。加入成功以 `toaster.success` 回饋，被上限拒絕的提示由外殼接 `QueueFull`。
- 控制器的事件（`playbackEventsProvider`：佇列滿、跳過、停下、試聽）只在外殼的
  `_onPlaybackEvent` 轉成提示；頁面不另外聽。新的事件類型加在那個 `switch`（編譯器會指出），
  並在 `app_shell_test.dart` 的 `playback toasts` 群組加一例。
- 播放列曲名下那一行的狀態標示（重試中、等待網路連線、試聽）由 `PlayerBar` 從
  `playbackStateProvider`、`playbackPreviewProvider` 推出；新的標示加在同一個 `switch`，並在
  `player_bar_test.dart` 的 `status labels` 三個寬度各加一例。
- 播放列的控制項照 ADR 0024 §決定 5 的三段，只放已經有的功能；加功能時同時改
  `player_bar_test.dart` 的 `controls per width` 與 golden。
- 封面用 `ArtworkImage(pluginId: 曲目鍵的第一段, artwork: TrackInfo.artwork, size: …)`：`pickArtwork` 挑一張、
  以顯示尺寸的高解碼，經 `artworkCacheManagerProvider(pluginId)` 的 cache manager 讀（統一快取庫，
  沒有才經那個插件的媒體 client 下載）。沒有、載入中、失敗與還沒有 cache manager 都是同一個
  佔位圖。不帶 header（B 站的 hdslb 不帶 `Referer` 讀得到，帶別的網域反而 403）。
- 測試 `ArtworkImage` 以 `artworkCacheManagerProvider.overrideWith((ref, pluginId) => 假的)`
  注入只實作 `getFileStream` 的假 `BaseCacheManager`（`test/ui/artwork/artwork_image_test.dart`）；
  解碼是真的非同步工作，要 `tester.runAsync`。外殼的測試插件沒有封面，不用 override。

## 測試

- 畫面測試用 `buildAppTheme` 的主題；有提示的包 `ToastHost`，以
  `toasterProvider.overrideWithValue(Toaster(...))` 注入（例子：
  `test/ui/toast/toast_host_test.dart`）。
- 外殼與頁面用 `test/ui/support/shell_harness.dart` 的 `ShellHarness`：可搜尋、可解析的假插件
  （`searchSourcesProvider` override）、假後端上的真 `PlaybackController`、記憶體資料庫、英文
  介面。`pumpShell` 開整個外殼，`pumpApp` 開單一個 widget，`play` 直接開始播。
- golden（`alchemist`，只比 CI 版：文字畫成色塊、不畫陰影，`test/flutter_test_config.dart`
  關掉平台版）：一個情境一個 `goldenTest`、不用 `GoldenTestScenario`（它的名稱標籤在 Windows 與
  Linux 差一個像素）。更新：`flutter test --update-goldens <檔案>`，產生的圖在旁邊的
  `goldens/ci/`，看過再提交。只守版面結構，數量保持少（ADR 0024 §如何確認）。
- 時間：`Toaster` 讀 `clock.now()`，單元測試用 `fakeAsync`，widget 測試的
  `tester.pump(duration)` 也會推進它。
- 新畫面加進 guideline 測試（`test/ui/guidelines_test.dart` 的寫法）：淺色、深色各跑
  `labeledTapTargetGuideline`、`androidTapTargetGuideline`、`textContrastGuideline`，
  `tester.ensureSemantics()` 要開。
- 語言：`TestWidgetsFlutterBinding.instance.platformDispatcher.localesTestValue` 設系統語言，
  `addTearDown(clearLocalesTestValue)`；測試預設是 `en_US`。

## Quality Check

- `lib/ui/`（theme 以外）沒有數字字面值的間距、圓角、字級與 `Colors.*`：`dart analyze`
  乾淨。
- 新字串三個 JSON 都有、產生檔已重跑並提交。
- 新畫面在淺色、深色都過 guideline 測試。
- 新的只有圖示的按鈕有 tooltip（有快捷鍵就附上）與語意標籤。
