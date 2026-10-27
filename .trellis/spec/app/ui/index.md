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
  layout/              # WindowClass、WindowClassScope、layoutStateProvider 與面板展開、寬度（rememberPanel 寫入）
  i18n/ui_locale.dart  # LocaleSetting → Flutter locale／slang／字型；translationsProvider
  errors/              # AppError → 訊息
  empty_state/         # EmptyState（置中版、error 色圖示、compact 橫條）、LoadingState（轉圈加一行說明）
  offline/             # OfflineBanner（外殼）、OfflineMessage（頁面的離線空狀態）
  toast/               # Toaster、ToastHost；fmp_toast_entry 的允許目錄
  shell/               # AppShell（導覽、內容、播放列三區；每個目的地一個巢狀 Navigator）、導覽類快捷鍵表、
                       # PlaybackShortcuts（播放類快捷鍵表）、now_playing_panel（右側面板、把手、面板寬度規則）、
                       # legacy_side_rail（medium 以上的可展開側欄）、page_app_bar（每頁的置中頁頂 PageAppBar 與頁面的底 PageSurface）
  home/                # 首頁（區塊：排行、我的歌單、電台、最近播放；recentPlaysProvider；一排卡片 _ShelfRow：底色卡片、滑鼠移入的箭頭與漸層、滑鼠拖曳；卡片選單重用 PlaylistMenu、removeStation）
  charts/              # 首頁的排行區塊（home_charts）、探索頁（explore_page；openExplore 開在巢狀導覽裡）、
                       # 兩者共用的狀態行、內容狀態與排行曲目列（chart_parts）
  library/             # 音樂庫（歌單卡的清單／格狀、拖曳排序、卡片選單）、建立與編輯歌單的對話框（playlist_dialogs，
                       # 含自訂封面）、歌單封面（playlist_cover）、歌單詳情（playlist_detail_page；openPlaylist 開在巢狀導覽裡）、
                       # 它們讀的 provider 與分組、重排的純函數（library_state：playlistOverviewsProvider、playlistDetailProvider、
                       # groupParts、reorderedEntryIds）、曲目選單的「加入歌單…」與它的對話框（add_to_playlist）、
                       # 匯入對話框（import_dialog）、匯入預覽（import_preview_page；openImportPreview 開在巢狀導覽裡）、
                       # 手動刷新（manual_refresh：manualRefreshProvider）
  search/              # 搜尋頁、searchProvider（曲目與直播間兩種模式）、音源 chip 列、搜尋歷史清單（search_history_list：輸入框空白且有歷史時取代結果區；點一筆再搜，叉叉刪一筆，「清除」不確認，同舊版；只有輸入框的 Enter 與點歷史會記，換音源、自動載入與重試不記）
  radio/               # 電台頁（compact／medium 清單、expanded 以上網格、liveFirst 開播優先、排序模式）、狀態標記（RadioStatusTag）與「標記＋文字」那一行（TaggedLine）
  queue/               # 佇列目的地（QueuePage：佇列空時是空狀態，否則整頁的 QueueView）與可編輯的佇列（QueueView）
  history/             # 歷史頁（播放歷史，分頁讀、依日分組；openHistory 開在巢狀導覽裡）、historyProvider
  settings/            # 設定頁（分組、list-detail；分組列的一行摘要在 settings_page 的 `summary`，加新摘要時加一條 `SettingsSection` 分支與三語字串 `settings.summary.*`，沒有值可說的組不放副標）與外觀、音樂庫（首頁排行）、網路的控制項、「關於」（版本列，連點開啟開發者模式）
  debug/               # Debug 頁（openDebugPage、路由閘門、區塊的 list-detail）與它的區塊（DebugSection；區塊的 widget 與純函數放 debug_*.dart）
  player/              # 播放列（讀佇列項目的 TrackInfo；隨機、循環、medium 的「⋯」；頂端的進度細線在 thin_progress_bar）、播放頁、
                       # 兩者共用的控制（player_controls）、播放頁的頂列（player_top_bar）、播放列與頂列共用的音量與輸出裝置（audio_controls）、TrackDetails（詳細區的欄位、佔位與失敗在
                       # track_detail_parts，trackDetailProvider 與記憶體 LRU 在 track_detail_provider）、
                       # 直播版共用的元件（live_widgets：hasNowPlaying、nowPlayingLiveProvider、LiveBadge、
                       # LiveFacts、LiveDetails、StatusTag）
  artwork/             # 封面縮圖（CachedNetworkImage）；cached_network_image 只准在這裡
  tracks/              # NowPlayingOverlay（封面上的在播遮罩，佇列、歷史等共用；暫停或減少動態時不動，所以 pumpAndSettle 的測試要先 disableAnimations，見 ShellHarness.openQueue 與 test/ui/tracks/marker_support.dart 的 reduceMotion）；
                       # track_markers：曲目列的在播標示（currentTrackKeyProvider、watchIsPlaying、TrackCover、playingTitleStyle）與固定寬的時長欄（TrackDuration），新的曲目清單照用；TrackRowMenu：搜尋結果、歷史、佇列、歌單詳情、首頁卡片的曲目共用的選單（右鍵、長按、「⋯」）；
                       # track_selection：多選（TrackSelection、TrackSelectionScope、TrackSelectionBar、SelectableTrackRow）
  plugins/             # pluginNameProvider、sourceUnavailableProvider；插件頁（plugins_page）、它讀的 provider（plugins_state）、
                       # 確認與網址對話框（plugin_dialogs）、能力名稱與來源的文字（plugin_text）、
                       # 插件列的共用元件（plugin_widgets）、搜尋頁的首次啟動引導（plugin_onboarding）
  accounts/            # 設定頁的帳號頁（accounts_section）、它讀的 provider、登入方式的交集與登入失敗的訊息（accounts_state）、
                       # QR 登入對話框（qr_login_dialog）；qr_flutter 只准在這裡；網頁登入的全螢幕頁
                       # （web_login_page）、貼上 cookie 的對話框（cookie_login_dialog）
  format/              # 時長、位元組數、人數（CLDR 縮寫，formatCount）與日期（CLDR yMMMd，formatDate）的文字
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
  內容區扣掉 rail 是 medium；播放列橫跨整個視窗，讀到的就是視窗的等級）。
- 只在等級改變時重建。要精確寬度的版面仍用 `LayoutBuilder`。

## 字串

加一條字串：

1. 三個 JSON 都加同一個 key，先寫繁中。參數寫 `{name}`，三個語言的參數要一樣。
2. `dart run slang`（設定在 `slang.yaml`），提交 `lib/i18n/*.g.dart`。
3. widget 裡 `final t = ref.watch(translationsProvider);`，`t.section.key` 或
   `t.section.key(name: …)`。沒有 slang 的全域 `t`、`context.t`。

- 缺某個語言也編譯得過（`fallback_strategy: base_locale`，退回繁中），擋住漏翻的是
  `test/i18n/translations_test.dart`。
- 帶數量的字串用複數語法：`"trackCount(plural, param=count)": {"one": "{count} song", "other": "{count} songs"}`，
  中文只寫 `other`；呼叫照舊 `t.library.trackCount(count: n)`，不要自己判斷 `n == 1`。不在 widget 樹裡要翻譯時用
  `buildTranslations(locale)`，不直接 `buildSync`（中文的複數解析器在它裡面）。
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
- `error` 的動作是自動附的，頁面不用管：開發者模式附「詳細」、一般使用者只有 `Unsupported`、`UnexpectedError` 附「回報」，
  都開 `ErrorDetailPage`（`openErrorDetail(navigator, record)`）；要換成自己的動作才傳 `action`（會取代它）。Debug 頁的錯誤紀錄
  用同一個 `openErrorDetail`。規則與閘門見 `app/AGENTS.md` § 介面的「提示與錯誤詳細頁」。
- 測試提示的動作：`ShellHarness.toaster` 已接上 `navigatorKey`，`toastDeveloperMode = true` 當成開發者模式；網址開啟器用
  `test/ui/support/fake_url_opener.dart`（`ShellHarness(urlOpener: …)`，不給就是平台沒有這個能力）。

## 外殼、快捷鍵與焦點

- 導覽項是 `ShellDestination` 的六個（首頁｜搜尋｜音樂庫｜佇列｜電台｜設定，ADR 0035 §決定 2）；圖示與文字在 `_destinationLabel` 一份，底部導覽列與側欄
  照它的順序產生。內容區的 `IndexedStack` 每一格是那個目的地的巢狀 `Navigator`（換頁不丟狀態與內頁，沒選的頁面焦點被排除），
  根頁在 `_rootPage`。
- 開一個內頁（在內容區裡、導覽與播放列留著）：`Navigator.of(context).push(MaterialPageRoute(...))`，照 `openHistory` 寫一個
  `openXxx(context)`，route 的內容包 `PageSurface`；頁頂用 `PageAppBar`（`lib/ui/shell/page_app_bar.dart`），下面還有頁時它自己放返回鈕（tooltip `shell.backTooltip`）。返回鍵、
  Esc、再點導覽項都由外殼處理，頁面不放 `PopScope`。要蓋住整個外殼的全螢幕頁用 `Navigator.of(context, rootNavigator: true)`
  （或 `rootNavigatorKeyProvider`）；`showDialog` 預設就在根上，`showModalBottomSheet` 預設不是（要蓋住外殼時給
  `useRootNavigator: true`）。新的全螢幕 route 進 `integration_test/toast_layering_test.dart`。例外：離開要確認的內頁（匯入預覽）自己放
  `PopScope`，見下面「匯入預覽」。
- 頁面讀「表一變動就重讀」的本機資料時（首頁的最近播放、音樂庫的歌單卡），provider 照 `recentPlaysProvider`：先訂閱
  repository 的 `changes()`、再讀一次，之後每次變動再讀（`async*` 依序讀，讀失敗以 `yield* Stream.error` 送出、之後照樣重讀）；
  讀失敗的 `log.report` 在頁面的 `ref.listen`（同電台頁），不在 build；外殼裡幾頁讀同一個 provider 時只由一頁報（首頁的歌單、電台區塊交給音樂庫與電台頁）。外殼裡的頁面一直掛著，不要對 join 了 `tracks` 的查詢用
  `watch()`：每寫一次曲目（每播一首）都會重查。
- 加一個 App 內快捷鍵（ADR 0024 §決定 8 的表）：
  1. 播放類：`playback_shortcuts.dart` 加一個 `Intent`、`playbackShortcuts` 的一列與
     `PlaybackShortcuts` 的 action（讀控制器放在 `onInvoke` 裡，建構時讀會在沒有後端的環境拋錯）；
     導覽類：`shell_shortcuts.dart` 加 `Intent` 與 `navigationShortcuts` 的一列，`AppShell` 的 `Actions`
     接上。
  2. 輸入框裡的規則一句話：導覽類（Esc、F6、Ctrl+F、Ctrl+,）有效，其餘讓給輸入框，所以播放類的 action
     用 `TextInputAwareAction`，焦點在輸入框時停用、交給輸入框；
  3. 有對應按鈕的，翻譯檔的 `*Tooltip` 字串寫上按鍵（`播放（空白鍵）`），按鈕的語意標籤
     （`Icon.semanticLabel`）不帶按鍵；
  4. `test/ui/shell/app_shell_test.dart` 的 `shortcuts` 群組加案例（`chord` 輔助函式按組合鍵），播放類
     另外在輸入框裡按一次確認沒作用、對話框開著時也沒作用。
  5. 播放頁（M2 PR 18a）是另一個 route，不在外殼的 `Shortcuts` 之下：自己包一層
     `PlaybackShortcuts`。新的全螢幕 route 或面板要讓播放鍵有效時照做（對話框不包：開著時播放鍵不作用）。
  6. 根 Navigator 上的頁要外殼做事（播放頁的 Ctrl+Q 切到佇列目的地）：照 `openQueueProvider`／`openAccountsProvider`，
     外殼在 `initState` 接上 handler、handler 先看 `mounted`；頁面先 `ref.read` 好、關掉自己、`await route.completed`
     再呼叫（排在 `openPlayerPage` 把焦點還給開它的元件之後，焦點才落在新的地方）。
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

- 篩選（ADR 0035，R5）：`historyFilterProvider`（音源、日期、搜尋文字、排序；autoDispose，頁面關掉就丟）一變，`historyProvider` 重建、從第一頁重讀；
  統計卡讀 `historyStatsProvider`（歷史表一變就重讀）。播放次數排序不分組（`PlayHistoryEntry.playCount`）。折疊的日子只存在頁面的 State。
  確認框用 `showDestructiveConfirm`（`lib/ui/dialogs/`，紅色確認鈕）。測試：「去搜尋」靠外殼接的 `openSearchProvider`，要 `pumpShell` 才有效。
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
- 一列的選單用 `TrackRowMenu`（`lib/ui/tracks/`，搜尋結果、歷史、佇列共用）：呼叫端給選單項目與 `builder`
  （把給的「⋯」放在列尾、`openMenu` 接長按），機制（`MenuAnchor`、`childFocusNode`、右鍵 `excludeFromSemantics`、
  「⋯」下方開）改一處。
- 測試：`h.pumpApp(tester, const HistoryPage())`（要外殼與離線橫幅就 `pumpShell` 後 `h.openHistory(tester)`：從音樂庫的「歷史」開）；寫歷史用
  `container.read(playHistoryRepositoryProvider).record(...)`，要包 `tester.runAsync`，之後 `h.loadSettings`
  讓變動的串流與重讀跑完。

## 歌單詳情與「加入歌單…」

規則與閘門見 `app/AGENTS.md` § 介面的「音樂庫」「歌單詳情」「加入歌單…」；ADR 0033 §決定 9、11，M4 design §10.4–§10.6。

- 曲目選單加「加入歌單…」：`AddToPlaylistItem(onPressed: () => unawaited(showAddToPlaylist(context, tracks)))`，`context` 用列自己的
  （`build` 的那一個，不是選單項目的）。要先取東西才知道加哪幾首的（搜尋的多分 P 影片）先 `await` 取好，再看 `context.mounted`。
- 歌單的封面一律用 `PlaylistCover(artwork: playlist.artwork, firstTrack: …)`，不要直接把 `playlist.artwork` 給 `ArtworkImage`：
  自訂封面不屬於曲目，要先以 `artworkPluginProvider` 找到網域包含它的插件，才有 cache manager。
- 畫面寫本機歌單的曲目時呼叫 `PlaylistService` 的 `addTracks`、`removeEntries`、`moveEntries`：它們拒絕不是本機的歌單
  （`playlist_service_test.dart` 的 `an imported playlist is refused…`），repository 那層只動指定歌單的項目；刷新器
  （`lib/library/`）寫匯入歌單是另一條路。
- 匯入與刷新的畫面端（`import_dialog.dart`、`manual_refresh.dart`，M4 PR 8b）：手動刷新一律經 `ref.read(manualRefreshProvider.notifier)(playlistId)`
  （卡片選單、詳情的「刷新」與狀態列的「重試」同一條）：它記著正在刷新的歌單 id（按鈕據此顯示進行中、不接受第二次）並負責提示
  （失敗而網路不是 `online` 寫離線字樣，其餘照 ADR 0013 的類別表，自動刷新不經這裡所以不跳 toast）。匯入對話框用
  `PlaylistImporter.importUrl(onProgress:, cancel:)` 顯示「已匯入 n／M 首」（`ImportProgress`），進行中不能關、只能取消。帳號匯入的全頁是 `account_import_page.dart`（`AccountImportRun` 跑、`AccountImportPage` 畫；測試 `account_import_page_test.dart`）。匯入成功後的詳情由呼叫端（音樂庫頁）開，
  因為對話框在根 Navigator 上、詳情要開在音樂庫的巢狀導覽裡。詳情的「登入」經 `openAccountsProvider`（外殼接上，換到設定頁的「帳號」區塊）。
- 測試匯入畫面：`ShellHarness(registryOfSources: true, sources: [FakeImportPlugin(...)])`（`test/library/fake_import_plugin.dart`）。
  介面上插件名稱由 harness 固定為 `Test Source`。進度條會一直轉，進行中的畫面不要 `pumpAndSettle`。
- 巢狀導覽的每一頁（外殼的根頁、`openPlaylist`、`openHistory`，之後新加的內頁也一樣）包 `PageSurface`（透明的 `Material` 加自己的
  `ScrollNotificationObserver`）：頁面轉場在頁外包有底色的 `ColoredBox`，頁面沒有自己的 Material 時 `ListTile` 的水波與底色畫在外殼的
  Material 上、被它蓋住，除錯版另有「ListTile background color or ink splashes may be invisible」的斷言（轉場中重建的 `ListTile` 才會觸發，
  例如匯入完成時音樂庫長出新卡片）；頁面不在自己的 `Scaffold` 裡，沒有自己的觀察者時 `PageAppBar` 聽的是外殼 `Scaffold` 的，側欄或別的頁一捲
  就變色。閘門：`app_shell_test.dart` 的 `every page of a nested navigator paints on its own Material`、`page_app_bar_test.dart` 的
  `only the page's own list scrolling under the bar tints it`。
- 詳情清單的列是 `groupParts` 排出來的（群組標題＋分 P），所以 `ReorderableListView` 的位置不是項目的位置：重排一律經
  `reorderedEntryIds`。多選的鍵同樣只取 `PlaylistEntryRow` 的項目 id，標題列不是項目。
- 測試：`ShellHarness` 開在音樂庫，`runAsync` 裡以 `playlistRepositoryProvider` 建歌單（匯入歌單用 `createImported`）與 `addTracks`，
  `loadSettings` 幾次讓重讀跑完再點卡片（`playlist_detail_page_test.dart` 的 `_open`）。對話框裡 `enterText` 之後先 `pump` 再按送出：
  按鈕的啟用狀態要重建一次才跟上（不 `pump` 的話按到的是停用的鈕，什麼都不發生）。測自訂封面向哪個插件要了什麼網址時，以
  `extraOverrides` 換掉 `artworkCacheManagerProvider`，並在每個測試開頭清 `imageCache`（跨測試留著，讀過的網址不會再問 cache manager；
  `playlist_cover_test.dart`）。測試插件 `fmp-test` 的允許網域是 `cdn.example`，`registryOfSources: true` 才在插件清單上。

## 匯入預覽

規則與閘門見 `app/AGENTS.md` § 音樂庫的「外部匯入」與 § 介面的「匯入預覽」；M4 design §8.4、§10.9。

- 頁面不呼叫插件：一頁一個 `ExternalImport`（`externalImportsProvider.open`），State `addListener` 它、整頁重畫，`dispose` 時一起 `dispose`
  （之後回來的搜尋結果丟掉）。`await` 之後先看 `mounted`；頁面已經拆了才開好的那一個當場 `dispose`。
- **這一頁有自己的 `PopScope`**（外殼「頁面不放 `PopScope`」的例外：離開要確認）。外殼的返回鍵與 Esc 走 `maybePop`、再點導覽項停在
  `doNotPop` 而且不是根頁的 route 才 `maybePop`（停在根頁不動，根頁的多選才留得住），所以三條路都到它。`canPop` 只在建立中或
  `ExternalImport.touched` 時為假：沒有要丟的東西就直接離開；建立中攔下但不開確認框。確認後先設 `_leaving`（`canPop` 變真）再 `pop`。建好歌單以
  `openPlaylist(replace: true)` 換頁，`pushReplacement` 不經 `PopScope`。新的「離開要確認」的內頁照這個寫，不要另外攔導覽列。
- 讀完之後整頁是一個 `CustomScrollView`（標頭與摘要是 `SliverToBoxAdapter`，清單是 `SliverList.builder`），只有底部列固定：要一直看得到的（進度、
  建立鈕）放底部列，不要放標頭。測試捲動找 `CustomScrollView`。
- 測「建立中」：在 `runAsync` 外開一個佔著資料庫的 `transaction`（`await` 一個 `Completer`），建立的寫入就排在它後面（`import_preview_test.dart` 的
  `while the playlist is being created…`）。
- 展開區放 `RadioListTile` 就要包 `Material(color:)`，不能用 `Container(color:)`（ListTile 的水波畫在最近的 Material 上，除錯版會斷言）。
- 測試用 `test/ui/library/import_preview_harness.dart` 的 `PreviewHarness`：來源是僅元資料的 `FakeImportPlugin`（`Test Source`），目標是能搜能播的
  `video`；`open` 開在音樂庫並讀完、`start` 開始匹配。匹配與建立都在假時間裡跑，`settle` 以 `runAsync` 與 `pump` 輪流推進；有一首一直在搜時
  進度圈在轉，給 `animations: false`。

## 設定頁「音樂庫」

- 「首頁排行」讀被動的 `chartCatalogProvider`；「匹配目標音源」讀 `matchTargetOptionsProvider`，**會把插件清單拉起來**：只在使用者點進這一區時才建，
  所以沒事。別的、一直掛在外殼裡的頁面不要 watch 它（理由見「多選」的搜尋頁前例與「首頁排行與探索頁」）。
- 兩個清單的寫法一樣（`ReorderableListView` 的 `shrinkWrap`、樂觀排序、`identical(_pendingOrder, order)` 才退回）：再加一個同類的清單就照抄，
  不要抽共用元件（兩份的值型別與 repository 不同）。測試找某一個清單的勾選框時以 `find.descendant(of: find.byType(MatchTargetSettings))` 限定範圍。

## 多選

規則與閘門見 `app/AGENTS.md` § 介面的「多選」；ADR 0033 §決定 10，M4 design §10.7。

- 給一頁加多選：頁面的 State 建一個 `TrackSelection<K>`（dispose 時一起），整頁（標題列與清單）包 `TrackSelectionScope(selection:, keys:)`，
  `keys` 是畫面上可選的列、依畫面順序（全選與 Shift 範圍照它，不在裡面的不再算選了）；標題列包 `TrackSelectionBar(tracks:, actions:, child: 原本的標題列)`；
  每列用 `SelectableTrackRow(selectionKey:, menuChildren:, builder:)` 取代 `TrackRowMenu`，`builder` 的 `ListTile` 用 `row.selected`、
  `row.trailing`（「⋯」或勾選框）、`row.onTap ?? 自己的點擊`、`row.onLongPress`，選取模式裡拿掉把手之類的（`row.selecting`）。
- 選取列放不下時（手機）只留取消、數字、全選，其餘動作依序收進尾端「⋯」；新增動作加進 `_TrackSelectionBarState.build` 的 `collapsible` 清單即可，不要另外塞進 `Row`。
- 鍵要在「結果換成新的一份」時失效：位置當鍵的（搜尋）自己在換結果時 `selection.exit()`（`ref.listen`），id 當鍵的靠 `keys` 自動剔除。
- `tracks` 回已選的曲目（依畫面順序）；要先取東西的在裡面取，取不到時自己提示並回 `null`。頁面自己的動作是 `TrackSelectionAction`
  （回 `true` 才離開選取模式）；PR 14 的遠端動作、PR 21 的探索都照這個接，沒有改共用元件。
- 返回鍵與 Esc 不要另放 `PopScope`：`TrackSelectionScope` 在 route 上放 `LocalHistoryEntry`，外殼原本的「退出內頁」先移除它。
- `SelectableTrackRow` 不在 scope 底下時（`ReorderableListView` 拖著走的那一列在 Overlay 裡）畫成沒有「選取」的普通列。
- 一直掛在外殼裡的頁面（搜尋）算 `keys` 時不要無條件 `watch` 整份插件清單：測試裡在假時間開始的讀取會擋住 `runAsync` 裡的寫入
  （drift 的鎖），整個 `import_ui_test.dart` 會卡到逾時。只對需要的列 `select`。
- 測試：長按一列進入（`tester.longPress`），Esc 與返回鍵要在外殼裡（`pumpShell`、`h.openHistory`）；Shift 範圍以
  `sendKeyDownEvent(shiftLeft)`、點、`sendKeyUpEvent`；機制本身的案例在 `test/ui/tracks/track_selection_test.dart` 的 `_ListPage`。

## 首頁排行與探索頁

規則與閘門見 `app/AGENTS.md` § 排行與 § 介面的「首頁的排行」「探索頁」。

- 畫面只讀 `enabledChartsProvider`／`chartEntriesProvider`（榜單）與 `chartContentProvider`、`chartFailuresProvider`（內容與失敗）、`networkProvider`（刷新間隔關閉時不轉圈、說明怎麼手動載入），不呼叫插件；刷新只經 `ChartJobs.runNow`。
  「沒有快取、在線、沒失敗、間隔沒關」才轉圈：通常有一次執行要來（`ChartJobs` 登記時發現沒有快取就 `dueNow`）。例外（見 `.trellis/tasks/archive/2026-10/10-15-m4-library-sync/implement.md` 的「PR 21 → 之後」）：
  執行中途才被淘汰的快取（不重新登記）、插件更新後 `chartList` 丟錯而沿用舊清單（登記時不知道啟用哪些榜單，不帶 `dueNow`）、停用後立刻啟用的競態；這些情況會轉到下一輪。
  新的「沒有內容」狀態要先確定有人會讓它結束，不然 `pumpAndSettle` 與使用者都會等到下一輪。
  畫面不要 watch `pluginRegistryProvider` 或 `chartJobsProvider` 來找榜單。正式環境裡兩者本來就常駐（`searchSourcesProvider` 就是插件清單、`FmpApp` 聽著排行工作），
  問題在測試：多數外殼測試 override 了 `searchSourcesProvider`，一直掛著的首頁一旦把插件清單拉起來，假時間裡開始的讀取拿著 drift 的鎖、擋住 `runAsync` 的寫入（同上面「多選」記的
  搜尋頁前例），watch 排行工作則把它與排程器在每個外殼測試裡拉起來。細節見 `app/AGENTS.md` § 排行。
- 測試用 `test/ui/charts/chart_harness.dart` 的 `ChartHarness`：插件清單上一個 `FakeChartPlugin`、記憶體的排行快取，排程器與排行工作照 App 常駐（harness 自己 listen；畫面不會把它們拉起來；沒有快取時工作一開始就跑）。
  首頁在監看 `chart_settings`：種資料一律在假時間裡直接 `await`（不包 `runAsync`，同電台）；`setOrder` 這種 batch 寫入要真的事件迴圈與假時間輪流推進才寫完，用 `settleUntil`。
  載入中的進度圈一直在轉，不用 `pumpAndSettle`（`settle`）。要在開外殼前就有的資料（刷新間隔關閉：`chartsOffDatabase`，`ChartHarness(database:)`）在開外殼前以 `runAsync` 寫進資料庫：
  那時還沒有人監看，不會撞鎖；開了之後才寫，排行工作已經跑過一次。讓快取一直是空的用 `hangCharts`；「沒有提供排行的插件」用 `ChartHarness(declaresCharts: false)`
  （排行工作真的跑過、清單是空的），不要用沒有排行工作的 `ShellHarness`：那時清單一直是 `null`，什麼都沒驗到。

## 播放頁

規則與閘門見 `app/AGENTS.md` § 介面的「播放頁」；design §9.3、§9.5、§9.6。

- 檔案：`player_page.dart`（route 與上滑轉場、開關、三種版面、詳細面板）、`player_top_bar.dart`（頂列與「⋯」速度選單）、`audio_controls.dart`（`OutputDeviceButton`、`MuteButton`、`VolumeSlider`，播放列共用）、`player_controls.dart`（播放列與播放頁
  共用：`ShuffleButton`、`LoopButton`、`PreviousButton`、`NextButton`、`PlayPauseButton`、`ProgressRow`、`IconMenu`、
  `playbackStatusLabel`）、`track_details.dart`。播放列新加共用的控制時放 `player_controls.dart`，
  兩邊都會有。
- 開頁一律 `openPlayerPage(context, opener: …)`（不自己 `Navigator.push`）：它設 `playerPageOpenProvider`（外殼靠它改
  提示的位移）、已開著就不推、關閉後把焦點還給 `opener`。給開它的元件一個 `FocusNode`（見播放列的 `_OpenPlayerArea`）。
- 加一個頁內快捷鍵：在 `PlayerPage` 的 `Actions` 加（導覽類）或 `playbackShortcuts` 加一列、`PlaybackShortcuts` 接
  action（播放類）；輸入框規則同外殼。Ctrl+L 外殼接開頁、頁面不接（歌詞 M7 才做）；Ctrl+Q 外殼接切到佇列目的地、
  頁面接「關掉自己再請外殼切過去」（`openQueueProvider`）。
- 加一個頁內焦點區：`FocusScopeNode` 放進 `_PlayerPageState`、包 `FocusScope`＋`FocusTraversalGroup`、列進 `regions`（目前是控制區與開著時的詳細面板）；
  區裡要至少有一個可聚焦的東西，否則 F6 跳過它。
- 版面由頁面的 `LayoutBuilder` 量到的整個視窗寬高決定（`resolvePlayerLayout`，不是 `WindowClass`），測試與 golden 因此只要給頁面該有的限制。窄版／矮版的資訊是 `DraggableScrollableSheet`：
  捲動控制器要交給裡面的捲動元件（`TrackDetails(scrollController:)`），拖曳才跟內容連在一起；M7 的歌詞放進 `_WideContent.lyrics`，窄版的封面／歌詞切換也在那時回來。
- 播放頁的控制區沒有底板、沒有毛玻璃（ADR 0035 §決定 3）；背景是模糊的封面加 `surface` 遮罩，數值在 `AppLayout`。新的文字放在背景上時，淺色、深色 ×
  最淺、最深的封面都要過 guideline（`guidelines_test.dart` 的 `the player page over …`）：次要文字用
  `onSurfaceVariant` 在深色封面上會不夠對比，遮罩用主題的 `surface` 就是為了這個。
- 佇列（M2 PR 18b；ADR 0035 起是導覽目的地，`lib/ui/queue/`）：`QueuePage` 是佇列目的地的根頁，沒選到時（`visible` 為假）
  不建清單，所以每次切過來都從目前這首附近開始；佇列空時是空狀態，否則是整頁的 `QueueView`。改清單時：列的鍵是佇列
  項目的實例（`ObjectKey`），所以編輯不能換掉既有項目的實例（`QueueModel` 的編輯本來就沿用）；拖曳只經把手，放下用
  `onReorderItem`（`newIndex` 已調整），呼叫 `PlaybackController.move`；選單項目加在 `_QueueRow`。要在 widget
  被拆掉之後還用的東西（清空後佇列頁換成空狀態）要在 `await` 之前先 `ref.read` 好，像 `_clear`。切歌時自動捲動讀
  `playbackPreferencesProvider` 的 `autoScrollToCurrent`，比的是目前項目的實例，不是位置。測試切到佇列用 `h.openQueue(tester)`。
- 測試：`h.play(…)` 後點播放列的曲名開頁（`player_page_test.dart` 的 `_openByTap`）；要封面用
  `ShellHarness(artworkManager: FakeArtworkManager())` 與 `TestArtwork.lightest／darkest`
  （`test/ui/support/fake_artwork.dart`）；輸出裝置與音量的頂列用 `ShellHarness(outputDeviceSelection: true, outputDevices: FakeOutputDevices(...))`。golden 在 `player_page_golden_test.dart`，播放頁讀的 provider 在那裡 override。

## 右側「正在播放」面板

規則與閘門見 `app/AGENTS.md` § 介面的「右側『正在播放』面板」；design §9.4。

- 面板的展開與寬度讀 `panelExpandedProvider`、`panelStoredWidthProvider`（`lib/ui/layout/layout_state.dart`，
  與 `layoutStateProvider` 同檔），寫一律 `rememberPanel(ref, expanded:/width:)`（失敗只記 log）；要等寫入結果時用
  `savePanel`（回 `bool`）。新的開關入口只呼叫 `rememberPanel(ref, expanded: !現在)`。
- 畫面上的寬度只經 `panelWidthFor`（夾取在那裡，數值在 `AppLayout`）；元件本身（`NowPlayingPanelSide`）在 build 裡
  讀視窗寬度（`MediaQuery`）與整個視窗的 `WindowClass`，所以要放在頁面的 `WindowClassScope` 之外。
- 面板加進外殼內容區時結構不能隨有無面板而變（`if (hasPanel)` 放在 `Row` 的子項，不要換包法），否則視窗跨過 840
  時頁面的 State 會丟。內容區的焦點順序靠 `FocusTraversalOrder`（頁面 0、面板 1）。
- 面板只在有東西在播時放（`hasPanel = hasNowPlayingPanel(windowClass) && hasTrack`），所以測面板的測試要先 `h.play(...)`
  （`now_playing_panel_test.dart` 的 `_pumpPlaying`）；開關鈕在播放列第三段，播放列橫跨整個視窗，沒有別的參數要給。
- 面板的詳細最後的區塊（「下一首」）經 `TrackDetails(footer:)` 放，播放頁的詳細面板不給；要讀下一首用 `QueueState.upNext`，
  不自己從 `entries` 與 `shuffleOrder` 推。
- 測試：`h.pumpShell(tester, collapsePanel: true)` 把面板收起（測頁面本身在內容區寬度下的版面時用）；找把手用
  `Tooltip` 的 `message`（名稱在 `Semantics`，`find.byTooltip` 找不到）；拖曳用 `TestGesture`（把手用
  `DragStartBehavior.down`，位移就是寬度變化）；寫入次數用 `tableUpdates` 的通知數（`now_playing_panel_test.dart` 的
  `_countWrites`）；資料庫要真的事件迴圈（`_store`、`_stored` 包 `runAsync`），寫入加 stream 回來要兩次 `loadSettings`。

## Debug 頁

- 診斷包與 log 匯出（`debug_export.dart`，M3 PR 15）：UI 只呼叫 `exportBundle(context, ref, kind:, action:)` 與 `copyDiagnosticsSummary(ref)`；組裝、zip、暫存都在 `lib/app/diagnostics/`（規則與閘門見 `app/AGENTS.md` § 診斷包）。第一次匯出前的「送出前請檢查」用共用的 `confirmSubmitReminder(context, ref, body:)`（`lib/ui/errors/submit_reminder.dart`），與 GitHub 回報同一個「不再提醒」設定；新增要把內容送出裝置的動作時也走它。按鈕依 `capabilities.files`／`shareFiles` 出現，不寫平台判斷。widget 測試的 zip 在另一個 isolate 壓，要等真實時間：用 `settleUntil`（輪詢條件），不要固定 `pump` 幾次。

規則與閘門見 `app/AGENTS.md` § 介面的「Debug 頁」；ADR 0025 §決定 1、2，M3 design §12.1。

- 加一個區塊：`DebugSection` 依 ADR 0025 §決定 2 表上的順序加一個值與圖示，`_name` 與 `_body` 的
  `detail` 兩個 `switch` 會指出要補的地方（名稱放 `debug.*`，三個語言）；區塊的 widget 放 `lib/ui/debug/`。只在某些平台有的
  區塊（插件開發）讀 `platformCapabilitiesProvider` 決定列不列出。新的區塊加進 guideline 測試的 `the Debug overview at …` 旁邊。
- 播放狀態與資料庫區塊（PR 14a）：資料來自 `playbackDiagnosticsProvider`（播放層組好的快照）與 `databaseInspectorProvider`
  （資料層的唯讀查詢），widget 不自己查 drift、不讀控制器的私有狀態。可選取的文字（`SelectableText`）在 guideline 測試會因
  點擊目標小於 48 而紅：表格的格子用 `Text`。測試在 `test/ui/debug/debug_playback_database_test.dart`；`ShellHarness` 要給
  `redactor:`（資料庫與播放快照都要遮蔽函式）。
- 區塊內容放在 `detail` 那個捲動的欄裡；自己有捲動清單的區塊（Log、網路）照設定頁 `filling` 的寫法填滿高度（`DebugPage` 的
  `filling`）。這類區塊的狀態：記憶體歷史讀 `logHistoryProvider`（不要自己監聽 `Log.changes`），篩選條件放在 widget 的 State；
  資料轉換與篩選寫成 `debug_*_state.dart` 裡的純函數，單元測試直接測。
- Log／網路區塊的測試在 `test/ui/debug/debug_log_network_test.dart`：`ShellHarness(log: …)` 可以換成有 `LogFile` 的門面。log 檔的
  操作從畫面發起時（清除、含之前的紀錄），後續落在假時間的微任務裡，要用該檔的 `settleIo`（交替等真實時間與 `pump`）；直接
  `await log.file!.flush()` 會卡死，要在 `tester.runAsync` 裡寫入再 flush。
- 要離開 Debug 頁去設定頁的某一組時，照概覽的快取用量：先 `Navigator.pop` 這一頁，再呼叫設定頁給的 callback（它經外殼的
  `SettingsBack.show` 選組，Debug 頁開著期間設定頁換位置重建也找得到）。
- 測試：`ShellHarness(flavor: …, buildLogLevel: …)`（dev 的開發者模式預設開；要關著用 `AppFlavor.prod`，或先寫
  `developerSettingsRepositoryProvider`；建置模式預設固定為 release 的 info，要看 debug build 給 `LogLevelSetting.debug`），
  開設定頁後點清單的「Debug」列；Debug 頁看整個視窗的寬度（不受面板影響）。概覽讀的 `appInfoProvider`、`dataDirectoryProvider`
  由 harness 給（家目錄 `/home/tester`）。提示會去重 5 秒：測「離開後重新計數」這類同一則提示要再出現的，先 `pump` 過 6 秒。

## 插件頁

規則與閘門見 `app/AGENTS.md` § 介面的「插件頁」；ADR 0030 §決定 6–11。

- 設定頁加一個不是設定組的區塊：`SettingsSection` 加一個值與它的名稱，`detail` 的 `switch` 決定它要不要包在捲動的欄裡
  （自己有捲動清單的像插件頁就不包，填滿剩下的高度）。
- 設定頁「備份與還原」（`SettingsSection.backup`）：UI 只呼叫 `AppBackup`（匯出、選檔並驗證）與 `DataReset`（還原後半），確認與執行共用 `lib/ui/backup/restore_flow.dart` 的 `confirmAndRestore`（Debug 頁的還原也走它）；進行中蓋全螢幕的進度用 `runBlocking`。規則與閘門見 `app/AGENTS.md` § 介面的「備份與還原」。
- 插件頁的動作照 `_install` 的寫法：provider 在第一個 `await` 之前讀好；等網路或資料庫的那段包 `_work`（進度條、其他
  動作停用），對話框不包；`await` 之後先看 `mounted` 再碰 `ref` 或開下一個對話框。失敗用 `_failed`（`Toaster.error` 加一句
  「無法…：原因」），預期內的拒絕用 `_rejected`。
- 加一個能力：`capabilityName` 的 `switch` 會指出要加的字串（`plugins.capabilityNames.<能力>`，三個語言）。
- 測試用 `PluginPageHarness`（`test/ui/support/plugin_page_harness.dart`）：外殼的 `ShellHarness` 加上同一個資料庫上的真插件
  載入器（QuickJS）、查表的假下載（`publish` 放一份 index 與它的 `.js`，SHA 照內容算；沒列的網址是 `NetworkError`）、
  假的檔案對話框。以 `await PluginPageHarness.create(tester)` 建立：它在假時間 zone 裡先 `pump` 一次，讓
  `CredentialStore` 一建立就開始的資料庫載入跑完，否則之後 `runAsync` 裡的寫入排在它後面、永遠等不到 drift 的鎖。插件以 `install` 直接寫進資料庫（包 `tester.runAsync`），開頁後 `settle`（真的事件迴圈加 `pump`，背景
  isolate 與 drift 都要它）；按鈕用 `find.bySubtype<ButtonStyleButton>()` 找（`widgetWithText` 只認確切型別）。沒有回應的
  插件以 `UnresponsivePlugin` 經 `PluginRegistry.register` 換上去，不跑真的看門狗。

## 首次啟動引導

規則與閘門見 `app/AGENTS.md` § 介面的「首次啟動引導」；ADR 0030 §決定 12。

- 引導是搜尋頁在 `showOnboarding` 為真時換上的內容區（`PluginOnboarding`）；狀態在 `onboardingProvider`（`working`、
  `failures`、`dismissed`）。安裝流程在 `_install`，照插件頁的寫法：provider 在第一個 `await` 之前讀好；因為 `working`
  讓引導留到整批結束，流程中途 State 不會被拆掉，但開對話框前仍看 `mounted`。
- 列用 `PluginHeading`、`PluginTag`（`plugin_widgets.dart`，與插件頁共用）；多個插件的確認用 `confirmInstallAll`，單一插件的
  `confirmInstall` 不動。
- 測試：`PluginPageHarness.create(tester, registrySources: true)`（搜尋的音源讀真的插件清單，不是 `ShellHarness` 的假插件），
  `h.publish([...])` 放官方 index，`h.shell.pumpShell`。`working` 時進度條一直在動，`pumpAndSettle` 不會結束：用
  `h.settle` 加 `pump(Duration)`。全部裝好時的成功提示會蓋住頁面底部，之後要點底部的東西先 `pump` 過它的時間（有失敗時不跳）。
  按「安裝」會重讀 index：要測「插件庫修好之後再按一次」就在按之前重新 `h.publish`。

## 帳號頁

規則與閘門見 `app/AGENTS.md` § 介面的「帳號頁」；ADR 0029 §決定 8，M3 design §6.7。

- 卡片清單讀 `loginPluginsProvider`（資料庫的已安裝清單篩出已啟用、宣告 `login` 的），每張卡讀
  `accountViewProvider(pluginId)`（`CredentialStore.changes` 與 `source_settings` 變動就重讀）。動作照插件頁的寫法
  （`_work`、`_failed`、`mounted`）；要插件本身（登入）時才 `ref.read(pluginRegistryProvider.future)`。
- 三種登入方式都接上了（M3 PR 9）。加新的一種時：`LoginMethod` 加值，`availableLoginMethods`、`_AccountCard` 的按鈕與
  `_login` 的 `switch` 會指出要補的地方。QR 與貼上 cookie 在對話框裡驗證寫入、回 `Account`；網頁登入的頁面只交回
  cookie，關頁後 `_login` 才 `AccountService.login`（包 `_work`，State 不在了就不包）。
- 失效提示在外殼：`AppShell` 聽 `accountInvalidationsProvider`，`Toaster.credentialInvalidated` 附「登入」動作（`_openAccounts`：
  換到設定頁、選帳號區塊）；它佔住 `CredentialInvalid`＋音源的錯誤去重鍵，接著從搜尋、播放送來的同一個失敗不再換掉它，呼叫端
  照常 `Toaster.error`、不必另外判斷。事件類別 `AccountInvalidated` 刻意不定義 `==`，同一插件失效、重新登入、再失效才都會通知。測試造失效用
  `harness.plugins.guard.run(...)` 丟 `CredentialInvalid`；外殼的測試環境只認得它自己的測試音源名稱，提示裡的音源名稱要
  `overrides: [pluginNameProvider('<id>').overrideWithValue('<名稱>')]`。最後刷新那行的測試給 `_signIn(lastRefreshAt:, lastRefreshResult:)`。
  從搜尋或播放造失效：`PluginPageHarness.create(tester, onSearch:)`、`h.shell.plugin.respond` 經 `h.plugins.guard.run` 丟
  `CredentialInvalid`（`a rejected credential during a user action`）。
- 測試用 `PluginPageHarness.create(tester)`（平台預設宣告有 secure storage；`secureStorage: false` 測沒有的平台），插件以
  `pluginScript(..., login: {...})` 或 `testPluginFile` 寫進資料庫。造已登入的狀態在假時間 zone 呼叫
  `h.plugins.credentials.save(...)` 再 `pump`（不要包 `runAsync`，理由見插件頁那一節）。QR 對話框的輪詢是假計時器：
  `pump(2 秒)` 後 `h.settle` 讓插件的回覆回來；對話框關閉還要 `pump` 過它的動畫。
  網頁登入：`PluginPageHarness.create(tester, loginWebView: FakeLoginWebView())`（`test/support/fake_login_webview.dart`；
  平台就宣告 `loginWebView`），插件的 manifest 要有 `login.webView`。假 WebView 的 cookie 以主機名稱存（`setCookies`），
  `loadPage()` 模擬一頁載入完成；頁面載入中的進度條一直在動，不用 `pumpAndSettle`，按按鈕後先 `h.settle`（等插件清單）
  再 `pump`。卡住的計時直接 `pump(webLoginStuckAfter)`。`CredentialStore` 的 `unreadable`
  不好造，以 `overrides: [accountViewProvider(id).overrideWith(...)]` 給畫面看的狀態。

## 電台頁與直播

規則與閘門見 `app/AGENTS.md` § 介面的「電台頁」「搜尋頁的直播間模式」「直播版」；ADR 0031 §決定 3–5、7。

- 判斷「有沒有在播」一律用 `hasNowPlaying(queue)`，不要再寫 `queue.current != null`：直播時 `current` 是 `null`，那樣寫的元件
  （播放列、播放頁的自動關閉、外殼的 Ctrl+L）會在直播時消失或自己關掉。直播的內容讀 `nowPlayingLiveProvider`。
- 新的直播狀態：階段（`LivePhase`）加在 `LiveBadge` 的 `switch`，播放狀態（重連、停止、失敗）加在 `liveStatusLabel`；兩個都是
  exhaustive，編譯器會指出。只對佇列有意義的新播放鍵用 `_QueueAction` 包（直播時接下、不做事）。
- 一列「標記＋主播」用 `TaggedLine`（`Wrap`：放不下時主播換行、兩者都省略不撐破列）。不要改成 `Text.rich` 的
  `WidgetSpan`：那裡面的字不在 guideline 的對比度檢查範圍內（變異驗證時把標記的字改成看不清楚，guideline 照樣綠）。
- 測試：`ShellHarness(live: true)` 讓測試插件宣告 `live`（`onLiveSearch`、`onLiveStatus`、`onResolveLive`、`onLiveRoomFromUrl`
  給回應）；電台要向插件清單要插件時另給 `registryOfSources: true`。`h.liveInfoJob` 是控制器登記的 `live-info`，呼叫它當作排程器
  到期（人數、標題更新）。
- 電台頁在外殼的 `IndexedStack` 裡一直監看 `radio_stations`，所以**種資料要在假時間裡直接 `await`**（記憶體資料庫只靠微任務）；
  包在 `runAsync` 裡的交易等不到假時間裡那個查詢放開的鎖，測試會卡到逾時。寫好之後才 `listen` `backgroundSchedulerProvider` 與
  `radioStatusJobsProvider`（App 裡是 `FmpApp` 常駐它們，手動刷新要它們）；之後讀資料庫看 `radioStationsProvider` 的值，不在
  `runAsync` 裡查。見 `test/ui/radio/radio_page_test.dart` 的 `_openRadio`。
- 直播播放中進度一直在走（已收聽時間），`pumpAndSettle` 等不到靜止：用 `pump(Duration)`。

## 播放列與封面

- 開始播放與加入佇列都直接呼叫 `PlaybackController`（`playTemporary`、`playNext`、`addToQueue`，
  曲目是 `TrackSummary.toTrackInfo()`）。播放列讀 `QueueState.current`（`TrackInfo`）的顯示資料。
- 一首曲目的選單：用 `TrackRowMenu`（右鍵在點的位置開、長按與尾端「⋯」在「⋯」下方開，三處同一份選單；
  「⋯」的 `FocusNode` 同時是 `MenuAnchor` 的 `childFocusNode`，Esc 才關得掉以滑鼠開的選單）。加入成功以
  `toaster.success` 回饋，被上限拒絕的提示由外殼接 `QueueFull`。
- 控制器的事件（`playbackEventsProvider`：佇列滿、跳過、停下、試聽）只在外殼的
  `_onPlaybackEvent` 轉成提示；頁面不另外聽。新的事件類型加在那個 `switch`（編譯器會指出），
  並在 `app_shell_test.dart` 的 `playback toasts` 群組加一例。
- 播放列曲名下那一行的狀態標示（重試中、等待網路連線、試聽）由 `PlayerBar` 從
  `playbackStateProvider`、`playbackPreviewProvider` 推出；新的標示加在同一個 `switch`，並在
  `player_bar_test.dart` 的 `status labels` 三個寬度各加一例。
- 播放列的進度是頂端的細線（`ThinProgressBar`，ADR 0035 §決定 4）：位置與時長的判斷與播放頁共用 `watchProgressView`，改了 `Idle` 時的規則就兩邊一起變。
  細線上沒有文字，時間只在滑鼠移入或拖曳時浮在把手上方（「位置 / 時長」），平時只在語意裡：測試讀 `player_bar_test.dart` 的 `progressValue`
  （要 `tester.ensureSemantics()`）與 `hoverBar`（滑鼠移到播放列上，再各 `pump` 一幀開始動畫、一幀走完）、點與拖用 `onThinBar(fraction)`。
  單獨測播放列時放在 `Column(mainAxisSize: min)` 裡（`pumpBar`）：直接放在 `Align` 裡，`Row` 裡的 `Align` 會把播放列撐成整個視窗高，
  頂端的細線與「滑鼠在播放列外」都不是真實情況。
- 播放列點曲名與封面那一塊開播放頁（`_OpenPlayerArea`，測試點曲名文字）；播放列的控制項照 ADR 0024 §決定 5 的三段；加功能時同時改 `player_bar_test.dart` 的
  `controls per width`（有宣告與沒宣告輸出裝置兩組）與 golden。golden 沒有真的控制器：播放列新讀的
  provider（音量、輸出裝置、`outputDeviceSelectionProvider`）要在 golden 的 `ProviderScope` override。
- 只有圖示的 `IconButton`：tooltip 當名稱（有快捷鍵就附上，翻譯檔的 `*Tooltip`），`Icon` 不給
  `semanticLabel`，否則輔助技術念成「X. X」。要把控制器的值放進畫面時，先看控制器有沒有發出它的
  stream（音量、輸出裝置經 `playbackVolumeProvider`、`playbackOutputDevicesProvider`），沒有就先讓
  控制器發，不從畫面讀它的私有狀態。
- 輸出裝置與音量的選單／彈出滑桿用 `MenuAnchor`：Esc 與點外面都由它關。Esc 只在焦點在 anchor 或選單裡
  時到得了它，所以給 `childFocusNode`，同一個 `FocusNode` 給打開它的按鈕（播放列的 `_IconMenu`；搜尋、歷史
  的「⋯」照同樣寫）；彈出的滑桿另外 `autofocus`。選單項目的內容在 widget 裡要用到控制器時，在
  `onPressed` 裡才 `ref.read`。
- 封面用 `ArtworkImage(pluginId: 曲目鍵的第一段, artwork: TrackInfo.artwork, size: …)`：`pickArtwork`（`lib/domain/track_info.dart`，系統媒體控制的封面也用它）挑一張、
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
  介面。`pumpShell` 開整個外殼（再點 `at` 的導覽項，預設搜尋；App 本身開在首頁，要測首頁給 `at: ShellDestination.home`），
  `open` 點導覽項（`navigationItem` 是它的 finder），`pumpApp` 開單一個 widget，`play` 直接開始播。
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
