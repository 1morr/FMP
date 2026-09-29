# 平台層與能力宣告（M1 PR 4）

父任務：`../09-28-m1-skeleton-tracer`（design §2；implement「4.」）。

依據：
- ADR 0009 §決定 1–4：每能力一目錄、不可變的能力宣告、平台判斷只在平台層、不寫空實作；
- ADR 0009 §決定 7：目錄規則，Windows 免安裝版改 `userdata/`；
- ADR 0024 §決定 2：字型 fallback。

## 範圍原則

`PlatformCapabilities` 只放 M1 用到的能力，不預先宣告托盤、快捷鍵、歌詞視窗等欄位；引入該能力的里程碑再加欄位與實作（ADR 0009 §決定 4 的「不寫空實作」）。播放後端與可播格式在 PR 10 加。

## 做什麼

1. **`lib/platform/platform_capabilities.dart`**：不可變的 `PlatformCapabilities`，M1 的欄位：
   - `dataDirectory`：有沒有 App 資料目錄的實作；
   - `singleInstance`：Windows 為真，由原生 runner 實作（PR 2），Dart 端只宣告；
   - `fontFallback`：依語言排序的字型清單，見第 3 點。
   
   欄位型別與命名照 ADR 0009 §決定 2。
2. **平台組裝**：`lib/platform/platform.dart` 在啟動時依平台組出能力宣告與各能力的實作，只有這裡判斷平台。
   - Android 與 Windows 有實作；
   - Linux、macOS、iOS 宣告全部為「沒有」，沒有實作檔。
   - PR 2 的 `appDataDirectoryFor` 併進這個組裝點，`app_data_directory/` 的結構維持「每能力一目錄」。
3. **字型 fallback**（ADR 0024 §決定 2）：`lib/platform/fonts/`：

   | 語言 | Windows | 其他平台 |
   |---|---|---|
   | zh-TW | `Microsoft JhengHei UI`、`Microsoft JhengHei` | `Noto Sans TC` |
   | zh-CN | `Microsoft YaHei UI`、`Microsoft YaHei` | `Noto Sans SC` |
   | en | 繁中清單在前，簡中在後 | 同左 |

   - Android 上 Flutter 怎麼選 CJK 字形：`fontFamilyFallback` 能不能用系統字型名，還是要靠 `Locale`。先查官方文件與 Flutter issue，把結論與來源記在 `research/notes.md`。
   - 如果 Android 上寫 `Noto Sans TC` 沒有效果，就照官方做法，靠 `Locale` 讓引擎選字形，並在 ADR 0024 補一句更正。
   - 主題怎麼套用字型在 PR 12；本 PR 只提供清單與取得方式。
4. **不支援的平台**：`main()` 在 `dataDirectory` 為「沒有」時不啟動資料層，顯示一個「此平台尚未支援」的最小畫面。
   - 字串先寫死繁中，註解說明 slang 在 PR 12 接上後改掉。
   - Linux、macOS、iOS 只要能編譯、能開出這個畫面就好。
5. **測試**：
   - 各平台的能力宣告：以注入的平台值組裝，不讀真實 `Platform`；
   - 三種語言在 Windows 與其他平台的字型清單；
   - 不支援的平台顯示那個畫面（widget test）；
   - PR 2 的資料目錄測試維持通過。
6. **文件**：
   - `app/AGENTS.md` 平台段寫三件事：
     - 能力宣告只含已實作的能力；
     - 新能力連同實作一起加；
     - 平台判斷只在組裝點（`fmp_platform_checks` 守）。
   - `.trellis/spec/app/platform/index.md`（繁中）寫怎麼加一個能力：目錄、介面、各平台實作、宣告欄位、測試。

## 驗收

- [ ] `app/`：
  - format 通過；
  - `dart analyze --fatal-infos`、`flutter analyze` 零問題；
  - `flutter test` 全綠；
  - 哨兵通過。
- [ ] Windows dev 版建置並開啟，畫面與 PR 2 相同（主對話實機）。
- [ ] 平台判斷只出現在 `lib/platform/`（lint 已守）。
