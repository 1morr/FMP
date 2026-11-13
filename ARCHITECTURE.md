# FMP 新版架構

> 模組地圖與跨模組的規則。里程碑的順序與範圍在 `docs/roadmap.md`；怎麼建置、在各平台實跑、閘門怎麼跑在 `docs/development.md`；決定的來源是 `docs/design-brief.md`，兩者衝突時以 brief 為準。
>
> 寫法：只寫現況，改了就改寫原句，舊說法留給 git；票號不寫進來。只寫打開程式碼看不出來的：模組的分工、誰能依賴誰、跨模組的資料與契約。操作步驟寫在 `docs/development.md`，選型與取捨的理由寫 ADR。節用標題引用、不編號。全檔上限 15,000 字元，`scripts/check_docs.py` 強制。

## 工程慣例

- 一張票一個分支，在本機 `git merge --no-ff` 合回 main 再 push，不開 PR（`AGENTS.md`）。
- 每張票在四個平台做完並驗收，合併前跑 `dart run tool/check.dart`（完整版）。
- 新字串在同一張票補齊 zh-TW、zh-CN、en 三種語言。
- 依賴的版本開工時查 pub.dev 決定，寫進〈主要依賴〉，不憑記憶寫。
- 命名用 `GLOSSARY.md` 的詞。


## 執行形態

單一 Flutter App。插件在 fjs 的 JS 引擎（QuickJS-NG，brief 事實 K11）裡執行：每個插件一個引擎，JS 跑在 fjs 全行程共用的 2 條原生執行緒，Dart 端在主 isolate 以 async 呼叫，不另開 isolate。每個引擎設記憶體上限；每次呼叫都有逾時，逾時就 `close()` 這個引擎再重建、重新載入插件（2 個插件同時卡住會讓其他插件停擺到逾時為止）。宿主 API 都經 fjs 的單一 bridge 進 Dart，在一處分派與檢查；建立引擎時只開白名單內的內建模組。音訊在原生播放器裡（ExoPlayer、AVPlayer、libmpv）。

## 目錄結構

新版放在 `app/`，根目錄舊版不動；建好後補進 `AGENTS.md`〈目錄〉。

```text
app/
  lib/
    app/        組裝、路由、主題、i18n
    domain/     曲目、歌單、存取等級等模型（純 Dart）
    core/       log、遮蔽、錯誤分類
    plugins/    JS 引擎、宿主 API、宿主網路（只放行 manifest 宣告的網域）、插件管理
    playback/   佇列、臨時播放、音訊後端介面與兩個實作（實作在 `playback/backends/`）
    library/    本地歌單、匯入歌單、刷新、遠端寫入
    accounts/   帳號、登入、會員狀態
    lyrics/     歌詞匹配與顯示用的資料
    data/       drift 資料庫
    platform/   平台能力
    ui/<頁面>/  畫面與 view model
  plugins/      官方插件原始碼：bilibili、youtube、netease、lrclib（TypeScript）
                每個插件一個目錄：manifest.json、src/index.ts、dist/plugin.js
                （esbuild 產物，提交）、fixtures/（契約測試的案例與 keep.json，§3）；
                共用的 host.d.ts、build.mjs、package.json
  test/
  integration_test/
  tool/check.dart
```

## 依賴規則

- `ui` 只能依賴功能模組與 `domain`，不能直接碰 `data`、`plugins` 的內部，也不能碰平台套件。
- 只有 `data/` 能 import drift，只有 `platform/` 能 import 平台套件，例外是 `playback/backends/`（音訊後端的兩個實作）可 import `just_audio`、`media_kit`；平台層以外不得用 `Platform.isXxx`（依平台選音訊後端也在平台層做）。
- 音源專屬的邏輯只能在 `app/plugins/` 裡；Dart 端不得出現音源識別碼的字面值分支（ADR 0038）。
- 由一支掃 import 與識別碼的 Dart 測試強制，並在測試檔內做雙向變異驗證；不自寫 analyzer lint 套件（flutter/flutter#187999）。已接上。
- 模組的實際介面在 M0 用 codebase-design skill 細化。

## 主要依賴

版本寫的是加入時 `pubspec.lock` 解出的版本；還沒加的由加入的那張票寫。

| 用途 | 依賴 | 理由 |
| --- | --- | --- |
| 狀態管理 | flutter_riverpod 3.5.0（手寫 provider） | 舊版與上一輪都用；自動重試全域關閉（brief 事實 K5） |
| 路由 | go_router | flutter.dev 官方維護，舊版用過；外殼用 `ShellRoute` |
| 資料庫與設定 | drift 2.35.4（帶進 sqlite3 3.9.1）；drift_dev 2.35.3、build_runner 2.17.1（dev） | schema 快照與升級測試（〈測試策略〉）；設定也存這裡，不用 shared_preferences。sqlite3 3.x 用 build hook 自帶 SQLite，不用 `sqlite3_flutter_libs`（brief 事實 K14）；沒用 `drift_flutter`，檔案位置由 `platform/` 給 |
| HTTP | dio 5.11.1 | 插件請求都經宿主網路層（`plugins/src/host_network.dart`：網域白名單、log 與遮蔽；依音源限流與重試還沒做，〈風險與回寫點〉），只有 `plugins/` 能 import（依賴規則）；測試換掉 `HttpClientAdapter` |
| 音訊 | just_audio 0.10.6（Android、iOS、macOS；帶進 audio_session 0.2.4）、media_kit 1.2.6 與 media_kit_libs_windows_audio 1.0.9（Windows） | brief §6、事實 K1；介面在 `playback/audio_backend.dart`，兩個實作在 `playback/backends/`，依平台挑在 `platform/audio_backend.dart`。just_audio 關掉 Dart 端的 header proxy，由原生播放器帶 header（事實 K25）；media_kit 的錯誤只在 mpv 的 log（事實 K26） |
| 媒體控制 | audio_service（Android、iOS、macOS）、audio_session、smtc_windows | macOS 已實測（brief 事實 M10、K18）；Windows 不在 audio_service 的平台內（事實 R4） |
| 登入 WebView | flutter_inappwebview 6.1.5 | 唯一涵蓋四平台的穩定版（事實 R1） |
| 憑證 | flutter_secure_storage 11.2.0 | brief §8 |
| 圖片 | cached_network_image | |
| 玻璃 | liquid_glass_easy 5.2.0（實測的版本；加入的票照當時的 stable 重查） | 四平台都做得到折射級，擁有者看過對照圖並試過 prototype 後選定（brief §11、事實 K21）；standard 用它的 lite glass，minimal 自己畫；只在玻璃元件裡用。不讀系統的「降低透明度」，只看設定的「玻璃效果」（brief §11） |
| i18n | slang 4.19.2、slang_flutter 4.19.0；flutter_localizations（SDK） | 舊版用過 |
| log | logger 2.8.0 | `AdvancedFileOutput` 依大小輪替、限制保留份數；只在 `core/log/` 用（brief 事實 K12） |
| App 目錄 | path_provider 2.1.6 | flutter.dev 官方；log 目錄與資料庫檔案由 `platform/` 經它取得（brief 事實 K13） |
| JS 引擎 | fjs 3.3.2 | 四平台同一個 QuickJS-NG，能中斷、能設記憶體上限、支援 async（brief 事實 K11） |
| 插件建置 | TypeScript 7.0.2、esbuild 0.28.2（`app/plugins/package.json`，需 Node） | ADR 0038；版本由 `package-lock.json` 鎖住，閘門以 `npm ci` 安裝後重建比對 |
| lint（dev） | flutter_lints 6.0.0 | `flutter create` 的預設；`app/analysis_options.yaml` 另開幾條 |
| 依賴規則測試（dev） | analyzer 14.7.0 | 以 AST 判斷 import 與分支，不靠字串比對；只在測試裡用，不做 lint 套件（〈依賴規則〉） |
| 主機上跑 fjs（dev） | flutter_rust_bridge 2.13.0 | fjs 釘死的版本；`test/support/fjs.dart` 用它的 `ExternalLibrary` 載入 macOS 動態庫（brief 事實 K19） |
| 換掉平台實作（dev） | path_provider_platform_interface 2.1.3、plugin_platform_interface 2.1.8 | path_provider 官方的測試做法：換一個假的 `PathProviderPlatform` |
| 平台上的測試（dev） | integration_test（SDK） | Flutter 官方的 `flutter test integration_test/…`；完整閘門在四平台跑（`docs/development.md`） |

## 測試策略

- 預設零聯網：`live` tag 預設跳過；`HttpOverrides` 讓任何真實連線直接報錯（`app/test/support/no_network.dart`）。`test/` 由 `flutter_test_config.dart` 裝；`integration_test/` 不吃那個設定，每個檔在 `main()` 裡呼叫 `installNoNetworkGuard()`，`test/architecture/integration_test_guard_test.dart` 守著。
- `domain`、`playback`、`library` 用單元測試，音訊後端用 fake。
- 每個插件套同一套契約測試，用 fixture 重播；錄製工具寫檔前經過遮蔽函式。已接上（工具在 `test/support/plugin_fixtures.dart`）：
  - `test/plugins/plugin_contract_test.dart` 掃 `app/plugins/` 底下每個插件，對 manifest 宣告的每個插件能力，重播 `plugins/<id>/fixtures/<插件能力>/*.json` 的每個案例（格式照 VCR 的 cassette：`input` 加一串請求與回應，見 `PluginFixture`）。案例可以加選填的 `expect`，要求插件能力的結果多滿足一條期望，例如 resolveStream 的 `{"expiresAt": true}`（串流要有有效期）；各插件能力認得哪些期望寫在 `checkContract`，認不得的會紅。錄製、重播與 live 冒煙測試都套用，錄製時照原樣寫回。請求以方法加遮蔽後的網址比對，每筆只用一次；沒有 fixture 的請求、沒用到的錄製請求、宣告了插件能力卻沒有案例或沒有 `keep.json` 的欄位清單都會紅。各插件能力的契約在 `checkContract` 的 switch，新增插件能力時編譯不過，提醒補契約。同一個測試檢查每份 fixture 都是遮蔽函式的不動點（沒有 cookie、token、簽名網址的值），回應內文只有 `keep.json` 列的欄位。
  - 錄製（打真實音源，一次一個案例）：先建 `plugins/<id>/fixtures/<插件能力>/<案例>.json`，至少寫 `{"input": {…}}`，再在 `app/` 跑 `FMP_RECORD=<id>/<插件能力>/<案例> flutter test --run-skipped --tags live test/plugins/record_plugin_fixture_test.dart`。網址、header、內文經遮蔽函式，回應內文再裁成插件會讀的欄位（清單在插件的 `fixtures/keep.json`，例如 `{"search": ["code", "data.result.title"]}`，路徑照 MongoDB projection：`.` 分隔、陣列套到每個元素；沒列的插件能力不錄），才寫檔；回應 header 只留 `content-type`、`location`；契約不過（例如被限流）就不寫。契約測試也檢查提交的 fixture 只有 `keep.json` 列的欄位。插件改成讀新的欄位時，先加進 `keep.json` 再重錄。提交前看一次 diff，確認沒有個人資訊（`AGENTS.md`〈公開 repo〉）。
  - 聯網冒煙測試：`flutter test --run-skipped --tags live test/plugins/plugin_live_test.dart`（加 `--plain-name <id>` 只跑一個插件），每個插件的每個插件能力用第一個案例的 `input` 打一次真實音源，檢查同一套契約。
- 插件宿主與插件的單元測試在 Mac 上跑真的 fjs 引擎（`loadFjsForTests()`，brief 事實 K19），網路換成 `test/support/fake_http.dart`。widget 測試裡會呼叫引擎的動作要在 `tester.runAsync` 裡發起，等結果時交替真實等待與 `pump`（事實 K19）。
- 每個里程碑的主要流程有一條 `integration_test`，四個平台都跑。M0 的是 `integration_test/search_and_play_test.dart`（搜尋、點一首、播放、暫停、繼續），跑的是這個平台真的音訊後端。原生播放器的連線不經 Dart 的 `HttpOverrides`，所以它的串流網址指向 `test/support/local_audio_server.dart`：只聽 127.0.0.1 的假 CDN，回產生出來的無聲 WAV、支援 Range，少了 Referer 或瀏覽器的 User-Agent 就回 403（brief 事實 F22），播得起來就證明 header 帶到了。
- drift 的 schema：每個版本的快照在 `app/drift_schemas/app_database/`，升級測試在 `app/test/drift/app_database/`。改 schema 時：改表、`schemaVersion` 加一、在 `app/` 跑 `dart run drift_dev make-migrations`（產生新快照、`generated/` 的各版本資料庫、`lib/data/database.steps.dart`），在 `AppDatabase.migration` 用 `stepByStep` 寫這一步；`migration_test.dart` 自動涵蓋每一對版本，改到既有欄位時照檔頭加資料完整性測試。閘門的 `schema snapshot (drift)` 比對目前的 schema 與最新快照，`migration_test.dart` 比對 `schemaVersion` 與最新快照的版本，忘了任一步都會紅。`*.g.dart` 不進 git，閘門的 `codegen (build_runner)` 先產生。
- 聯網冒煙測試：每個音源每種插件能力最多一條，手動執行，不擋合併；用真實帳號時照 `AGENTS.md` 的最少操作規則。

## 待決

定了方向、細節未定的事。每條寫明卡在哪、怎麼定；定案後移到對應的章節，這裡刪掉。

- **P1 取代舊版的方式**：同 brief §17。卡在新版功能還沒齊全，到「取代舊版」的里程碑由擁有者決定。
- **P3 插件能力清單**：設計稿用到的能力（搜尋排序、排行榜、評論、點讚、複製連結、在瀏覽器開啟、遠端歌單分建立與收藏等）還沒列成清單，見 `docs/design/audit-2026-11-11.md` §3 第 6 項。宿主 API 在 v2.0.0 凍結，所以清單在 M1 拆票時定，寫進 M1 spec；M0 只做了搜尋與解析串流。定案後寫進 brief §5.3 與 ADR。

## 風險與回寫點

- YouTube 的 client 會變（事實 F8）：解析串流準備候選序列；壞了就更新插件。
- B 站風控（事實 F2）：網路層依音源限流；登入後要確實帶憑證。
- `flutter_inappwebview` 的穩定版停在 2024-10（事實 R1、K8）：登入票先實測四個平台。建置與開頁 已驗過（`scripts/experiments/inappwebview/`，要加的設定見事實 A4、W8、M3、K17）。Apple 端沒有 SwiftPM，Flutter 已警告將來會變成錯誤（事實 K17）：升級 Flutter 前先用 `scripts/experiments/inappwebview/` 建一次 iOS、macOS。
- Windows 的 libmpv 是舊快照（事實 W3）：遇到 Windows 獨有的播放失敗先懷疑它。
- iOS 的中斷與 Now Playing（事實 I2、I5）：模擬器驗不到的部分記在票的 Comments。
- audio_service 更新慢（事實 I5、K18：#1139 的 iOS 修正 2026-07 合併，至今沒發佈）：macOS 端壞了就改用自己的 platform channel 接 `MPNowPlayingInfoCenter`、`MPRemoteCommandCenter`（已實測可行，原型在 `scripts/experiments/macos-now-playing/probe_channel/`）。
- `liquid_glass_easy` 主版本換得快（4.0.0 在 2026-08、5.0.0 在 2026-10）：升級前用 `scripts/experiments/glass/` 在四平台重量。套件壞了或停更，退回自己用 `BackdropFilter` + `ImageFilter.shader` 做折射（原型是同目錄 probe 的 `own-refract`，四平台實測可行；GLES 上不要翻 Y 軸，事實 K24）。手機的捲動幀時間 M0 量不到（iOS 只有模擬器、Android 模擬器沒有 GPU 加速），里程碑量效能時若掉幀，玻璃元件改成捲動時降到 standard（brief §11），降級時的模糊半徑不能比折射級大（事實 K21）。手機的幀時間要在實機或有 GPU 加速的模擬器量（例如舊版基準用的 `winpc` 模擬器）。
- 實作時發現與 brief 不符：停下來問擁有者，改 brief 並在 progress.md〈偏差與決定〉記一行。
