# 網易雲插件（M3 PR 2）

> 父任務：`.trellis/tasks/10-08-m3-sources-accounts-devtools`。技術設計在父任務 `design.md` §5.2；§16 第 14 條（`X-Real-IP`）。執行清單在父任務 `implement.md`「2.」。本檔只列做什麼與驗收。分支疊在 PR 1（`feat/m3-youtube-plugin`）上：錄 fixture 要用 PR 1 加的 IP 替換。

## 目標

App 能以 `--fmp-dev-plugin` 裝上網易雲插件，匿名搜尋並播放；只拿得到試聽片段的歌回報 `previewOnly`，交給 M2 的「跳過試聽片段」設定處理。

## 做什麼

1. FMP：`officialPluginIds` 加 `netease`，`fmp_source_id_literal` 的案例跟著加。
2. fmp-plugins `netease/`（舊 `lib/data/sources/netease_source.dart` 為規格，JS 重寫）：
   - manifest 1.0.0，能力 `search`、`resolveStream`；`allowedHosts` 只列實際用到的網域。
   - `search`：`/api/cloudsearch/pc`（舊版收了 `order` 卻沒用，不帶過來）。
   - `resolveStream`：eapi `/song/enhance/player/url/v1`；AES-128-ECB 以插件內附的純 JS（MIT 相容）實作，MD5 用宿主 `crypto`；音質 `high`→`exhigh`、`medium`/`low`→`standard`（不送 `lossless`）；回應的 `freeTrialInfo` 不為空時 `previewOnly: true`。
   - 錯誤對應表：`code: -460`（風控）→ `VerificationRequired`；`code: 404` 或空 `url` → `Unavailable`（原因依 `fee`）；查詢類 POST 標 `idempotent: true`。
   - `X-Real-IP`：先以匿名真實連線各測一次「不帶」與「帶」的搜尋與取流；不帶也能用就不送，需要時只在必要的請求送；結果寫進插件 README。
   - `checks.json`（`search`、`resolveStream`）與命令列錄的 fixture（匿名）；錯誤對應表以插件 repo 的 Node 測試守（PR 1 的做法，契約每能力只有一條案例）。
   - README：能力、錯誤對應、`X-Real-IP` 實測結果、打包方式（若有）。

## 不做

- 登入、「憑證無效」判定（PR 8、10）；VIP 音質；歌詞（M7）。

## 驗收

- [ ] 網易的契約（`FMP_PLUGIN_DIR=../fmp-plugins/netease`）全綠：DTO、媒體請求不帶憑證、fixture 掃描（含 IP）；`npm test` 的錯誤對應；`fmp_source_id_literal` 的案例。
- [ ] 驗證清單全綠（`app/AGENTS.md` § 驗證）。
- [ ] 實機（主對話做；**真實，匿名**）：兩平台搜尋一次、播一首。
- 試聽的實機驗收延到登入之後（PR 8 起；M3a 驗收）：匿名時 VIP 歌回 `code` -110、沒有網址也沒有 `freeTrialInfo`（帶了 `X-Real-IP` 也一樣），拿不到試聽片段。`previewOnly` 的判斷以 `test/resolve.test.js` 的手寫回應守。
