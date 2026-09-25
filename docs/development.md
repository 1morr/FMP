# FMP 開發文件

本文件面向想了解專案結構或參與開發的貢獻者。架構邊界、驗證要求與專案慣例在 [AGENTS.md](../AGENTS.md)，人類貢獻者適用同一套。

## 平臺分工

| 平臺 | 音訊後端 | 平臺特性 |
|------|----------|----------|
| Android | `JustAudioService` / ExoPlayer | 背景播放、通知列控制、儲存權限 |
| Windows | `MediaKitAudioService` / libmpv | 音訊裝置切換、SMTC、系統匣、全域快速鍵、歌詞子視窗 |

為什麼保留兩個後端見 [ADR 0003](adr/0003-two-audio-backends.md)。技術棧見 [README](../README.md#built-with)，版本以 `pubspec.yaml` 為準；Windows 本機建置需要的原生工具見〈[建置指南](building.md)〉。

## 架構地圖

FMP 大體採用 UI -> Provider/Controller -> Service -> Data/Source 的分層。最重要的邊界是音訊邊界：UI 必須呼叫 `AudioController`，不要直接呼叫 `FmpAudioService`。兩個後端哪裡行為不同，寫在 `FmpAudioService` 各成員的 dartdoc。

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

狀態管理是 Riverpod 3 的 `Notifier` / `FutureProvider` / `StreamProvider`，沒有 `StateNotifier`。
各模組的設計理由寫在程式碼的 dartdoc 與守著它的測試裡。

## 資料模型分類

`lib/data/models/` 裡的檔案不全是 Isar collection。註冊為 collection 的那些列在
`lib/data/database/database_catalog.dart`（那是權威清單，不要在別處抄一份）；其餘
是 DTO 與 value object，放在旁邊只是因為它們描述同一批概念，除非顯式註冊否則不
需要資料庫遷移。

資料庫固定開在應用程式 documents 目錄下的 `FMP/` 子目錄，入口只有
`openFmpDatabase()`。欄位變動時的遷移與 default repair 規則見
`lib/data/database/database_migration.dart` 的 `kFmpSchemaVersion` dartdoc。

## 音源

各音源支援的功能見 [README](../README.md#what-it-does)。直接音源的 API 例外共享 `SourceApiException`（`lib/data/sources/source_exception.dart`），播放層可以統一處理不可用、限流、需要登入和網路錯誤等情況。

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

路由常量與完整清單在 `lib/ui/router.dart`。

## 響應式版面配置

權威定義在 `lib/core/constants/breakpoints.dart`。那裡有**兩組** API，回答兩個
不同的問題，不可以互相代用：`WindowClass.of(width)` 決定視窗骨架（底部導覽列還是
側邊導覽軌、要不要給詳情面板），`columnsFor(containerWidth)` 決定一個容器內部放
幾欄。

容器拿到的寬度已經扣掉導覽軌與詳情面板，所以 1280dp 的視窗可能只給內容區
868dp —— 那時候容器該回答「2 欄」，即使視窗級距是 `large`。混用兩者正是「拖寬
面板讓首頁掉一個音源」那個 bug 的成因。

## 常用指令

見〈[建置指南](building.md#常用指令)〉；CI/release 行為見〈[建置與發布指南](build-and-release.md)〉。

## 執行期除錯（VM Service）

問題是關於「正在跑的 app」而不是原始碼時用它：某個服務現在的欄位值、打了哪些
HTTP 請求、資料庫裡實際存了什麼。只在 debug / profile build 可用；Isar 的
`ext.isar.*` 只在 debug（`Isar.open` 的 `inspector` 在 profile / release 被
tree shake 掉）。

**取得 BASE。** `flutter run` 會印出 `A Dart VM Service on <device> is available
at: http://127.0.0.1:<PORT>/<TOKEN>/`。去掉結尾的 `/` 就是 BASE；token 通常已經
以 `=` 結尾，再補一個會讓每個請求回 403。**token 是本機除錯憑證**：不要貼進
issue、PR、log 或報告，要提只寫埠號與用途。每次 `flutter run` 都換新的；hot
reload / hot restart 不換。isolate id 從 `$BASE/getVM` 的 `result.isolates[].id`
拿（`isolates/<number>`）。Windows 的 PowerShell 裡 `curl` 是別名，用 `curl.exe`。

```bash
BASE="http://127.0.0.1:<PORT>/<TOKEN>="
ISOLATE="isolates/<number>"
```

**HTTP 請求：先開、再產生流量。** profiling 只記開啟之後的請求。app 起來才拿得
到 URI，所以啟動那幾秒的流量量不到。

```bash
curl -s "$BASE/ext.dart.io.httpEnableTimelineLogging?isolateId=$ISOLATE&enabled=true"
# 操作 app 之後
curl -s "$BASE/ext.dart.io.getHttpProfile?isolateId=$ISOLATE"
curl -s "$BASE/ext.dart.io.getHttpProfileRequest?isolateId=$ISOLATE&id=<id>"  # 單筆，含 header 與 body
curl -s "$BASE/ext.dart.io.clearHttpProfile?isolateId=$ISOLATE"
```

FMP 的 Dio 沒有自訂 `httpClientAdapter`，走的是 `dart:io HttpClient`，三個音源與
圖片 CDN 都攔得到。回應裡有簽名過的串流 URL 與 Cookie，同樣不要貼出去。

**讀活物件的欄位。** HTTP 端點的 `evaluate` 不通（`No compilation service
available` —— 編譯服務註冊在 `flutter run` 自己那條連線上）。改用三個 RPC：
`getClassList` 找 class id → `getInstances`（`objectId=classes/<n>`）拿活實例 →
`getObject` 讀 `fields[]`（`decl.name`、`value.valueAsString`）。`Duration`
欄位要再 `getObject` 一層，讀它的 `_duration`（微秒）。

**Isar。** 除了 `isolateId`，參數全部包在一個 `args` JSON 字串裡（`isar_community`
的 `isar_connect.dart` 只讀 `parameters['args']`，直接掛在 URL 上會回
`type 'Null' is not a subtype of type 'String'`）。回傳是雙層包裝：
`{"result": {"result": ...}}`。

```bash
ARGS='{"instance":"fmp_database","collection":"Track","limit":1}'
curl -s -G "$BASE/ext.isar.executeQuery" --data-urlencode "isolateId=$ISOLATE" --data-urlencode "args=$ARGS"
ARGS='{"instance":"fmp_database","collection":"Settings","id":0,"path":"minimizeToTrayOnClose","value":true}'
curl -s -G "$BASE/ext.isar.editProperty" --data-urlencode "isolateId=$ISOLATE" --data-urlencode "args=$ARGS"
```

其餘端點：`listInstances`、`getSchema`、`exportJson`、`importJson`。三個地雷：

- **`editProperty` 的路徑用 `.` 分段**，清單索引寫成數字段。`sourceSettings[1].streamPriority`
  這種寫法寫不進去；實測可行的是把整個 `sourceSettings` 清單當 `value` 覆寫。
  （`sourceSettings.1.streamPriority` 照 `isar_connect.dart` 的實作應該可行，未實測。）
- **`Settings.youtubeStreamPriority` 是 `@Deprecated` 的 v1 欄位**，改它沒有效果；
  生效的是 `sourceSettings` 裡各音源的那一筆。
- **寫入會和 app 自己的寫入者搶。** 例如 `QueueManager` 每 10 秒
  （`AppConstants.positionSaveInterval`）把記憶體裡的 `PlayQueue` 整份存回去，改完
  讀回來看到新值不代表留得住。改完立刻結束進程，或改走 app 自己的 UI。

查詢與匯出會帶出搜尋詞、播放紀錄、本機路徑與帳號資料：只查需要的 collection 與
欄位，匯出檔用完就刪，不要附進報告。

其他 RPC（記憶體、timeline、widget tree dump）是上游的通用 API，見
[Dart VM Service Protocol](https://github.com/dart-lang/sdk/blob/main/runtime/vm/service/service.md)。

## 更多文件

- [文件地圖](README.md)
- [建置指南](building.md)
- [建置與發布指南](build-and-release.md)
- [Agent 規則](../AGENTS.md)
