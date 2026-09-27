# 設計：快取與離線（階段二第 17 項）

## 目標

為 `app/` 定下圖片、串流網址、歌詞、排行與插件回應等快取的統一策略，以及沒有網路時 App 能做什麼。產出 ADR 0016。

依據：parent `prd.md` 階段二第 17 項；`phase2-plan.md`（B6、D9，及相關的 B10、B12）；ADR 0010–0015。

## 現況（`research/current-state.md`，已以程式碼核對）

- **圖片**：三層互不統一——Flutter 記憶體 `ImageCache`（寫死 行動 100 張／50MB、桌面 200 張／80MB，`lib/main.dart:156-164`）、
  `flutter_cache_manager` 磁碟快取（7 天、上限由設定「圖片快取大小」16–64MB 推估檔案數，`network_image_cache_service.dart:127-140`）、
  解碼縮放。使用者設定只管磁碟那一層；「清除圖片快取」不清記憶體層。同一張圖不同顯示尺寸各存一份（`image_loading_service.dart:315-383`）。
- **串流網址**：存進 Isar `Track.audioUrl`／`audioUrlExpiry`（`track.dart:68-71`），另有行程內 32 筆快取（`stream_resolution_service.dart:109-113`）。
  播放只看行程內快取、不用 Isar 那份，所以持久化實際沒用；**反而造成預取失效**：下一首在 Isar 有「未過期」網址時 `prefetchTrack` 直接返回
  （`:299-304`），切歌時退化成同步解析。過期來源：B 站讀 `deadline`、YouTube 寫死 1 小時（D9）、網易讀 `expi` 否則 16 分鐘。
- **歌詞**：`getApplicationCacheDirectory()/lyrics/` 每首一個 JSON，LRU，檔數上限可調（10–200）、總量寫死 5MB（`lyrics_cache_service.dart:19-64`）。
- **排行**：只在記憶體，重啟重抓；離線時保留舊資料；**停用首頁顯示的音源仍在背景抓**（`ranking_cache_service.dart:158-172`，B12）。
- **電台**：沒有快取，只有記憶體中的直播狀態。搜尋歷史是使用者資料（Isar，上限 100），不是快取。
- **音訊**：沒有邊聽邊存。Windows mpv 只是播放期記憶體緩衝；已下載的曲目優先播本機檔，離線可播。
- **離線**：每 15 秒對三個公共 DNS 查詢判定（`connectivity_service.dart:51-116`，B10）；只有一個全域 Banner，沒有任何頁面有離線狀態。

## 研究結論（`research/prior-art.md`、`research/packages-and-platform.md`）

- MusicFree 讓音源插件自己宣告網址能否重用（`cacheControl`），App 不必懂各平台的 `expire`／`deadline`；NewPipe 用固定 TTL（YouTube 1 小時）。
- Namida 是唯一分類可調上限＋LRU 的；Spotube 一個開關；MusicFree 一個音樂快取容量＋三個清除按鈕；Finamp 不做快取、只靠明確下載，並有自動＋手動的離線模式。
- `cached_network_image`／`flutter_cache_manager` 仍活躍（2026-09 發版）。`just_audio` 的 `LockCachingAudioSource` 仍是 experimental，Windows／Linux 不保證；
  `media_kit` 沒有邊聽邊存，只能自建本機 proxy。
- `getApplicationCacheDirectory()` 在 Android 會被系統在空間不足時清掉，官方要求 App 自行處理。
- `connectivity_plus` 官方文件明說「有網路介面不代表能上網」，建議以請求本身的錯誤判斷——與 B10 的方向一致。

## 已確定的方向（先前的勾選）

- B6：串流網址不進資料庫，只放短期快取。D9：網址期限從網址本身讀，不寫死。B10：拿掉 DNS 輪詢，改系統網路狀態＋請求失敗判定。B12：停用就不抓排行。

## 依功能凍結歸入待辦（第 20 項），本項不做

- 邊聽邊存（音訊快取）：新功能，且 Windows 需自建 proxy。現有的「下載」照舊是唯一的離線保存方式。
- 手動離線模式開關、已下載內容的容量管理（LRU＋釘選）：新功能。

## 待決定

- [ ] 快取的使用者設定形式（一個總上限 vs 分類上限）

## 驗收條件

- [ ] ADR 0016 記錄：快取的定義與位置、每一類的鍵／期限／上限／清除、串流網址期限由插件回報、離線判定與離線時各功能的行為、使用者設定。
- [ ] B6、D9、B10（離線判定部分）、B12 各自對到決定與閘門；舊預取失效問題在新設計下不再成立並有測試守。
- [ ] `phase2-plan.md` §3 第 17 項標 ✅ 與 ADR 編號。

## 不在範圍

- 背景刷新的排程機制（第 16 項）；播放佇列跳過的細節（第 13 項）；下載（第 11 項）；設定頁版面（第 5 項）。
