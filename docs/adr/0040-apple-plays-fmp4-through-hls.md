# 0040 — Apple 平台把單檔 fragmented MP4 串流包成 byte-range HLS 交給 AVPlayer

- 狀態：已採納
- 日期：2026-11-18
- 影響範圍：`app/lib/playback/backends/`（just_audio 後端、HLS 包裝）、`app/lib/platform/audio_backend.dart`、`app/lib/domain/audio_stream.dart`、插件的 `resolveStream` 回應（ADR 0039）、`app/macos/Runner/Release.entitlements`

## 背景

B 站的音訊軌是單一個 fragmented MP4 檔（`.m4s`：ftyp、moov、一個 sidx、每 5 秒一段 moof＋mdat）。B 站 CDN 偶爾會把長的下載連線在中途關掉（事實 F24）。AVPlayer（macOS 27、iOS 27 模擬器）遇到時，把斷線前接得上的那一段當成整個檔：`duration` 與可 seek 範圍變短（看過 59:33 的曲目報 33:10、3:08:28 的報 20:53 與 6:00），播到那裡就發 `DidPlayToEndTime`，seek 超過那裡也一樣，之後重開同一網址也一樣（事實 M14）。ExoPlayer 與 mpv 會續傳，Android、Windows 不受影響。只改顯示擋不住「播到一半就停、跳下一首」（M1 票 06b）。

## 考慮過的選項

### 選項 A：byte-range HLS 包裝

依檔頭的 sidx 產生一份 VOD 的 HLS 清單：每段一個 `EXT-X-BYTERANGE`（約 5 秒、200 KB），`EXT-X-MAP` 指 init 的範圍，長度寫在 `EXTINF`。AVPlayer 照清單一段一段直接向 CDN 要，連線短，被斷也只影響那一段。清單由 App 內只聽 127.0.0.1 的伺服器提供。實測：會斷線的假 CDN 上長度精確、seek 到 50 分照常播，片段請求帶著原本的 Referer 與 User-Agent（事實 M15）。缺點：Apple 專屬的程式路徑；播放前多一個小的 Range 請求；`file://` 的清單 AVPlayer 不播，所以要本機伺服器。

### 選項 B：Apple 平台也改用 media_kit（mpv）

mpv 會續傳。缺點：推翻 brief「Android、iOS、macOS 用 just_audio」，App 變大，iOS 的背景播放與音訊工作階段要重驗。

### 選項 C：AVPlayer 停在假結尾時重開並 seek 回去

實測不行：重開的項目又被斷線截短，seek 被夾回去，甚至倒退（事實 M14）。

### 選項 D：媒體經 Dart 轉送（just_audio 的本機 proxy、`StreamAudioSource`）

Dart 能在斷線時續傳。缺點：媒體繞過原生播放器的網路堆疊，正是 M0 不用 just_audio 本機 proxy 的理由（事實 K25）。

### 選項 E：`AVAssetResourceLoaderDelegate`

just_audio 不開放，等於自己寫一個 Apple 播放器。

## 決定

選 A（2026-11-18 擁有者選）。

- 插件的 `resolveStream` 回應多一個選填的 `segmentBase`：`{"initialization": "0-836", "indexRange": "837-9432"}`，兩個都是含頭尾的位元組範圍，命名照 MPEG-DASH 的 `SegmentBase`（`Initialization@range`、`@indexRange`）。串流是單檔 fragmented MP4、而且插件拿得到這兩個範圍時才給；bilibili 照 playurl 的 `SegmentBase` 填。宿主收進 `AudioStream.segmentBase`；格式不對時整次解析算解析失敗。
- 只有 Apple 平台的音訊後端（`platform/audio_backend.dart` 決定）用它：串流有 `segmentBase` 時，用串流的 header 對 `indexRange` 發一次 Range 請求、解析 sidx，產生清單（`EXT-X-VERSION:7`、`EXT-X-PLAYLIST-TYPE:VOD`、`EXT-X-MAP`、每段 `EXTINF`＋`EXT-X-BYTERANGE`、`EXT-X-ENDLIST`），由只聽 127.0.0.1、路徑是隨機字串的伺服器提供，交給 just_audio 播，header 照舊經 `AVURLAssetHTTPHeaderFieldsKey` 帶到每個片段請求。媒體不經 Dart。伺服器第一次用到才開，只留最近的幾份清單。
- 抓索引或解析失敗時照舊直接播網址，寫一筆 warning。Android 與 Windows 不看 `segmentBase`。
- macOS 的 Release entitlements 加 `com.apple.security.network.server`（Debug 已有）：沙盒裡聽 loopback 也要它。

採用的慣例：HLS 的 byte-range 與 fMP4 分段（RFC 8216 §4.3.2.2、§4.3.2.5）；DASH 播放器（dash.js、Shaka）處理 `SegmentBase` 也是先讀 sidx、再照它逐段發 Range 請求。

## 後果

- 好的：Apple 平台的長度精確、seek 不受斷線影響；每個請求都短。
- 壞的：每次載入多一個小的 Range 請求（約 10–30 KB）；多一條 Apple 專屬的路徑與一個本機伺服器；清單裡的簽名網址在 loopback 上可讀，靠隨機路徑擋。
- 之後要注意：預載下一首（票 12）同時有兩份清單；串流過期重新解析（票 11）要產生新清單；背景播放（票 13）要確認 App 在背景時 AVPlayer 不需要再要清單（VOD 只要一次）；YouTube 若給得出同樣的兩個範圍，照填即可。

## 如何確認

- 單元測試：sidx 解析、清單產生、宿主收 `segmentBase` 的格式檢查。
- `integration_test/stream_duration_test.dart`：本機假 CDN 每個回應傳 1 MB 就斷，macOS 與 iOS 模擬器上這個後端的長度要對、seek 過斷點要繼續播；不走 HLS 時這條是紅的。
- 契約測試：bilibili 的 resolveStream fixture 要有 `segmentBase`。
