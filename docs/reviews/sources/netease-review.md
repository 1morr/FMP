# Netease Source Review

## Findings

1. **[Medium] Netease 播放 media headers 會繞過 `useNeteaseAuthForPlay`，與下載和 stream resolution 的 auth 決策不一致。**
   證據位置：`lib/services/audio/internal/audio_stream_delegate.dart:71`、`lib/services/audio/internal/audio_stream_delegate.dart:74`、`lib/services/download/download_service.dart:702`、`lib/services/download/download_service.dart:706`、`lib/services/audio/audio_stream_manager.dart:181`、`lib/services/audio/audio_stream_manager.dart:182`、`lib/data/sources/source_http_policy.dart:54`、`lib/data/sources/source_http_policy.dart:55`。
   播放 primary stream 與 fallback 解析會依 `settings.useAuthForPlay(track.sourceType)` 決定是否取 auth headers，下載解析與下載 media headers 也使用同一個 setting。但真正交給播放器的 `getPlaybackHeaders()` 對 Netease 一律呼叫 `_neteaseAccountService?.getAuthHeaders()`，而 `SourceHttpPolicy.mediaHeaders()` 只要收到 Netease authHeaders 就合併 Cookie/Origin/Referer/User-Agent。結果是使用者關閉 `useNeteaseAuthForPlay` 後，播放 media request 仍可能帶 `MUSIC_U`，而下載不會。

2. **[Medium] 外部 Netease playlist import source 硬編 Netease HTTP headers，未使用 shared `SourceHttpPolicy`。**
   證據位置：`lib/data/sources/playlist_import/netease_playlist_source.dart:12`、`lib/data/sources/playlist_import/netease_playlist_source.dart:120`、`lib/data/sources/playlist_import/netease_playlist_source.dart:126`、`lib/data/sources/playlist_import/netease_playlist_source.dart:127`、`lib/data/sources/playlist_import/netease_playlist_source.dart:129`、`lib/data/sources/playlist_import/netease_playlist_source.dart:170`、`lib/data/sources/playlist_import/netease_playlist_source.dart:176`、`lib/data/sources/playlist_import/netease_playlist_source.dart:177`、`lib/data/sources/playlist_import/netease_playlist_source.dart:179`、`lib/data/sources/source_http_policy.dart:66`、`lib/data/sources/source_http_policy.dart:83`。
   `NeteasePlaylistSource` 直接建 `Dio()`，並在 playlist detail/song detail request 中重複寫 `User-Agent` 與 `Referer`。這和 direct `NeteaseSource`、account service 使用 `SourceHttpPolicy.createApiDio()` 的 shared policy 不一致，也讓 Netease Referer/UA 若未來調整時容易漏改外部歌單導入路徑。

3. **[Low] Netease login-required 的 semantic `code` 字串與其他 source 不一致，雖然 `SourceErrorKind` 仍正確。**
   證據位置：`lib/data/sources/bilibili_exception.dart:50`、`lib/data/sources/youtube_exception.dart:30`、`lib/data/sources/netease_exception.dart:37`、`lib/data/sources/netease_exception.dart:51`、`lib/data/sources/netease_exception.dart:52`、`test/data/sources/source_exception_test.dart:235`、`test/data/sources/source_exception_test.dart:237`。
   Bilibili 與 YouTube 使用 `login_required`，Netease 301 的 `SourceErrorKind` 是 `loginRequired`，但 `code` 回傳 `requires_login`。目前播放層主要使用 `kind`，所以這不是播放錯誤分類缺陷；但 shared exception contract 的 `code` getter 被註解為語義化錯誤碼，三音源字串不一致會增加測試、診斷或未來 UI 直接使用 `code` 時的分歧。

## Evidence

- Netease audio stream 使用 eapi 加密與 `/eapi/song/enhance/player/url/v1`：`lib/data/sources/netease_source.dart:116`、`lib/data/sources/netease_source.dart:117`、`lib/data/sources/netease_source.dart:120`，加密實作位於 `lib/core/utils/netease_crypto.dart:67` 到 `lib/core/utils/netease_crypto.dart:82`。
- Netease auth-for-play default 是 true，且 Settings 與 provider 預設一致：`lib/data/models/settings.dart:236`、`lib/data/models/settings.dart:237`、`lib/providers/audio_settings_provider.dart:54`、`lib/providers/audio_settings_provider.dart:56`；舊資料修復也會把未遷移的 `useNeteaseAuthForPlay` 設回 true（`lib/providers/database_provider.dart:173` 到 `lib/providers/database_provider.dart:177`）。
- `MUSIC_U` 作為長期 token 的帳號語義已在 account service 中落實：`lib/services/account/netease_account_service.dart:19`、`lib/services/account/netease_account_service.dart:20`；`getAuthCookieString()` 回傳 credential cookie（`lib/services/account/netease_account_service.dart:238` 到 `lib/services/account/netease_account_service.dart:241`），`getAuthHeaders()` 回傳完整 playback/media header（`lib/services/account/netease_account_service.dart:244` 到 `lib/services/account/netease_account_service.dart:249`）。
- Netease stream error classification 保留 VIP/copyright/region 語義：`_classifyStreamUnavailable()` 先看 `fee/code/flag/message`（`lib/data/sources/netease_source.dart:735` 到 `lib/data/sources/netease_source.dart:741`），VIP/付費轉 `-10`（`lib/data/sources/netease_source.dart:743` 到 `lib/data/sources/netease_source.dart:747`），copyright/region 轉 `-110`（`lib/data/sources/netease_source.dart:750` 到 `lib/data/sources/netease_source.dart:759`）。對應測試涵蓋 copyright、VIP message、404 + copyright flag、404 + VIP flag（`test/data/sources/netease_source_test.dart:8`、`test/data/sources/netease_source_test.dart:34`、`test/data/sources/netease_source_test.dart:60`、`test/data/sources/netease_source_test.dart:87`）。
- Netease song detail batch 與 playlist import 的 400 IDs batch 符合文檔：direct source 在 `lib/data/sources/netease_source.dart:296` 到 `lib/data/sources/netease_source.dart:303` 分批；account playlist service 在 `lib/services/account/netease_playlist_service.dart:321` 到 `lib/services/account/netease_playlist_service.dart:328` 分批。
- Netease audio URL expiry 目前固定 16 分鐘並寫入 stream metadata：`lib/data/sources/netease_source.dart:28`、`lib/data/sources/netease_source.dart:154`、`lib/data/sources/netease_source.dart:160`，refresh path 也使用同一 TTL（`lib/data/sources/netease_source.dart:340` 到 `lib/data/sources/netease_source.dart:344`）。
- Netease source-owned cookie merge 保持 narrow：source request 只從 authHeaders 取 Cookie（`lib/data/sources/netease_source.dart:672` 到 `lib/data/sources/netease_source.dart:677`），而 media header merge 的 allowlist 在 `SourceHttpPolicy.mediaHeaders()` 中限定為 Netease（`lib/data/sources/source_http_policy.dart:54` 到 `lib/data/sources/source_http_policy.dart:60`）。

## Source-specific reason if applicable

- Finding 1 是 Netease-specific。Netease media/CDN request 帶 Cookie 是合理的 source-specific 行為，因為部分歌曲需要 `MUSIC_U` 才可播放；問題不是「Netease 不該帶 Cookie」，而是播放與下載對同一個 auth-for-play 設定的解讀不同。
- Finding 2 涉及外部歌單導入。Netease playlist import 使用 public `/api/v6/playlist/detail` 與 `/api/v3/song/detail` 是合理的 source-specific API 選擇；不合理的是 header policy 沒有走 shared helper。
- Finding 3 只影響 semantic string consistency。Netease 數字碼 301 仍正確映射到 `SourceErrorKind.loginRequired`，因此不應為了統一 `code` 字串改壞既有 `kind` 行為或播放 UI。

## Suggested direction

1. 讓 `AudioStreamManager.getPlaybackHeaders()` 讀取與 stream resolution 相同的 auth decision。若 `settings.useAuthForPlay(SourceType.netease)` 為 false，播放 media headers 不應合併 Netease Cookie；true 時保留目前 Netease-only Cookie/Origin/Referer/UA allowlist。
2. 將 `NeteasePlaylistSource` 改為透過 `SourceHttpPolicy.createApiDio(SourceType.netease)` 或 `SourceHttpPolicy.apiHeaders(SourceType.netease)` 建立 request headers。若 playlist import 需要不同 UA，應以 `userAgent:` 參數表達，而不是散落硬編 header。
3. 評估是否把 `NeteaseApiException._mapCode(301)` 改為 `login_required`，或在 shared docs 中明確說 `SourceErrorKind` 才是跨 source 穩定契約、`code` 只保留 source-owned 診斷字串。若改字串，要同步 `test/data/sources/source_exception_test.dart:237`。
4. 補測試：`useNeteaseAuthForPlay=false` 時 playback selection headers 不含 Cookie，true 時含 `MUSIC_U`；`NeteasePlaylistSource` request headers 來自 `SourceHttpPolicy`；Netease 301 的 `kind` 與 `code` contract 有明確測試。

## Instruction docs accuracy notes

- `lib/data/sources/AGENTS.md:54` 到 `lib/data/sources/AGENTS.md:71` 對 Netease search/detail/audio/eapi/playlist batch/short URL/VIP/availability/16 min expiry/MUSIC_U/default auth 的描述大致可由當前程式碼驗證。
- `lib/data/sources/AGENTS.md:150` 到 `lib/data/sources/AGENTS.md:155` 說 backend resolution paths 讀 `settings.useAuthForPlay(track.sourceType)`；播放與下載 stream resolution 符合，但 playback media headers 例外未被文檔點出，對應 Finding 1。
- `lib/data/sources/AGENTS.md:157` 到 `lib/data/sources/AGENTS.md:160` 要求 direct source adapters/account services 使用 `SourceHttpPolicy`，但外部 `NeteasePlaylistSource` 沒有使用 shared policy。若外部 playlist import source 也屬於此規範範圍，文檔準確、實作偏離；若不是，文檔應明確排除並另定外部 import header policy。
