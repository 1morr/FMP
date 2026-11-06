# M0 骨架與 tracer bullet

細化自 plan §5.1（2026-11-06）。決定的來源是 brief；本檔與 brief 衝突時以 brief 為準，要推翻先問擁有者。

## 目標

repo 骨架與閘門就位，四個平台都建得起來，並跑通同一條 tracer bullet：在佔位畫面搜尋 B 站、點一首、播放出聲。M0 結束時，plan §1.3 的依賴規則與 ADR 0038 的三道閘門（依賴規則測試、插件契約測試、打包產物檢查）都已生效，四項實驗的結論已寫進 brief。

## 範圍

### 做

- `app/` 四平台骨架（dev 身分 `com.personal.fmp.dev`，brief §12）、佔位首頁、slang 三語、Riverpod 全域關閉自動重試（事實 K5）。
- `tool/check.dart`：`--quick`（format、analyze、單元測試）與完整版（四平台建置與 `integration_test`、插件打包產物是否最新），`.githooks/pre-commit` 跑 `--quick`。
- 依賴規則測試（plan §1.3）：掃 import 與音源識別碼，測試檔內做雙向變異驗證。
- 零聯網防線（plan §3）：`HttpOverrides` 讓真實連線直接報錯；`live` tag 預設跳過。
- log 門面與遮蔽、錯誤分類骨架（brief §13）。
- drift 空庫、schema 快照與升級測試的流程。
- 插件宿主：JS 引擎（實驗定）、manifest（插件能力、網域）、宿主網路 API（dio、只放行 manifest 宣告的網域）、插件錯誤代碼轉錯誤分類；TypeScript 加 esbuild 打包，產物提交。
- 插件契約測試：fixture 重播；錄製工具寫檔前經過遮蔽函式。
- bilibili 插件的兩個插件能力：搜尋、解析串流。
- 音訊後端介面與兩個實作：just_audio（Android、iOS、macOS）、media_kit（Windows），brief §6。
- 主要流程（搜尋到播放）的 `integration_test`，四平台都跑。
- 四項實驗（`scripts/experiments/`）：JS 引擎、macOS 的 Now Playing 接法、`winpc` 截圖傳回、`flutter_inappwebview` 6.1.5 四平台建置。
- 舊版的 `ci.yml` 與根目錄的 analyze、format、test 不受 `app/` 影響。

### 不做

- 照設計稿的畫面（D 未定稿，M1 做）；M0 的畫面一律佔位。
- youtube、netease、lrclib 插件（M1、M4）。
- 佇列、臨時播放、播放模式、背景播放、系統媒體控制（M1）。M0 只要求前景播放一首。
- 登入、憑證、存取等級（M2）。M0 只用匿名請求。
- 插件更新、設定頁、匯出診斷（M5）。
- 新版的 GitHub Actions（plan §4：`app-release.yml` 在 M5）。
- 正式身分 `com.personal.fmp` 與 flavor（發佈的里程碑再建）。

## 共同規則

- **四平台**：每張實作票都在 macOS、iOS 模擬器、Android 模擬器、Windows（`winpc`）做完並驗收，方式照 brief §4，以讀回的畫面為準。實驗票照票上寫的平台。
- **閘門**：票 01 合併前跑票 01 寫的驗證；票 02 合併後，每張票合併前跑 `dart run tool/check.dart` 完整版。pre-commit 只在 commit 改到 `app/` 時跑 `--quick`，舊版的緊急修正不受新版閘門影響。
- **依賴**：加依賴時查 pub.dev 當前 stable，版本寫進 plan §1.4。
- **模組介面**：插件宿主與音訊後端的介面用 `mattpocock-skills:codebase-design` 設計；只照現有需求，不預留 M1 之後的入口。
- **命名**：用 `GLOSSARY.md` 的詞；缺的詞照〈擁有者確認〉補。
- **事實**：用到 brief 標【待重驗】的事實時當場重驗，驗過拿掉標記、對不上就改寫並附來源。封存 tag `archive/trellis-rewrite-20261106` 只是線索。
- **實驗**：用 `mattpocock-skills:prototype`，程式放 `scripts/experiments/<主題>/`。查到的事實寫進 brief §18；屬於決定的結論（JS 引擎、macOS Now Playing 接法）先把草稿給擁有者確認，才改 brief §6、§17 與 plan §1.4、§2、§6。
- **聯網**：測試零聯網。實跑與 `live` 測試用匿名請求，每次只搜一次、播一首（事實 F2 的匿名風控）。fixture 照 `AGENTS.md`〈公開 repo〉遮蔽。
- **`winpc`**：透過 SSH 同步工作樹與取回產物，不靠 push 分支（push 是遠端寫入）。已知怪癖在 plan §2。
- **舊版**：不改舊版的行為；為了不受 `app/` 影響而改根目錄設定（例如 analyzer 排除 `app/`）時，在票的 Comments 記下改了什麼。

## 驗收

- [ ] 四個平台各自搜尋並播放出一首 B 站曲目（佔位畫面）。
- [ ] `dart run tool/check.dart` 完整版綠燈，含主要流程的 `integration_test` 四平台通過。
- [ ] 依賴規則測試、插件契約測試、打包產物檢查都在閘門裡，ADR 0038〈如何確認〉的三條都有對應。
- [ ] 四項實驗的結論已寫進 brief，plan §6 P2 已移到 §1.4、§2。
- [ ] 舊版的 `ci.yml` 在 main 上綠燈。
- [ ] 擁有者在四個平台各親手試一次。

## 票序

票在 `issues/`。被擋的票等擋它的票 `done` 才開工；可開工的票依編號先做。

| 票 | 標題 | 被誰擋 |
| --- | --- | --- |
| 01 | app 骨架與快速閘門 | 無 |
| 02 | 完整閘門 | 01 |
| 03 | 實驗：JS 引擎 | 無 |
| 04 | 實驗：flutter_inappwebview 6.1.5 四平台建置 | 無 |
| 05 | 實驗：macOS 的 Now Playing 接法 | 無 |
| 06 | log 門面、遮蔽與錯誤分類 | 02 |
| 07 | drift 空庫與 schema 快照 | 02 |
| 08 | 插件宿主跑通 bilibili 搜尋 | 02、03、06 |
| 09 | 插件契約測試與 fixture 錄製 | 08 |
| 10 | bilibili 解析串流 | 09 |
| 11 | 播放出聲 | 10 |

03、05 的結論要擁有者確認才寫入 brief，做到那一步會停下等。
