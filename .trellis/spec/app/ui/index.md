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
  empty_state/         # EmptyState：置中的圖示、標題、說明與動作
  offline/             # OfflineBanner（外殼）、OfflineMessage（頁面的離線空狀態）
  toast/               # Toaster、ToastHost；fmp_toast_entry 的允許目錄
  shell/               # AppShell（導覽、內容、播放列三區）、導覽類快捷鍵表、PlaybackShortcuts（播放類快捷鍵表）、
                       # now_playing_panel（右側面板、把手、面板寬度規則）
  search/              # 搜尋頁、searchProvider、音源 chip 列
  history/             # 歷史頁（播放歷史，分頁讀、依日分組）、historyProvider
  settings/            # 設定頁（分組、list-detail）與外觀、網路的控制項
  player/              # 播放列（讀佇列項目的 TrackInfo；隨機、循環、medium 的「⋯」）、播放頁、
                       # 兩者共用的控制（player_controls）、毛玻璃面板、TrackDetails、
                       # 可編輯的佇列（QueueView：分頁與底部面板共用）
  artwork/             # 封面縮圖（CachedNetworkImage）；cached_network_image 只准在這裡
  tracks/              # TrackRowMenu：搜尋結果、歷史、佇列的一列曲目共用的選單（右鍵、長按、「⋯」）
  plugins/             # pluginNameProvider；插件頁（plugins_page）、它讀的 provider（plugins_state）、
                       # 確認與網址對話框（plugin_dialogs）、能力名稱與來源的文字（plugin_text）、
                       # 插件列的共用元件（plugin_widgets）、搜尋頁的首次啟動引導（plugin_onboarding）
  accounts/            # 設定頁的帳號頁（accounts_section）、它讀的 provider 與登入方式的交集（accounts_state）、
                       # QR 登入對話框（qr_login_dialog）；qr_flutter 只准在這裡；網頁登入的全螢幕頁
                       # （web_login_page）、貼上 cookie 的對話框（cookie_login_dialog）
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
  5. 播放頁（M2 PR 18a）與佇列的底部面板（PR 18b）各是另一個 route，不在外殼的 `Shortcuts` 之下：各自包一層
     `PlaybackShortcuts`。新的全螢幕 route 或面板要讓播放鍵有效時照做（對話框不包：開著時播放鍵不作用）。
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
- 一列的選單用 `TrackRowMenu`（`lib/ui/tracks/`，搜尋結果、歷史、佇列共用）：呼叫端給選單項目與 `builder`
  （把給的「⋯」放在列尾、`openMenu` 接長按），機制（`MenuAnchor`、`childFocusNode`、右鍵 `excludeFromSemantics`、
  「⋯」下方開）改一處。
- 測試：`h.pumpApp(tester, const HistoryPage())`（要離線橫幅就 `pumpShell` 後點「History」）；寫歷史用
  `container.read(playHistoryRepositoryProvider).record(...)`，要包 `tester.runAsync`，之後 `h.loadSettings`
  讓變動的串流與重讀跑完。

## 播放頁

規則與閘門見 `app/AGENTS.md` § 介面的「播放頁」；design §9.3、§9.5、§9.6。

- 檔案：`player_page.dart`（route、開關、版面、分頁、佇列清單、速度選單）、`player_controls.dart`（播放列與播放頁
  共用：`ShuffleButton`、`LoopButton`、`PreviousButton`、`NextButton`、`PlayPauseButton`、`ProgressRow`、`IconMenu`、
  `playbackStatusLabel`）、`glass_panel.dart`、`track_details.dart`。播放列新加共用的控制時放 `player_controls.dart`，
  兩邊都會有。
- 開頁一律 `openPlayerPage(context, opener: …)`（不自己 `Navigator.push`）：它設 `playerPageOpenProvider`（外殼靠它改
  提示的位移）、已開著就不推、關閉後把焦點還給 `opener`。給開它的元件一個 `FocusNode`（見播放列的 `_OpenPlayerArea`）。
- 加一個頁內快捷鍵：在 `PlayerPage` 的 `Actions` 加（導覽類）或 `playbackShortcuts` 加一列、`PlaybackShortcuts` 接
  action（播放類）；輸入框規則同外殼。要開頁的鍵（Ctrl+L、Ctrl+Q）外殼接開頁、頁面接切分頁，兩邊各一個 action。
- 加一個頁內焦點區：`FocusScopeNode` 放進 `_PlayerPageState`、包 `FocusScope`＋`FocusTraversalGroup`、列進 `regions`；
  區裡要至少有一個可聚焦的東西（歌詞欄用 `Focus(focusNode:)` 當目標），否則 F6 跳過它。
- 毛玻璃只用 `GlassPanel`；數值（不透明度、模糊半徑、遮罩）在 `AppLayout`。新的文字放在毛玻璃上時，淺色、深色 ×
  最淺、最深的封面都要過 guideline（`guidelines_test.dart` 的 `the player page over …`）：次要文字用
  `onSurfaceVariant` 在深色封面上會不夠對比，遮罩用主題的 `surface` 就是為了這個。
- 佇列（M2 PR 18b）：分頁與底部面板都是 `QueueView`（`queue_view.dart`），面板由 `showQueueSheet` 開，把
  `DraggableScrollableSheet` 給的捲動控制器傳進去（不給就自己建，開啟時直接從目前這首附近開始）。改清單時：列的鍵是佇列
  項目的實例（`ObjectKey`），所以編輯不能換掉既有項目的實例（`QueueModel` 的編輯本來就沿用）；拖曳只經把手，放下用
  `onReorderItem`（`newIndex` 已調整），呼叫 `PlaybackController.move`；選單項目加在 `_QueueRow`。要在 widget
  被拆掉之後還用的東西（清空後播放頁與面板都關）要在 `await` 之前先 `ref.read` 好，像 `_clear`。會讓播放頁關掉的動作
  要跳提示時，先 `await WidgetsBinding.instance.endOfFrame` 再發：`ToastHost` 在顯示當下讀位移，頁面還開著就貼在底部
  安全區、蓋住外殼的導覽列（`queue_view_test.dart` 的 `clearing from the sheet…` 守著）。切歌時自動捲動讀
  `playbackPreferencesProvider` 的 `autoScrollToCurrent`，比的是目前項目的實例，不是位置。
- 測試：`h.play(…)` 後點播放列的曲名開頁（`player_page_test.dart` 的 `_openByTap`）；要封面用
  `ShellHarness(artworkManager: FakeArtworkManager())` 與 `TestArtwork.lightest／darkest`
  （`test/ui/support/fake_artwork.dart`）；記住的分頁讀寫經 `layoutStateRepositoryProvider`，資料庫要真的事件迴圈
  （`tester.runAsync`）。golden 在 `player_page_golden_test.dart`，播放頁讀的 provider 在那裡 override。

## 右側「正在播放」面板

規則與閘門見 `app/AGENTS.md` § 介面的「右側『正在播放』面板」；design §9.4。

- 面板的展開與寬度讀 `panelExpandedProvider`、`panelStoredWidthProvider`（`lib/ui/layout/layout_state.dart`，
  與 `layoutStateProvider` 同檔），寫一律 `rememberPanel(ref, expanded:/width:)`（失敗只記 log）；要等寫入結果時用
  `savePanel`（回 `bool`）。新的開關入口只呼叫 `rememberPanel(ref, expanded: !現在)`。
- 畫面上的寬度只經 `panelWidthFor`（夾取在那裡，數值在 `AppLayout`）；元件本身（`NowPlayingPanelSide`）在 build 裡
  讀視窗寬度（`MediaQuery`）與整個視窗的 `WindowClass`，所以要放在頁面的 `WindowClassScope` 之外。
- 面板加進外殼內容區時結構不能隨有無面板而變（`if (hasPanel)` 放在 `Row` 的子項，不要換包法），否則視窗跨過 840
  時頁面的 State 會丟。內容區的焦點順序靠 `FocusTraversalOrder`（頁面 0、面板 1）。
- 播放列自己量不出整個視窗，要不要開關鈕由外殼的 `PlayerBar(panelToggle:)` 給。
- 測試：`h.pumpShell(tester, collapsePanel: true)` 把面板收起（測頁面本身在內容區寬度下的版面時用）；找把手用
  `Tooltip` 的 `message`（名稱在 `Semantics`，`find.byTooltip` 找不到）；拖曳用 `TestGesture`（把手用
  `DragStartBehavior.down`，位移就是寬度變化）；寫入次數用 `tableUpdates` 的通知數（`now_playing_panel_test.dart` 的
  `_countWrites`）；資料庫要真的事件迴圈（`_store`、`_stored` 包 `runAsync`），寫入加 stream 回來要兩次 `loadSettings`。

## 插件頁

規則與閘門見 `app/AGENTS.md` § 介面的「插件頁」；ADR 0030 §決定 6–11。

- 設定頁加一個不是設定組的區塊：`SettingsSection` 加一個值與它的名稱，`detail` 的 `switch` 決定它要不要包在捲動的欄裡
  （自己有捲動清單的像插件頁就不包，填滿剩下的高度）。
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
- 測試用 `PluginPageHarness.create(tester)`（平台預設宣告有 secure storage；`secureStorage: false` 測沒有的平台），插件以
  `pluginScript(..., login: {...})` 或 `testPluginFile` 寫進資料庫。造已登入的狀態在假時間 zone 呼叫
  `h.plugins.credentials.save(...)` 再 `pump`（不要包 `runAsync`，理由見插件頁那一節）。QR 對話框的輪詢是假計時器：
  `pump(2 秒)` 後 `h.settle` 讓插件的回覆回來；對話框關閉還要 `pump` 過它的動畫。
  網頁登入：`PluginPageHarness.create(tester, loginWebView: FakeLoginWebView())`（`test/support/fake_login_webview.dart`；
  平台就宣告 `loginWebView`），插件的 manifest 要有 `login.webView`。假 WebView 的 cookie 以主機名稱存（`setCookies`），
  `loadPage()` 模擬一頁載入完成；頁面載入中的進度條一直在動，不用 `pumpAndSettle`，按按鈕後先 `h.settle`（等插件清單）
  再 `pump`。卡住的計時直接 `pump(webLoginStuckAfter)`。`CredentialStore` 的 `unreadable`
  不好造，以 `overrides: [accountViewProvider(id).overrideWith(...)]` 給畫面看的狀態。

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
