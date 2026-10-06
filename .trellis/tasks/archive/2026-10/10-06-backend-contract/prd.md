# 後端契約補齊：前瞻失敗、HTTP 狀態碼（M2 PR 11）

> 父任務：`.trellis/tasks/10-01-m2-full-playback`。技術設計在父任務 `design.md` §7.6「契約測試」兩條（前瞻開不起來、`SourceFailed.httpStatus`）；來源是 M1 follow-up（`.trellis/tasks/archive/2026-10/09-28-m1-skeleton-tracer/implement.md:227`：前瞻開不起來時 Android 會被當成目前這首中斷、Windows 可能卡在 Playing）。本檔只列做什麼與驗收。

## 目標

前瞻（下一首）的網址開不起來時，目前這首照常播完，失敗算在下一首上，走恢復；開流被 HTTP 拒絕時，失敗事件帶狀態碼，給 PR 12 的 `RecoveryPolicy` 用。

## 做什麼

1. **兩個後端的前瞻失敗契約**（`lib/playback/backends/`，`just_audio_backend.dart`、`media_kit_backend.dart`）：
   - 前瞻開不起來時，目前這首照常播完，發 `SourceEnded(目前, completed)`，不發 `SourceAdvanced`；
   - 失敗以 `SourceFailed(前瞻的 id, BackendFailure.open)` 回報，不算在目前這首上；
   - Windows（mpv）不卡在 Playing；Android（ExoPlayer）不把它當成目前這首中斷。
   - 事件順序（失敗先到還是播完先到）以契約寫定；兩個引擎若無法一致，契約斷言兩者都允許的順序並在 `app/AGENTS.md` 寫明。
2. **`SourceFailed.httpStatus`**（可空 int）：
   - 解析放在 `backend_rules.dart` 的純函數：ExoPlayer 的 `InvalidResponseCodeException`（`Response code: 403` 這類）與 mpv log 行（`HTTP error 403` 這類）；
   - 以錄下的兩種真實錯誤文字做單元測試，含沒有狀態碼的反例（例如 DNS 失敗、逾時、非 HTTP 錯誤）；
   - 後端在開流失敗時填上；拿不到就是 null。
3. **控制器與 session**：前瞻失敗當成下一首的開流失敗——作廢那份解析結果的網址快取（PR 7 的 `invalidate`），到那首時重新解析；目前這首不受影響、不重試、不跳過。前瞻失敗發生在目前這首播完之後（交接時才開不起來）的情況也要正確：走既有的 `Recover` 路徑。
4. **契約測試**（`test/playback/backends/audio_backend_contract.dart`，假後端在 `flutter test`、兩個真後端在 `integration_test/audio_backend_contract_test.dart` 實機）：加「前瞻開不起來」「開流被 HTTP 拒絕時帶狀態碼」兩個案例。假後端（`test/playback/fake_audio_backend.dart`）跟著實作同一份契約。
5. **測試插件**（`app/test/fixtures/plugins/test_plugin/test_plugin.js`）：加一個關鍵字，讓第二首的網址開不起來（例如回一個不存在的 asset 或本機不可連的網址；不得連外網），供實機重播驗證。照現有 `fail` 關鍵字的寫法與註解；同步更新 `checks.json`、`README.md` 與受影響的契約 fixture／測試。
6. 文件：`app/AGENTS.md` § 播放（前瞻失敗契約、`httpStatus`）、playback spec；每條寫閘門。

## 不做

- `RecoveryPolicy` 依狀態碼的分支與播放提示（PR 12）。
- 單曲循環換候選後前瞻重開第一候選（PR 10 留下，歸 PR 12）。
- E19 音量、速度、輸出裝置（PR 13）。

## 驗收

- [ ] 契約兩個新案例，假後端在 `flutter test` 通過。
- [ ] 狀態碼解析的單元測試：兩種錄下的錯誤文字各取得狀態碼；反例回 null。
- [ ] 控制器測試：前瞻失敗時目前這首播完、下一首重新解析並走恢復；快取被作廢（不重用壞網址）。
- [ ] 驗證清單全綠（父任務 implement.md「每個 PR 的固定流程」第 5 步）。
- [ ] 實機（主對話做）：Windows、Android 模擬器各跑真後端契約 `integration_test/audio_backend_contract_test.dart`；測試插件的新關鍵字連播時第一首完整播完、第二首走恢復（重播）。
