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

`lib/data/models/` 裡的檔案不全是 Isar collection。註冊為 collection 的那些列在
`lib/data/database/database_catalog.dart`（那是權威清單，不要在別處抄一份）；其餘
是 DTO 與 value object，放在旁邊只是因為它們描述同一批概念，除非顯式註冊否則不
需要資料庫遷移。

資料庫固定開在應用程式 documents 目錄下的 `FMP/` 子目錄，入口只有
`openFmpDatabase()`。欄位變動時的遷移與 default repair 規則見
`lib/data/AGENTS.md`。

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

權威定義在 `lib/core/constants/breakpoints.dart`。那裡有**兩組** API，回答兩個
不同的問題，不可以互相代用：`WindowClass.of(width)` 決定視窗骨架（底部導覽列還是
側邊導覽軌、要不要給詳情面板），`columnsFor(containerWidth)` 決定一個容器內部放
幾欄。

容器拿到的寬度已經扣掉導覽軌與詳情面板，所以 1280dp 的視窗可能只給內容區
868dp —— 那時候容器該回答「2 欄」，即使視窗級距是 `large`。混用兩者正是「拖寬
面板讓首頁掉一個音源」那個 bug 的成因。

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

不在這裡重複。AI agent 的強約束規則在 [AGENTS.md](../AGENTS.md)（根目錄）以及
`lib/data`、`lib/data/sources`、`lib/providers`、`lib/services`、
`lib/services/audio`、`lib/ui` 各自的 `AGENTS.md`；人類貢獻者適用同一套。抄一份
摘要到這裡只會多一個會漂移的副本。

## 更多文件

- [文件地圖](README.md)
- [建置指南](building.md)
- [建置與發布指南](build-and-release.md)
- [VM Service 除錯指南](debugging-with-vm-service.md)
- [Agent 規則](../AGENTS.md)
