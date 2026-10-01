# sandbox 實跑結果（PR 13b，擁有者決定 4）

2026-10-01，私人 repo `1morr/fmp-release-sandbox`（驗完已封存），步驟照 `sandbox-plan.md`。
sandbox 專屬的 commit：刪掉 `ci.yml`、`release.yml`、`dependabot.yml`；`app-release.yml` 加
`push: branches: [main]`；v2.0.0 之後刪掉 `release-as`（正式環境發完 2.0.0 也要做，測試會逼）。
簽名用臨時產生的 PKCS12 金鑰（效期 7 天，只存在 sandbox 的 secrets，本機檔已刪），
憑證 SHA-256 `91d48fa6…7e2ae9`。

## 經過

| run | 觸發 | 結果 |
|---|---|---|
| 36785853896 | 手動 | 只有 release-please 跑，開出發版 PR #1「chore(main): release 2.0.0」；建置以後 skipped |
| 36786003893 | 合併 #1 | tag `v2.0.0` 與草稿建好；Windows 成功；Android 第一次被 runner 關掉，重跑成功；verify 失敗（見問題 2）；publish skipped，v2.0.0 留在草稿 |
| 36791364480 | push（修正＋刪 `release-as`） | 開出 #2「chore(main): release 2.0.1」 |
| 36791437669 | 合併 #2 | 全部成功，v2.0.1 正式發布、成為 latest |
| 36792378008 | 手動 | 沒有新 PR、沒有新 release，建置以後 skipped |

- 發版 PR 都只改 `.release-please-manifest.json`、`app/pubspec.yaml`（`version: 2.0.0`／`2.0.1`，沒有 `+`）、`app/CHANGELOG.md`。
- 2.0.0 的 CHANGELOG 有 27 條，只收 `bootstrap-sha` 之後動到 `app/` 的 commit；log 有 `found configured bootstrapSha 1857fa4b…`。
- 合併 #1 後、建置期間 Releases 頁已有 `v2.0.0` 草稿，latest 仍是替身 v1.11.0；v2.0.1 發布後 latest 換成 v2.0.1。

v2.0.1 那次各 job 時間（Android 與 Windows 平行）：release-please 11s、Build Android APKs 8m46s、
Build Windows 4m14s、Verify 1m03s、Publish 13s，整條約 10 分 20 秒。

## 發佈物核對（v2.0.1，下載後在本機做，沒有安裝或執行）

- 11 個檔，名稱照 ADR 0022 §決定 3：四個 APK、`windows-installer.exe`、`windows.zip`、`checksums.sha256`、四個 `fmp-latest-*`。
- `sha256sum -c` 六個版本化檔全部 OK；四個別名與版本化檔 `cmp` 相同；GitHub 的 asset `digest` 與 checksums 一致。
- APK：`com.personal.fmp`、versionCode `2000001`、versionName `2.0.1`；簽名憑證是臨時金鑰（build-tools 37 的 apksigner）。
- zip 根目錄就是程式目錄：`fmp.exe`、`data/app.so`、`vcruntime140.dll` 都在最上層。
- release 內容是 CHANGELOG 的 2.0.1 段落，不是草稿。
- verify job 內的舊版更新器相容檢查通過。

## 遇到的問題

1. **Android 建置被 runner 關掉（偶發）**：同一個 job 連續建四個 APK，第三個卡 22 分鐘後 runner 收到
   shutdown 訊號（Gradle exit 143）。重跑一次 17 分鐘成功，v2.0.1 那次 8 分 46 秒成功，沒有重現。
   私人 repo 的 runner 是 2 核 7GB，FMP 是公開 repo（4 核 16GB）。沒改；再出現就把 ABI 拆成 matrix。
2. **verify 解析不到 APK 簽名（已修）**：runner 映像的 build-tools 37.0.0 把 `apksigner --print-certs`
   的 `Signer #1 certificate DN:` 改成依方案列出 `V2 Signer: certificate DN:`。在本機另裝 37.0.0 重現，
   `parseSigners` 改成兩種都認、依憑證去重（`fix(app): parse the apksigner 37 certificate output`），
   本機以 sandbox 的產物配 36 與 37 都 `Verified all 11 assets`。
3. **失敗後的補救**：v2.0.0 的 tag 與草稿留著，修正進 main 後由 release-please 發 2.0.1，流程照常。
   `releases/latest` 始終沒有指到缺檔的版本。ADR 0022 的「發版失敗由下一個 patch 補上」因此實測過。
4. **`git push` 沒有觸發 push**：推入完整歷史與第一個觸發 commit 的兩次 push，repo events 裡沒有
   PushEvent、也沒有 run；之後合併 PR 與再推的 commit 都正常觸發。原因沒查明，第一次改用手動觸發
   （FMP 本來就是手動觸發）。
5. **2.0.0 的 CHANGELOG 比較連結是 `v0.1.0...v2.0.0`**：沒有 v0.1.0 這個 tag，連結打不開。只影響
   第一版的標題連結。

## sandbox 證明不了的（留給 M9 或切換前）

- 正式金鑰簽出的 APK、v1.11.0 在 App 內實際升到 2.x（Android、Windows 安裝版與免安裝版）。
- FMP `main` 的必要檢查 `CI Result`：`GITHUB_TOKEN` 開的發版 PR 不會觸發 `ci.yml`，M9 要改 token 或允許略過。
- FMP 的「允許 Actions 建 PR」設定（M9 開自動觸發時一起開）。
- SmartScreen、Mark of the Web、真實安裝。
- 發佈物沒有授權聲明（舊版附 LICENSE、第三方授權，libmpv 是 LGPL），M9 公開發版前補上。
