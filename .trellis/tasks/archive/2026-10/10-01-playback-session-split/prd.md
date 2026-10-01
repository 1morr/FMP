# M2 PR 1：拆出 PlaybackSession 與 PlaybackEventRouter

M2 的第一個程式 PR（`../10-01-m2-full-playback/implement.md` §1；design §7.1、§2）。行為不變的重構，加 ADR 0018 §如何確認的兩條匯入規則。

## 做什麼

1. 從 `lib/playback/playback_controller.dart` 拆出：
   - `lib/playback/playback_session.dart` 的 `PlaybackSession`：唯一持有 `AudioBackend` 的協作者，負責開流、前瞻、代際與來源 id 過濾，把後端事件轉成帶代際的事件交給控制器；
   - `lib/playback/playback_event_router.dart` 的 `PlaybackEventRouter`：純函數，(後端事件, 控制器目前的快照) → 動作（往下一首、交給 `RecoveryPolicy`、忽略）。
   - `PlaybackController` 仍是唯一入口與 `PlaybackState` 唯一的寫入者。
2. `fmp_layer_imports` 加通用的 `restrictedImports`（被匯入檔 → 允許的匯入端）：
   - `lib/playback/backends/audio_backend.dart` 只給 `lib/playback/backends/`、`lib/playback/playback_session.dart`、`lib/playback/playback_providers.dart`；
   - `TrackEndReason` 所在的 `lib/playback/backends/backend_rules.dart` 只給 `lib/playback/backends/`、`lib/playback/playback_event_router.dart`。
   - 實際檔名以拆完的結果為準；若測試檔需要匯入，照既有規則對 `test/` 的處理方式。
   - `tool/lint_sentinel.dart` 加違規行。
3. 文件：`app/AGENTS.md` § 播放與 § Lint 改寫（拿掉「等 M2 有路由器與 `PlaybackSession` 時再加」）；`.trellis/spec/app/playback/index.md` 的「實機驗證」段改成指向 `verify-on-device` skill（M1 follow-up 6）；`.trellis/spec/app/lints/index.md` 需要時補 `restrictedImports` 的寫法。

## 驗收

- [ ] 既有 `test/playback/playback_controller_test.dart` 的期望不改、全綠（證明行為不變）。
- [ ] 新增 `test/playback/playback_event_router_test.dart`，逐一餵事件斷言動作。
- [ ] lint 的報與不報案例（在規則測試檔內）：違規匯入會報；同前綴的 `backends_helpers.dart` 之類也報；改名、註解裡提到不報。哨兵報出新規則名。
- [ ] 通用驗證：format、build_runner 後沒有實質變動、`dart analyze --fatal-infos`、`flutter analyze`、`flutter test`、`dart run tool/lint_sentinel.dart`、`packages/fmp_lints` 的 `dart test`（含 `TEST_ANALYZER_WINDOWS_PATHS=true`）。
- [ ] 實機：改到播放後端的呼叫路徑，Windows 與 Android 模擬器各跑一次 `integration_test/audio_backend_contract_test.dart`；用測試插件從搜尋頁播兩首確認前瞻交接（模式：重播）。由主對話照 `verify-on-device` 做。
