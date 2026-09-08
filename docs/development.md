# FMP 開發文件

本文件面向想了解專案結構或參與開發的貢獻者。更詳細的 agent 規則、資料庫遷移規則和專案特定編碼約束維護在 [AGENTS.md](../AGENTS.md)。

## 技術棧

| 層級 | 技術 | 說明 |
|------|------|------|
| UI | Flutter / Dart | Material 3，Android + Windows 響應式 UI |
| 狀態管理 | Riverpod 2.x | Providers、StateNotifier、FutureProvider、StreamProvider |
| 本機儲存 | Isar 3.x | 持久化應用程式資料和設定 |
| 路由 | go_router | 宣告式路由 |
| 網路 | Dio | 音源 API 和媒體請求 |
| 國際化 | slang | 產生型別安全翻譯程式碼 |
| 音訊 | just_audio / media_kit | Android 使用 just_audio，桌面使用 media_kit |
| 加密 | crypto / encrypt / pointycastle | 網易雲 eapi/weapi 支援 |

## 平臺分工

| 平臺 | 音訊後端 | 平臺特性 |
|------|----------|----------|
| Android | `JustAudioService` / ExoPlayer | 背景播放、通知列控制、儲存權限 |
| Windows | `MediaKitAudioService` / libmpv | 音訊裝置切換、SMTC、系統匣、全域快速鍵、歌詞子視窗 |

Windows 本機建置還需要部分原生工具：

| 工具 | 相關外掛 | 用途 |
|------|----------|------|
| NuGet CLI | `flutter_inappwebview_windows` | 下載 WebView2、WIL 等原生依賴 |
| Rust 工具鏈 | `smtc_windows` | 建置 cargokit 原生函式庫 |

安裝和排錯細節見〈[建置指南](building.md)〉。

## 架構地圖

FMP 大體採用 UI -> Provider/Controller -> Service -> Data/Source 的分層。最重要的邊界是音訊邊界：UI 必須呼叫 `AudioController`，不要直接呼叫 `AudioService`。

```
UI pages/widgets
  -> Riverpod providers/controllers
  -> services/* 業務邏輯
  -> data/repositories 存取 Isar
  -> data/sources 存取外部平臺
```

關鍵目錄：

```text
lib/
├── core/          # 常量、主題、共享服務、工具
├── data/          # models、repositories、外部音源解析
├── providers/     # Riverpod provider 定義
├── services/      # audio、account、lyrics、download、library、update 等業務邏輯
├── ui/            # pages、widgets、layouts、windows
├── i18n/          # slang 翻譯資源
├── app.dart       # app 進入點和路由接線
└── main.dart      # 行程啟動和平臺初始化
```

更完整的檔案結構見 [AGENTS.md](../AGENTS.md#key-paths)，目前 provider 規則見
[lib/providers/AGENTS.md](../lib/providers/AGENTS.md)。

## 資料模型分類

`lib/data/models/` 裡的檔案不全是 Isar collection。

### 持久化 Isar Collections

以下 collection 註冊在 `lib/data/database/database_catalog.dart`；`database_provider.dart` 只負責 open/遷移/default repair。欄位變化時需要檢查遷移/default repair，並同步檢查資料庫檢視器。

資料庫檔案透過 `openFmpDatabase()` 開啟，固定存放在應用程式 documents 目錄下的 `FMP/` 子目錄中。不要在其他位置手寫 `getApplicationDocumentsDirectory()/fmp_database.isar`；需要路徑或大小資訊時複用 `resolveFmpDatabaseDirectory()` 和 `fmpDatabaseFileName`。

| Collection | 用途 |
|------------|------|
| `Track` | 歌曲/音訊實體和音源後設資料 |
| `Playlist` | 本機/匯入歌單後設資料 |
| `PlayQueue` | 佇列、Mix 模式、播放持久化 |
| `Settings` | 應用程式設定、音質、認證、歌詞、重新整理間隔 |
| `SearchHistory` | 搜尋歷史 |
| `DownloadTask` | 下載佇列/任務狀態 |
| `PlayHistory` | 播放歷史 |
| `RadioStation` | 電臺/直播站點 |
| `LyricsMatch` | Track 到歌詞源的匹配記錄 |
| `LyricsTitleParseCache` | 執行期 AI 標題解析快取（執行期暫存、啟動時清空、非耐用資料；權威規則見 `lib/data/AGENTS.md`） |
| `Account` | 平臺登入/帳號狀態 |

### 非持久化 DTO / Value Objects

這些型別放在 data model 附近，是因為它們描述音源或 UI 資料；除非顯式註冊為 Isar schema，否則不需要資料庫遷移。

| 型別 | 用途 |
|------|------|
| `LiveRoom` / `LiveSearchResult` | Bilibili 直播間搜尋，以及轉換成 radio/track |
| `VideoDetail` / `VideoPage` / `VideoComment` | 詳情面板和後設資料顯示 |
| `HotkeyConfig` / `HotkeyBinding` | 透過 `Settings` 儲存的 JSON 桌面快速鍵設定 |

## 音源支援

| 音源 | 目前支援 |
|------|----------|
| Bilibili | 影片音訊、多 P 影片、直播間音訊、收藏夾匯入 |
| YouTube | 影片音訊、播放清單、Mix/Radio 動態佇列、Opus/AAC 偏好 |
| Netease | 搜尋、歌曲詳情、eapi 音訊流、歌單匯入、VIP/可用性處理 |
| 外部歌單匯入 | Netease、QQ Music、Spotify 搜尋匹配匯入 |

直接音源的 API 例外共享 `SourceApiException`，播放層可以統一處理不可用、限流、需要登入和網路錯誤等情況。

## 歌詞系統概覽

自動歌詞匹配使用 `Settings.lyricsSourcePriorityList` 中目前的設定順序，並跳過被停用的歌詞源。預設順序是 Netease -> QQ Music -> lrclib，且預設自動匹配停用 lrclib。

高層流程：

1. 已有 `LyricsMatch` 記錄時直接用快取。
2. 網易雲 track 直接用 sourceId 取得歌詞。
3. 匯入自 Netease/QQ Music 的 track 用原平臺 ID 直取。
4. 按使用者設定的歌詞源順序搜尋。
5. 根據設定選擇是否使用 AI 標題解析或 AI 進階匹配。

自動匹配預設只接受同步歌詞，除非開啟 `allowPlainLyricsAutoMatch`。桌面歌詞視窗使用獨立 Flutter engine，關閉時隱藏而不是銷毀。

## 路由

重要路由常量在 `lib/ui/router.dart`。

| 區域 | 路由 |
|------|------|
| 主導覽 | `/`、`/search`、`/explore`、`/queue`、`/history`、`/library`、`/radio`、`/settings` |
| 詳情頁 | `/player`、`/radio-player`、`/library/:id`、`/library/downloaded`、`/library/downloaded/:folderName` |
| 設定 | `/settings/audio`、`/settings/lyrics-source`、`/settings/download-manager`、`/settings/user-guide`、`/settings/home-ranking`、`/settings/account`、`/settings/account/bilibili-login`、`/settings/account/youtube-login`、`/settings/account/netease-login`、`/settings/developer` |
| 開發者工具 | `/settings/developer/database`、`/settings/developer/logs` |

## 響應式版面配置

權威定義在 `lib/core/constants/breakpoints.dart`。那裡有**兩組**API，回答的是
兩個不同的問題，不可以互相代用：

`WindowClass.of(width)` 決定視窗骨架（值取自 Material 3 與 `androidx.window`）：

| WindowClass | 寬度 | 導覽方式 |
|------|------|----------|
| `compact` | `< 600dp` | 底部導覽列 |
| `medium` | `600–839dp` | 精簡側邊導覽軌 |
| `expanded` | `840–1199dp` | 可收合側邊導覽軌 + 可選詳情面板 |
| `large` | `1200–1599dp` | 同上 |
| `extraLarge` | `>= 1600dp` | 同上 |

`columnsFor(containerWidth)` 決定**一個容器內部**放幾欄（每 400dp 一欄，上限
3）。容器拿到的寬度已經扣掉導覽軌與詳情面板，所以 1280dp 的視窗可能只給內容區
868dp —— 那時候容器該回答「2 欄」，即使視窗級距是 `large`。

## 常用指令

```bash
flutter run
flutter run -d windows
flutter analyze
flutter test
dart run build_runner build
dart run slang
```

本機 release 建置見〈[建置指南](building.md)〉，CI/release 行為見〈[建置與發布指南](build-and-release.md)〉。

## 開發規則摘要

這裡只保留簡短摘要。詳細目前規則見 [AGENTS.md](../AGENTS.md)。

- UI 程式碼呼叫 `AudioController`，不要直接呼叫平臺音訊 service。
- 修改 Isar collection 或註冊 schema 時，需要檢查遷移/default repair 和資料庫檢視器。
- UI 圖片載入應使用語義圖片元件，例如 `TrackThumbnail`、`TrackCover`、
  `PlaylistCoverImage`、`RadioCoverImage`、`RecentPlayCoverImage` 或
  `AvatarImage`。
- 公共 track actions 應走 `TrackActionCoordinator` 和共享 menu builders。
- 檔案系統 `FutureProvider` 資料源被修改後必須 invalidate。
- 清單/網格重複項應使用穩定 key。
- `AppBar.actions` 如果最後一個是 `IconButton`，末尾應加 `SizedBox(width: 8)`。

## 更多文件

- [文件地圖](README.md)
- [建置指南](building.md)
- [建置與發布指南](build-and-release.md)
- [VM Service 除錯指南](debugging-with-vm-service.md)
- [Agent 規則](../AGENTS.md)
