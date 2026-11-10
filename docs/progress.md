# 進度

工作單位是票（`.scratch/<里程碑>/issues/NN-slug.md`），狀態在票的 `Status:` 行。這裡只記各里程碑的閱讀指引、session 紀錄、偏差與決定。

本檔只留進行中的里程碑。封存由里程碑的驗收票做，同一個 commit：它的 session 紀錄與偏差整段移到 `docs/archive/<里程碑>.md`，逐列比對沒有遺失；里程碑表的備註換成那個檔的連結。封存後再加一列 session 紀錄，票欄標下一個里程碑（例如 `M1 準備`），「下一步」寫它的開工指令，這一列留在本檔。

## 里程碑與閱讀指引

| 里程碑 | 票目錄 | 拆票前讀 | 備註 |
| --- | --- | --- | --- |
| M0 | `.scratch/m0/issues/` | `.scratch/m0/spec.md`，再讀票列出的章節 | 已拆 12 張票，票序在 spec |
| D | 無 | brief §2.3、§11、§17、事實 K10；`docs/design/DESIGN.md`、`PRODUCT.md`；舊版截圖（`docs/audit/screenshots/`） | 和 M0 並行，M1 開工前完成；設計系統已出稿，外殼採 A |

## Session 紀錄

| 日期 | 票 | 結果 | 下一步 |
| --- | --- | --- | --- |
| 2026-11-06 | 框架 | 放棄 Trellis 與上一輪的 `app/`、ADR 0008–0037（封存在 tag `archive/trellis-rewrite-20261106`）；照 QIM 建 `AGENTS.md`、brief 與 plan 骨架、本檔、`docs/agents/` | 新 session 下 `/grill-with-docs 填 FMP 新版的 docs/design-brief.md` |
| 2026-11-06 | 訪談 | brief 第一版範圍定稿；plan 里程碑 M0–M5 與 D；`GLOSSARY.md`；ADR 0038；`docs/research/` 研究檔 2 份 | 新 session 下 `/to-tickets docs/plan.md 拆 M0 的票` |
| 2026-11-06 | M0 拆票 | plan §5.1 細化成 `.scratch/m0/spec.md`，拆成 12 張票（01–11 實作與實驗、12 驗收與封存），plan §5.1 縮成連結 | 新 session 下 `/implement .scratch/m0/issues/01-app-skeleton-and-quick-gate.md` |
| 2026-11-08 | D 方向 | 設計稿方向定案：以舊版為底、玻璃只用在控制層、App 外殼出 A／B 兩版；查證 Flutter Liquid Glass 現況（事實 K10）；brief §2.3、§11、§17、plan §5.2 已更新 | 新 session 下 `/implement .scratch/m0/issues/01-app-skeleton-and-quick-gate.md`（D 設計稿可並行開工） |
| 2026-11-08 | D 設計系統與外殼 | 設計世界選定「卡帶 J-card」；`docs/design/` 出設計系統、外殼 A、外殼 B（手機與桌面、深淺色），頁面由 `docs/design/src/build.py` 產生；finish review 判 ship；`DESIGN.md` 記錄 token 與規則 | 擁有者選 A（見下一列） |
| 2026-11-08 | D 外殼與佇列 | 外殼選 A，寫回 brief §11；佇列拿掉 A／B 面字樣，隨機時的佇列顯示分兩種（brief §6）；私人網頁已重新發佈 | 新 session 下 `/impeccable 照 docs/design/DESIGN.md 與外殼 A 做 D 設計稿的其餘頁面：全螢幕播放頁（含歌詞）、搜尋與結果、音樂庫`；或並行做 M0：`/implement .scratch/m0/issues/01-app-skeleton-and-quick-gate.md` |
| 2026-11-08 | D 播放頁 | `docs/design/player.html`：手機封面／歌詞、桌面封面＋歌詞或佇列兩欄，深淺色；背景跟封面取色；桌面歌詞／佇列切換在頂列；DESIGN.md 已補播放頁一節。未送獨立審查 | 新 session 下 `/impeccable 照 docs/design/DESIGN.md 與外殼 A 做 D 設計稿的其餘頁面：搜尋與結果、音樂庫`；或並行做 M0：`/implement .scratch/m0/issues/01-app-skeleton-and-quick-gate.md` |
| 2026-11-09 | D 搜尋與音樂庫 | `docs/design/search.html`（搜尋紀錄、歌單中＋線上結果、B 站分 P、多選、載入、單一音源失敗、離線、零結果、桌面右鍵選單）與 `library.html`（封面網格、匯入歌單刷新狀態、動作選單、排序、匯入、空狀態），深淺色；DESIGN.md 補兩節；finish review 判 fix，已改完，未再送審 | 新 session 下 `/impeccable 照 docs/design/DESIGN.md 與外殼 A 做 D 設計稿的其餘頁面：歌單詳情（本地、匯入）、加入歌單對話框`；或並行做 M0：`/implement .scratch/m0/issues/01-app-skeleton-and-quick-gate.md` |
| 2026-11-10 | D 歌單詳情與加入歌單 | `docs/design/playlist.html`（本地：播放中與 B 站多 P、列的「更多」、多選、空歌單；匯入：平常、刷新中、刷新失敗、你的收藏夾的遠端移除入口與確認、遠端移除失敗、別人的歌單沒有移除；桌面本地右鍵選單、匯入鍵盤焦點與選單、桌面確認）與 `add-to-playlist.html`（單首、多選混音源、取消勾選遠端歌單、遠端寫入失敗、就地新建、沒有歌單也沒登入；桌面單首與多選），深淺色；新 token `on-error` 與危險按鈕；外殼 A 的歌單詳情改用同一個頭部；DESIGN.md 補兩節；finish review 判 fix，六項改完再送審判 ship | 等使用者：看稿確認「加入遠端歌單併進加入歌單對話框」（見〈偏差與決定〉）。確認後新 session 下 `/impeccable 照 docs/design/DESIGN.md 與外殼 A 做 D 設計稿的其餘頁面：帳號與登入、插件管理、設定、匯入舊版備份`；或並行做 M0：`/implement .scratch/m0/issues/01-app-skeleton-and-quick-gate.md` |

## 偏差與決定

- 2026-11-06 框架：新版從零重做，不沿用上一輪的 `app/` 與 ADR 0008–0037；未合併的 macOS 登入 WebView 在 tag `archive/macos-webview-20261106`。舊版照舊凍結。
- 2026-11-06 框架：流程照 QIM（文件是唯一的記憶、一個 session 一張票）；指令檔沿用 `AGENTS.md` 檔名；名詞表用 `GLOSSARY.md`。
- 2026-11-06 框架：合併照 Berth，票分支本機合併成 `merge: ticket NN …` 再 push main，不開 PR；`protect-main` 拿掉 required status check，保留禁止刪除與禁止 force push。
- 2026-11-06 訪談：推翻上一輪的 VIP 不存（ADR 0029）、App 不內建插件（ADR 0014）、另一個插件 repo（ADR 0030）、讀舊版 Isar（ADR 0010）。
- 2026-11-06 清理：刪 `docs/audit/questions.md`（決定已被 brief 取代）；`dependabot.yml` 的 GitHub Actions 版本更新暫停，M5 重新開啟；遠端只留 main，`probe/youtubejs` 存成 tag `archive/youtubejs-probe-20261106`。舊版的 `docs/` 文件、ADR 0001–0007、`ci.yml`、`release.yml` 留到取代舊版時刪。
- 2026-11-06 M0 拆票：pre-commit 只在 commit 改到 `app/` 時跑 `--quick`，舊版緊急修正不受新版閘門影響；`winpc` 以 SSH 同步工作樹，不 push 分支。擁有者確認，已寫進 plan §4。
- 2026-11-08 D 方向：以舊版為底只限頁面地圖、資訊架構、功能入口，設計系統重定；材質加入玻璃，只用在控制層、四平台統一；App 外殼出 A（舊版結構）／B（Apple Music 式）兩版，看稿後選。擁有者確認，已寫進 brief §2.3、§11、§17、事實 K10 與 plan §5.2。
- 2026-11-08 D 設計系統：擁有者選定設計世界「卡帶 J-card」（密排曲目列、等寬時長欄、書脊式迷你播放器與摺線），強調色保留自選、玻璃與底色不帶強調色（擁有者確認）。設計 session 自行決定、待擁有者看稿確認：舊版 9 個預設色劃掉黃色（淺色底對比不足）；需登入的曲目整列變淡。細節在 `docs/design/DESIGN.md`。
- 2026-11-08 D 外殼：擁有者選外殼 A（舊版結構換玻璃），B 的稿留作參考；帳號與插件管理從設定進入。已寫進 brief §2.3、§11、§17、plan §5.2、`docs/design/DESIGN.md`。
- 2026-11-08 D 佇列：拿掉「A 面／B 面」字樣；隨機時的佇列顯示分兩種（預設依播放順序、設定可改回舊版的維持原順序），兩種都要讓「下一首播放」與拖動排序和實際播放一致。擁有者確認，已寫進 brief §6 與 `docs/design/DESIGN.md`。「維持原順序」下拖動排序的細節留到 M1 定。
- 2026-11-08 D 佇列（續）：推翻同日「設定可改回舊版的維持原順序」，只做新版：佇列畫面永遠是播放順序。播放模式從四選一改成隨機、循環兩個獨立控制（可同時開，照 Spotify、Apple Music 與舊版）；隨機＋列表循環播完重新打亂、只開隨機播完就停；開關隨機不改原順序；佇列頁照舊版可跳回正在播的那首。擁有者確認，已寫進 brief §6 與 `docs/design/DESIGN.md`。
- 2026-11-08 D 佇列標頭：擁有者看稿後拿掉「正在播放 · 第 N 首」列，改成標頭一顆「跳到正在播放」圖示鈕；隨機與循環改回分段樣式的兩顆圖示鈕（各自獨立）。已改 brief §6 最後一條與 `docs/design/DESIGN.md`。
- 2026-11-08 D 佇列標頭（續）：擁有者要求回退圖示鈕組，隨機與循環回到帶文字的兩顆切換鈕；拿掉定位鈕，改成點「佇列」標題捲回正在播放。已改 brief §6 與 `docs/design/DESIGN.md`。
- 2026-11-08 D 播放頁：桌面的「歌詞／佇列」切換放在頂列右側的兩顆圖示鈕（照 Apple Music、Spotify 桌面版）；手機維持底部玻璃膠囊。擁有者確認。
- 2026-11-09 D 音樂庫：擁有者選歌單用封面網格（照舊版），不用設計 session 建議的密排列表；這是 J-card 密排規則唯一的例外，已寫進 `docs/design/DESIGN.md`。搜尋結果照舊版混排加音源篩選，排序鈕移到「線上結果」段標題（修審計 §6.1 第 4 點）。
- 2026-11-10 D 加入歌單：設計 session 把舊版另一個入口「加入遠端歌單」（每個音源各跳一個對話框）併進加入歌單對話框，本地歌單下依選取曲目的音源各列一段自己帳號的遠端歌單，對話框本身當作建立與加入的確認（brief §7），取消勾選遠端歌單照 §7 再確認一次。待擁有者看稿確認；不同意就改回兩個入口。細節在 `docs/design/DESIGN.md`〈加入歌單對話框〉。
