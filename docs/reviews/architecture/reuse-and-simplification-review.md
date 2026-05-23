# Reuse And Simplification Review

## Findings

### P1 - Playlist detail download flows duplicate path setup, batching, scheduling, and result toasts

理由：`PlaylistDetailPage` 已有 `DownloadService.addTracksDownload()` 的批次 interface，但同一頁仍在多個下載入口重複「確認下載目錄 -> 取得 playlist -> addTrack(s) -> triggerSchedule -> 顯示結果 toast」流程。其中 group 下載還逐首呼叫 `addTrackDownload()` 後自行統計結果，等於繞過已存在的批次 leverage。

風險：下載入口越多，越容易出現提示文案、排程時機、`DownloadResult` 統計與下載目錄初始化行為不一致。這類重複也讓未來調整下載 queue semantics 時需要同時檢查多段 UI switch。

建議方向：不要做大規模下載架構重寫。先在 `PlaylistDetailPage` 或鄰近 UI helper 中抽一個很小的 module，例如「確保下載路徑已設定」和「用 `DownloadBatchAddSummary` 顯示 queue 結果」；group 下載改用 `addTracksDownload(group.tracks, skipSchedule: true)`，保留 page-specific 文案。這能降低複雜度，因為同一頁的四個入口會共享同一個下載 preflight 和 result mapping。

### P2 - Search page multi-part track actions partially reimplement common track action handling

理由：搜尋結果和分 P/group tile 已經使用 `buildCommonTrackActionMenuItems()` 建菜單，但 `SearchPage` 內仍為多 P track/group 直接 switch common action id，重複了 `playNext`、`addToQueue`、`addToPlaylist`、`addToRemote`、登入檢查和 toast。相比之下，普通 track tile 和其他頁面已把 common action 交給 `TrackActionCoordinator`。

風險：common action 新增或行為調整時，`TrackActionCoordinator` 和 search group switch 會分叉。例如 remote playlist 的登入/partial behavior 已經由 multi-track handler 集中處理，但 search group 只對 `group.firstTrack.sourceType` 做登入檢查。

建議方向：不建議把整個搜尋頁拆掉。較小的做法是讓 search 的分 P/group action 先把 `VideoPage` 轉成 `List<Track>`，再走 `TrackActionCoordinator.handleMulti()` 或一個薄的 `handleTrackGroup()` helper；只把「播放第一首」、「match lyrics 用 parent track」、「分 P 專用 toast 文案」留在 search local code。這比抽象整個 tile 有更好的 locality。

### P2 - Account services duplicate Set-Cookie response parsing

理由：Bilibili 與 Netease account services 各自實作幾乎相同的 `_extractCookiesFromResponse(Response)`：讀 `set-cookie` header、拆第一段 `key=value`、保留含 `=` 的 value、空 map 回傳 `null`。這是同一個 protocol parsing module 的重複，不是 domain-specific policy。

風險：Cookie parsing bug 或安全修正需要改兩份。Netease 另有 response body cookie fallback，這部分是 source-specific；但 Set-Cookie header parsing 本身沒有必要散落在兩個 account service。

建議方向：抽一個窄 helper，例如 `lib/services/account/http_cookie_parser.dart`，只處理 `Response.headers['set-cookie']` 到 `Map<String, String>?`。保留 Bilibili refresh token、Netease body fallback、各 source credential object 在原 service 內，避免把 auth boundary 做大。

### P3 - Lyrics AI callers duplicate OpenAI-compatible request setup

理由：AI title parser 與 AI lyrics selector 都做 endpoint normalize、api key/model trim、timeout fallback、JSON content type、Bearer auth、Dio timeout options、`model` / `temperature` / `messages` payload assembly。兩者 prompt 和 response parser 不同，但 transport/config setup 相同。

風險：AI endpoint、timeout、header 或 logging 策略改動時容易只更新其中一個 call path。這會造成 title parsing 和 advanced matching 在同一設定下表現不一致，尤其是 timeout fallback 和 endpoint normalization。

建議方向：只抽 transport-level helper，不抽 prompt。可在 lyrics AI 目錄中建立一個 internal `OpenAiChatClient`/request helper，輸入 system/user messages 和 log label，回傳 response content 或 `null`。保留 `AiTitleParser.parseContent()` 與 `AiLyricsSelector.parseContent()` 的 domain parsing，各自測試仍以 parser 為核心。

### No finding - Image loading is already centralized enough

理由：規範要求不得直接使用 `Image.network()` / `Image.file()`，目前 `rg -n "Image\\.(network|file)\\(" lib` 只命中 instruction 文檔，未命中 app code。`TrackThumbnail` / `TrackCover` 和多數 caller 已透過 `ImageLoadingService.loadImage()`，且傳入 `width`/`height` 或 `targetDisplaySize`，符合 thumbnail optimization 的 locality。

風險：再抽更高層 image wrapper 會讓 caller 需要理解更多間接 interface，反而降低可讀性。真正的風險不是缺 abstraction，而是新 UI 繞過既有 image module。

建議方向：不建議新增全域 image facade。維持 `TrackThumbnail`、`TrackCover`、`ImageLoadingService.loadAvatar()`、`ImageLoadingService.loadImage()` 這四個入口，靠現有 scoped instructions 和 targeted tests/rg guard 防止直接 image usage。

### No finding - Source error mapping and media header wrappers should stay mostly as-is

理由：`SourceApiException.classifyDioError()` 已集中 Dio-level classification；Bilibili/Netease/Youtube 各自只把 shared semantic code 映射成平台 exception/code。`buildDownloadMediaHeaders()` 與 `buildDownloadImageHeaders()` implementation 相同，但它們在 service layer 保留了「下載音訊」與「下載圖片」兩個 call-site names，符合 `lib/services/AGENTS.md` 的明確規範。

風險：把 source-specific error numeric/string mapping 繼續抽深，可能把 Bilibili HTTP 412/429、Netease 460/462、YouTube string codes 等平台語義藏到更遠的 module，降低 locality。合併 download media/image wrapper 也會省很少代碼，卻削弱 instruction docs 和測試對 download header policy 的表達。

建議方向：不做 broad abstraction。若未來新增第四個 source，再考慮把「classified code -> source exception」做成小 factory；現階段只補足 source-specific tests 即可。Download header wrappers 保留，但可在註解中說明它們是 policy names，不是不同 implementation。

## Evidence

- `lib/ui/pages/library/playlist_detail_page.dart:292` 到 `lib/ui/pages/library/playlist_detail_page.dart:297`、`lib/ui/pages/library/playlist_detail_page.dart:1091` 到 `lib/ui/pages/library/playlist_detail_page.dart:1096`、`lib/ui/pages/library/playlist_detail_page.dart:1322` 到 `lib/ui/pages/library/playlist_detail_page.dart:1327`、`lib/ui/pages/library/playlist_detail_page.dart:1620` 到 `lib/ui/pages/library/playlist_detail_page.dart:1625` 重複下載路徑設定檢查。
- `lib/ui/pages/library/playlist_detail_page.dart:304` 到 `lib/ui/pages/library/playlist_detail_page.dart:310` 已使用 `addTracksDownload()` 批次入口；但 `lib/ui/pages/library/playlist_detail_page.dart:1339` 到 `lib/ui/pages/library/playlist_detail_page.dart:1355` 對 group tracks 逐首呼叫 `addTrackDownload()` 並自行統計。
- `lib/services/download/download_service.dart:376` 到 `lib/services/download/download_service.dart:391` 顯示 `addTrackDownload()` 本身只是包 `addTracksDownload()`；`lib/services/download/download_service.dart:400` 到 `lib/services/download/download_service.dart:504` 是真正的批次 module。
- `lib/ui/pages/library/playlist_detail_page.dart:319` 到 `lib/ui/pages/library/playlist_detail_page.dart:335`、`lib/ui/pages/library/playlist_detail_page.dart:1365` 到 `lib/ui/pages/library/playlist_detail_page.dart:1383`、`lib/ui/pages/library/playlist_detail_page.dart:1637` 到 `lib/ui/pages/library/playlist_detail_page.dart:1654` 重複 queue/toast/result mapping。

- `lib/ui/handlers/track_action_handler.dart:243` 到 `lib/ui/handlers/track_action_handler.dart:280` 是 single common action module；`lib/ui/handlers/track_action_handler.dart:175` 到 `lib/ui/handlers/track_action_handler.dart:229` 是 multi-track action module。
- `lib/ui/handlers/track_action_coordinator.dart:17` 到 `lib/ui/handlers/track_action_coordinator.dart:66` 將 single common action 接到 UI toast/dialog；`lib/ui/handlers/track_action_coordinator.dart:68` 到 `lib/ui/handlers/track_action_coordinator.dart:128` 提供 multi-track path。
- `lib/ui/pages/explore/explore_page.dart:347` 到 `lib/ui/pages/explore/explore_page.dart:363` 是符合規範的薄 wrapper 範例。
- `lib/ui/pages/search/search_page.dart:1155` 到 `lib/ui/pages/search/search_page.dart:1158`、`lib/ui/pages/search/search_page.dart:1243` 到 `lib/ui/pages/search/search_page.dart:1253`、`lib/ui/pages/search/search_page.dart:1401` 到 `lib/ui/pages/search/search_page.dart:1408` 使用 common menu builders。
- `lib/ui/pages/search/search_page.dart:880` 到 `lib/ui/pages/search/search_page.dart:927` 和 `lib/ui/pages/search/search_page.dart:1415` 到 `lib/ui/pages/search/search_page.dart:1460` 又手寫 common action switch。`lib/ui/pages/search/search_page.dart:938` 到 `lib/ui/pages/search/search_page.dart:959` 對單一分 P 也重複 `play` / `play_next` / `add_to_queue`。

- `lib/services/account/bilibili_account_service.dart:585` 到 `lib/services/account/bilibili_account_service.dart:606` 與 `lib/services/account/netease_account_service.dart:504` 到 `lib/services/account/netease_account_service.dart:525` 是重複 Set-Cookie parsing。
- `lib/services/account/netease_account_service.dart:528` 到 `lib/services/account/netease_account_service.dart:543` 是 Netease response body cookie fallback，這部分不應被合併進 generic Set-Cookie helper。

- `lib/services/lyrics/ai_title_parser.dart:36` 到 `lib/services/lyrics/ai_title_parser.dart:50` 與 `lib/services/lyrics/ai_lyrics_selector.dart:90` 到 `lib/services/lyrics/ai_lyrics_selector.dart:97` 重複 endpoint/config/timeout normalization。
- `lib/services/lyrics/ai_title_parser.dart:62` 到 `lib/services/lyrics/ai_title_parser.dart:76` 與 `lib/services/lyrics/ai_lyrics_selector.dart:122` 到 `lib/services/lyrics/ai_lyrics_selector.dart:136` 重複 OpenAI-compatible Dio options 和 payload shell。
- `lib/services/lyrics/openai_chat_endpoint.dart:4` 到 `lib/services/lyrics/openai_chat_endpoint.dart:5` 已有 endpoint normalization helper；`lib/services/lyrics/lyrics_ai_config_service.dart:66` 到 `lib/services/lyrics/lyrics_ai_config_service.dart:79` 已有 config loader。

- `lib/core/services/image_loading_service.dart:52` 到 `lib/core/services/image_loading_service.dart:63` 是統一 image loader interface；`lib/core/services/image_loading_service.dart:118` 到 `lib/core/services/image_loading_service.dart:124` 根據 display size 做 thumbnail URL candidates。
- `lib/ui/widgets/track_thumbnail.dart:98` 到 `lib/ui/widgets/track_thumbnail.dart:105` 傳入 cover width/height；`lib/ui/widgets/track_thumbnail.dart:210` 到 `lib/ui/widgets/track_thumbnail.dart:217` 傳入 `targetDisplaySize`。
- `lib/ui/pages/library/downloaded_page.dart:307` 到 `lib/ui/pages/library/downloaded_page.dart:313`、`lib/ui/pages/radio/radio_page.dart:424` 到 `lib/ui/pages/radio/radio_page.dart:430` 是其他 caller 傳 display size 的例子。

- `lib/data/sources/source_exception.dart:79` 到 `lib/data/sources/source_exception.dart:145` 是 shared Dio error classification。
- `lib/data/sources/bilibili_source.dart:851` 到 `lib/data/sources/bilibili_source.dart:882`、`lib/data/sources/youtube_source.dart:2125` 到 `lib/data/sources/youtube_source.dart:2131`、`lib/data/sources/netease_source.dart:852` 到 `lib/data/sources/netease_source.dart:876` 是各 source 的薄 mapping。
- `lib/data/sources/source_http_policy.dart:33` 到 `lib/data/sources/source_http_policy.dart:64` 是 shared media header policy；`lib/services/audio/audio_stream_manager.dart:181` 到 `lib/services/audio/audio_stream_manager.dart:188` 使用它。
- `lib/services/download/download_media_headers.dart:4` 到 `lib/services/download/download_media_headers.dart:21` 的 media/image download wrappers implementation 相同；`lib/services/download/download_service.dart:764` 到 `lib/services/download/download_service.dart:767` 和 `lib/services/download/download_service.dart:1176` 到 `lib/services/download/download_service.dart:1179` 分別在音訊與圖片下載路徑使用。

- `lib/providers/library_invalidation_coordinator.dart:41` 到 `lib/providers/library_invalidation_coordinator.dart:122` 已集中 playlist/download provider invalidation。`lib/ui/pages/lyrics/lyrics_search_sheet.dart:161` 到 `lib/ui/pages/lyrics/lyrics_search_sheet.dart:164` 與 `lib/ui/pages/lyrics/lyrics_search_sheet.dart:175` 到 `lib/ui/pages/lyrics/lyrics_search_sheet.dart:177` 的 lyrics invalidation triplet 只有同檔兩處，建議只在觸碰該檔時抽 local helper，不值得新增跨子系統 coordinator。

## Risk

最高風險是下載 UI 重複。它已經跨越 path setup、batch service、scheduler 和 toast，未來改下載規則時容易漏掉其中一個入口。

第二風險是 search multi-part action 重複。它不是純 UI 文案差異，而是重做 common action semantics，會侵蝕 `TrackActionCoordinator` 的 leverage。

較低風險是 account cookie parsing 與 lyrics AI transport。兩者目前只有兩個 caller，但都是 protocol/transport 重複，抽窄 helper 可以提升 locality，不需要改 domain flow。

不建議現在處理的風險：image loading、source error mapping、download header wrappers。這些已經有合適 module；再抽會增加 shallow interface，而不是降低複雜度。

## Suggested direction

1. 優先處理 `PlaylistDetailPage` 下載入口：抽小型 preflight/result helper，group 下載改用 `addTracksDownload()`，不要改 `DownloadService` queue semantics。
2. 接著收斂 search multi-part action：把可轉成 `List<Track>` 的 common action 交給 `TrackActionCoordinator.handleMulti()` 或一個同等薄 wrapper，只保留 search 特有播放和分 P 文案。
3. 小步抽 account Set-Cookie parser，並只替換 Bilibili/Netease 的 duplicated header parsing；Netease body cookie fallback 留原位。
4. 小步抽 lyrics AI chat transport helper，保留 parser/selector prompt 與 response parsing 不變。
5. 明確不做全域 image facade、source error factory 大重構、download header wrapper 合併。這些不會通過 deletion test：刪掉它們後，複雜度會回到 callers 或讓 policy names 消失。

## Instruction docs accuracy notes

- `AGENTS.md:9` 到 `AGENTS.md:20` 正確要求先讀 root instructions 再讀 scoped instructions；本次審查使用了 `lib/services/AGENTS.md`、`lib/data/sources/AGENTS.md`、`lib/ui/AGENTS.md`、`lib/providers/AGENTS.md`。
- `AGENTS.md:45` 到 `AGENTS.md:47`、`docs/README.md:17` 到 `docs/README.md:20` 正確描述 `.serena/memories/` 應是窄補充，核心規則應回到 `AGENTS.md` 或 scoped docs。本次把 Serena memories 當補充假說，並用代碼驗證。
- `docs/development.md:3` 和 `docs/development.md:157` 正確說明它是 onboarding 摘要、詳細規則在 `AGENTS.md`；`docs/development.md:161` 的 image loading 摘要與當前 code scan 一致。
- `lib/ui/AGENTS.md:7` 到 `lib/ui/AGENTS.md:11` 與 `.serena/memories/refactoring_lessons.md:51` 到 `.serena/memories/refactoring_lessons.md:53` 對 image loading 的規範仍準確；目前 app code 未見 direct `Image.network()` / `Image.file()`。
- `lib/ui/AGENTS.md:41` 到 `lib/ui/AGENTS.md:46` 對 common track actions 的規範準確；但 search multi-part/group actions 是目前最明顯的例外候選，應以代碼收斂，而不是改文檔降低標準。
- `lib/services/AGENTS.md:18` 到 `lib/services/AGENTS.md:21` 與 `lib/data/sources/AGENTS.md:155` 到 `lib/data/sources/AGENTS.md:167` 對 header policy 的描述準確；`SourceHttpPolicy`、audio playback headers、download media/image wrappers 都符合該方向。
- `lib/data/sources/AGENTS.md:85` 到 `lib/data/sources/AGENTS.md:99` 對 source exception 的描述準確；代碼已有 shared `SourceApiException.classifyDioError()`，因此不建議再做大範圍 error abstraction。
- `lib/providers/AGENTS.md:19` 到 `lib/providers/AGENTS.md:20` 與 `.serena/memories/refactoring_lessons.md:28` 對 library invalidation coordinator 的描述準確；本次沒有發現需要新增跨系統 invalidation wrapper 的重複，只有 lyrics sheet 同檔 triplet 可在局部觸碰時整理。
