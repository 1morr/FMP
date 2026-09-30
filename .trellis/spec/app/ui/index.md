# 介面（`app/lib/ui/`、`app/lib/i18n/`）

寫畫面、加字串、跳提示時適用。規則（token、字串來源、提示入口）與閘門見
`app/AGENTS.md` § 介面；為什麼是這些選擇，見 ADR 0023、ADR 0024 與
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
  toast/               # Toaster、ToastHost；fmp_toast_entry 的允許目錄
  settings/            # 設定頁的控制項
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

- `WindowClass.of` 讀最近的 `WindowClassScope`；App 根放了一個（量整個視窗），外殼（12b）
  在內容區再放一個，頁面讀到的是內容區的等級。
- 只在等級改變時重建。要精確寬度的版面仍用 `LayoutBuilder`。

## 字串

加一條字串：

1. 三個 JSON 都加同一個 key，先寫繁中。參數寫 `{name}`，三個語言的參數要一樣。
2. `dart run build_runner build --delete-conflicting-outputs`（和 drift 一起產生），提交 `lib/i18n/*.g.dart`。
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
- 外殼（12b）以 `ref.read(toastBottomInsetProvider.notifier).set(高度)` 發佈從視窗底邊算起
  被佔住的高度（含安全區）；全螢幕頁不發佈時要設回 0。
- M1 沒有「詳細」與「回報」（ADR 0023 §決定 4 延到 M3，和 Debug 頁的錯誤歷史一起做）。

## 測試

- 畫面測試用 `buildAppTheme` 的主題；有提示的包 `ToastHost`，以
  `toasterProvider.overrideWithValue(Toaster(...))` 注入（例子：
  `test/ui/toast/toast_host_test.dart`）。
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
