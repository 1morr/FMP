# Implement

先紅後綠：測試步驟先做，確認在舊程式碼上紅，再改實作。

1. 測試（先紅）
   - `test/services/audio/playback_media_test.dart`：`redactStreamUrl` 與 `logLabel`
     （query 簽章、path 簽章、無 path、解析失敗、本機路徑）。
   - `test/services/audio/media_kit_audio_service_state_test.dart`：`playUrl`、
     `setUrl`、`setNextMedia`、引擎推進到下一首後，`AppLogger.logs` 不含簽章
     片段與完整網址，但含 host。
   - `test/services/audio/playback_request_session_test.dart`：fallback 路徑的 log。
   - `test/services/audio/audio_controller_next_medium_test.dart`：未 arm 的推進的
     warning。
   - `test/services/static_rules/audio_backend_shared_rules_static_rule_test.dart`：
     `_sharedUnits` + `_delegation`。
   - 跑一次，確認以上都紅（純函式那條是編譯錯，算紅）。
2. 實作
   - `playback_media.dart`：`redactStreamUrl`、`logLabel`、`debugUrl` dartdoc。
   - 兩個後端、`playback_request_session.dart`、`audio_provider.dart` 換呼叫點。
   - 編輯到的行的註解轉繁體。
3. 驗證
   - `flutter test test/services/audio test/services/static_rules test/core/logger`
   - `dart format --output=none --set-exit-if-changed lib test tool`
   - `flutter analyze`
4. Spec：`.trellis/spec/shared/errors-and-logging.md` 改寫簽名網址那一條；
   `.trellis/spec/services/index.md` Quality Check 的「Not gated」裡簽名網址那句
   視閘門範圍調整。
5. Commit（不 push、不開 PR）。

回退點：步驟 2 前的工作樹只有測試；步驟 5 後 `git revert` 單一 commit。
