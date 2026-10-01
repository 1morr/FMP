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
  settings/            # 設定頁（list-detail）與外觀的控制項
  player/              # 播放列、queueTracksProvider（佇列的顯示資料）、playTracks
  artwork/             # 封面縮圖與 pickArtwork
  format/              # 時長文字
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
- 每則最多一個動作；帶動作的也照時長消失（成功與資訊 4 秒、警告與錯誤 6 秒）。
- 去重 5 秒：訊息以「種類＋文字」，錯誤以「類別＋音源」。
- 外殼的 `_BottomInsetReporter` 量底部那一塊（compact 是播放列加底部導覽列，更寬是播放列）
  的高度，排版後以 `toastBottomInsetProvider` 發佈；頁面不用管。M2 的全螢幕播放頁蓋住外殼時
  要設回 0。
- 要看狀態變化跳提示（播放停在 `Failed`），在 `ref.listen` 的 callback 裡呼叫 `Toaster`，不在
  `build` 裡：`Toaster` 同步送出，`ToastHost` 當場 `showSnackBar`。
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

## 播放列與封面

- 開始播放一律經 `playTracks(ref, tracks, index)`（`lib/ui/player/queue_tracks.dart`）：它把
  顯示資料放進 `queueTracksProvider`，再把整份清單交給 `PlaybackController`。播放列以曲目鍵查
  顯示資料；M2 有曲目表之後改從那裡查。
- 播放列的控制項照 ADR 0024 §決定 5 的三段，只放已經有的功能；加功能時同時改
  `player_bar_test.dart` 的 `controls per width` 與 golden。
- 封面用 `ArtworkImage`：`pickArtwork` 挑一張、以顯示尺寸解碼，沒有、載入中與失敗都是同一個
  佔位圖。網址在 DTO 解碼時已經過 `allowedHosts`；不帶 header（B 站的 hdslb 不帶 `Referer` 讀得到，
  帶別的網域反而 403）。

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
