# 研究：Dart 能力宣告慣用法、可播放來源比對、歌詞來源抽象、契約測試

> 對應 `.trellis/tasks/09-27-design-source-plugins` 研究第 3–6 點。
> 查證方式：官方文件（WebFetch）與 `curl`／`gh api` 直讀原始碼（一手
> 來源）。查不到的一律寫「查不到」，推論一律標「推測」。查證時間
> 2026-09-27。與 `peer-plugin-interfaces.md` 引用同一批專案，LICENSE
> 已在該文件列出，此處不重複。

---

## 第 3 點：Dart／Flutter 生態系宣告「可選能力」的慣用法

FMP 需要的能力清單包含：搜尋、串流解析、歌單匯入、登入、收藏同步、
遠端歌單編輯、排行／探索、電台／直播、推薦／Mix、歌詞、下載——十種
左右，且不是每個音源都全部支援。以下是三種真實存在的做法。

### 3.1 一個大介面 + 全部可選方法（MusicFree 風格，Dart 對照）

Dart 沒有「全部方法可選」的介面語法（TS 的 `method?: Fn` 在 Dart 裡要
嘛用 `Fn?` 型別欄位，要嘛全用 `mixin` 預設實作）。若照抄 MusicFree
的形狀，Dart 版大概是一個大 abstract class，非必要方法給
`UnimplementedError` 的預設實作，能力靠 `is` 或執行期呼叫時
`try/catch UnimplementedError` 判斷——**這個做法在 Dart 生態系找不到
真實先例**（查不到任何知名 Flutter 套件採此形狀），推測是因為 Dart的
靜態型別檢查讓「呼叫了不支援的方法才在執行期爆炸」的代價比 TS/JS
更不划算：TS 的可選方法呼叫端至少會被 `method?.()` 強制寫可選鏈，
Dart 沒有對應的介面層級強制。**不建議 FMP 採用**。

### 3.2 能力列舉 + 一個核心介面 + 可選擴充介面，用 `is` 檢查
（AetherTune 風格，`peer-plugin-interfaces.md` 1.5 已詳列程式碼）

- 核心介面只放「每個來源都一定要有」的最小方法集合
  （`id`、`name`、`capabilities`、`search()` 等）。
- 每個可選能力對應**一個獨立的小介面**（`MusicSourceSearchPagingProvider`
  等），實作者需要該能力就額外 `implements` 那個介面。
- 執行期用 `provider is XxxProvider` 判斷這個實例是否真的提供了某個
  可選能力的方法簽章。
- **關鍵優點**：`capabilities` 集合是宣告（給 UI／設定頁用的「這個
  來源支援什麼」清單），`is` 檢查是型別系統保證（呼叫端在拿到
  `provider as XxxProvider` 後，編譯期就能保證方法存在，不會呼叫到不
  存在的方法）——兩者是分開但可交叉驗證的兩層，AetherTune 的
  `validateMusicSourceProviderContract`（見第 6 點）正是拿這兩層互相
  核對，抓「宣告了某能力但沒 implements 對應介面」這種不一致。

### 3.3 聯邦式 Flutter 外掛（`PlatformInterface`）——宣告的是「平台」不是「能力」

官方文件：
<https://docs.flutter.dev/packages-and-plugins/developing-packages>
（WebFetch 一手來源，Flutter 官方頁）。

三層角色：app-facing 套件（開發者直接 import 的 API）／platform
interface 套件（定義抽象 API 的 base class）／platform 實作套件
（各平台各自實作）。核心機制：

- `PlatformInterface` 基底類別的 `verifyToken()`：**強制實作方用
  `extends`，禁止 `implements`**（防止實作方繞過基底類別未來新增的
  方法而不出現編譯錯誤——這其實是一種「向前相容」保護，跟本任務要
  解決的「能力宣告」問題方向不同）。
- 每個平台實作透過靜態 `instance` getter/setter 註冊自己；純 Dart
  實作用 `registerWith()` 靜態方法。
- pubspec.yaml 的 `platforms` map 用 `implements`／`pluginClass`／
  `dartPluginClass`／`default_package` 宣告「這個套件替哪個平台提供
  哪個介面的哪個實作」。

**這個模式解決的是「同一份 API，不同平台各自實作，且不見得每個
API 呼叫都由套件強制檢查平台支援」的問題**，官方文件只講到「宣告
支援的平台」層級，沒有更細的「這個平台支援哪些子能力」機制——換句
話說，federated plugin 本身沒有比 3.2 更細的能力宣告顆粒度，
對「一個音源支援搜尋但不支援登入」這種同平台內的部分能力沒有直接
幫助，但它示範的「一個抽象契約套件，被多個實作各自依附」結構，
與 FMP 想要的「音源目錄」結構是同一個精神：**平台實作套件對應到 FMP
的「一個音源一個目錄」，platform interface 套件對應到 FMP 要建的
「音源契約」介面本身**。

### 3.4 動態、依當下狀態變化的能力宣告（`audio_service` 的 `MediaControl`）

`audio_service/lib/audio_service.dart`
<https://github.com/ryanheise/audio_service/blob/master/audio_service/lib/audio_service.dart>
（第 140 行 `class PlaybackState`）：

```dart
/// The list of currently enabled controls which should be shown in the media
/// notification.
final List<MediaControl> controls;   // 第 168 行

/// The set of system actions currently enabled. ...
final Set<MediaAction> systemActions;  // 第 196 行
```

`MediaControl`（第 835 行）本身是一組**靜態常數實例**
（`MediaControl.stop`／`.pause`／`.play`／`.rewind`／`.skipToNext`／
`.skipToPrevious`／`.fastForward`，各帶 `androidIcon`／`label`／
`MediaAction action`），另有 `.custom()` 建構子接受
`CustomMediaAction? customAction` 做自訂動作。

這與 AetherTune 的 `Set<MusicSourceCapability>` 本質不同：
`PlaybackState.controls`／`systemActions` 是**每次播放狀態更新都可能
變動**的「現在這一刻允許哪些操作」（例如正在緩衝時可能拿掉快轉），
是**動態、依情境變化**的能力宣告；AetherTune 的能力集合是**靜態、依
音源本身**、跟播放狀態無關的能力宣告。

### 3.5 建議：FMP 採 3.2（AetherTune 風格）為主幹，3.4 的思路用在播放層

- **音源層**（本任務範圍）：採 AetherTune 風格——一個
  `SourceCapability` enum（列出全部十種能力）＋一個核心
  `MusicSourcePlugin`／`Source` 介面（放搜尋等每個音源都有的最小
  集合）＋每個可選能力一個獨立小介面，執行期用 `is` 檢查。這個形狀
  同時滿足擁有者「UI 依宣告能力自動出現入口」（讀 `capabilities`
  集合）與「服務層無音源分支」（呼叫端用 `is` 拿到有型別保證的可選
  介面，不用 `switch (sourceId)`）兩個要求。
- **能力顆粒度**：不要學 Spotube 的 4 種粗顆粒（會逼著把「搜尋」跟
  「串流解析」這種明顯該分開的能力擠在一起），也不要學 MusicFree
  的「有實作就算」（Dart 有更好的型別系統可用，沒必要退化成執行期
  觀察）；抓 AetherTune 的 19 種量級，依 FMP 需求清單（搜尋、串流
  解析、匯入、登入、收藏同步、遠端歌單編輯、排行／探索、電台／
  直播、推薦／Mix、歌詞、下載，共 11 類，部分再拆子項如「收藏讀取」
  vs「收藏寫入」）逐一列舉即可，不需要更抽象的通用機制。
- **播放層（超出本任務範圍，供交接）**：`audio_service` 的
  `MediaControl`／`systemActions` 動態宣告模式是既有播放核心
  （`AudioController`，見 `AGENTS.md` 邊界章節）已經在用的機制
  （`audio_service` 已是 FMP 的既有依賴），不需要因為本任務而改動；
  音源層的靜態能力宣告與播放層的動態控制宣告是兩層不同的關注點，
  不應該合併成同一個模型。

---

## 第 4 點：metadata-only 來源比對可播放來源

### 4.1 Spotube 的演算法（`peer-plugin-interfaces.md` 1.1 已列出介面，
此處聚焦比對邏輯本身）

檔案：`lib/services/sourced_track/sourced_track.dart`
<https://github.com/team-spotube/spotube/blob/master/lib/services/sourced_track/sourced_track.dart>

流程：

1. `SourcedTrack.fetchFromTrack()`：先查 drift 的 `sourceMatchTable`
   有沒有這首 Spotify 曲目對這個音源外掛的快取比對結果，有就直接用
   快取結果去解析串流（`audioSource.streams(cachedMatch)`），**不重新
   搜尋、不重新評分**。
2. 沒快取才呼叫 `fetchSiblings()` → 外掛的 `matches(track)`（見
   `MetadataPluginAudioSourceEndpoint`）取得候選清單。
3. 評分只在**非純英文標題**時才跑（`ServiceUtils.onlyContainsEnglish`
   判斷），純英文標題直接信任外掛回傳的搜尋排序，不額外評分——這是
   一個實用但也可能引入偏差的捷徑（推測：可能是因為英文搜尋引擎/
   YouTube 搜尋排序本身對英文查詢已經夠準，不需要二次加權）。
4. 評分公式 `rankResults()`——**純字串比對／正則，完全不看時長**：
   - 候選標題含藝人名 +1、候選藝人清單含該藝人（小寫完全相等）+1
     （對每個 Spotify 藝人各算一次，可疊加）；
   - 候選標題含曲名 +3；
   - 候選標題命中「官方MV／官方音檔／官方歌詞影片／視覺化」正則
     +1，且該正則命中同時標題又含曲名時再 **+2**（疊加獎勵「官方
     頻道的正確曲目」這個最常見的正確答案形狀）；
   - 依分數由高到低排序，取第一名寫入快取。
5. 使用者可以手動 `swapWithSibling()` 選其他候選，這個動作會**刪除
   舊快取列、寫入新列（`InsertMode.replace`）**，下次直接沿用使用者
   選的結果——即人工修正是「覆蓋快取」而非另開一張表，往後同一首歌
   都不會再自動重新評分。

**關鍵設計取捨**：Spotube 完全不用時長作比對訊號，只信任「標題／
藝人字串相似度 + 官方標記」；比對結果快取後即凍結，除非使用者手動
換源。

### 4.2 FMP 舊版比對問題（`docs/audit/sources.md` §5，已讀取確認）

FMP 舊版其實**有**時長比對，且複雜度遠高於 Spotube，但正是這個複雜度
帶來了問題（`docs/audit/sources.md:391-467`）：

- **雙重實作、行為不一致**：歌單匯入的自動比對
  （`playlist_import_service.dart`）與歌詞匹配
  （`lyrics_auto_match_service.dart`）是兩套完全獨立的評分函式
  （`_calculateRelevanceScore` vs. `_selectBestMatch`），權重、門檻、
  相似度演算法（N-gram/Jaccard vs. Levenshtein）都不同，同一個「這
  是不是同一首歌」的問題在 FMP 裡有兩個不同答案的來源。
- **自動比對與手動重搜不一致**：歌單匯入的自動比對只搜 YouTube＋
  Bilibili（`docs/audit/sources.md:403` 註解承認網易雲被排除），但
  使用者手動重搜 `searchForTrack` 卻搜「全部已註冊音源」且**只依
  播放量排序、完全不打分**（`:414`, `:1163-1179`）——同一個 UI 動作
  的「自動」與「手動」路徑用不同的音源集合、不同的排序邏輯，使用者
  完全無法預期兩者為何給出不同結果。
- **文件與程式碼不一致**：歌詞比對的類別註解宣稱「只有一個候選
  結果符合時長條件時才自動匹配」，但實際程式碼在多筆候選時一樣會
  跑 `_selectBestMatch` 選一筆（`:467`）——即文件描述的「保守」行為
  與程式碼實際的「總是自動選一個」行為不符。
- **來源優先序寫死在比對邏輯裡**：歌詞比對用「命中就停」
  （`:461`，依 `lyricsSourcePriority` 逐源查，第一個有結果的就用），
  沒有跨來源比較所有候選再挑最好的，等於「最先查到的來源」比
  「品質最好的來源」優先權更高。

### 4.3 建議設計：統一比對流程 + 明確區分兩種音源角色

依擁有者要求，音源要分「可播放來源」「metadata-only／匯入專用來源
（必須比對到可播放來源）」「歌詞來源」三種角色，且要有**統一**的
比對流程。建議：

1. **用能力宣告表達角色，不用另一套型別階層**：一個來源可能同時
   宣告 `metadataSearch`（能查到「有這首歌」但不一定能播）與
   `streamResolution`（能解出播放網址）——**沒有 `streamResolution`
   能力的來源，就是 metadata-only／匯入專用來源**，不需要額外的
   `MetadataOnlySource` 標記型別；这直接對應 AetherTune 把
   `streamResolution` 與 `directPlayback` 分開列舉的做法（見
   `peer-plugin-interfaces.md` 1.6 的表格結論）。
2. **比對邏輯只寫一份，供匯入與歌詞共用比對評分核心**：把
   「候選清單 → 加權評分 → 門檻過濾 → 排序取前 N」抽成一個共用函式，
   参數化輸入（標題、藝人、時長、優先旗標如「官方」）與權重，匯入
   流程和歌詞比對都呼叫同一份，避免舊版兩套邏輯各自演化、行為
   分岔的問題重演。是否要完全比照 Spotube 拿掉時長訊號，還是保留
   舊版的時長過濾但修掉「兩套不同門檻」的不一致，**是需要擁有者
   決定的產品行為**（見文末待決策清單），本研究只指出「兩套邏輯」
   本身是舊版問題根源，不是「有沒有用時長」。
3. **自動比對與手動重搜必須走同一份邏輯與同一個來源集合**：舊版
   「自動只搜兩源、手動搜全部且不評分」的不一致要在新設計裡消除——
   手動重搜應該是同一個比對函式、允許使用者事後從候選清單挑其他
   選項（近似 Spotube 的 `swapWithSibling`），而不是另一套排序規則。
4. **比對結果需要可覆寫且覆寫後不再自動重算**：採 Spotube 的快取
   +手動覆蓋模式（覆蓋後寫回同一個持久化欄位，往後直接採用，不
   重新評分）——這與 ADR 0010 的 drift/`TrackKey` 資料層可以自然
   對應（比對結果表用 `TrackKey` 或原始平台 id 做鍵，覆蓋即
   upsert）。

---

## 第 5 點：歌詞來源作為插件類別

### 5.1 三個腳本插件專案的實際做法（`peer-plugin-interfaces.md` 已詳列
程式碼位置，此處聚焦「歌詞是不是一等能力」與「有沒有評分」）

| 專案 | 歌詞是否為插件系統的一部分 | 有無自動評分／比對 |
|---|---|---|
| Spotube | 否，完全獨立、寫死呼叫 `lrclib.net` | 無需比對（單一硬編碼來源，直接用當前曲目的 artist/track/album/duration 查） |
| MusicFree | 是，但只是 `search()` 的一種 `SupportMediaType` | 無，使用者手動建立「聯合 key」關聯 |
| LX Music | 是，`lyric` 是 3 個動作之一 | 無，文件未描述任何評分機制 |

**誠實結論：本研究涵蓋的所有同類專案，沒有一個對歌詞做自動評分式
比對**——這點在啟動研究前不確定，現在可以確定地寫下來。FMP 舊版
（`docs/audit/sources.md` §5.2）反而是**唯一**做了自動評分歌詞比對的
（Levenshtein 標題 ×0.4、藝人 ×0.3、時長 ×0.2、有同步歌詞 ×0.1，
門檻 0.6），但如第 4.2 節所述，這套邏輯本身有文件與程式碼不一致、
「命中即停」而非「比較所有來源」的問題。

### 5.2 建議：歌詞來源用同一個能力框架宣告，但比對邏輯與音軌比對共用核心

1. **歌詞來源同樣是「能力宣告」的一種**：一個音源可能只提供
   `lyrics`（純文字）或同時提供 `lyrics` + `syncedLyrics`（含時間軸），
   對齊 AetherTune 把兩者分開列舉的作法；一個「歌詞專用」來源
   （不提供播放、不提供 metadataSearch）在能力集合上就是「只有
   `lyrics`／`syncedLyrics`，沒有 `streamResolution`／
   `metadataSearch`」的音源，不需要獨立型別階層。
2. **比對核心複用第 4.3 點的共用評分函式**：歌詞來源的候選（多首
   同名/ 同名異曲）用同一套「標題/藝人相似度 + 時長 + 加分項」框架
   評分，而不是像舊版一樣另開一份 `_selectBestMatch`。是否要保留
   舊版「有同步歌詞加分」這個訊號、要不要恢復「跨來源比較所有候選
   而非命中即停」——這些是行為變更，需要擁有者確認（見待決策清單），
   本研究只指出「兩套獨立評分邏輯」是要避免的結構問題。
3. **沒有同類產品的自動評分先例可抄，FMP 等於是在四個同類專案裡
   做得最細的那個**——這是把舊版的評分邏輯**修對**（消除不一致），
   而不是抄一個更成熟的外部模型；因為外部真的沒有更成熟的模型可抄。

---

## 第 6 點：契約測試（Contract Testing）

### 6.1 AetherTune 的結構化契約驗證器（最接近的真實先例）

`apps/mobile/lib/src/domain/music_source_provider_sdk.dart`
<https://github.com/Yunushan/aethertune/blob/main/apps/mobile/lib/src/domain/music_source_provider_sdk.dart>

```dart
final class MusicSourceProviderContractReport {
  const MusicSourceProviderContractReport(this.issues);
  final List<MusicSourceProviderContractIssue> issues;
  bool get isCompliant => issues.isEmpty;
}

MusicSourceProviderContractReport validateMusicSourceProviderContract(
  MusicSourceProvider provider,
) {
  // 檢查 id 格式（RegExp）、name/description/capabilities 非空、
  // 網域格式與去重、disclosure 與 capabilities 是否互相對應
  // （例如宣告了 authentication 能力卻沒有對應揭露），並交叉核對
  // 宣告的能力與實際 implements 的擴充介面是否一致：
  if (provider.capabilities.contains(MusicSourceCapability.searchSuggestions) &&
      provider is! MusicSourceSearchSuggestionProvider) { /* 記一筆 issue */ }
  ...
}
```

這是**結構化／宣告一致性**驗證：檢查的是「宣告的能力」與「實際
implements 的介面」「隱私揭露欄位」彼此對不對得上，**不是**拿真實
或錄製的 HTTP 回應去跑這個 provider、斷言它解析出正確結果——也就是
說，即使一個音源的 `search()` 實作邏輯完全是錯的（例如永遠回傳空
清單），只要它宣告的能力跟它 implements 的介面一致，這個驗證器一樣
會回報「合規」。

### 6.2 `shared_preferences_platform_interface` 的結構化測試（次要先例）

`packages/shared_preferences/shared_preferences_platform_interface/test/shared_preferences_platform_interface_test.dart`
（`flutter/packages` monorepo）：只驗證「用 `implements` 而非
`extends` 去實作這個 platform interface 會噴錯」，同樣是**結構化**
（型別系統層級）而非行為層級的契約測試。

### 6.3 誠實陳述：Dart 生態系沒有強力的「行為式、fixture 驅動」契約
測試先例

本研究透過 `gh search code`／repo 瀏覽，在 Spotube、MusicFree、
LX Music、Listen1、AetherTune、以及 Flutter 官方 federated plugin
生態系裡，**找不到**任何「用同一組錄製好的 fixture／夾具，自動跑過
每一個插件實作，斷言輸出符合某個共同斷言集」的 CI 測試套件。
四個「必查」同類專案沒有一個做自動化的逐插件測試（插件多半是外部
社群倉庫，主 repo 沒有義務或機制去跑它們）；AetherTune 與
`shared_preferences_platform_interface` 提供的都只是**結構化**驗證。

**這點不必視為壞消息**：FMP 的 ADR 0011–0013 已經明確要求（且用詞
就是「契約測試」）三種行為式契約，且已經指定好每種契約要斷言什麼：

- ADR 0011：「遮蔽測試：每個音源一組假憑證與假簽名 URL，斷言經 log
  檔、記憶體歷史、診斷包、網路紀錄後都不再出現原值」；
- ADR 0012：「契約測試：每個音源的媒體請求經媒體 client 發出後，
  請求上不含任何 Cookie／Authorization」；
- ADR 0013：「契約測試：每個音源以錄下的錯誤回應 fixture，斷言
  對應到的 `AppError` 類別」。

這三條全部是「**同一組測試邏輯，套用在每個音源各自提供的 fixture
上**」的形狀——技術上就是「一個共用的 test helper 函式（或
`group`/`test` 產生器），接受音源 id ＋ fixture 路徑為參數，被每個
音源的測試檔各自呼叫一次」，Dart `package:test` 原生就能表達這種
「參數化測試套件」（用一個函式包住 `group()`/`test()`，在每個音源的
測試檔裡呼叫該函式並傳入自己的 fixture），不需要额外框架。

### 6.4 建議：把 ADR 既有的三種契約測試模式，擴充成本任務的「音源能力
契約」測試骨架，並補一層 AetherTune 風格的結構化檢查

1. **結構化層**（抄 AetherTune 的精神，不抄程式碼）：一個
   `validateSourceContract(Source source)` 之類的函式，在測試環境
   （或啟動時 debug 模式）跑過所有已註冊音源，斷言「宣告的
   `capabilities` 與實際 `implements` 的擴充介面一致」——這一層可以
   直接寫成一個 `test/support/*_static_rule_test.dart`（依
   `AGENTS.md` 既有的 static-rule 慣例），不需要新框架。
2. **行為層**（延伸 ADR 0011–0013 已經定義的三種契約，外加本任務
   新增的「搜尋／比對」契約）：每個音源目錄下放自己的 fixture
   （錄製的 API 回應／錯誤回應／假憑證），共用測試 helper 驗證：
   - 錯誤對應表（ADR 0013）；
   - 憑證不外洩到媒體請求（ADR 0012）；
   - 已知敏感值經遮蔽（ADR 0011）；
   - （本任務新增）宣告了 `metadataSearch` 但沒有
     `streamResolution` 的來源，比對流程能正確把它標記為
     「需要比對到可播放來源」而非直接嘗試播放。
3. **不引入新的測試框架或第三方契約測試套件**——生態系裡沒有更成熟
   的現成方案可用（見 6.3），FMP 自己已經在 ADR 裡定義好要斷言什麼，
   缺的只是「共用 test helper + 每個音源提供 fixture」這個組裝方式，
   這是本任務設計階段要生產的東西，不是能從外部抄來的。

---

## 待補查項（誠實列出）

- LX Music `inited` 事件的能力宣告是否在執行期被「檢查」過（例如
  UI 是否會因為某個自訂源沒宣告 `lyric` 動作而隱藏歌詞按鈕），還是
  純粹信任腳本自己不要呼叫不支援的動作：官方文件頁沒有說明到這個
  細節，查不到。
- AetherTune 的 `validateMusicSourceProviderContract` 完整方法體
  （本研究只讀到約前 200 行，含 `searchSuggestions`／
  `favoriteMutation` 等幾個 `is!` 檢查分支）是否涵蓋全部 19 種能力
  各自的介面交叉檢查：未讀完全文，不確定是否有遺漏分支，需要在
  設計階段若要參考此模式時重新完整核對一次原始碼。
- FMP 新設計的比對評分是否要保留舊版的時長訊號、要不要恢復「跨
  來源比較所有候選」而非「命中即停」：這是行為變更，本研究不代為
  決定，列入下方最終報告的待決策清單。
