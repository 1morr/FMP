# 播放（`app/lib/playback/`）

改控制器、佇列、恢復策略或播放後端、寫播放測試、跑播放的實機驗證時適用。規則（唯一入口、
引擎套件只在後端目錄、共用規則、標頭、引擎訊息的遮蔽、一個後端實例、前瞻、恢復）與閘門見
`app/AGENTS.md` § 播放；為什麼這樣做，見 ADR 0018。這裡只寫怎麼做。

## 目錄

```
lib/playback/
  playback_controller.dart  # PlaybackController：唯一入口，唯一寫 PlaybackState
  playback_state.dart       # sealed PlaybackState、PlaybackProgress
  queue_model.dart          # QueueModel、QueueState（M1：記憶體、依序）
  stream_resolver.dart      # StreamResolver、ResolvedStream（期限）
  recovery_policy.dart      # decideRecovery 與它的輸入、輸出型別（純函數）
  playback_providers.dart   # audioBackendProvider、playbackControllerProvider、狀態／佇列／進度 stream
  backends/
    audio_backend.dart      # AudioBackend 介面、BackendSource、狀態與事件
    backend_rules.dart      # classifyTrackEnd、LookAheadEdit（兩個後端共用）
    audio_backends.dart     # createAudioBackend：依平台宣告建實作
    just_audio_backend.dart # Android
    media_kit_backend.dart  # Windows

lib/platform/audio/         # AudioBackendKind、PlayableFormat、PlaybackSupport 與兩個平台的宣告
```

## 一首歌怎麼播

1. `playQueue`／`next`／`previous`／恢復 → `_load`：換一代（`_generation`）、狀態 `Loading`，
   用前瞻留下的 `ResolvedStream`（還沒過期）或呼叫 `StreamResolver.resolve`。
2. `_open`：建 `BackendSource`（新的 id、經 `mediaRequestHeaders`），`AudioBackend.open`。
3. 後端回報 `ready` → `Playing`／`Paused`；第一次 ready 時 `_prepareLookAhead` 解析下一首一次，
   `setNext` 交給後端，有期限就排一個計時器在過期前 30 秒重新解析。
4. 引擎自己接上前瞻 → `SourceAdvanced`：佇列往下、換一代，接上的那首不再解析，再為下一首
   準備前瞻。沒有前瞻時是 `SourceEnded`：還有下一首就照 1 開始，沒有就 `Idle`。
5. 失敗（`SourceFailed`、提前結束、解析丟出的 `AppError`）→ `decideRecovery` → 重試、換候選、
   跳過或停下。

每個非同步步驟回來時比對代，不同就丟掉結果。狀態、位置、事件都帶來源 id，控制器只收
目前來源的。

## 改後端

- 引擎的型別只出現在兩個實作檔；介面的型別（`BackendStatus`、`BackendEvent`）以外的東西不要
  往上傳。
- 兩個後端都要成立的規則寫進 `backend_rules.dart` 並在 `backend_rules_test.dart` 加案例，後端
  只轉呼叫；只有一個引擎才有的怪癖寫在那個實作裡，收斂不了的差異寫進 `AudioBackend` 的
  dartdoc。
- 清單的修改（`open`、`setNext`、`stop`、交接後的修剪）一律經 `_edit` 排隊，每次依當下的清單
  算 `LookAheadEdit`；排隊期間來源換了就不做。
- `playing` 是使用者要不要出聲，不是引擎當下有沒有在輸出：mpv 在換檔的瞬間會把 `playing`、
  `buffering` 閃一下，而且那時的來源還是舊的。
- mpv 的屬性只在值改變時發事件（兩個檔案一樣長時，接上後不會再收到 `duration`）。依賴屬性
  事件的狀態，換來源時先從 `player.state` 取目前的值。
- media_kit 的事件不帶項目：`open` 之後、`Player.open` 回來之前收到的位置、時長、結束與錯誤
  是上一個檔案的（`Player.open` 內的 mpv 指令是非同步的），`_opening` 期間一律丟掉。
- just_audio 在清單修改期間的事件一律丟掉，改完以 `_player.playbackEvent` 補一次：暫停中
  載入好的來源之後不會再有事件，不補就一直停在緩衝。
- 要不要出聲以執行當下的意願（`_wantPlaying`）為準：`open` 排隊或載入中被 `pause` 的，
  載入完不能照 `open` 當時的 `play` 開始播。契約的 `pausing before the source is ready…`
  守這條。
- 引擎給的錯誤文字只放 `SourceFailed.cause` 或 log 的 `error:`，不接進訊息字串。
- 改完照 `app/AGENTS.md` § 驗證 在 Windows 與 Android 各跑一次真後端的契約。

## 測試

- 控制器：`test/playback/playback_controller_test.dart` 的 `Harness` 在 `fakeAsync` 裡組控制器、
  `FakeAudioBackend`（計時器推進位置，所以假時間也會播完）與 `FakeSourcePlugin`（依請求回候選
  或丟 `AppError`，記下每次請求）。`h.elapse` 前進時間，`h.settle` 只跑微任務。
- 解析次數用 `plugin.resolvedCount(sourceId)`；開了哪些網址用 `h.openedPaths`；前瞻用
  `backend.nextSources`；log 用 `h.logged(message)`。
- 碰 log 檔的案例（遮蔽）不用 `fakeAsync`：真的 `LogFile` 在暫存目錄，等待用 `pumpUntil`。
- 後端契約：`audio_backend_contract.dart` 的 `audioBackendContract` 收一個 `DefineCase`，
  `flutter test` 傳 `test`，整合測試傳包了 `testWidgets`＋`runAsync` 的版本。新的後端行為在這裡
  加一個案例，假後端與真後端一起跑到；`FakeAudioBackend` 用同一份 `backend_rules.dart`。
- 真後端要實際播放，契約的 `Recorder.until` 等的是實際時間（事件驅動＋逾時計時器），不是
  `pumpUntil`。

## 實機驗證（ADR 0018 §如何確認）

建置、安裝、啟動、讀 log 與 `dumpsys audio` 照 `verify-on-device` skill（`.claude/skills/verify-on-device/`）。
播放一律從 UI 開始：以 `--fmp-dev-plugin` 裝測試插件（重播，三首同一個 2 秒的 `tone.wav`、
不連網）或 B 站插件（真實），搜尋後點一首。播放相關要看的：

- 交接：`Look-ahead handover`（`previousPositionMs` 是上一首最後回報的位置）與接著的
  `Track audible`：`sinceHandoverMs` 是交接事件到這首第一次回報位置，`estimatedGapMs` 是從
  上一首最後的位置推算的結束時間到這首第一次回報位置（含位置回報的間隔，只是估計）。
- Android 音訊焦點：播放中與交接前後，`Audio Focus stack` 的最上面一直是
  `com.personal.fmp.dev`（`AUDIOFOCUS_GAIN`），沒有被 abandon 又重新 request；播完之後也仍在
  （just_audio 不主動放）。模擬器要有聲音輸出（不是 `-no-audio` 啟動的），ExoPlayer 才會真的播。
- 真實連線（ADR 0027 §決定 2 的最少操作）：B 站播一首，看 `Opening stream` 的 `headers` 有
  `Referer`。
