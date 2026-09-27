# 研究：同類音樂播放器的音源／插件介面，與編譯期 vs. 執行期插件的取捨

> 對應 `.trellis/tasks/09-27-design-source-plugins` 研究第 1、2 點。
> 查證方式：`gh api` / `gh search code` / `curl` 直接讀各 repo 的原始碼與
> LICENSE 檔（一手來源）；LX Music 的部分官方文件頁面用 WebFetch（標明
> 為文件頁摘要，非原始碼）。查不到的一律寫「查不到」，推論一律標
> 「推測」。查證時間 2026-09-27。
>
> 依擁有者要求：只看設計、不抄程式碼；本文引用的程式碼片段僅為指出介面
> 形狀與關鍵字，並非要移植進 FMP。

---

## 第 1 點：同類專案的音源／插件介面

### 1.1 Spotube — 執行期腳本插件（hetu_script）

- Repo：`team-spotube/spotube`（`KRTirtho/spotube`已重新導向到此）。
  License：`LICENSE` 開頭為 BSD 系列四條款文字（**BSD-4-Clause**）。
  <https://github.com/team-spotube/spotube/blob/master/LICENSE>

**插件本體是腳本，不是 Dart 類別。** Spotube 內嵌 `hetu_script`（一個
Dart 風格的腳本語言直譯器），插件是打包成 `.hetu`／`.json` 的腳本＋
manifest，安裝後由直譯器在執行期載入、執行。Dart 側只有一層「端點」
薄封裝，透過 `Hetu.fetch("metadataPlugin")` 取出腳本物件，再用
`HTInstance.invoke("methodName", ...)` 以字串方法名反射呼叫腳本裡的
函式。例如音源解析端點：

`lib/services/metadata/endpoints/audio_source.dart`
<https://github.com/team-spotube/spotube/blob/master/lib/services/metadata/endpoints/audio_source.dart>

```dart
class MetadataPluginAudioSourceEndpoint {
  final Hetu hetu;
  Future<List<SpotubeAudioSourceMatchObject>> matches(...) async {
    final raw = await hetuMetadataAudioSource
        .invoke("matches", positionalArgs: [track.toJson()]) as List;
    ...
  }
}
```

其餘端點（`album.dart`、`artist.dart`、`auth.dart`、`browse.dart`、
`core.dart`、`playlist.dart`、`search.dart`、`track.dart`、`user.dart`，
均在 `lib/services/metadata/endpoints/`）同一種寫法：Dart 端只定義
「這個能力長什麼型別」，實際邏輯永遠在腳本裡，Dart 側完全不檢查腳本
是否真的實作了該方法（呼叫不存在的方法會在執行期才失敗）。

**能力宣告**：manifest（`PluginConfiguration`，
`lib/models/metadata/plugin.dart`
<https://github.com/team-spotube/spotube/blob/master/lib/models/metadata/plugin.dart>）：

```dart
enum PluginApis { webview, localstorage, timezone }

enum PluginAbilities {
  authentication,
  scrobbling,
  metadata,
  @JsonValue('audio-source')
  audioSource,
}

factory PluginConfiguration({
  required String name, required String description, required String version,
  required String author, required String entryPoint, required String pluginApiVersion,
  @Default([]) List<PluginApis> apis,
  @Default([]) List<PluginAbilities> abilities,
  String? repository,
}) = _PluginConfiguration;
```

只有 4 種能力旗標（認證、Scrobble、metadata、音源），metadata 插件的
`type` 固定是 `"metadata"`——即 Spotube 的插件系統設計目標窄：只解決
「幫 Spotify 的曲目找到可播放來源」與「metadata 補充」，不是通用音源
系統。**歌詞不是插件能力**：`lib/provider/lyrics/synced.dart`
<https://github.com/team-spotube/spotube/blob/master/lib/provider/lyrics/synced.dart>
的 `SyncedLyricsNotifier.getLRCLibLyrics()` 直接用 Dio 打死 `lrclib.net`
的公開 API（`Uri(host: "lrclib.net", path: "/api/get", ...)`），完全在
插件系統之外，是寫死的單一內建功能。

**iOS 分發**：官方 `README.md`
<https://github.com/team-spotube/spotube/blob/master/README.md>
的下載表格 iOS 欄位原文：「\*iPA file only. Requires sideloading with
AltStore or similar tools.」——即官方**未上架 App Store**，只提供側載
IPA。是否直接因為 Guideline 2.5.2（見 2.7）而不上架，Spotube 維護者
沒有公開這樣講，此因果關係標「推測」。

### 1.2 MusicFree — 執行期腳本插件（一個大介面 + 執行期 duck typing）

- Repo：`maotoumao/MusicFree`。License：`LICENSE`
  <https://github.com/maotoumao/MusicFree/blob/master/LICENSE> 開頭為
  「GNU AFFERO GENERAL PUBLIC LICENSE Version 3」（**AGPL-3.0**）。

插件是 JS/TS 檔（打包成 `.js`），執行期用 `eval` 類機制載入成物件。
介面定義在
`src/types/plugin.d.ts`
<https://github.com/maotoumao/MusicFree/blob/master/src/types/plugin.d.ts>：

一個 `IPlugin.IPluginDefine`，14 個方法**全部可選**（`search?`、
`getMediaSource?`、`getMusicInfo?`、`getLyric?`、`getAlbumInfo?`、
`getMusicSheetInfo?`、`getArtistWorks?`、`importMusicSheet?`、
`importMusicItem?`、`getTopLists?`、`getTopListDetail?`、
`getRecommendSheetTags?`、`getRecommendSheetsByTag?`、
`getMusicComments?`），外加 `platform`／`supportedSearchType` 等描述性
欄位——**沒有獨立的「能力」列舉**，能力等於「這個方法有沒有被實作」。

執行期怎麼知道一個插件支援什麼：`src/core/pluginManager/plugin.ts`
<https://github.com/maotoumao/MusicFree/blob/master/src/core/pluginManager/plugin.ts>
的 `class Plugin`：

```ts
public supportedMethods: Set<keyof IPlugin.IPluginInstanceMethods> = new Set();
...
this.supportedMethods = new Set(Object.keys(_instance).filter(
    key => typeof (_instance[key]) === "function",
) as any);
```

即載入腳本物件後，**用 `typeof === "function"` 逐一檢查每個 key**，
把「真的是函式」的 key 收進一個 `Set` 當作這個插件的能力清單。這是
典型的執行期 duck typing：介面本身不強制實作，能力清單是「觀察」出來
的，不是插件「宣告」出來的（雖然實務上兩者通常一致）。

歌詞：`getLyric?` 只是 `IPluginDefine` 裡衆多可選方法之一，且歌詞在
搜尋層被當成 `ICommon.SupportMediaType` 的一種（跟音樂、專輯、歌單同
一個 `search()` 入口，`type` 參數切換），**沒有比對評分**——使用者手動
把歌詞結果與曲目建立「聯合 key」關聯，是人工配對，不是自動匹配。

### 1.3 LX Music — 執行期腳本插件（極窄，3 種動作）

-桌面版 repo：`lyswhut/lx-music-desktop`。License：`LICENSE`
  <https://github.com/lyswhut/lx-music-desktop/blob/master/LICENSE>
  為 **Apache-2.0**。行動版 `lyswhut/lx-music-mobile` 同樣
  Apache-2.0（`gh api repos/lyswhut/lx-music-mobile` 回報
  `license.spdx_id = "Apache-2.0"`）。

自訂源（custom source）是 JS 腳本，檔頭以註解宣告
`@name`／`@description`／`@version`／`@author`／`@homepage`；執行期用
一個 `inited` 事件把該腳本「登記」進主程式，payload 裡列出這個腳本
（可能同時登記多個具名音源）各自支援哪些 `actions`。文件明確列出的
動作只有 3 種：`musicUrl`（解析播放網址）、`lyric`（歌詞）、
`pic`（封面圖）；內建的一般音源甚至只保證 `musicUrl`。
來源：LX Music 官方文件頁
<https://lxmusic.toside.cn/desktop/custom-source>（此為文件頁摘要，
非原始碼一手引用；文件對應的原始碼倉庫 `lyswhut/lx-music-doc` 確切
檔案路徑查不到，未進一步核實）。

即 LX Music 把「能力」壓到最窄的顆粒度（3 個動作），且歌詞是動作之一
但**沒有評分機制**——文件沒有描述任何自動比對邏輯，行為上更接近「這個
音源要嘛回得出歌詞要嘛回不出來」。

### 1.4 Listen1 — 沒有正式介面，命名慣例 + 極簡能力旗標

- Repo：`listen1/listen1_chrome_extension`。License：`LICENSE`
  <https://github.com/listen1/listen1_chrome_extension/blob/master/LICENSE>
  為 **MIT**。

每個音源是 `js/provider/*.js` 裡的一個物件，**沒有任何 TypeScript／
JSDoc 介面宣告**，方法名純粹靠約定（`search`、`get_playlist`、
`lyric`、`bootstrap_track`、`get_user`、`get_login_url`、`logout`、
`get_playlist_filters` 等）。

但確實有一個**輕量中央註冊表**，`js/loweb.js`：

```js
/* global netease xiami qq kugou kuwo bilibili migu taihe localmusic myplaylist */
const PROVIDERS = [
  { name: 'netease', instance: netease, searchable: true,  support_login: true,  id: 'ne' },
  { name: 'xiami',   instance: xiami,   searchable: false, hidden: true, support_login: false, id: 'xm' },
  { name: 'kugou',   instance: kugou,   searchable: true,  support_login: false, id: 'kg' },
  ...
];
function getProviderByName(sourceName) { return (PROVIDERS.find(...) || {}).instance; }
function getAllSearchProviders() { return PROVIDERS.filter((i) => i.searchable).map((i) => i.instance); }
```

即每個條目除了 `name`/`instance` 外，還帶 3 個**布林能力旗標**
（`searchable`、`support_login`、`hidden`）。這些旗標**確實在分派時
被用來過濾**：例如全源搜尋 `MediaService.search('allmusic', ...)`
呼叫 `getAllSearchProviders()`（只挑 `searchable: true` 的音源）；
登入頁用等價的 `getLoginProviders()` 過濾 `support_login: true`。
但除了這 3 個旗標涵蓋的「可搜尋」「可登入」「要不要在清單顯示」之外，
其餘能力（例如 `lyric`、`get_playlist_filters`）完全沒有旗標，呼叫端
（`getLyric()`、`getPlaylistFilters()`）**假設每個註冊的 provider 都有
該方法**，不做任何存在性檢查——找不到就是執行期噴錯。

**結論**：Listen1 是「命名慣例 + 極簡集中式能力旗標」的中間型態，比
MusicFree 的全動態 duck typing 更死板（旗標要手動維護），但比起完整
介面又更鬆散（大多數方法無旗標保護）。

### 1.5 AetherTune — 編譯期 Dart class 註冊（本研究找到的關鍵先例）

- Repo：`Yunushan/aethertune`。License：`LICENSE`
  <https://github.com/Yunushan/aethertune/blob/main/LICENSE>，
  全文為 **BSD Zero Clause License (0BSD)**，
  版權標示「Copyright (C) 2026 AetherTune Contributors」。
  `pubspec.yaml`
  <https://github.com/Yunushan/aethertune/blob/main/apps/mobile/pubspec.yaml>
  確認是真實在維護的 Flutter App（`audio_service`、`just_audio`、
  `media_kit`、`flutter_secure_storage: ^11.2.0` 等依賴），描述為
  「Free and open-source music app with local playback and provider
  plugins.」，且每個音源都有對應 `test/*_test.dart`，不是玩具專案。

這是四個「必查」專案之外，額外找到的第五個案例，**直接對應本任務要找
的「編譯期 Dart 類別註冊」模式**：音源不是腳本、不是動態載入的外部檔，
而是**編譯進 App 本體的 Dart class**，一個介面＋一個能力列舉：

`apps/mobile/lib/src/domain/music_source_provider.dart`
<https://github.com/Yunushan/aethertune/blob/main/apps/mobile/lib/src/domain/music_source_provider.dart>

```dart
enum MusicSourceCapability {
  metadataSearch, searchSuggestions, radioDirectory, streamResolution,
  directPlayback, libraryBrowse, playlists, playlistMutation,
  favoriteMutation, albumFavoriteMutation, artistFavoriteMutation,
  artwork, lyrics, syncedLyrics, offlineCache, downloads,
  subscriptions, recommendations, authentication,
}

/// Implement this contract to add a legal source adapter.
abstract interface class MusicSourceProvider {
  String get id;
  String get name;
  Set<MusicSourceCapability> get capabilities;
  ProviderPrivacyDisclosure get disclosure;
  Future<List<Track>> search(String query);
  Future<Uri?> resolveStream(Track track);
}
```

以及可選擴充能力用**獨立小介面**（不是塞進大介面的可選方法）：

```dart
abstract interface class MusicSourceSearchPagingProvider
    implements MusicSourceProvider {
  Future<MusicSourceSearchPage> searchPage(String query, {String? cursor, int limit = 20});
}
```

公開 SDK 入口是一個獨立的 library barrel 檔
`apps/mobile/lib/aethertune_provider_sdk.dart`
<https://github.com/Yunushan/aethertune/blob/main/apps/mobile/lib/aethertune_provider_sdk.dart>，
匯出 `MusicSourceProvider`、能力列舉、`Track` 等契約型別，並帶版本號
`aethertuneProviderSdkVersion`，也提供一個結構化契約驗證函式
`validateMusicSourceProviderContract`（見本文件第 6 點）。

真實存在超過 15 個具體實作（`internet_archive_provider.dart`、
`jellyfin_provider.dart`、`subsonic_provider.dart`、
`radio_browser_provider.dart`、`lrclib_lyrics_provider.dart`、
`spotify_metadata_provider.dart` 等，倉庫樹狀清單已核實存在對應
`test/*_test.dart`），證明這不是設計草稿，而是可運作、有測試覆蓋的
編譯期插件系統。

`dddevid/musly` 曾在 WebSearch 中出現為次要線索（Subsonic 家族多後端
客戶端），本次研究**未驗證**，不納入結論。

### 1.6 五個專案的能力清單比較

| 專案 | 插件形態 | 能力宣告單位 | 顆粒度 | 歌詞是否為獨立能力 |
|---|---|---|---|---|
| Spotube | hetu_script 腳本 | manifest 的 `abilities: List<PluginAbilities>` | 極粗（4 種：認證／Scrobble／metadata／音源） | 否，硬編碼 LRCLib，不經插件系統 |
| MusicFree | JS/TS 腳本 | 執行期觀察函式是否存在（`supportedMethods: Set`） | 細（14 個可選方法） | 是，但只是 `search()` 的一種媒體類型 |
| LX Music | JS 腳本 | `inited` 事件的 `actions` 陣列 | 極細但選項極少（3 種動作） | 是，`lyric` 是 3 動作之一 |
| Listen1 | 命名慣例物件 | 中央 `PROVIDERS` 表的少數布林旗標 | 部分能力有旗標，多數靠假設 | 有 `lyric` 方法但無旗標保護 |
| AetherTune | 編譯期 Dart class | `Set<MusicSourceCapability>` enum + 可選介面 | 細（19 種能力，含 `lyrics`／`syncedLyrics`） | 是，明確列舉且與可播放能力分離 |

**共通點**：五個專案都用「一個中心點知道有哪些音源／插件」＋「每個
音源／插件用某種方式宣告或暴露自己支援什麼」，沒有例外；差別只在
「能力顆粒度」與「宣告是靜態聲明還是執行期觀察」。**沒有一個專案**
把「metadata-only 來源」「playable 來源」「歌詞來源」統一成同一種
能力物件的三個子集——它們要嘛用完全獨立的系統（Spotube 的歌詞），
要嘛把歌詞併入既有的搜尋/動作機制（MusicFree、LX Music），要嘛用
能力列舉的其中幾項區分（AetherTune 的 `lyrics`／`syncedLyrics` vs.
`streamResolution`／`directPlayback`）。AetherTune 是唯一同時涵蓋
「metadata-only 標記」概念的：它的 `streamResolution` 能力與
`directPlayback` 分開宣告，暗示「能查到資訊但不能直接播放」與
「能直接播放」是兩種不同能力，這點值得 FMP 借鑑（見第二份文件第 4 點）。

---

## 第 2 點：編譯期插件 vs. 執行期腳本插件的取捨

FMP 的情境：Bilibili／YouTube／網易雲三源，音源清單由**擁有者**決定
新增，不是讓一般使用者自己裝任意第三方插件市集。這點會讓天平明顯偏
向編譯期。以下逐項比較，每項都盡量掛上實例證據。

### 2.1 安全性

- **腳本插件**（Spotube／MusicFree／LX Music）：載入的是**外部、
  執行期取得**的程式碼，即使解讀為「腳本」而非原生機器碼，仍然是
  「App 執行期改變自己的行為」。MusicFree 用 AGPL-3.0、插件生態明確
  鼓勵第三方社群貢獻與分享插件檔（`.js` 檔直接分享安裝），代表使用者
  會安裝來路不明的第三方插件——這正是 App 供應鏈風險的來源：插件能
  存取的 API（`fetch`、`localStorage` 等）等於它能做的事，惡意插件
  可以外洩使用者資料或請求任意網域。
- **編譯期插件**（AetherTune）：音源程式碼與 App 一起走 code review、
  一起發版，沒有「執行期安裝未經審查程式碼」這個攻擊面；代價是新增
  音源需要重新發版，使用者不能自己裝插件。
- FMP 現況（`docs/audit/sources.md`）音源就是三個固定、擁有者維護的
  來源，不存在「讓使用者自由裝插件」的需求，編譯期插件的安全模型
  （沒有外部程式碼載入面）直接適用，不需要腳本插件解決的「多方不
  信任程式碼共存」問題。

### 2.2 法律風險

- 三個腳本插件專案（Spotube／MusicFree／LX Music）都採用「App 本體
  乾淨、插件另外分發」的切割：MusicFree 的插件倉庫與主 App 分開，
  Spotube 的插件也是另外安裝的 `.hetu` 檔。這個切割的**動機之一**
  （專案本身沒有明文承認，此處標「推測」）很可能是降低「App 本體
  內建直接繞過版權保護的程式碼」的法律曝險——插件是使用者自行安裝的
  第三方內容，App 本體看起來只是一個「通用播放器框架」。
- 這個切割對 FMP **不適用**：FMP 的三個音源就是 App 的核心賣點，
  是擁有者自己維護、跟 App 一起發版的功能，沒有「甩鍋給使用者自行
  安裝插件」的空間或意圖，法律責任本來就在 App 本體上，編譯期或
  執行期都不改變這個事實。
- 換句話說：法律風險考量在 Spotube／MusicFree 的情境裡是選擇腳本
  插件的理由之一（推測），但**這個理由對 FMP 不成立**，因為 FMP
  沒有意圖把音源包裝成「使用者自選第三方插件」。

### 2.3 效能

- hetu_script／JS 引擎都是**直譯執行**，比原生 Dart AOT 編譯碼慢；
  對 FMP 這種音源呼叫頻率不高（搜尋、解析串流是網路 I/O bound，不是
  CPU bound）的場景，效能差異在實務上可忽略——**兩個方案都不會是
  瓶頸**，但編譯期 Dart 沒有「載入腳本引擎」與「跨語言呼叫（Dart↔腳本
  的 `invoke`／JSON 序列化）」這層開銷與複雜度。

### 2.4 除錯

- Spotube 的 `MetadataPluginAudioSourceEndpoint.matches()` 呼叫失敗時，
  例外從 hetu_script 直譯器丟出，Dart 側只看到一個泛用執行期錯誤，
  對照 ADR 0013 要求的「每個音源在自己目錄內把錯誤轉換成 sealed
  `AppError`」——**腳本插件的錯誤天然缺乏型別**，要做到 ADR 0013 那樣
  精確的錯誤分類，必須先在腳本裡手動序列化錯誤碼再讓 Dart 側解析，
  多一層轉換與失敗可能。
- 編譯期 Dart 插件的例外就是普通 Dart 例外，IDE 斷點、stack trace、
  型別檢查全部原生可用，直接對齊 ADR 0013 的分類需求。

### 2.5 測試

- 腳本插件的「契約測試」要嘛要跑一個腳本直譯器去執行插件（MusicFree／
  Spotube 都沒有看到自動化這樣做的證據——本研究未找到任一專案有
  「用同一組 fixture 自動跑過所有插件」的 CI 流程），要嘔另外寫一層
  mock 直譯器。
- 編譯期 Dart 插件可以直接用 `flutter test` 對每個音源類別跑同一組
  抽象測試（AetherTune 的 `validateMusicSourceProviderContract` 就是
  能在編譯期靜態拿到 class 去驗證的例子），與 ADR 0011–0013 已經
  要求的「契約測試」／「遮蔽測試」風格完全對齊，不需要額外的腳本
  執行環境。

### 2.6 打包／分發

- 腳本插件的賣點是「不用重新發版就能更新音源」——Spotube／MusicFree／
  LX Music 都有插件市集／插件倉庫，讓使用者或社群更新單一音源而不用
  等 App 更新。這對「音源可能因網站改版而失效、需要頻繁修補」的場景
  是真實優勢。
- 但 FMP 是**擁有者自己維護三個音源**，發版頻率由擁有者控制，且
  ADR 0009／0010 已經確立「新專案在 `app/`、Isar→drift 遷移」等會伴隆
  重新發版的既定路徑，音源程式碼的更新沒有跟 App 版本脫鉤的急迫需求。

### 2.7 iOS App Review：Guideline 2.5.2

Apple Developer 官方 App Review Guidelines 2.5.2 原文（已在既有姊妹
研究 `platform-policy-and-peers.md` 中確認並沿用同一段引用）：

> 「Apps should be self-contained in their bundles, and may not read or
> write data outside the designated container area, nor may they
> download, install, or execute code which introduces or changes
> features or functionality of the app, including other apps.
> Educational apps designed to teach, develop, or allow students to
> test executable code may, in limited circumstances, download code
> provided that such code is not used for other purposes.」

這條規則字面上直接針對「執行期下載並執行會改變功能的程式碼」——
**腳本插件系統如果讓使用者從網路上下載新插件檔並在 App 內執行，屬於
這條規則的核心打擊範圍**。

實例佐證：Spotube 官方 `README.md` 的下載表格顯示 iOS 版**沒有上架
App Store**，只提供側載 IPA（見 1.1）。Spotube 團隊沒有公開說明這是
否直接因為 2.5.2（此因果關係標「推測」），但至少可以確認的事實是：
一個具備「執行期載入外部腳本插件」架構的音樂 App，**目前沒有出現在
App Store 上**。MusicFree、LX Music 兩者也都不在官方文件或 README
中聲稱有上架 App Store（`MusicFree`／`LX Music` 官網與 GitHub README
均只提供 Android／桌面／側載下載連結，查不到 App Store 連結）。

編譯期插件（AetherTune）沒有這個問題：音源程式碼在編譯時就固定在
App bundle 內，符合「self-contained」，不涉及執行期下載可執行程式碼。

### 2.8 結論與對 FMP 的建議

**建議 FMP 採編譯期 Dart class 註冊，不做執行期腳本插件系統**：

1. FMP 的音源是擁有者自己維護的固定三源，不存在「讓一般使用者自由
   安裝第三方插件」的產品需求，腳本插件解決的「多方不信任程式碼共存
   ＋不重新發版即可更新」兩個核心痛點對 FMP 都不成立或優先度低。
2. 編譯期方案直接對齊 ADR 0011（統一日誌／遮蔽）、ADR 0012（請求層
   `AuthRequirement` 宣告）、ADR 0013（sealed `AppError`＋契約測試）
   已經確立的「音源在自己目錄內做轉換、用型別系統窮舉」的既定方向——
   這三份 ADR 的機制全部假設音源程式碼在編譯期可被型別系統看見，腳本
   插件會讓這些機制多一層序列化橋接。
3. 未來若 FMP 想上架 iOS App Store，編譯期方案不會撞上 Guideline
   2.5.2；若走側載，這個顧慮就不成立，但編譯期的其餘優點（除錯、
   測試、與既有 ADR 對齊）仍然成立，所以建議不論 iOS 分發策略為何都
   走編譯期。
4. 唯一的取捨代價：新增或修補一個音源必須跟著 App 一起重新發版，
   不能做到「音源失效時不等 App 更新就先修好」。這點擁有者已經在
   ADR 0008（App 重寫、沿用舊身分）與既有專案的開發節奏中，用「擁有
   者自己維護、快速發版」的模式運作，評估為可接受的代價，但**這是
   一個需要擁有者確認的產品決策**（見兩份研究文件共用的「待決策」
   清單）。

---

## 待補查項（誠實列出）

- LX Music 自訂源 `inited` 事件與 `actions` 陣列的**確切原始碼位置**
  （`lyswhut/lx-music-doc` 或桌面版/行動版 repo 內實際處理該事件的
  檔案）查不到；本文引用僅到官方文件頁 `https://lxmusic.toside.cn/desktop/custom-source`
  的內容摘要，未能核對成一手程式碼引用。
- Spotube／MusicFree／LX Music 的 iOS 未上架是否**明確因為**
  Guideline 2.5.2（而非其他條款，例如 5.2.2 第三方內容或版權疑慮）
  ，三個專案都沒有公開聲明因果關係，本文只呈現「有腳本插件系統的
  音樂 App 目前都不在 App Store 上」這個相關性事實，因果推論已標
  「推測」。
- `dddevid/musly` 是否也是編譯期插件模式：本次研究未驗證，不納入
  結論，僅記錄為未查證線索。
- MusicFree／Spotube 是否有任何形式的自動化「插件契約測試」（CI 對
  每個已知插件跑同一組驗證）：透過 `gh search code` 與倉庫瀏覽**未
  找到**任何此類 workflow 或測試檔，判定為「沒有」而非「查不到」，
  因為兩個 repo 的 CI 設定與測試目錄都是公開可查的，且插件本身是
  外部倉庫，主 repo 沒有理由對其跑契約測試。
