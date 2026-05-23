# Bilibili Source Review

## Findings

1. **[High] Bilibili 多 P 播放、下載與 lower-quality fallback 會忽略 `Track.cid`，可能解析到影片預設分 P。**
   證據位置：`lib/data/models/track.dart:240`、`lib/data/models/video_detail.dart:40`、`lib/services/audio/internal/audio_stream_delegate.dart:74`、`lib/services/download/download_service.dart:706`、`lib/data/sources/bilibili_source.dart:214`、`lib/data/sources/bilibili_source.dart:223`、`lib/data/sources/bilibili_source.dart:231`、`lib/data/sources/bilibili_source.dart:646`。
   Bilibili track 已有 `cid` 作為分 P 身分，`VideoPage.toTrack()` 也會把 page cid 寫進 track。但播放 primary resolution 與下載 primary resolution 都只把 `track.sourceId` 傳進 shared quality fallback helper；`BilibiliSource.getAudioStream()` 隨後重新查 view API 的 `data.cid`，再用該 cid 取流。這條 shared path 沒有使用已保存的 `Track.cid`，而 source 內其實已有 `getAudioStreamWithCid()` 可支援分 P。`AudioStreamDelegate.getAlternativeAudioStream()` 在 lower-quality fallback 呼叫 `source.getAudioStream(track.sourceId, ...)` 的路徑同樣沒有 cid。

2. **[Medium] Bilibili 帳號的直播間匯入路徑使用一般 API Dio 打 live API，沒有套用 live header policy。**
   證據位置：`lib/services/account/bilibili_account_service.dart:74`、`lib/services/account/bilibili_account_service.dart:77`、`lib/services/account/bilibili_account_service.dart:488`、`lib/services/account/bilibili_account_service.dart:511`、`lib/data/sources/source_http_policy.dart:111`、`lib/data/sources/source_http_policy.dart:143`。
   `BilibiliAccountService` 建構的 `_dio` 是 `SourceHttpPolicy.createApiDio(SourceType.bilibili)`，但 `fetchMedalWall()` 會用同一個 `_dio` 呼叫 `api.live.bilibili.com/xlive/.../MedalWall` 與 `api.live.bilibili.com/room/v1/Room/getRoomInfoOld`。相較之下，live policy 明確提供 `bilibiliLiveHeaders()` / `createBilibiliLiveDio()`，其中 Referer 是 `https://live.bilibili.com/`。這會讓帳號直播間匯入成為目前 live API header policy 的例外。

3. **[Medium] Bilibili 沒有實作 same-quality alternative stream；runtime URL 失敗後無法排除 failed URL 並改用 DASH backup 或 muxed durl。**
   證據位置：`lib/data/sources/base_source.dart:211`、`lib/data/sources/base_source.dart:217`、`lib/data/sources/bilibili_source.dart:346`、`lib/data/sources/bilibili_source.dart:348`、`lib/data/sources/bilibili_source.dart:387`、`lib/services/audio/internal/audio_stream_delegate.dart:133`、`lib/services/audio/internal/audio_stream_delegate.dart:152`。
   `BaseSource.getAlternativeAudioStream()` 預設回傳 `null`，`BilibiliSource` 沒有 override。DASH 解析只取 `baseUrl` / `base_url` / 第一個 `backupUrl`，durl 也只取第一個 URL；runtime handoff 失敗時，delegate 會先問 source alternative，再試 lower-quality primary stream，最後同品質 alternative 仍回到預設 `null`。因此播放器已知某個 Bilibili CDN URL 失敗時，source 沒有機制用 `failedUrl` 排除它，也不會在同品質內轉向其他 backup URL 或 muxed durl。

## Evidence

- Bilibili direct source 使用獨立的一般 API Dio 與 live Dio：`lib/data/sources/bilibili_source.dart:77` 建立一般 `_dio`，`lib/data/sources/bilibili_source.dart:84` 建立 `_liveDio`，live room info/play URL 走 `_liveDio`（`lib/data/sources/bilibili_source.dart:1084`、`lib/data/sources/bilibili_source.dart:1122`）。這符合 live helper 不重用 search/API Dio 的規範。
- 一般 Bilibili API/media header policy 已集中在 `SourceHttpPolicy`：Bilibili media headers 是 `Referer: https://www.bilibili.com` 與 media UA（`lib/data/sources/source_http_policy.dart:37` 到 `lib/data/sources/source_http_policy.dart:41`）；API headers 是 `Referer: https://www.bilibili.com/`、`Origin: https://www.bilibili.com`（`lib/data/sources/source_http_policy.dart:71` 到 `lib/data/sources/source_http_policy.dart:77`）；search API 另外保留 search host 與 buvid cookie（`lib/data/sources/source_http_policy.dart:95` 到 `lib/data/sources/source_http_policy.dart:108`）。
- Bilibili auth-for-play 只進 stream-resolution，不進 media/CDN headers：播放 resolver 依 `settings.useAuthForPlay(track.sourceType)` 取得 auth headers（`lib/services/audio/internal/audio_stream_delegate.dart:69` 到 `lib/services/audio/internal/audio_stream_delegate.dart:79`），下載 resolver 也同樣讀 setting（`lib/services/download/download_service.dart:699` 到 `lib/services/download/download_service.dart:711`）；但 `SourceHttpPolicy.mediaHeaders()` 只在 Netease 時合併 auth（`lib/data/sources/source_http_policy.dart:54`），Bilibili media headers 保持窄邊界。
- Bilibili rate-limit API code 有保留語義：`_checkResponse()` 把 `-412`、`-509`、`-799` 轉成 `BilibiliApiException`（`lib/data/sources/bilibili_source.dart:839` 到 `lib/data/sources/bilibili_source.dart:842`），`BilibiliApiException.kind` 會把這些 code 分類為 `SourceErrorKind.rateLimited`（`lib/data/sources/bilibili_exception.dart:26` 到 `lib/data/sources/bilibili_exception.dart:30`）。
- Bilibili stream type fallback 有保留 non-fallbackable error kind：`_getAudioStreamWithCid()` 在 stream type loop 中用 `_shouldAbortStreamFallback()` 判斷，遇到不可降級的 `SourceApiException.kind` 會直接 throw（`lib/data/sources/bilibili_source.dart:261` 到 `lib/data/sources/bilibili_source.dart:267`），而可降級範圍由 `SourceErrorKind.canFallbackToLowerAudioQuality` 限定為 unavailable / vipRequired（`lib/data/sources/source_exception.dart:24` 到 `lib/data/sources/source_exception.dart:26`）。
- Bilibili URL expiry metadata 已與 track TTL 對齊：DASH 與 durl 都回傳 `AudioStreamResult.expiry`（`lib/data/sources/bilibili_source.dart:360`、`lib/data/sources/bilibili_source.dart:397`），track refresh 也用同一個 `AppConstants.bilibiliAudioUrlExpiryHours`（`lib/data/sources/bilibili_source.dart:432`、`lib/core/constants/app_constants.dart:26`）。
- Download audio/image headers 是 source-aware：音訊下載用 `buildDownloadMediaHeaders()`（`lib/services/download/download_service.dart:764`），metadata 封面與頭像用 `buildDownloadImageHeaders()`（`lib/services/download/download_service.dart:1176`），實際 image download 有傳 `Options(headers: imageHeaders)`（`lib/services/download/download_service.dart:1244`、`lib/services/download/download_service.dart:1260`）。
- Thumbnail URL optimization 的 Bilibili 規則是 width-only suffix：`ThumbnailUrlUtils` 判斷 hdslb/bilibili URL（`lib/core/utils/thumbnail_url_utils.dart:75` 到 `lib/core/utils/thumbnail_url_utils.dart:78`），移除既有 `@...` suffix 後加 `@{size}w.jpg`（`lib/core/utils/thumbnail_url_utils.dart:97` 到 `lib/core/utils/thumbnail_url_utils.dart:109`）。

## Source-specific reason if applicable

- Finding 1 是 Bilibili-specific。Bilibili 多 P 的真實播放身分是 `bvid + cid`；YouTube / Netease 用單一 `sourceId` 解析音訊通常是正確抽象。修正時應讓 Bilibili 的 resolver 保留 cid，而不是把 cid/page semantics 推到所有 source。
- Finding 2 是 Bilibili live/account-specific。帳號匯入需要 Cookie，但 live API 仍應保留 live Referer / live media UA。修正方向不應把 live Referer 套到一般 Bilibili video/search/favorites API。
- Finding 3 是 Bilibili runtime fallback-specific。Bilibili DASH response 可能有 `backupUrl`，且同一影片也可能可用 durl muxed stream；這些是 Bilibili 自有的 fallback 素材，不應要求 shared layer 猜測 Bilibili URL 結構。

## Suggested direction

1. 建立 cid-aware Bilibili stream resolver：播放、下載、lower-quality fallback 若 `track.sourceType == SourceType.bilibili && track.cid != null`，應走 `BilibiliSource.getAudioStreamWithCid(track.sourceId, track.cid!, config: ..., authHeaders: ...)`，同時保留現有 high -> medium -> low fallback 與 non-fallbackable error kind 行為。避免把這個判斷散落在多個呼叫點；可以做一個以 `Track` 為輸入的 shared resolver。
2. 讓 `BilibiliAccountService.fetchMedalWall()` 的 live API 呼叫使用 live header policy，同時在 request options 中合併 Cookie。若需要保留一般 account API Dio，請為 live account import 建立專用 live Dio 或局部 options，不要改變一般 Bilibili account/nav/favorites API 的 header。
3. 在 `BilibiliSource` override `getAlternativeAudioStream()`：同 cid、同 quality 下先排除 `failedUrl` 後嘗試 DASH `backupUrl`，再依 Bilibili stream priority 嘗試 durl muxed；遇到 rate-limit/login/permission/network/timeout/geo 等 non-fallbackable error 必須 rethrow，不要回傳 `null`。
4. 補測試：Bilibili 多 P playback/download/fallback 都使用指定 cid；Bilibili account medal wall live API 使用 live Referer 並保留 Cookie；runtime failed DASH URL 可 fallback 到 backup/durl，且 rate-limit/login 類錯誤不被 alternative fallback 吞掉。

## Instruction docs accuracy notes

- `lib/data/sources/AGENTS.md` 對 Bilibili DASH audio-only、durl muxed、多 P、收藏夾、Referer、rate-limit code、URL expiry、auth/media header 邊界的規範大致可由當前程式碼驗證。
- `lib/data/sources/AGENTS.md:11` 說「Live room audio streams use HLS」，但同一檔 `lib/data/sources/AGENTS.md:113` 又說「live streams always muxed」。當前程式碼在 `lib/services/radio/radio_source.dart:266` 到 `lib/services/radio/radio_source.dart:290` 以及 `lib/data/sources/bilibili_source.dart:1122` 到 `lib/data/sources/bilibili_source.dart:1140` 都是呼叫 `Room/playUrl` 並取 `data.durl[0].url`，不是 HLS manifest。建議修正文檔，除非後續改實作到 HLS API。
- `lib/data/sources/AGENTS.md` 要求 live room API clients 使用 live header policy；`BilibiliSource` 與 `RadioSource` 已符合，但 `BilibiliAccountService.fetchMedalWall()` 的 live API 例外未被文件點出，對應 Finding 2。
- `docs/development.md:101` 與 `README.md:46` 對 Bilibili「視頻音頻、多 P、直播間音頻、收藏夾」的描述只作為功能索引；本報告沒有把它們當作事實，已用 `bilibili_source.dart`、`radio_source.dart`、`download_service.dart` 與 shared resolver 程式碼逐項驗證。
- `docs/history/refactoring-log.md` 僅作背景；本報告沒有引用其歷史描述作為 finding 證據。
