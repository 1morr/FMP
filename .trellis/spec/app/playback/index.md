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
  playback_events.dart      # PlaybackEvent（控制器的 events：QueueFull、TrackSkipped、PlaybackStopped、PreviewPlaying）
  playback_state.dart       # sealed PlaybackState、PlaybackProgress
  queue_model.dart          # QueueModel、QueueState、QueueStep（純 Dart：模式、循環、位置式隨機、臨時播放、上限）
  stream_resolver.dart      # StreamResolver（記憶體網址快取）、ResolvedStream（期限、previewOnly）
  recovery_policy.dart      # decideRecovery 與它的輸入、輸出型別、各個常數（純函數）
  playback_providers.dart   # audioBackendProvider、playbackControllerProvider、temporaryReturnSettingsProvider、
                            # skipPreviewClipsProvider、狀態／佇列／試聽／進度／事件 stream
  backends/
    audio_backend.dart      # AudioBackend 介面、BackendSource、狀態與事件
    backend_rules.dart      # classifyTrackEnd、LookAheadEdit（兩個後端共用）
    audio_backends.dart     # createAudioBackend：依平台宣告建實作
    just_audio_backend.dart # Android
    media_kit_backend.dart  # Windows

lib/platform/audio/         # AudioBackendKind、PlayableFormat、PlaybackSupport 與兩個平台的宣告
```

## 一首歌怎麼播

1. `playTemporary`／`jumpTo`／`next`／`previous`／`play`／恢復 → 控制器的 `_load`：`session.beginRequest()` 換一代、
   狀態 `Loading`，用前瞻留下的 `ResolvedStream`（`session.isFresh`）或 `session.resolve`。
   解析一律經 `StreamResolver` 的網址快取：還有效的直接拿、同一首正在解析的共用請求，
   所以前瞻解析過（或還在解析）的那首不會再問插件。
2. `session.open`：建 `BackendSource`（新的 id、經 `mediaRequestHeaders`），`AudioBackend.open`。
3. 後端回報 `ready` → session 發 `SourceReady` → 路由器給 `MarkReady` → `Playing`／`Paused`；
   第一次 ready 時 `session.prepareLookAhead` 解析下一首一次，`setNext` 交給後端，有期限就排一個
   計時器在過期前 30 秒重新解析。
4. 引擎自己接上前瞻 → `SourceAdvanced` → `LookAheadTookOver` → `AdoptLookAhead`：
   `session.adoptLookAhead` 換一代，控制器把佇列往下，接上的那首不再解析，再為下一首準備前瞻。
   沒有前瞻時是 `SourceEnded` → `SourceFinished`：單曲循環（`RepeatTrack`）從頭再開，還有下一首
   （`PlayNextTrack`）就照 1 開始，沒有（`FinishQueue`）就 `Idle`。
   前瞻要接什麼由控制器的 `_nextTrack` 決定：單曲循環是目前這首（位置 `null`，接上時
   `adoptLookAhead` 回 `true`、佇列不動），臨時播放中沒有，其他是佇列的下一首。
   前瞻開不起來時後端不接上它：先發前瞻的 `SourceFailed`（session 作廢它的網址快取、放掉
   前瞻，不交給控制器），再發目前這首的 `SourceEnded`，照「沒有前瞻」往下，到那首時重新解析。
5. 失敗（`SourceFailed`、提前結束、解析丟出的 `AppError`、插件說只有試聽片段、緩衝飢餓）→
   控制器的 `_decide`（`decideRecovery` 加上當下的計數、網路狀態、設定，記一筆
   `Playback recovery`）→ `_apply`：重試、等網路、重新解析、換候選、照播試聽、跳過或停下。
   串流本身的失敗（`Recover`、緩衝飢餓）先 `session.invalidateCurrentStream` 作廢快取裡的
   那一筆，所以 `ReResolve` 與重試都會再問插件；解析失敗本來就不進快取。

## 改恢復策略

- 新的情況先在 `recovery_policy.dart` 加一種 `PlaybackFailure` 或 `RecoveryAction`，在
  `recovery_policy_test.dart` 照 design §7.5 的表加一列的案例（`online` 與不是 `online` 各一）；
  控制器的 `_decide` 的 log 欄位（`failure`、`action`）與 `_apply` 的 `switch` 編譯器會指出。
- 計數只在控制器：換一首（`_beginTrack`、交接）時 `_resetTrackCounters`；重試計數另外在位置前進
  累計 10 秒時歸零（`_onProgress`）；重新解析的次數不因此歸零（「同一首第二次」才有意義）。
- 會發提示的結果發 `PlaybackEvent`（`_emitEvent`），不在控制器裡碰 UI；外殼的 `_onPlaybackEvent`
  的 `switch` 編譯器會指出要補的提示。
- 時間：計時器只有一次性的（重試的等待、緩衝飢餓）；要「播了多久」就累計位置，不開週期計時器。

狀態、位置、事件都帶來源 id，session 只轉目前來源的。每個非同步步驟回來時比對
`session.generation`，不同就丟掉結果。

分工：引擎的型別、來源 id、前瞻的計時器與交接的量測 log 在 session；「這個事件該做什麼」
在 `routePlaybackEvent`（新的判斷先在這裡加一個事件或動作，並在
`playback_event_router_test.dart` 加案例）；改狀態、動佇列、恢復計數在控制器。session 要給
控制器新的資訊時，加在 `SessionEvent` 或 `PlaybackSnapshot`，不讓控制器 import 後端。

## 改佇列

- 規則都在 `QueueModel`（純 Dart），控制器只依 `moveNext`／`movePrevious` 回的 `QueueStep`
  做事（`_follow`）：`MovedToTrack` 從頭開始、`RestartTrack` seek 回 0、`ReturnedToQueue` 交給
  `_returnToQueue`（從 `snapshot.resumeAt(...)` 開始、原本在播才播；`current` 為空或進入時
  那首沒載入就停在 `Idle`）、`QueueUnchanged` 不動。
- 控制器加一個編輯入口時：改完 `QueueModel` 呼叫 `_queueEdited()`（發出佇列、重新指定前瞻）；
  編輯換掉了正在播的那首時改走 `_beginTrack`。加入類回傳 `bool`，被拒時 `_add` 發 `QueueFull`。
  在 `playback_controller_test.dart` 的 `editing the queue prepares the look-ahead again` 加一例
  （交接到的是新的下一首、沒有再開流）。
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
- 引擎換到前瞻時先記下 `_PendingHandover`，前瞻真的載入（just_audio：事件有時長；media_kit：
  換過去後的第一個位置或時長）才發 `SourceAdvanced`；載入前的錯誤算前瞻的（`SourceFailed`
  之後補發上一首的 `SourceEnded`，`_ended` 讓狀態不再是在播），載入前 `setNext` 換掉前瞻就停下
  引擎、補發 `SourceEnded`。新的交接邏輯要維持「失敗先到、不發 `SourceAdvanced`」。
- 引擎給的錯誤文字只放 `SourceFailed.cause` 或 log 的 `error:`，不接進訊息字串。HTTP 狀態碼
  只從錄下來的格式取（`backend_rules.dart` 的 `httpStatusFromLogLine`，單元測試附錄下的原文與
  出處）；引擎的新格式先錄一行再加。
- 改完照 `app/AGENTS.md` § 驗證 在 Windows 與 Android 各跑一次真後端的契約。

## 測試

- 控制器：`test/playback/playback_controller_test.dart` 的 `Harness` 在 `fakeAsync` 裡組控制器、
  `FakeAudioBackend`（計時器推進位置，所以假時間也會播完）與 `FakeSourcePlugin`（依請求回候選
  或丟 `AppError`，記下每次請求）。`h.elapse` 前進時間，`h.settle` 只跑微任務。
- 解析次數用 `plugin.resolvedCount(sourceId)`；開了哪些網址用 `h.openedPaths`（起點
  `backend.openedAt`）；前瞻用 `backend.nextSources`；log 用 `h.logged(message)`；控制器的事件
  用 `h.events`。佇列從 `h.playQueue(tracks, startIndex:)` 開始（加入再 `jumpTo`）；臨時播放回到
  佇列讀的設定是 `h.returnSettings`，「跳過試聽片段」是 `h.skipPreviewClips`。
- 恢復的情境：網路狀態用 `h.setNetwork(NetworkStatus.x)`（同時通知控制器）；插件回試聽片段用
  `plugin.previewOnly = (request) => …`；開流被 HTTP 拒絕用 `Harness(failsToOpen:, httpStatusOf:)`
  （`httpStatusOf` 回 `null` 就是 Android 那種沒有狀態碼的失敗）；中途緩衝用 `backend.stall()`、
  `backend.resume()`；播放中中斷用 `backend.interrupt()`。斷言恢復的步驟看 `Playback recovery` 的
  `action` 欄位。
- 後端的清單修改還在排隊時引擎就接上了舊前瞻：`backend.setNextGate` 給一個沒完成的 Future，
  `setNext` 會等它才套用。
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
- 契約的兩種開不起來：`missing`（Dart 端就失敗：不存在的 asset）、`forbidden`（引擎開流時才
  失敗：整合測試在 `setUpAll` 起的 loopback 伺服器一律回 403；假後端以 `failsToOpen`、
  `httpStatusOf` 模擬）。假後端的前瞻在交接時才失敗（ExoPlayer 的形狀）。要看引擎實際怎麼報，
  在 `integration_test/` 寫一個暫時的檔案直接用 just_audio／media_kit 記下每個事件（media_kit
  加 `logLevel: MPVLogLevel.warn` 與 `stream.log`），跑完刪掉。

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
- 佇列編輯與交接撞在一起：`The engine took over a replaced look-ahead; stopping it` 表示引擎
  接上了剛被換掉的前瞻，session 停下它、控制器重新開流（下一筆是新的下一首的 `Track
  requested`，或佇列到底時的 `Queue finished`）。log 看不出被換掉的那首有沒有出聲（session
  不轉它的回報），要用耳朵確認。
- 前瞻開不起來：`Look-ahead failed to open`（`track` 是下一首，Windows 有 `httpStatus`）之後
  沒有 `Look-ahead handover`；下一筆是那一首的 `Track requested` 與 `Resolving stream`（重新
  解析）。重播模式用測試插件的關鍵字 `missing`（`test_plugin/README.md`）。那首開流再失敗時
  照恢復表走：沒有狀態碼先 `Playback recovery` 的 `action: reResolve`（再一筆 `Resolving
  stream`），仍失敗才跳過或停下。
- 恢復：每次決定一筆 `Playback recovery`（`failure`、`error`、`action`，不在 `online` 時有
  `network`，開流被拒時有 `httpStatus`）。等網路是 `action: waitForNetwork`，網路回來時一筆
  `Network is back; retrying` 接著 `Track requested`；網路狀態本身看 tag `network-status` 的
  `Network status changed`。正常播放 10 秒後重試計數歸零記 `Retry count reset after normal
  playback`；緩衝飢餓記 `Buffering stalled`。試聽片段不當前瞻時記 `Look-ahead skipped: preview
  only`。測試插件的關鍵字 `preview`、`flaky`、`unavailable` 造這些情境（`test_plugin/README.md`）。
- 真實連線（ADR 0027 §決定 2 的最少操作）：B 站播一首，看 `Opening stream` 的 `headers` 有
  `Referer`。
