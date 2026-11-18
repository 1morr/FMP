# B 站串流的出聲時間（2026-11-18）

票 11 看門狗的兩個門檻（`app/lib/playback/playback.dart` 的 `stallTimeoutsProvider`）照這裡的數字定，結論寫成事實 F25。換音訊後端或套件版本時用同一支情境重量。

## 量法

- 情境：`app/integration_test/real_run/start_time_run.dart`，跑法 `dart run tool/real_run.dart -d <平台> integration_test/real_run/start_time_run.dart`（docs/development.md〈實跑驅動〉）。
- 匿名搜一次「lofi 3小时」，臨時播放畫出來的結果裡最長與最短的一首。
- 量的是 `playbackProvider` 的狀態時間：點下到「載入中」（解析），「載入中」到第一次「播放中」（開始載入到出聲），以及出聲後 20 秒內進入「緩衝中」的次數與最久的一次。
- 只搜一次，所以「短」的那首是結果裡最短的 34:06，不是一般長度的歌。
- 程式：`0b121de5` 前後的工作目錄（Apple 平台走 byte-range HLS，ADR 0040）。Flutter 3.47.5；iPhone 18 Pro 模擬器、Android 模擬器 `Medium_Phone_API_37.0`、`winpc`。

## 結果

| 平台 | 3:11:49：解析 | 3:11:49：開始載入到出聲 | 34:06：解析 | 34:06：開始載入到出聲 | 出聲後 20 秒內緩衝 |
| --- | --- | --- | --- | --- | --- |
| macOS | 343 ms | 391 ms | 336 ms | 240 ms | 1 次，1 ms |
| iOS 模擬器 | 180 ms | 530 ms | 267 ms | 267 ms | 1 次，5 ms |
| Android 模擬器 | 387 ms | 841 ms | 282 ms | 225 ms | 0 |
| Windows | 391 ms | 229 ms | 311 ms | 196 ms | 0 |

## 先前的零星觀察

不是同一套量法，但都是「正常但慢」的開頭，門檻不能切掉它們：

- M0 驗收（2026-11-12）：macOS 直接播 45 分鐘的 m4a，點下到「播放中」約 15 秒，解析只占 150 ms（`.scratch/m0/issues/12-m0-acceptance.md`）。
- 票 06b（2026-11-18）：iOS 直接播 3 小時長片，開頭卡過 15–38 秒；改走 byte-range HLS 後約 8 秒。

## 門檻

- 開始載入到出聲：45 秒。已知最慢 38 秒（iOS 直接播），再留約 20% 餘裕；Android、Windows 不走 HLS，一樣可能碰到 CDN 慢的時候。
- 播放中途卡住：15 秒，照舊版的 `bufferStarvation`（`legacy:lib/core/constants/app_constants.dart`）；這次量到的中途緩衝最久 5 ms，沒有反例。
