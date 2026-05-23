# Playback / Download Integration Review

## Findings

1. **Bilibili 多 P 遠端播放、下載與播放 handoff fallback 會忽略 `Track.cid`，可能抓到第一 P 音訊。**
   播放 primary resolution 在 `lib/services/audio/internal/audio_stream_delegate.dart:74` 透過 `fetchAudioStreamWithQualityFallback()` 只傳 `track.sourceId`，下載路徑在 `lib/services/download/download_service.dart:706` 也只傳 `track.sourceId`。Bilibili 的通用 `getAudioStream()` 會先從 view API 取影片預設 `cid`（`lib/data/sources/bilibili_source.dart:223`），再用該 cid 取流（`lib/data/sources/bilibili_source.dart:231`）。但同一 source 已有 cid-aware 路徑，`refreshAudioUrl()` 會在 `track.cid != null` 時呼叫 `getAudioUrlWithCid()`（`lib/data/sources/bilibili_source.dart:425`），且 public `getAudioStreamWithCid()` 存在於 `lib/data/sources/bilibili_source.dart:646`。播放 handoff fallback 也同樣在 `lib/services/audio/internal/audio_stream_delegate.dart:141` 用 `source.getAudioStream(track.sourceId, ...)` 嘗試低音質 fallback，因此 Bilibili 多 P 的 fallback 也沒有 cid。

2. **Netease 播放 media headers 與下載 media headers 對 `useNeteaseAuthForPlay` 的處理不一致。**
   播放 header path 在 `lib/services/audio/audio_stream_manager.dart:181` 進入 `getPlaybackHeaders()` 後，只要來源是 Netease 就直接向 `_neteaseAccountService` 取 auth（`lib/services/audio/audio_stream_manager.dart:182`），再傳給 `SourceHttpPolicy.mediaHeaders()`（`lib/services/audio/audio_stream_manager.dart:185`）。下載 path 則先讀設定，只有 `settings.useAuthForPlay(track.sourceType)` 為 true 才取得 auth（`lib/services/download/download_service.dart:702`），並把同一份 auth 交給下載 media headers（`lib/services/download/download_service.dart:764`）。差異只會實際影響 Netease，因為 `SourceHttpPolicy.mediaHeaders()` 只在 Netease 且 `authHeaders != null` 時合併 `Cookie` / `Origin` / `Referer` / `User-Agent`（`lib/data/sources/source_http_policy.dart:54`）。

## Evidence

- Primary stream resolution 已共用同一個 quality fallback helper：播放在 `lib/services/audio/internal/audio_stream_delegate.dart:74` 呼叫 `fetchAudioStreamWithQualityFallback()`，下載在 `lib/services/download/download_service.dart:706` 呼叫同一 helper；helper 本身按照 high -> medium -> low 梯度呼叫 `source.getAudioStream()`（`lib/data/sources/audio_stream_quality_fallback.dart:33`、`lib/data/sources/audio_stream_quality_fallback.dart:40`），且只對 `SourceErrorKind.canFallbackToLowerAudioQuality` 允許的錯誤繼續降級（`lib/data/sources/audio_stream_quality_fallback.dart:49`）。
- 播放 alternative stream handoff 先試低音質 alternative，再試低音質 primary stream，最後才回到同音質 source alternative：見 `lib/services/audio/internal/audio_stream_delegate.dart:128`、`lib/services/audio/internal/audio_stream_delegate.dart:133`、`lib/services/audio/internal/audio_stream_delegate.dart:141`、`lib/services/audio/internal/audio_stream_delegate.dart:152`。這個順序符合目前 instruction docs 的描述，但 Bilibili cid 問題仍存在於 `source.getAudioStream(track.sourceId, ...)`。
- Download media/image headers 有走 helper，不依賴 Dio defaults：音訊下載 headers 由 `buildDownloadMediaHeaders()` 建立（`lib/services/download/download_service.dart:764`），封面與頭像 headers 由 `buildDownloadImageHeaders()` 建立（`lib/services/download/download_service.dart:1176`），實際 image download 有傳 `Options(headers: imageHeaders)`（`lib/services/download/download_service.dart:1244`、`lib/services/download/download_service.dart:1260`）。`DownloadService` 的 Dio default 只有 `User-Agent`（`lib/services/download/download_service.dart:159`），沒有硬編某一 source 的 Referer。
- 三個 source 的 stream metadata 回傳大致完整但 source-specific：Bilibili DASH 回傳 bitrate/container/codec/streamType/expiry（`lib/data/sources/bilibili_source.dart:354`），Bilibili durl 因 muxed 無準確音訊碼率而 `bitrate: null`（`lib/data/sources/bilibili_source.dart:391`）；YouTube audio-only/muxed/HLS 分別回傳對應 metadata（`lib/data/sources/youtube_source.dart:406`、`lib/data/sources/youtube_source.dart:448`、`lib/data/sources/youtube_source.dart:492`）；Netease 回傳 br/type/codec/audioOnly/16 分鐘 expiry（`lib/data/sources/netease_source.dart:154`）。
- 錯誤分類已有統一基類：`SourceErrorKind.canFallbackToLowerAudioQuality` 僅允許 unavailable / vipRequired 降級（`lib/data/sources/source_exception.dart:24`），`AudioController` 對 retry、skip、rate-limit 使用 `SourceApiException.kind`（`lib/services/audio/audio_provider.dart:2053`、`lib/services/audio/audio_provider.dart:2112`、`lib/services/audio/audio_provider.dart:2141`）。

## Source-specific reason if applicable

- Finding 1 是 **Bilibili-specific**。Bilibili 多 P 的可播放實體由 `bvid + cid` 決定；YouTube 與 Netease 的整合層用 `sourceId` 取單首音訊是合理的，不應為了統一把它們改成 cid/page semantics。
- Finding 2 是 **Netease-specific**。目前 media auth 邊界刻意不把 Bilibili cookie 或 YouTube authorization 傳給 CDN/media request；這由 `SourceHttpPolicy.mediaHeaders()` 的 Netease-only merge 證明（`lib/data/sources/source_http_policy.dart:54`）。建議只校正 Netease 播放與下載對 user setting 的一致性，不要把 Bilibili/YouTube auth header 也塞進 media requests。

## Suggested direction

1. 對 Bilibili 建立 cid-aware stream resolution adapter，而不是讓整合層散落 `if (source is BilibiliSource)`。可行方向是讓 `AudioStreamDelegate` / `DownloadService` 的 shared resolver 接收 `Track`，在 Bilibili 且 `track.cid != null` 時呼叫 `getAudioStreamWithCid(track.sourceId, track.cid!, config: ..., authHeaders: ...)`，並讓 quality fallback 仍使用同一個降級梯度。這樣 primary playback、download、alternative lower-quality fallback 才會一致。
2. 對 Netease 播放 media headers，讓 `getPlaybackHeaders()` 使用與 stream resolution 同一個 auth decision：若 `settings.useAuthForPlay(SourceType.netease)` 為 false，就不要取或合併 Netease media Cookie。若未來需要「URL 解析不用 auth，但 media request 仍需 auth」這種獨立設定，應明確新增 setting/docs，而不是讓播放 path 暗中不同於下載 path。
3. 補測試時優先覆蓋：Bilibili multi-P `Track.cid` 在 playback primary、download primary、playback fallback 中都被傳到 cid-aware stream getter；Netease `useNeteaseAuthForPlay=false` 時 playback/download media headers 都不帶 Cookie，true 時都帶允許清單內的 Netease media auth。

## Instruction docs accuracy notes

- `lib/services/AGENTS.md` 關於下載必須用 `buildDownloadMediaHeaders()` / `buildDownloadImageHeaders()` 的規範，已由 `lib/services/download/download_service.dart:764` 與 `lib/services/download/download_service.dart:1176` 驗證為準確。
- `lib/data/sources/AGENTS.md` 關於 media headers 比 stream-resolution auth headers 更窄、且目前只允許 Netease media request 合併 auth 的描述，已由 `lib/data/sources/source_http_policy.dart:54` 驗證為準確；但它沒有點出播放 `getPlaybackHeaders()` 目前不讀 `useNeteaseAuthForPlay`，這是 Finding 2 的文件缺口。
- `lib/data/sources/AGENTS.md` 說 Bilibili 支援 multi-page，且 source code 確實有 `getAudioStreamWithCid()`（`lib/data/sources/bilibili_source.dart:646`）；但目前 instruction docs 沒有明確要求播放/下載整合層必須保留 `Track.cid` 進 stream resolver。若修 Finding 1，建議補上這條整合層規範。
- `docs/history/refactoring-log.md` 僅作背景；本報告沒有把其中描述當作當前事實，所有 finding 都以當前程式碼行號驗證。
