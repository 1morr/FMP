# 播放（`app/lib/playback/`）

改控制器、佇列、恢復策略或播放後端、寫播放測試、跑播放的實機驗證時適用。規則（唯一入口、
引擎套件只在後端目錄、共用規則、標頭、引擎訊息的遮蔽、一個後端實例、前瞻、恢復）與閘門見
`app/AGENTS.md` § 播放；為什麼這樣做，見 ADR 0018。這裡只寫怎麼做。

## 目錄

```
lib/playback/
  playback_controller.dart  # PlaybackController：唯一入口，唯一寫 PlaybackState
  playback_session.dart     # PlaybackSession：唯一碰 AudioBackend；解析、開流、前瞻、代與來源 id
  playback_event_router.dart # SessionEvent、routePlaybackEvent（純函數）與它的動作
  playback_state.dart       # sealed PlaybackState、PlaybackProgress
  queue_model.dart          # QueueModel、QueueState、QueueStep（純 Dart：模式、循環、位置式隨機、臨時播放、上限）
  stream_resolver.dart      # StreamResolver（記憶體網址快取）、ResolvedStream（期限）
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

1. `playQueue`／`next`／`previous`／恢復 → 控制器的 `_load`：`session.beginRequest()` 換一代、
   狀態 `Loading`，用前瞻留下的 `ResolvedStream`（`session.isFresh`）或 `session.resolve`。
   解析一律經 `StreamResolver` 的網址快取：還有效的直接拿、同一首正在解析的共用請求，
   所以前瞻解析過（或還在解析）的那首不會再問插件。
2. `session.open`：建 `BackendSource`（新的 id、經 `mediaRequestHeaders`），`AudioBackend.open`。
3. 後端回報 `ready` → session 發 `SourceReady` → 路由器給 `MarkReady` → `Playing`／`Paused`；
   第一次 ready 時 `session.prepareLookAhead` 解析下一首一次，`setNext` 交給後端，有期限就排一個
   計時器在過期前 30 秒重新解析。
4. 引擎自己接上前瞻 → `SourceAdvanced` → `LookAheadTookOver` → `AdoptLookAhead`：
   `session.adoptLookAhead` 換一代，控制器把佇列往下，接上的那首不再解析，再為下一首準備前瞻。
   沒有前瞻時是 `SourceEnded` → `SourceFinished`：還有下一首（`PlayNextTrack`）就照 1 開始，
   沒有（`FinishQueue`）就 `Idle`。
5. 失敗（`SourceFailed`、提前結束、解析丟出的 `AppError`）→ `Recover`／`decideRecovery` →
   重試、換候選、跳過或停下。串流本身的失敗（`Recover`）先 `session.invalidateCurrentStream`
   作廢快取裡的那一筆；解析失敗本來就不進快取。

狀態、位置、事件都帶來源 id，session 只轉目前來源的。每個非同步步驟回來時比對
`session.generation`，不同就丟掉結果。

分工：引擎的型別、來源 id、前瞻的計時器與交接的量測 log 在 session；「這個事件該做什麼」
在 `routePlaybackEvent`（新的判斷先在這裡加一個事件或動作，並在
`playback_event_router_test.dart` 加案例）；改狀態、動佇列、恢復計數在控制器。session 要給
控制器新的資訊時，加在 `SessionEvent` 或 `PlaybackSnapshot`，不讓控制器 import 後端。

## 改佇列

- 規則都在 `QueueModel`（純 Dart），控制器只依 `moveNext`／`movePrevious` 回的 `QueueStep`
  做事：`MovedToTrack` 從頭開始、`RestartTrack` seek 回 0、`ReturnedToQueue` 從
  `snapshot.resumeAt(...)` 開始（`current` 為空就停）、`QueueUnchanged` 不動。
- 隨機的內部表示：`_order` 是本輪的位置排列，目前這首在 `_order.indexOf(_current)`；
  `_playNextRun` 是緊接在目前這首之後、連續「下一首播放」的位置數（清單與排列上都緊接著）。
  新的編輯要同時維持這兩件事，並讓 `_order` 仍是全部位置的排列。
- 一輪的最後一首時，`next` 先決定下一輪的排列（`_nextRound`），`moveNext` 照用；任何編輯經
  `_publish` 作廢它。所以前瞻看到的下一首與實際接上的一致。
- 測試：`test/playback/queue_model_test.dart`，隨機一律 `QueueModel(random: Random(種子))`。
  斷言用曲目 id 寫（`upcoming`、`played` 取本輪之後、之前的曲目），不寫死排列：排列由 `Random`
  的實作決定，測試只認規則。新的編輯操作加進 `a seeded run of edits…` 的 `switch`，並照它
  維護 `slots`（每個位置的身分）。

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
- 時間：程式碼讀 `clock.now()`，`fakeAsync` 裡的 `clock` 跟著假時間走（`h.now()` 就是它）。
  網址快取以時間判斷有效，同一個 `Harness` 裡的解析共用一份快取：要測「再解析一次」就讓
  期限落在 5 分鐘的餘裕內，或製造一次串流失敗。
- `StreamResolver` 自己的快取規則在 `stream_resolver_test.dart`，以 `withClock` 換一個可調
  的時鐘，不用 `fakeAsync`。
- 碰 log 檔的案例（遮蔽）不用 `fakeAsync`：真的 `LogFile` 在暫存目錄，等待用 `pumpUntil`。
- 路由器：`test/playback/playback_event_router_test.dart` 直接以 `SessionEvent` 與
  `PlaybackSnapshot` 呼叫 `routePlaybackEvent`，不組控制器。事件與快照的組合在這裡窮舉；
  控制器測試只驗端到端的結果。
- 後端契約：`audio_backend_contract.dart` 的 `audioBackendContract` 收一個 `DefineCase`，
  `flutter test` 傳 `test`，整合測試傳包了 `testWidgets`＋`runAsync` 的版本。新的後端行為在這裡
  加一個案例，假後端與真後端一起跑到；`FakeAudioBackend` 用同一份 `backend_rules.dart`。
- 真後端要實際播放，契約的 `Recorder.until` 等的是實際時間（事件驅動＋逾時計時器），不是
  `pumpUntil`。

## 實機驗證（ADR 0018 §如何確認）

照 `verify-on-device` skill（`.claude/skills/verify-on-device/`）：模式與平台、從搜尋頁開始播、
讀 log、Android 音訊焦點（`references/android.md` 的「音訊焦點」）都在那裡。skill 沒寫的、
播放的 log 欄位怎麼讀：

- 交接：`Look-ahead handover`（`previousPositionMs` 是上一首最後回報的位置）與接著的
  `Track audible`：`sinceHandoverMs` 是交接事件到這首第一次回報位置，`estimatedGapMs` 是從
  上一首最後的位置推算的結束時間到這首第一次回報位置（含位置回報的間隔，只是估計）。
- 解析次數：`Resolving stream` 一筆是一次插件 `resolveStream`；連播 n 首應該剛好 n 筆，
  多出來的看同一首旁邊有沒有 `Stream URL invalidated`（失敗後重解析是對的）或
  `Look-ahead refreshed before expiry`。
- 真實連線（ADR 0027 §決定 2 的最少操作）：B 站播一首，看 `Opening stream` 的 `headers` 有
  `Referer`。
