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
