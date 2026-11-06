# 進度

工作單位是票（`.scratch/<里程碑>/issues/NN-slug.md`），狀態在票的 `Status:` 行。這裡只記各里程碑的閱讀指引、session 紀錄、偏差與決定。

本檔只留進行中的里程碑；里程碑驗收後，它的 session 紀錄與偏差整段移到 `docs/archive/<里程碑>.md`，里程碑表的備註換成那個檔的連結。

## 里程碑與閱讀指引

| 里程碑 | 票目錄 | 拆票前讀 | 備註 |
| --- | --- | --- | --- |
| M0 | `.scratch/m0/issues/` | `.scratch/m0/spec.md`，再讀票列出的章節 | 已拆 11 張票，票序在 spec |
| D | 無 | brief §11；舊版截圖（`docs/audit/screenshots/`） | 和 M0 並行，M1 開工前完成 |

## Session 紀錄

| 日期 | 票 | 結果 | 下一步 |
| --- | --- | --- | --- |
| 2026-11-06 | 框架 | 放棄 Trellis 與上一輪的 `app/`、ADR 0008–0037（封存在 tag `archive/trellis-rewrite-20261106`）；照 QIM 建 `AGENTS.md`、brief 與 plan 骨架、本檔、`docs/agents/` | 新 session 下 `/grill-with-docs 填 FMP 新版的 docs/design-brief.md` |
| 2026-11-06 | 訪談 | brief 第一版範圍定稿；plan 里程碑 M0–M5 與 D；`GLOSSARY.md`；ADR 0038；`docs/research/` 研究檔 2 份 | 新 session 下 `/to-tickets docs/plan.md 拆 M0 的票` |
| 2026-11-06 | M0 拆票 | plan §5.1 細化成 `.scratch/m0/spec.md`，拆成 11 張票（01–11），plan §5.1 縮成連結 | 新 session 下 `/implement .scratch/m0/issues/01-app-skeleton-and-quick-gate.md` |

## 偏差與決定

- 2026-11-06 框架：新版從零重做，不沿用上一輪的 `app/` 與 ADR 0008–0037；未合併的 macOS 登入 WebView 在 tag `archive/macos-webview-20261106`。舊版照舊凍結。
- 2026-11-06 框架：流程照 QIM（文件是唯一的記憶、一個 session 一張票）；指令檔沿用 `AGENTS.md` 檔名；名詞表用 `GLOSSARY.md`。
- 2026-11-06 框架：合併照 Berth，票分支本機合併成 `merge: ticket NN …` 再 push main，不開 PR；`protect-main` 拿掉 required status check，保留禁止刪除與禁止 force push。
- 2026-11-06 訪談：推翻上一輪的 VIP 不存（ADR 0029）、App 不內建插件（ADR 0014）、另一個插件 repo（ADR 0030）、讀舊版 Isar（ADR 0010）。
- 2026-11-06 清理：刪 `docs/audit/questions.md`（決定已被 brief 取代）；`dependabot.yml` 的 GitHub Actions 版本更新暫停，M5 重新開啟；遠端只留 main，`probe/youtubejs` 存成 tag `archive/youtubejs-probe-20261106`。舊版的 `docs/` 文件、ADR 0001–0007、`ci.yml`、`release.yml` 留到取代舊版時刪。
- 2026-11-06 M0 拆票：pre-commit 只在 commit 改到 `app/` 時跑 `--quick`，舊版緊急修正不受新版閘門影響；`winpc` 以 SSH 同步工作樹，不 push 分支。擁有者確認，已寫進 plan §4。
