# Settings / Account / Database Viewer UI 審查

## Findings

1. **類型：UX 問題；嚴重度：中**
   **位置：** `lib/ui/pages/settings/account_management_page.dart:107`、`lib/providers/account_provider.dart:179`

   帳號管理頁的「檢查帳號」流程會在 `verifyAllAccountStatuses()` 完成後一律顯示成功訊息，但底層單一平台檢查失敗時只在 `catch` 中寫入 log，沒有回傳失敗狀態給 UI。結果是 Bilibili / YouTube / Netease 狀態檢查遇到網路錯誤、API 失敗或解析錯誤時，使用者仍可能看到「帳號已檢查」類成功提示，實際登入/VIP 狀態是否可靠不可見。

2. **類型：UX 問題；嚴重度：中**
   **位置：** `lib/data/models/settings.dart:231`、`lib/providers/audio_settings_provider.dart:8`、`test/ui/pages/settings/account_management_page_test.dart:21`

   後端有三個播放認證設定 `useBilibiliAuthForPlay` / `useYoutubeAuthForPlay` / `useNeteaseAuthForPlay`，且下載、播放串流解析會讀取這些設定；但一般 Settings / Account / Audio Settings UI 沒有可操作入口，`audio_settings_provider` 狀態也未暴露這些欄位或 setter。測試還明確保證帳號卡片不放 auth playback 按鈕。這和後端能力本身不衝突，但會讓使用者無法在 UI 中處理「想為 YouTube/Bilibili 開啟登入播放」或「想停用 Netease 登入播放來排查帳號問題」這類實際播放效率問題。

## Evidence

- 已讀取規則文件：`AGENTS.md`、`lib/ui/AGENTS.md`、`lib/providers/AGENTS.md`、`lib/data/AGENTS.md`、`lib/data/sources/AGENTS.md`、`lib/services/AGENTS.md`、`docs/README.md`；補充讀取 `.serena/memories/update_system.md`、`ui_coding_patterns.md`、`code_style.md`、`refactoring_lessons.md`。
- AppBar actions trailing spacing：檢查 `lib/ui/pages/settings/account_management_page.dart:37`、`database_viewer_page.dart:51`、`lyrics_source_settings_page.dart:261`，最後一個 `IconButton` 均有 `const SizedBox(width: 8)`；`download_manager_page.dart:25` 以 `PopupMenuButton` 結尾，符合 `lib/ui/AGENTS.md` 的例外規則。登入頁、音訊設定頁、開發者頁沒有 AppBar actions。
- Auth-for-play backend/design：`lib/data/sources/AGENTS.md` 記載預設為 Bilibili false、YouTube false、Netease true；`lib/data/models/settings.dart:231` 到 `237` 符合此預設；`lib/services/download/download_service.dart:702`、`lib/services/audio/internal/audio_stream_delegate.dart:71` 會使用 `settings.useAuthForPlay(track.sourceType)`。但 `rg -n "useAuth|AuthForPlay|authForPlay" lib/ui lib/providers test` 只找到 DB viewer、備份/匯入、測試與 library playlist refresh/import UI，沒有 Settings / Account 的播放認證設定入口。
- Database viewer 覆蓋：`lib/providers/database_provider.dart:27` 到 `38` 的 Isar schemas 包含 Track、Playlist、PlayQueue、Settings、SearchHistory、DownloadTask、PlayHistory、RadioStation、LyricsMatch、LyricsTitleParseCache、Account；`lib/ui/pages/settings/database_viewer_page.dart:29` 到 `42` 與 `103` 到 `115` 均列出並 switch 到對應 list view。Settings 欄位覆蓋見 `database_viewer_page.dart:471` 到 `659`，包含播放、音質、auth、refresh、桌面、音訊裝置、歌詞與 UI 設定。`test/ui/pages/settings/database_viewer_page_coverage_test.dart:56` 與 `109` 也有集合與欄位 token coverage。
- Settings mutation：播放設定走 `playbackSettingsProvider`（例如 `settings_page.dart:660`、`682`），音質/歌詞設定走 `audioSettingsProvider`（例如 `audio_settings_page.dart:29`、`lyrics_source_settings_page.dart:77`），下載設定走 `downloadSettingsProvider`（例如 `settings_page.dart:2481`），更新狀態走 `updateProvider`（`lib/ui/widgets/update_dialog.dart:36`、`226`），符合 provider/state 為主的模式。
- 錯誤/進度/登入狀態：下載管理顯示 task 進度與錯誤訊息（`download_manager_page.dart:357` 到 `379`）；更新對話框顯示下載、安裝、ready 與錯誤狀態（`update_dialog.dart:145` 到 `197`）；登入頁顯示 WebView/QR 載入、QR 掃碼/過期狀態，YouTube 登入失敗有 toast（`youtube_login_page.dart:115`），Netease QR 生成失敗有 toast（`netease_login_page.dart:247`）。主要缺口是 Finding 1 的帳號狀態檢查錯誤被隱藏。
- 已執行驗證：`flutter test test/ui/pages/settings/database_viewer_page_coverage_test.dart test/ui/pages/settings/account_management_page_test.dart test/ui/pages/settings/download_manager_page_phase4_test.dart test/ui/pages/settings/lyrics_source_settings_page_test.dart test/data/models/audio_settings_defaults_test.dart`，全部通過。

## User impact

- 帳號狀態檢查誤顯成功會降低使用者對登入狀態的判斷能力。對音樂播放器而言，這會直接影響 VIP 曲、私人/登入內容、Netease 音訊 URL 解析等播放成功率排查。
- 播放認證設定只能被預設、遷移、備份還原或測試修改，正常使用者不能在 UI 中調整。當登入憑證造成某平台播放問題，或未登入解析失敗但登入可解時，使用者缺少低成本的自助切換入口。

## Suggested direction

- 讓 `verifyAllAccountStatuses()` 回傳每個平台的檢查結果摘要，或至少回傳是否有錯誤；Account Management 根據結果顯示「全部正常 / 部分無法檢查 / session 已過期」等不同提示。單一平台檢查失敗時，不要和成功檢查使用同一個成功 toast。
- 為播放認證設定補一個明確入口，但不要塞回帳號卡片主操作列。較合適的位置是 Audio Settings 或 Account Management 的次級設定區，顯示三個 source 的目前值與預設說明：Bilibili/YouTube 預設關閉、Netease 預設開啟。mutation 應走 provider，例如擴充 `audio_settings_provider` 或新增 scoped settings provider。

## Instruction docs accuracy notes

- `lib/data/sources/AGENTS.md` 對 auth-for-play 預設與後端使用路徑的描述和目前程式碼一致。
- `lib/ui/AGENTS.md` 的 AppBar actions 尾端間距規則和本次檢查的 settings/account/database viewer 範圍一致，未發現違反。
- `lib/ui/AGENTS.md` 的 Database Viewer Maintenance 規則有對應測試守住集合與重要欄位；目前 DB viewer 與 `fmpDatabaseSchemas` 一致。
- 文檔未明確說明播放認證設定是否刻意不提供一般 UI。若目前產品設計是「只用預設，不讓使用者切換」，建議在 `lib/data/sources/AGENTS.md` 或 `lib/ui/AGENTS.md` 補一句，避免後續 agent 把缺少 UI 誤判為遺漏；若不是刻意設計，則應按 Suggested direction 補 UI。
