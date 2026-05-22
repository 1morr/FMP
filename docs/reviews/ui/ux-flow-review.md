# UX Flow Review

## Findings

1. **類型：UX 問題；嚴重度：High；位置：`lib/ui/pages/search/search_page.dart:464`、`lib/providers/search_provider.dart:254`、`lib/services/search/search_service.dart:173`、`lib/data/repositories/track_repository.dart:170`**

   搜尋頁的音源 chip 只限制線上搜尋來源，未限制本地「歌單中的結果」。使用者切到 YouTube 或 Netease 後，頁面上方仍可能出現其他音源的本地歌曲，造成「我已切換音源但結果仍混雜」的流程落差。

2. **類型：UX 問題；嚴重度：Medium；位置：`lib/ui/pages/search/search_page.dart:846`、`lib/ui/pages/search/search_page.dart:938`、`lib/ui/pages/search/search_page.dart:1243`**

   搜尋結果的 Bilibili 多 P 展開後，單一分 P 的選單只保留播放、下一首、加入隊列，沒有加入歌單、歌詞匹配、加入遠端歌單。父層影片選單則會把多 P 全部套用。使用者若只想把某一個分 P 加入歌單或匹配歌詞，展開後反而找不到對應操作。

3. **類型：UX 問題；嚴重度：Medium；位置：`lib/ui/pages/search/search_page.dart:813`、`lib/ui/pages/search/search_page.dart:825`**

   搜尋頁載入 Bilibili 分 P 失敗時只移除 loading 狀態，沒有 toast、inline error、重試提示或保留錯誤狀態。這會讓使用者點展開或對多 P 做選單操作後看起來「什麼都沒發生」。

4. **類型：UX 問題；嚴重度：Medium；位置：`lib/ui/widgets/download_path_setup_dialog.dart:64`、`lib/ui/widgets/download_path_setup_dialog.dart:79`、`lib/services/download/download_path_manager.dart:39`、`lib/services/download/download_path_manager.dart:66`**

   首次下載需要設定下載路徑，但路徑選擇或保存拋例外時，對話框只把 `_isSelecting` 設回 false，未顯示錯誤。權限不足會在 `DownloadPathManager` 顯示對話框，但 file picker / save settings / 其他平台錯誤沒有可見回饋。

5. **類型：UX 問題；嚴重度：Medium；位置：`lib/ui/pages/settings/bilibili_login_page.dart:161`、`lib/ui/pages/settings/bilibili_login_page.dart:167`、`lib/ui/pages/settings/bilibili_login_page.dart:267`、`lib/ui/pages/settings/bilibili_login_page.dart:272`**

   Bilibili 登入流程的錯誤回饋不一致。WebView 偵測到 cookie 後，`loginWithCookies()` 與 `fetchAndUpdateUserInfo()` 沒有 try/catch；QR polling stream 也沒有 `onError`，成功後更新使用者資料失敗也沒有可見錯誤。登入失敗或帳號資料更新失敗時，使用者可能只看到頁面停在原狀。

6. **類型：UX 問題；嚴重度：Low；位置：`lib/ui/pages/lyrics/lyrics_search_sheet.dart:155`、`lib/ui/pages/lyrics/lyrics_search_sheet.dart:172`、`lib/providers/lyrics_provider.dart:423`**

   手動歌詞匹配的搜尋結果有 loading/error 狀態，但「保存匹配」與「移除匹配」沒有進行中狀態，也沒有 catch 錯誤。若資料庫或 cache 寫入失敗，使用者沒有可理解的失敗提示。

## Evidence

- 搜尋歌曲 → 切換音源：`SearchPage` 的 chip 呼叫 `setFilters()`（`lib/ui/pages/search/search_page.dart:181`、`:193`、`:204`、`:215`），`SearchNotifier.search()` 用 `state.sourceTypesForSearch` 限制 `searchOnline()`（`lib/providers/search_provider.dart:251`），但本地搜尋固定呼叫 `_service.searchLocal(query)`（`:254`）。`SearchService.searchLocal()` 只呼叫 `TrackRepository.search(query)`（`lib/services/search/search_service.dart:173`），repository 只按 title/artist 查詢（`lib/data/repositories/track_repository.dart:170`），沒有 source filter。UI 仍無條件顯示 `state.localResults`（`lib/ui/pages/search/search_page.dart:464`）。

- 搜尋歌曲 → 播放：線上與本地結果點擊都走 `audioControllerProvider.notifier.playTemporary()`（`lib/ui/pages/search/search_page.dart:498`、`:856`、`:862`），符合 UI 不繞過 `AudioController` 的邊界。未發現主要問題。

- 搜尋歌曲 → 加入歌單：一般 track action 透過 `TrackActionCoordinator.handleSingle()`（`lib/ui/pages/search/search_page.dart:931`）與 `showAddToPlaylistDialog()`（`lib/ui/handlers/track_action_coordinator.dart:50`）。但展開後的 `_PageTile` 明確關閉 `includeAddToPlaylist`、`includeMatchLyrics`、`includeAddToRemote`（`lib/ui/pages/search/search_page.dart:1243`），且 `_handlePageMenuAction()` 只處理播放、下一首、隊列（`:938`）。

- 匯入播放列表：`ImportPlaylistDialog` 有 URL 偵測、登入狀態開關、外部歌單 search source、進度條、取消與錯誤區塊（`lib/ui/pages/library/widgets/import_playlist_dialog.dart:143`、`:288`、`:315`、`:341`、`:364`、`:462`）。內部匯入成功後會通知 library invalidation（`:515`），外部匯入完成後開 preview（`:573`）。本輪未發現足以列入 finding 的 UX 斷點。

- 下載歌曲：歌單詳情提供單曲、分 P、選取多首、整個歌單下載入口，並在加入隊列後提供前往下載管理的 action toast（`lib/ui/pages/library/playlist_detail_page.dart:288`、`:1067`、`:1320`、`:1618`）。主要問題在首次下載路徑設定錯誤被吞掉（`lib/ui/widgets/download_path_setup_dialog.dart:79`）。

- 登入帳號：帳號管理頁對三個平台提供登入、登出與歌單管理入口（`lib/ui/pages/settings/account_management_page.dart:55`、`:77`、`:98`），且測試覆蓋帳號管理卡片不混入 auth playback 按鈕（`test/ui/pages/settings/account_management_page_test.dart:6`）。Bilibili QR 生成錯誤有 toast（`lib/ui/pages/settings/bilibili_login_page.dart:254`），但 WebView cookie 保存與 QR polling 成功後更新資料缺少錯誤回饋。

- 歌詞匹配：手動搜尋 sheet 支援 All / Netease / QQ Music / lrclib filter，且 disabled source 不能選（`lib/ui/pages/lyrics/lyrics_search_sheet.dart:72`）。搜尋狀態有 loading/error/empty 結果（`:380`），provider 的 All filter 會按使用者來源順序並行搜尋並吞掉單一來源錯誤（`lib/providers/lyrics_provider.dart:357`）。保存/移除匹配沒有可見錯誤路徑（`lib/ui/pages/lyrics/lyrics_search_sheet.dart:155`、`:172`）。

## User impact

- 音源 chip 是高頻搜尋入口；本地結果不跟著切換會降低掃描效率，尤其使用者想只看 YouTube 或 Netease 時，仍要手動辨識本地 Bilibili 結果。
- 多 P 的單項操作缺失會迫使用戶把整個影片所有分 P 加入歌單，或先播放/另找入口再操作，對音樂播放器的實際整理效率影響明顯。
- 分 P 載入失敗與首次下載路徑錯誤都屬於多步流程中的「無聲失敗」，使用者難以判斷是網路、權限、平台限制，還是操作沒有生效。
- 登入流程若沒有穩定錯誤狀態，會直接影響後續 Netease 播放、遠端歌單與私有內容匯入的可用性判斷。
- 歌詞匹配保存失敗沒有回饋時，使用者可能以為已完成匹配，回到播放器才發現歌詞沒有更新。

## Suggested direction

- 搜尋音源切換應明確定義本地結果是否受 chip 影響。若遵守 `lib/providers/AGENTS.md` 的「source chip queries only that source」，建議讓 `searchLocal()` 接受 source filter，或 UI 在顯示 `localResults` 前用 `selectedSource` 過濾並同步 section count。
- 多 P 展開後的 `_PageTile` 應提供與單曲一致的常用操作，至少加入歌單與歌詞匹配；若刻意不支援，應在父層選單文字明確標示「全部分 P」。
- `_loadVideoPages()` catch 應顯示可理解錯誤，並保留重試入口；對多 P 選單操作觸發的載入失敗尤其需要 toast 或 inline 狀態。
- `DownloadPathSetupDialog` 應在 catch 中顯示錯誤訊息，並區分取消、權限不足、保存失敗。
- Bilibili login WebView 與 QR polling 建議統一 try/catch/onError，至少顯示 toast 並重置可重試狀態。
- 歌詞保存/移除匹配建議加 `_isSaving` 狀態、禁用重複點擊，並在 catch 中顯示錯誤。

## Instruction docs accuracy notes

- `lib/providers/AGENTS.md:27` 說 source chip 查詢單一來源；目前線上搜尋符合，但本地結果不符合使用者可見結果層面的「only that source」。
- `lib/ui/AGENTS.md:45` 要 common track actions 使用共享 builders 並透過 `TrackActionCoordinator`。搜尋頁主結果符合；展開後 `_PageTile` 明確裁掉部分 common actions，若這是產品決策，建議補進 UI instruction，否則應視為一致性問題。
- `lib/services/AGENTS.md` 對 lyrics manual search filter、playlist import 與 download path/header 規則的描述與本輪讀到的主要服務/UI 流程大致一致；未發現需要立即修正文檔的地方。
