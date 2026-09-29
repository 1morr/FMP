# 查證紀錄（M1 PR 6：設定、log 門面與遮蔽）

查證日期：2026-09-29。context7 在這次的執行環境不可用，改以 pub.dev API、官方文件
網頁與 pub cache 裡的套件原始碼（即實際鎖定的版本）為準。

## 1. 版本

| 套件 | 鎖定版本 | 來源 |
|---|---|---|
| `flutter_riverpod` | 3.4.3（`riverpod` 3.4.3） | https://pub.dev/api/packages/flutter_riverpod 的 `latest` |
| `talker` | 5.1.20（`talker_logger` 5.1.20，2026-07-28 發佈） | https://pub.dev/api/packages/talker |
| `riverpod_lint` | 3.1.9（analysis_options 的 `plugins:` 已是這版） | https://pub.dev/api/packages/riverpod_lint |

不加 `riverpod_generator`（PRD）；`talker_flutter`、`talker_dio_logger` 也不加（ADR 0011
否決了 `TalkerScreen` 與 `talker_dio_logger`）。

## 2. Riverpod 3

- **全域關閉重試**：riverpod.dev〈Automatic retry〉
  （https://riverpod.dev/docs/concepts2/retry）：預設最多重試 10 次、200ms 起指數退避到
  6.4 秒；「Disabling retry」一節的寫法是
  `ProviderScope(retry: (retryCount, error) => null, child: ...)`。
  - 原始碼：`flutter_riverpod-3.4.3/lib/src/core/provider_scope.dart:75-81`，
    `ProviderScope` 建構子有 `retry`；型別 `Retry = Duration? Function(int, Object)`
    （`riverpod-3.4.3/lib/src/core/provider_container.dart:287`）。
  - `ProviderScope` 是 `final class`，不能繼承，所以用回傳 `ProviderScope` 的函式
    `appProviderScope` 包一層。
- **`missing_provider_scope`**：`riverpod_lint-3.1.9/lib/src/lints/missing_provider_scope.dart`
  只看 `runApp` 第一個引數的靜態型別是否「正好是」`ProviderScope` 或
  `UncontrolledProviderScope`；函式回傳型別宣告為 `ProviderScope` 即可通過。已用暫放檔
  `runApp(const SizedBox())` 確認規則會報（本機，未編碼成測試，見 §5）。
- **`Override`** 從 `package:flutter_riverpod/misc.dart` 匯出（3.x 把它移出主函式庫）。
- **測試**：`ProviderContainer.test(...)`（`provider_container.dart:963`），測試結束
  自動 dispose。`StreamNotifier`／`StreamNotifierProvider`、`Notifier`／
  `NotifierProvider` 從 `flutter_riverpod.dart` 匯出。

## 3. talker 5.1.20

讀 `talker-5.1.20/lib/src/` 原始碼：

- `TalkerSettings(maxHistoryItems: 1000, useConsoleLogs: ..., useHistory: true)`；
  `DefaultTalkerHistory.write` 超過上限時 `removeAt(0)`（`history.dart`）。
- `Talker(observer: ...)`：`TalkerObserver.onLog(TalkerData)` 在每筆 `logCustom` 時
  呼叫（`talker.dart` 的 `_handleLogData`），用它把紀錄分派到 log 檔。
- `logCustom(TalkerLog)` 可以放自訂子類別；`TalkerLog` 的 `exception`、`stackTrace`
  會原樣留在歷史，所以門面不把原始 error／stackTrace 交給 talker，只交遮蔽過的
  `LogRecord`（包在 `_RecordLog`），並覆寫 `generateTextMessage` 給 console 用。
- 歷史是否寫入還要過 `TalkerLogger` 的 filter（`_handleForOutputs`），預設層級
  `verbose`，所以層級過濾放在門面。
- console 輸出：`talker_logger-5.1.20/lib/src/logger_io.dart` 用 `print`；
  `TalkerLoggerSettings(enableColors: false)` 關掉 ANSI 色碼（logcat 裡是亂碼）。
  `useConsoleLogs: kDebugMode` 讓 release 不輸出。

## 4. 舊專案的參考（ADR 為準）

- `lib/core/logger.dart:81-134`：鍵名名單（MUSIC_U、SESSDATA、bili_jct、csrf、
  SAPISID 系列等）與 `Authorization`／`Cookie`／`Bearer`／`SAPISIDHASH` 的樣式，搬進
  `redaction_lists.dart`。舊版沒遮 stackTrace、release 仍 `debugPrint`，新版都改掉。
- `lib/core/log_file_sink.dart`：串接佇列與 `fmp.log → fmp.1.log` 的輪替形狀。改動：
  JSON Lines、以 UTF-8 位元組計大小（舊版用字串長度，中文會低估）、同一輪的多行合成
  一次 append、失敗計數而不是吞掉。
- 媒體 CDN 簽名參數：舊專案沒有對應邏輯，只有 `redactStreamUrl`（整段 query 去掉）。
  名單依 `docs/audit/accounts-network.md` §4.1 列的缺口（`sig`、`signature`、`lsig`、
  `expire`、`upsig`、`deadline`、網易路徑簽章）加上 B 站 upos 的 `e`、`uparams`、
  `mid`、`oi`、`trid` 與 googlevideo 的 `ip`、`ei`、`pot`、`n` 等。

## 5. 實作中發現的事

- flutter_test 的 `TestPlatformDispatcher.onError` setter 不會寫入
  （`packages/flutter_test/lib/src/window.dart:915-916` 只讀取），測未捕捉錯誤要用
  `PlatformDispatcher.instance`。
- `missing_provider_scope` 沒有自動閘門：`tool/lint_sentinel.dart` 只驗 `fmp_` 規則。
  `riverpod_lint` 沒載入時沒有東西會紅，已在 `app/AGENTS.md` § Lint 寫明。
