# Lyrics Source Integration Review

## Findings

1. **影片音源的 regex auto-match fallback 會把 uploader/channel 當作歌曲 artist 搜尋，降低 Bilibili / YouTube 歌詞匹配語義準確度。**
   `LyricsAutoMatchService._matchRegexParsedTitle()` 在標題 parser 沒解析出 artist 時用 `track.artist` 補 artistName（`lib/services/lyrics/lyrics_auto_match_service.dart:231`），之後 Netease / QQ Music 搜尋會把 `trackName + artistName` 組成 query（`lib/services/lyrics/lyrics_auto_match_service.dart:669`、`lib/services/lyrics/lyrics_auto_match_service.dart:712`）。但 Bilibili `Track.artist` 來自 `data['owner']['name']`，即 UP 主（`lib/data/sources/bilibili_source.dart:183`）；YouTube `Track.artist` 來自 `video.author`，即頻道/作者（`lib/data/sources/youtube_source.dart:177`、`lib/data/sources/youtube_source.dart:840`）。Netease 則不同，`Track.artist` 是歌曲 artist join 後的值（`lib/data/sources/netease_source.dart:611`、`lib/data/sources/netease_source.dart:629`）。因此這不是三音源可無差別統一的欄位。

2. **Manual lyrics search 的單一來源 filter 沒有在 provider 層再次套用 `disabledLyricsSources`，仍可能透過 stale selected filter 搜尋已停用來源。**
   UI 會把停用 source chip 設為不可選（`lib/ui/pages/lyrics/lyrics_search_sheet.dart:133`、`lib/ui/pages/lyrics/lyrics_search_sheet.dart:143`），All filter 也會排除 disabled sources（`lib/providers/lyrics_provider.dart:358`、`lib/providers/lyrics_provider.dart:359`）。但 `LyricsSearchNotifier.search()` 的 `netease` / `qqmusic` / `lrclib` 單一 filter 分支直接呼叫對應 source（`lib/providers/lyrics_provider.dart:337`、`lib/providers/lyrics_provider.dart:339`、`lib/providers/lyrics_provider.dart:345`、`lib/providers/lyrics_provider.dart:351`），沒有檢查 `_disabledSources`。若 bottom sheet 已選某來源後設定被改成停用，`_selectedFilter` 仍可由搜尋按鈕或提交送進 notifier（`lib/ui/pages/lyrics/lyrics_search_sheet.dart:63`、`lib/ui/pages/lyrics/lyrics_search_sheet.dart:309`、`lib/ui/pages/lyrics/lyrics_search_sheet.dart:318`）。

## Evidence

- Auto-match direct fetch 的主要語義是正確保留的：`enabledSources` 空集合會直接 no-op（`lib/services/lyrics/lyrics_auto_match_service.dart:96` 到 `lib/services/lyrics/lyrics_auto_match_service.dart:100`）；Netease direct track 只有在 `enabledSourceSet.contains('netease')` 時才用 `sourceId` 直取（`lib/services/lyrics/lyrics_auto_match_service.dart:103` 到 `lib/services/lyrics/lyrics_auto_match_service.dart:115`）；`originalSongId` / `originalSource` direct fetch 也要求原來源仍在 enabled set（`lib/services/lyrics/lyrics_auto_match_service.dart:127` 到 `lib/services/lyrics/lyrics_auto_match_service.dart:144`）。
- `allowPlainLyricsAutoMatch` 的 auto-match gating 已由程式碼落實：只要有 synced lyrics 就接受，plain-only 只有在設定允許時才接受（`lib/services/lyrics/lyrics_auto_match_service.dart:216` 到 `lib/services/lyrics/lyrics_auto_match_service.dart:221`）；`AudioController` 每次 auto-match 前從 `SettingsRepository` 讀最新 source order、disabled set 與 plain lyrics 設定（`lib/services/audio/audio_provider.dart:1621`、`lib/services/audio/audio_provider.dart:1632` 到 `lib/services/audio/audio_provider.dart:1638`）。
- 外部歌單導入能把原平台資料帶到 matched track：`ImportedTrack.sourceId` / `source` 定義在 `lib/data/sources/playlist_import/playlist_import_source.dart:12` 到 `lib/data/sources/playlist_import/playlist_import_source.dart:16`；Netease importer 寫入 song ID 與 source（`lib/data/sources/playlist_import/netease_playlist_source.dart:201`、`lib/data/sources/playlist_import/netease_playlist_source.dart:209`、`lib/data/sources/playlist_import/netease_playlist_source.dart:210`）；QQ Music importer 寫入 songmid 與 source（`lib/data/sources/playlist_import/qq_music_playlist_source.dart:177`、`lib/data/sources/playlist_import/qq_music_playlist_source.dart:184`、`lib/data/sources/playlist_import/qq_music_playlist_source.dart:185`）；selected track 會保存到 `Track.originalSongId` / `Track.originalSource`（`lib/providers/playlist_import_provider.dart:65` 到 `lib/providers/playlist_import_provider.dart:69`）。
- Manual search 的 All filter 會按使用者 source priority 合併結果（`lib/providers/lyrics_provider.dart:357` 到 `lib/providers/lyrics_provider.dart:410`），但單一 filter 的 disabled enforcement 目前只靠 UI，不在 provider 層保證。

## Source-specific reason if applicable

- Finding 1 是 **Bilibili / YouTube-specific**。Bilibili 的 `artist` 是 UP 主、YouTube 的 `artist` 是頻道/作者；Netease 的 `artist` 則是歌曲 artist。修正方向不應把 Netease 的 artist 語義降級，也不應把 uploader 全域改名造成 UI 顯示回歸；應只讓 lyrics regex fallback 對影片音源不要把 uploader 當成歌曲 artist。
- Finding 2 不是單一 source 的 API 差異，而是 manual search filter 狀態與 `disabledLyricsSources` 的一致性問題。保留 All / Netease / QQ Music / lrclib 各自搜尋能力即可，不需要改變 Netease、QQ Music、lrclib 的查詢參數特性。

## Suggested direction

1. 調整 regex fallback 的 artist fallback 規則：對 `SourceType.bilibili` / `SourceType.youtube`，只有 `TitleParser` 從 title 解析出 artist 時才把 artist 拼入 lyrics source query；`Track.artist` 可繼續作為 AI uploader context，不要作為普通 lyrics 搜尋 artist。對 `SourceType.netease` 保留 `track.artist` fallback，因為該欄位在 Netease track 上是歌曲 artist。
2. 在 `LyricsSearchNotifier.search()` 的單一 source 分支加入 provider 層 enabled check。若目前 filter 對應來源在 `_disabledSources` 中，可回傳空結果或重置為 All；這樣 UI stale state、測試或未來入口都不會繞過 `disabledLyricsSources`。
3. 補測試時優先覆蓋：Bilibili / YouTube regex fallback 在 parser 無 artist 時只用 title 搜 lyrics；Netease 仍可用 `Track.artist`；manual search 已選 lrclib 後停用 lrclib，再 submit search 不應呼叫 `_lrclib.search()`。

## Instruction docs accuracy notes

- `lib/services/AGENTS.md` 對 auto-match priority 的描述已由程式碼驗證為大致準確：existing match、Netease source direct fetch、original platform direct fetch、enabled source order、manual filters 都能在目前程式碼中對上（`lib/services/lyrics/lyrics_auto_match_service.dart:89`、`lib/services/lyrics/lyrics_auto_match_service.dart:103`、`lib/services/lyrics/lyrics_auto_match_service.dart:127`、`lib/services/lyrics/lyrics_auto_match_service.dart:268`、`lib/providers/lyrics_provider.dart:337`）。
- `lib/services/AGENTS.md` 說 uploader 不應當作 song artist；這在 AI path 是準確的，AI parser prompt 明確把 uploader 當 context（`lib/services/lyrics/ai_title_parser.dart:46` 到 `lib/services/lyrics/ai_title_parser.dart:62`），auto-match 也把 `track.artist` 以 uploader 參數傳入 AI parser（`lib/services/lyrics/lyrics_auto_match_service.dart:564` 到 `lib/services/lyrics/lyrics_auto_match_service.dart:570`）。但 regex fallback 還沒有同等保護，這是 Finding 1 的文件/實作缺口。
- `disabledLyricsSources` 文件描述對 auto-match 與 All manual search 已驗證準確；對 manual single-source filter，現況依賴 UI chip disabled，而 provider 層沒有一致 enforcement，這是 Finding 2 的精確範圍。
- `docs/history/refactoring-log.md` 只作背景；本報告沒有把歷史描述直接當作當前事實，finding 都以當前程式碼行號驗證。
