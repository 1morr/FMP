# 決策清單

> 現況描述，未經確認，不代表目標。

這份清單給你勾選。每項列出**現況**（附證據，細節在對應的審計文件）、**影響**，以及選項。
在你要的選項前把 `[ ]` 改成 `[x]`；想補充就寫在「備註」後面。

排序原則：越前面越會決定重寫的形狀（平台、資料層、資料相容），越後面越是局部去留。
同一節內也按影響大小排。沒有預設答案；我在最後的對話摘要裡另給建議，這份文件不放建議，避免帶偏。

通用選項的意思：

- **保留**：新架構照現在的行為做。
- **刪除**：新架構不做，舊碼刪掉。
- **修改**：保留功能但改行為，在備註寫你要的樣子（或留給階段二提方案）。
- **不確定**：階段二先研究再問你。

---

## 1. 策略級（A 項，先決定，會改變整個重寫計畫）

### A1. 目標平台與上線順序

- 現況：只有 Android、Windows 能跑。程式裡另有 iOS／macOS／Linux 分支，全部未驗證，而且三種判斷寫法並存（`Platform.isWindows`、`isDesktopPlatform`、`AudioRuntimePlatform`），macOS／Linux 會出現半套桌面 UI、沒有標題列、推測無法播放。見 `platforms.md` §0、§2。
- ADR 0003 與 `pubspec.yaml:24` 說「不出 Linux／macOS」，`platform_utils.dart`、`audio_controller_provider.dart:23-25` 的註解讀起來像有支援：**不一致**。
- 影響：平台層抽象要不要一開始就按 5 平台設計；要不要刪掉現在的殘留分支。

| 平台 | 目標（重寫第一版就要） | 目標（之後加入） | 不支援 | 不確定 |
|---|---|---|---|---|
| Android | [ ] | [ ] | [ ] | [ ] |
| Windows | [ ] | [ ] | [ ] | [ ] |
| Linux | [ ] | [ ] | [ ] | [ ] |
| macOS | [ ] | [ ] | [ ] | [ ] |
| iOS | [ ] | [ ] | [ ] | [ ] |

備註：

### A2. 資料層是否更換

- 現況：`isar_community` 3.3.2（社群 fork，pub.dev 已驗證發佈者，自述只做 v3 bug 修正），`data.md` §1。上游 `isar` 在 pub.dev 最後發版 2023-08（4.0.0-dev.14），最後穩定版 3.1.0+1；ADR 0007 寫「自 2025-07 沒有再發版」：**不一致**（`engineering.md` §10）。
- fork 在 pub.dev 標 5 平台都支援（`platforms.md` §4.1）。
- 11 個 collection，**沒有任何 IsarLink**，關係全靠手動維護的 int id／字串鍵（`data.md` §1）；Isar 會把沒標 `@ignore` 的 getter 也存進去，其中 `needsRefresh`、`hasValidAudioUrl` 這類時間相關值在磁碟上會過時（`data.md` §1）。
- 資料量：ADR 0007 提到一份真實資料庫 1,534 列；你目前實際大小查不到。
- 影響：
  - **資料相容**：換庫＝要寫一次性匯出／匯入（或以現有備份格式為橋），不換＝可以原地打開舊 DB。
  - **全平台**：fork 宣稱 5 平台都支援，但長期維護依賴一個社群 fork。
  - **重寫順序**：換庫的話，資料層要在最前面的里程碑；不換的話可以延後或只清理邊界。

- [ ] 保留 isar_community（v3 格式）
- [ ] 更換（階段二比較 drift／sqlite 系列、ObjectBox 等，並給遷移方案）
- [ ] 不確定

備註：

### A3. 資料相容：重寫版本要不要讀得懂舊資料

| 資料 | 現況位置 | 保留並自動遷移 | 只支援經備份檔匯入 | 不保留 | 不確定 |
|---|---|---|---|---|---|
| 資料庫（歌單、曲目、歷史、設定、佇列） | Windows：`文件\FMP\fmp_database.isar`；Android：app 私有目錄（`data.md` §1） | [ ] | [ ] | [ ] | [ ] |
| 登入憑證（secure storage） | `flutter_secure_storage`（`data.md` §3、`accounts-network.md` §1） | [ ] | — | [ ] | [ ] |
| 已下載的音檔與 sidecar | Android `Music/FMP`、Windows `文件\FMP`（`data.md` §5） | [ ] | — | [ ] | [ ] |
| 備份檔（JSON 格式） | `data.md` §6 | [ ] 新版能匯入舊備份 | — | [ ] | [ ] |

備註：

### A4. 資料與 log 放在 Windows「文件」資料夾

- 現況：資料庫與 log 在 `Documents\FMP`（`database_provider.dart:50-53`、`log_file_sink.dart:24-28`），可能被 OneDrive 同步；資料庫內有含簽名的串流 URL（見 B6）。
- [ ] 保留  - [ ] 修改：移到 AppData（需遷移）  - [ ] 不確定

備註：

### A5. 音訊後端：兩套（ADR 0003）

- 現況：Android（與 iOS）用 just_audio→ExoPlayer，其他用 media_kit→libmpv；`media_kit_libs_windows_audio` 在 pub.dev 已 unlisted、最後發佈 2023-09（`platforms.md` §4）。兩個後端共用一批純規則，並有契約測試（`engineering.md` §10 ADR 0003：一致）。
- 影響：全平台時 macOS／Linux 要 libmpv 來源，iOS／macOS 帶 headers 需要 ATS 設定。
- [ ] 維持兩套  - [ ] 研究統一成一套  - [ ] 不確定

備註：

### A6. 發佈管道

- 現況：只有 GitHub Release；tag push 後自動驗證、建置、直接發布，沒有人工閘門，Windows 產物沒有 code signing，SHA-256 檔與產物放在同一個 Release（`engineering.md` §1、ADR 0006）。ADR 0004 寫「擁有者決定永遠不上架任何商店」。
- 平台政策（`platforms.md` §6）：App Store 5.2.3 禁止未授權從 YouTube 等來源下載媒體；2.5.2 禁止 iOS app 自行下載可執行碼；Mac App Store 2.4.5 禁止自有更新機制。

| 平台 | GitHub Release | 商店 | sideload／自簽（AltStore、TestFlight 等） | 套件庫（Flathub、AUR、winget 等） | 不發佈 | 不確定 |
|---|---|---|---|---|---|---|
| Android | [ ] | [ ] | — | [ ] F-Droid 類 | [ ] | [ ] |
| Windows | [ ] | [ ] | — | [ ] | [ ] | [ ] |
| Linux | [ ] | — | — | [ ] | [ ] | [ ] |
| macOS | [ ] | [ ] | [ ] 未公證 dmg | [ ] Homebrew | [ ] | [ ] |
| iOS | — | [ ] | [ ] | — | [ ] | [ ] |

另外：Release 要不要回到「草稿 → 你手動發布」（推翻 ADR 0006）？ [ ] 維持自動發布 [ ] 改回人工發布 [ ] 不確定

備註：

---

## 2. 會對外寫入、送資料給第三方、自己下載或執行東西的功能（B 項）

細節與證據在 `features.md` §15、`accounts-network.md` §4。

| # | 功能 | 現況 | 證據 | 保留 | 刪除 | 修改 | 不確定 |
|---|---|---|---|---|---|---|---|
| B1 | 在本機刪「匯入的平台歌單」裡的曲目＝在 B 站／YouTube／網易雲上刪 | 只靠確認框文案說明 | `playlist_detail_page.dart:565-610,1575-1610`；`remote_playlist_sync_provider.dart:47-50` | [ ] | [ ] | [ ] | [ ] |
| B2 | 「加入遠端」：在三個平台建歌單、加曲目 | 對話框操作 | `bilibili_favorites_service.dart:117-168`；`youtube_playlist_service.dart:88-111,218-223`；`netease_playlist_service.dart:101-188` | [ ] | [ ] | [ ] | [ ] |
| B3 | 網易雲寫入請求附偽造 `X-Real-IP: 118.88.88.88` | 固定送出 | `netease_playlist_service.dart:240-253` | [ ] | [ ] | [ ] | [ ] |
| B4 | 啟動時自動換 B 站 Cookie（伺服器要求時，舊 refresh_token 作廢） | 每次啟動檢查 | `account_provider.dart:131-152`；`bilibili_account_service.dart:350-444` | [ ] | [ ] | [ ] 改手動 | [ ] |
| B5 | AI 歌詞匹配：把標題、上傳者、**影片描述**、**歌詞預覽**連同 API key 送到自訂端點；端點不強制 https；debug 級別時整份 payload 寫進 log | 預設關閉 | `openai_chat_client.dart:41-67`；`ai_lyrics_selector.dart:106-137`；`openai_chat_endpoint.dart:1-6` | [ ] | [ ] | [ ] | [ ] |
| B6 | 含簽名的 CDN 串流 URL 明文存進資料庫（`Track.audioUrl`） | 每首一筆 | `stream_resolution_service.dart:427-471` | [ ] | [ ] 只放記憶體 | [ ] | [ ] |
| B7 | Windows 自動更新：安裝版以 `/SILENT` 靜默跑下載的安裝程式；免安裝版寫 bat＋vbs 用 `wscript` 隱藏執行、`robocopy` 覆蓋程式目錄 | 使用者按「更新」後 | `update_service.dart:587-684,830-876` | [ ] | [ ] | [ ] | [ ] |
| B8 | 更新檔 SHA-256：只有 release 附 checksum 檔才驗，否則只比大小 | — | `update_service.dart:462-470,776-783` | [ ] | — | [ ] 強制驗 | [ ] |
| B9 | Android 自動更新：下載 APK 開系統安裝器 | 使用者按「更新」後 | `update_service.dart:540-565` | [ ] | [ ] | [ ] | [ ] |
| B10 | 每 15 秒解析 `dns.google`、`one.one.one.one`、`dns.alidns.com` 偵測連線 | 常駐 | `connectivity_service.dart:52-56,102-116` | [ ] | [ ] | [ ] | [ ] |
| B11 | B 站匿名請求自產 `buvid3`／`buvid4`／`b_nut` 瀏覽器指紋 cookie | 常駐 | `bilibili_source.dart:92-146` | [ ] | [ ] | [ ] | [ ] |
| B12 | 首頁排行：停用某音源只影響顯示，背景仍每小時抓所有音源 | 常駐 | `ranking_cache_service.dart:233-245`；`home_ranking_settings_provider.dart:193-195` | [ ] | [ ] | [ ] 停用即不抓 | [ ] |
| B13 | 下載時附帶寫 metadata JSON、下載封面與 UP 主頭像 | 每次下載 | `download_service.dart:1509-1590` | [ ] | [ ] | [ ] | [ ] |
| B14 | YouTube 登入頁注入 JS 呼叫 `accounts_list` 取帳號名 | 登入時 | `youtube_login_page.dart:238-260` | [ ] | [ ] | [ ] | [ ] |

備註：

---

## 3. 安全與隱私缺陷（C 項；這些是「現況的錯」，不是功能去留）

| # | 問題 | 證據 | 重寫時修正 | 維持現狀 | 不確定 |
|---|---|---|---|---|---|
| C1 | 「重設所有資料」只清 Isar，不清 secure storage；重設後 UI 顯示未登入，但播放、詳情、排行榜仍帶舊 cookie（已由程式碼確認） | `data_integrity_repository.dart:55-56`；`data.md` §3 | [ ] | [ ] | [ ] |
| C2 | log 遮蔽不涵蓋 CDN 簽名參數：`media_kit` 與 just_audio 的錯誤原文未過 `redactStreamUrl`；stackTrace 不遮就寫進檔案與匯出；release 版 `debugPrint` 仍輸出到 logcat | `logger.dart:52-63,81-200,283-290`；`media_kit_audio_service.dart:379`；`just_audio_service.dart:301-304` | [ ] | [ ] | [ ] |
| C3 | B 站 QR 登入可能「假成功」：Set-Cookie 解析不到時沒存憑證仍走 `onLoginSuccess`（已由程式碼確認） | `bilibili_account_service.dart:184-200,469-473,511-517` | [ ] | [ ] | [ ] |
| C4 | B 站 cookie 刷新後的重試帶的是舊 cookie（程式碼確認；伺服器回應未實測） | `bilibili_auth_interceptor.dart:28-33,77` | [ ] | [ ] | [ ] |
| C5 | 網易雲啟動帳號檢查：任何非 200 碼（含限流 -460）都當登入失效並清憑證 | `netease_account_service.dart:290-297,360-362` | [ ] | [ ] | [ ] |
| C6 | 播放／搜尋用的連線偵測不到登入失效；YouTube 偵測到也只寫 log | `bilibili_source.dart:96-101`；`youtube_auth_interceptor.dart:30-37` | [ ] | [ ] | [ ] |
| C7 | 公開 repo 內有逆向取得的前端金鑰（InnerTube key、網易 weapi／eapi 金鑰、QQ 簽名表） | `accounts-network.md` §5（只列位置） | [ ] 集中管理 | [ ] 維持 | [ ] |

備註：

---

## 4. 帳號與「用登入狀態播放」（M 項）

細節在 `accounts-network.md` §6（帳號全貌）、§7（請求 × 音源憑證矩陣）、§8（登入與未登入的能力差異）。

| # | 項目 | 現況 | 證據 | 保留 | 刪除 | 修改 | 不確定 |
|---|---|---|---|---|---|---|---|
| M1 | 「是否登入」有兩份來源：UI 讀 Isar `Account`，實際送請求只看 secure storage | 兩者可能不一致（見 §3 C1） | `accounts-network.md` §6.1 | [ ] | — | [ ] 統一以一份為準 | [ ] |
| M2 | 「用登入狀態播放」（Auth For Play）開關，每個音源一個 | 預設：B 站、網易開，YouTube 關；控制播放、詳情、下載、B 站排行 | `settings.dart:76-79,686-693`；`accounts-network.md` §7 | [ ] | [ ] 一律帶 | [ ] | [ ] |
| M3 | v3→v4 migration 把 B 站「用登入狀態播放」**無條件改成開**，使用者自己關掉的也被打開 | 已執行過的遷移 | `database_migration.dart:236-238` | [ ] | — | [ ] 改成詢問／不動使用者值 | [ ] |
| M4 | 其他改寫使用者設定值的 migration（v0→v1 無條件改寫三個版面欄位等） | — | `database_migration.dart:171-193`；`accounts-network.md` §7 | [ ] | — | [ ] | [ ] |
| M5 | YouTube 的「用登入狀態播放」只是備援：先匿名，失敗才帶登入 | — | `youtube_source.dart:247-273,346-366` | [ ] | — | [ ] 登入後先帶登入 | [ ] |
| M6 | YouTube、網易的首頁排行永遠不帶登入（開關開了也一樣）；只有 B 站排行受開關影響 | — | `youtube_source.dart:1635-1638`；`netease_source.dart:355-357`；`ranking_cache_service.dart:269-275` | [ ] | — | [ ] | [ ] |
| M7 | 設定頁說明寫「播放與歌曲詳情」，實際還包括下載與 B 站排行 | **不一致** | `audioSettings.i18n.json:34` | — | — | [ ] 修文案 | [ ] |
| M8 | secure storage 暫時讀不到時，啟動檢查會當成失效並刪憑證、跳「登錄已失效」 | 推測可能刪掉仍有效的憑證 | `bilibili_account_service.dart:470-473`；`account_provider.dart:233-236` | [ ] | — | [ ] | [ ] |
| M9 | 登入失效提示每次 App 執行每個平台只跳一次，重新登入後再失效不再提示 | — | `session_expiry_notifier.dart:15,22-23` | [ ] | — | [ ] | [ ] |
| M10 | 播放時遇到「需要登入」的錯誤判斷存在但沒人使用，不會標記失效或引導登入 | — | `source_exception.dart:58` | [ ] | [ ] | [ ] 接上 | [ ] |
| M11 | 依登入／會員狀態選音質：B 站高解析與杜比音軌完全不讀；網易試聽片段不提示（見 D4） | — | `bilibili_source.dart:349-353`；`netease_source.dart:139-150` | [ ] | — | [ ] | [ ] |
| M12 | 歌單「使用登入狀態重新整理」會被重新匯入覆寫；帳號頁匯入的歌單一律帶登入 | — | `import_service.dart:250`；`account_playlists_sheet.dart:277` | [ ] | — | [ ] | [ ] |
| M13 | 各音源登入方式：B 站 WebView＋QR；YouTube 只有 WebView；網易 Android WebView＋QR、Windows 只有 QR | — | `platforms.md` §3；`accounts-network.md` §1 | [ ] | [ ] | [ ] | [ ] |

備註：

---

## 5. 下載與權限（N 項）

細節在 `downloads.md`。

**N1 要不要在舊版先修？** 它在目前發行的版本上就可能正在刪你的曲目，而重寫期間不發正式版。
- [ ] 審計後立刻在舊版 hotfix（需要例外發一版）  - [ ] 先不修，重寫時處理  - [ ] 先備份資料庫再決定  - [ ] 不確定

| # | 項目 | 現況 | 證據 | 保留 | 刪除 | 修改 | 不確定 |
|---|---|---|---|---|---|---|---|
| N1 | **已確認的資料遺失路徑**：每次啟動的下載同步重建曲目的 `playlistInfo`，只保留「DB 歌單原名 == 磁碟資料夾名」的關聯；資料夾名是 `sanitizeFileName` 過的，歌單名含 `: ? / \|` 等字元、或你照改名提示搬過資料夾時就對不上而被丟掉。約 10 秒後的孤兒清理只看 `playlistInfo` 有無 `playlistId > 0`、不看 `Playlist.trackIds`，於是曲目被從資料庫刪除並從歌單消失。另外，已下載曲目若同時在另一個未下載的歌單，那個關聯每次啟動都會被丟 | 呼叫鏈完整、未實機重現（`downloads.md` §4.4） | `download_path_sync_service.dart:162-197`；`track_repository.dart:635-669`；`queue_manager.dart:226`；`app.dart:131` | [ ] | — | [ ] 以 id 比對、清理改看 `Playlist.trackIds` | [ ] |
| N2 | Android 下載路徑只在第一次下載時選，設定頁不能改；權限被撤銷後每次下載都失敗，不重新請求、不導去系統設定 | — | `settings_storage.dart:60`；`storage_permission_service.dart:69` | [ ] | — | [ ] | [ ] |
| N3 | 改下載路徑時的行為（搬檔／掃新目錄／只重設）；歌單改名不會改資料夾，要使用者自己搬 | — | `download_path_maintenance_service.dart:59-80`；`playlist_service.dart:136-141,166-189` | [ ] | — | [ ] | [ ] |
| N4 | 續傳：每次繼續重新解析 URL，沒有 ETag／If-Range／大小驗證（推測可能接出損壞檔）；手動重試從頭下；下載本身不自動重試 | — | `download_service.dart:685-688,1904-1906` | [ ] | [ ] 取消續傳 | [ ] 加驗證 | [ ] |
| N5 | 下載音質跟播放共用設定，沒有下載專用音質；可能拿到 muxed 串流 | — | `base_source.dart:44-50`；`settings.dart:59-63` | [ ] | — | [ ] | [ ] |
| N6 | 副檔名一律 `.m4a`（opus、flac 也一樣）；metadata 只寫 sidecar JSON，不寫進音檔內嵌 tag | — | `download_path_utils.dart:40-46` | [ ] | — | [ ] | [ ] |
| N7 | 失敗任務在下次開啟下載功能時被清掉 | — | `download_repository.dart:66-96`；`download_service.dart:206-212` | [ ] | — | [ ] | [ ] |
| N8 | 下載只在 App 行程內的 isolate 跑，沒有前景服務或系統排程 | — | `downloads.md` §2 | [ ] | — | [ ] | [ ] |
| N9 | 播放時找不到本地檔就永久清掉下載路徑，不區分「儲存裝置暫時拔出」 | — | `stream_resolution_service.dart:128-136` | [ ] | — | [ ] | [ ] |
| N10 | 權限：沒宣告 `POST_NOTIFICATIONS`、沒有電池最佳化豁免；open_filex 合併進三個從不請求的 `READ_MEDIA_*`；Android 10 以下被拒時沒說明、不導去設定 | — | `downloads.md` §6；`AndroidManifest.xml` | [ ] | — | [ ] | [ ] |
| N11 | 權限請求統一入口（目前儲存權限走自有 MethodChannel，刻意不用 permission_handler） | — | `storage_permission_service.dart:22-24` | [ ] | — | [ ] 改用成熟套件 | [ ] |

備註：

---

## 6. 播放行為語意（D 項，目前行為可能不是你要的）

細節在 `playback.md`。

| # | 行為 | 現況 | 證據 | 保留 | 修改 | 不確定 |
|---|---|---|---|---|---|---|
| D1 | 點一首歌＝「臨時播放」（播完回原佇列），不是加入佇列 | 搜尋、歌單、首頁、排行、歷史、已下載都走 `playTemporary` | `playback.md` §0、§1；`search_page.dart:485` | [ ] | [ ] | [ ] |
| D2 | 歌單頁「全部」按鈕只加入佇列、不播放 | 方法名叫 `_playAll` | `playlist_detail_page.dart:884-890` | [ ] | [ ] | [ ] |
| D3 | Mix 模式（YouTube 無限佇列）：無法播放的歌不自動跳過、佇列無上限 | — | `audio_provider.dart:1955`；`mix_session_coordinator.dart:315` | [ ] | [ ] | [ ] |
| D4 | 網易雲試聽片段照常當完整歌曲播放，不提示；下載端也擋不到 | — | `netease_source.dart:139-150` | [ ] | [ ] 提示／跳過 | [ ] |
| D5 | 播放遇限流：只在解析層重試一次、等 3 秒，之後提示，不退避不跳過 | — | `stream_resolution_service.dart:210`；`audio_provider.dart:1984-1988` | [ ] | [ ] | [ ] |
| D6 | 播放歷史在「開流成功」時記一筆；單曲循環每圈都記 | — | `playback_side_effects.dart:166-175` | [ ] | [ ] | [ ] |
| D7 | 隨機模式下拖曳排序不更新隨機順序；「下一首播放」插到隨機位置 | — | `queue_manager.dart:541-547,594-613` | [ ] | [ ] | [ ] |
| D8 | 開電台時只暫停音樂、不取消正在載入的音樂（推測會被音樂串流蓋掉） | — | `radio_controller.dart:840-847` | [ ] | [ ] | [ ] |
| D9 | YouTube URL 有效期寫死 1 小時，不讀網址裡的 `expire` | — | `youtube_source.dart:52-54` | [ ] | [ ] | [ ] |
| D10 | 電台／直播 | 輪詢開播狀態；網路錯誤顯示成「未開播」 | `bilibili_live_client.dart:205-208`；`radio_refresh_service.dart:252-257` | [ ] | [ ] | [ ] |

電台／直播、Mix 整個功能要不要保留，另見 §7。

備註：

---

## 7. 功能去留（E 項，主要功能域）

完整清單在 `features.md`；這裡只列需要你表態的功能域。狀態欄沿用 `features.md` 的判定。

| # | 功能 | 狀態 | 平台 | 保留 | 刪除 | 修改 | 不確定 |
|---|---|---|---|---|---|---|---|
| E1 | 三個音源的搜尋與播放（B 站、YouTube、網易雲） | 完整 | A W | [ ] | [ ] | [ ] | [ ] |
| E2 | B 站分 P（多 cid 各自成曲，ADR 0005） | 完整 | A W | [ ] | [ ] | [ ] | [ ] |
| E3 | 音樂庫：本機歌單、排序、多選 | 完整 | A W | [ ] | [ ] | [ ] | [ ] |
| E4 | 匯入平台歌單（B 站收藏夾、YouTube 播放清單、網易雲歌單）並定時刷新 | 完整 | A W | [ ] | [ ] | [ ] | [ ] |
| E5 | 只能匯入的外部歌單（Spotify、QQ 音樂），自動匹配到可播放音源 | 完整；失敗時一律顯示「發生錯誤」（`errors.md` §1） | A W | [ ] | [ ] | [ ] | [ ] |
| E6 | 帳號登入（三個音源；WebView／QR） | 完整 | A W | [ ] | [ ] | [ ] | [ ] |
| E7 | 遠端歌單編輯（B1、B2） | 完整 | A W | [ ] | [ ] | [ ] | [ ] |
| E8 | 下載（含分類頁、路徑設定） | 完整；Android 在設定頁不能改下載路徑 | A W | [ ] | [ ] | [ ] | [ ] |
| E9 | 歌詞：多源搜尋（網易、QQ、lrclib）、自動匹配、手動選擇 | 完整 | A W | [ ] | [ ] | [ ] | [ ] |
| E10 | AI 歌詞匹配／標題解析（B5） | 完整，預設關 | A W | [ ] | [ ] | [ ] | [ ] |
| E11 | 桌面歌詞視窗（獨立視窗） | 完整，僅 Windows | W | [ ] | [ ] | [ ] | [ ] |
| E12 | 電台／直播（B 站直播間） | 完整；「收藏電台」無 UI 入口 | A W | [ ] | [ ] | [ ] | [ ] |
| E13 | Mix（YouTube 無限佇列） | 完整 | A W | [ ] | [ ] | [ ] | [ ] |
| E14 | 首頁排行／探索 | 完整 | A W | [ ] | [ ] | [ ] | [ ] |
| E15 | 播放歷史頁 | 完整 | A W | [ ] | [ ] | [ ] | [ ] |
| E16 | 備份與還原 | 完整 | A W | [ ] | [ ] | [ ] | [ ] |
| E17 | 應用內更新（B7–B9） | 完整，只有手動檢查一個入口 | A W | [ ] | [ ] | [ ] | [ ] |
| E18 | 托盤、全域快捷鍵、開機自啟、關閉縮到托盤、單一實例 | 完整，僅 Windows | W | [ ] | [ ] | [ ] | [ ] |
| E19 | 播放速度（0.5–2.0，不持久化）、音量、桌面輸出裝置選擇；**沒有**睡眠定時器與均衡器 | 完整（`playback.md` §3.14） | A W | [ ] | [ ] | [ ] | [ ] |
| E20 | 使用者指南頁（設定頁進入，`lib/ui/pages/settings/user_guide_page.dart`） | 完整 | A W | [ ] | [ ] | [ ] | [ ] |

備註：

---

## 8. 平台綁定功能在其他平台上的去留

現況在 `platforms.md` §3、§6。每格選：**全**＝全平台提供；**部分**＝只在部分平台（備註寫哪些）；**刪**＝刪除；**?**＝不確定。

| 功能 | 現況 | 其他平台會卡在哪 | 全 | 部分 | 刪 | ? |
|---|---|---|---|---|---|---|
| 自動更新（應用內下載安裝） | A W | iOS 政策禁止；Mac App Store 禁止；Linux 依打包格式 | [ ] | [ ] | [ ] | [ ] |
| 下載音檔 | A W | App Store 5.2.3；iOS 沙盒 | [ ] | [ ] | [ ] | [ ] |
| Android 用「所有檔案存取權」裸路徑（ADR 0004） | A | 上架 Play 會被擋；可改 SAF／app 專屬目錄 | — | [ ] 維持 | [ ] 改 SAF | [ ] |
| 登入 WebView | A W | flutter_inappwebview 無 Linux 實作；YouTube 沒有 QR 登入 | [ ] | [ ] | [ ] | [ ] |
| 托盤 | W | 套件支援 macOS／Linux，程式寫死 Windows | [ ] | [ ] | [ ] | [ ] |
| 全域快捷鍵 | W | 同上；Linux Wayland 限制 | [ ] | [ ] | [ ] | [ ] |
| 開機自啟 | W | macOS 需額外原生碼 | [ ] | [ ] | [ ] | [ ] |
| 關閉縮到托盤、單一實例 | W | runner C++ 自訂 | [ ] | [ ] | [ ] | [ ] |
| 桌面歌詞視窗 | W | 需 runner 註冊子視窗插件；Android 寬版面有無作用的按鈕 | [ ] | [ ] | [ ] | [ ] |
| 自訂標題列 | W | macOS／Linux 現在是藏起來沒替代 | [ ] | [ ] | [ ] | [ ] |
| 系統媒體控制 | A（audio_service）、W（SMTC，不支援 seek） | macOS 可接 audio_service；Linux 需 MPRIS | [ ] | [ ] | [ ] | [ ] |
| 內建 CJK 字型 | 無（fallback `Noto Sans SC` 未內建） | 各平台字型不一 | [ ] 內建 | [ ] 依平台 fallback | — | [ ] |

備註：

---

## 9. 架構與程式碼層面的現況問題（G 項）

多數會在階段二自然解決；列出來是讓你知道現在的樣子。

| # | 問題 | 證據 | 重寫時處理 | 不處理 | 不確定 |
|---|---|---|---|---|---|
| G1 | `AudioController` 2,953 行、約 125 個方法；一次播放經十幾層協作物件；播放器狀態至少 5 份 | `architecture.md` §7；`playback.md` §2 | [ ] | [ ] | [ ] |
| G2 | 19 個目錄的大循環依賴（起因：`main.dart` 全域可變狀態被反向 import） | `architecture.md` §3；`lib/main.dart:29-44` | [ ] | [ ] | [ ] |
| G3 | 新增一個音源最少改 15 檔、同網易雲程度約 54 檔；音源特定分支 50 處散在 28 檔 | `sources.md` §3、§4 | [ ] | [ ] | [ ] |
| G4 | 錯誤呈現：自訂例外到畫面一律「發生錯誤」；adapter 把 `e.toString()` 原文丟上畫面；多源搜尋只要一源成功就隱藏其他失敗；507 個 catch 中約 70 個空的 | `errors.md` §1、§4 | [ ] | [ ] | [ ] |
| G5 | 播放網路錯誤的重試訊號只有沒人用的入口接得住，臨時播放／Mix／上下首會出錯 | `playback.md` §3.6；`audio_provider.dart:596,1933-1943` | [ ] | [ ] | [ ] |
| G6 | 161–162 個手寫 provider，放置慣例三種以上；repository 被繞過直接 `XxxRepository(db)` 20 處以上；約 19 個 Notifier 各自讀寫同一列 `Settings` | `architecture.md` §4 | [ ] | [ ] | [ ] |
| G7 | 死代碼：84 個 public 成員零引用（候選）；`checkNow`、`reset`、`cleanupInvalidPaths`、`refreshStation`、`batchRemoveFromFolder`、`autoRefreshAll`、`playSingle`／`playAll`／`playPlaylist` 等已確認零呼叫 | `engineering.md` §7.2；`features.md` §14；`playback.md` §4.5 | [ ] | [ ] | [ ] |
| G8 | 重複邏輯：位元組格式化 6 份、InnerTube 文字抽取 2 份（行為不同）、兩個同名 `NeteaseSource`、兩條名稱倒裝的歌單匯入流程 | `engineering.md` §7.3；`architecture.md` §7 | [ ] | [ ] | [ ] |
| G9 | Toast／錯誤呈現三種寫法；背景錯誤只有 `AppShell` 在聽，全螢幕播放頁可能看不到（推測） | `devtools.md` §2 | [ ] | [ ] | [ ] |

備註：

---

## 10. 測試類別的去留

現況在 `engineering.md` §2、§3、§5。本機全量 `--exclude-tags live`：1,849 通過、0 失敗、2 分 48 秒。

| 類別 | 數量 | 現況評語 | 保留 | 刪除 | 修改 | 不確定 |
|---|---|---|---|---|---|---|
| 離線行為測試（services／data／providers／ui） | 約 1,700 個 | 以行為為主；部分大量依賴 `debug*ForTesting` 掛鉤（下載服務 44 處） | [ ] | [ ] | [ ] | [ ] |
| live 測試（打真實 API） | 4 個 | **不加參數的 `flutter test` 會跑它們**（`dart_test.yaml` 無預設 skip） | [ ] | [ ] | [ ] 預設排除 | [ ] |
| static-rule（正則比對原始碼） | 25 檔 144 個 | 都有合成違規測試；有些是計次預算（例如 `audio_provider.dart` 行數 ≤ 2,184、音源分支預算 9 處但實際 50 處沒守住） | [ ] | [ ] | [ ] | [ ] |
| 測 CI 設定本身（`test/workflows/`） | 4 檔 31 個 | 一半解析 YAML，一半比對 shell 片段字串 | [ ] | [ ] | [ ] | [ ] |
| benchmark（`test/performance/`） | 2 檔 13 個 | 可離線跑；斷言寬鬆的絕對上限 | [ ] | [ ] | [ ] | [ ] |
| 手動探針（`test/manual/`） | 2 檔 | 本機 HTTP 病態伺服器、真實 DB 探針 | [ ] | [ ] | [ ] | [ ] |
| `tool/demo/`（手跑、打真實 API） | 6 支 | 不引用 `lib/`，其中一支帶一份 `RegexTitleParser` 副本 | [ ] | [ ] | [ ] | [ ] |

另：main 分支 CI 目前是紅的（`account_repository_test.dart:105-118` 用固定 200ms 等待，時序不穩；run 36239727409）。
- [ ] 審計結束後先在舊版修掉  - [ ] 不管，重寫時處理  - [ ] 不確定

備註：

---

## 11. i18n 語言

- 現況：`en`、`zh-CN`、`zh-TW` 三種，每種 38 個 JSON 檔，用 slang 管理（`lib/i18n/`）。缺漏 key 與硬編碼字串統計見 `ui.md` §4。

| 語言 | 保留 | 刪除 | 不確定 |
|---|---|---|---|
| English（`en`） | [ ] | [ ] | [ ] |
| 簡體中文（`zh-CN`） | [ ] | [ ] | [ ] |
| 繁體中文（`zh-TW`） | [ ] | [ ] | [ ] |

其他想加的語言：

- base locale（缺字時的後備語言）目前是 `zh-CN`：[ ] 維持 [ ] 改 `zh-TW` [ ] 改 `en` [ ] 不確定
- 三語言目前完全對齊（各 1,176 個 key），但桌面浮動歌詞視窗有 33 個簡體字串寫死在程式碼（`lyrics_window.dart:33-66`），UI 裡另有硬編碼字串（`ui.md` §4）：[ ] 重寫時全部納入 i18n [ ] 不確定

---

## 12. UI／UX 現況問題（U 項）

現況在 `ui.md` §7、截圖在 `docs/audit/screenshots/`。階段二會出設計系統與桌面播放器版面方案；這裡先確認問題清單與範圍。

| # | 問題 | 證據 | 重寫時處理 | 不處理 | 不確定 |
|---|---|---|---|---|---|
| U1 | 間距與字級沒有 token：`EdgeInsets` 約 250 處、`SizedBox` 約 500 處字面數字，29 處 `fontSize:` 繞過主題 | `ui.md` §3.2 | [ ] | [ ] | [ ] |
| U2 | 桌面鍵盤操作：App 內沒有任何快捷鍵（`Shortcuts`／`Actions` 0 處），Esc 離不開播放頁；焦點指示在深色主題幾乎看不見，Tab 要穿過整個清單才到導航軌 | `ui.md` §5.3；`windows-focus-row.png` | [ ] | [ ] | [ ] |
| U3 | 無障礙：播放頁大播放鍵沒有名稱；迷你播放器是「按鈕包按鈕」 | `player_play_pause_button.dart:46-48`；`mini_player.dart:54-58` | [ ] | [ ] | [ ] |
| U4 | 窄桌面視窗的迷你播放器保留 7 顆鈕，標題只剩 2 個字 | `windows-compact-home.png` | [ ] | [ ] | [ ] |
| U5 | 搜尋頁來源篩選列被排序鈕蓋住、沒有可捲動提示 | `windows-search.png`、`android-search.png` | [ ] | [ ] | [ ] |
| U6 | 數字與複數格式：「4600.0萬」「46.0M」「1 tracks」 | `number_format_utils.dart:28-37` | [ ] | [ ] | [ ] |
| U7 | 右側「正在播放」面板在所有頁面常駐（寬度 ≥ 840） | `ui.md` §1.2 | [ ] 保留常駐 | [ ] 只在播放相關頁 | [ ] |
| U8 | `large`／`extraLarge` 斷點註解承諾的版面沒有實作 | `responsive_scaffold.dart:116-145` | [ ] 實作 | [ ] 刪註解 | [ ] |
| U9 | Windows debug／profile build 讀寫使用者真實資料（`Documents\FMP`），沒有隔離；本次審計因此誤觸播放你佇列中的曲目 | `database_provider.dart:49-52` | [ ] 開發版用獨立資料目錄 | [ ] | [ ] |

---

## 13. 開發者模式與 log（J 項）

現況在 `devtools.md`。

| # | 項目 | 現況 | 保留 | 刪除 | 修改 | 不確定 |
|---|---|---|---|---|---|---|
| J1 | 開發者模式開啟方式（「版本」連點 7 次）、不持久化、沒有關閉入口 | `developer_options_page.dart:69-77` | [ ] | [ ] | [ ] | [ ] |
| J2 | Debug 頁現有區塊（log 檢視、資料庫檢視器、重設資料等） | `devtools.md` §1 | [ ] | [ ] | [ ] 階段二重做 | [ ] |
| J3 | log 寫檔（位置、輪替見 `devtools.md` §3） | — | [ ] | [ ] | [ ] | [ ] |
| J4 | `DataIntegrityRepository.scan/repair`（只有測試用） | `data_integrity_repository.dart:59-85` | [ ] 接到 Debug 頁 | [ ] | — | [ ] |

備註：

---

## 14. ADR 逐份

比對細節在 `engineering.md` §10。選項：**確認**＝新架構沿用這個決定；**推翻**＝改走別的路；**不再適用**＝新架構下這題不存在。

| ADR | 它決定了什麼 | 代碼現況 | 確認 | 推翻 | 不再適用 |
|---|---|---|---|---|---|
| 0001 每源設定收成清單、音源改用字串 id | 刪 `enum SourceType`，改 `SourceIds` 字串常數；每源設定改成 `@embedded List<SourceSettingsEntry>` | **部分不一致**：ADR 說 `setUseAuthForPlay` 對未知 id 拋錯，`8ffa7d4f` 已改成建一筆預設（ADR 寫成時就已過時） | [ ] | [ ] | [ ] |
| 0002 Isar 只出現在 repository 層 | `isar.` 只准在 `lib/data/repositories/`，兩個明文豁免；由 static-rule 守 | 一致；但 `Isar` 實例本身傳遍各層，UI 甚至會自己跑遷移（`developer_options_page.dart:548-554`） | [ ] | [ ] | [ ] |
| 0003 保留兩個音訊後端 | Android／iOS just_audio，其他 media_kit；共用純規則 | 一致 | [ ] | [ ] | [ ] |
| 0004 Android 下載用所有檔案存取權與裸路徑 | 知情接受 `MANAGE_EXTERNAL_STORAGE`，理由是永不上架商店 | 一致 | [ ] | [ ] | [ ] |
| 0005 曲目識別鍵包含 cid | 分 P 以 cid 區分，鍵字串是持久化格式 | 一致 | [ ] | [ ] | [ ] |
| 0006 Release 驗過產物就直接發布 | 不留草稿，驗證 job 取代人工按發布 | 一致（release validate 比 CI 少 `dart format`） | [ ] | [ ] | [ ] |
| 0007 Isar 停在 v3，改用 isar_community | 留 v3 磁碟格式，依賴換成社群 fork | **部分不一致**：上游最後發版日期寫錯（實為 2023-08） | [ ] | [ ] | [ ] |

備註：

---

## 15. `CONTEXT.md` 逐個術語

比對細節在 `engineering.md` §11。選項：**保留**＝留在（新的）術語表；**併入**＝併進對應 spec 或 docs 術語表；**刪除**＝新架構不需要這個詞。

| 術語 | 意思（一句話） | 代碼現況 | 保留 | 併入 spec／docs 術語表 | 刪除 |
|---|---|---|---|---|---|
| Source Auth Context | 決定某次音源操作可以用哪些憑證的政策 | 有對應：`SourceAuthContext`（`source_auth_context.dart:76`） | [ ] | [ ] | [ ] |
| Media Handoff | 從解析出的串流 URL 交給播放／下載後端的那一步（headers、redirect 檢查） | 部分對應：redirect 檢查只在下載 isolate（`download_service.dart:1831-1885`），播放路徑沒有 | [ ] | [ ] | [ ] |
| Stream Resolution Auth | 向音源要串流 URL 時用的憑證 | 有對應；`streamResolutionAuth` 欄位在生產路徑上沒被讀取 | [ ] | [ ] | [ ] |
| Auth For Play | 使用者設定，控制播放／下載／詳情是否帶憑證 | 有對應（`settings.dart:724`）；實際也控制首頁排行榜，CONTEXT 沒寫 | [ ] | [ ] | [ ] |
| Media Request Credentials | 允許出現在音訊位元組請求上的憑證（目前為空） | 有對應（`source_http_policy.dart:82`） | [ ] | [ ] | [ ] |

備註：
