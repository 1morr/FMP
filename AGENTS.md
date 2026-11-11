# FMP

Flutter 音樂播放器，音源是 Bilibili、YouTube、網易雲音樂。新版從零重做；根目錄的舊版凍結，只收緊急修正。文件是唯一的記憶，對話不是。

## 文件

- `docs/design-brief.md`：需求、決定、查證過的事實（〈查證過的事實〉，附來源）。決定衝突時以它為準。
- `docs/plan.md`：架構、依賴規則、測試策略；〈里程碑任務〉是路線圖，還沒開工的里程碑各有一小節，開工後縮成一行連到它的 spec；〈待決〉是定了方向、細節未定的事。
- `docs/progress.md`：各里程碑的閱讀指引、session 紀錄、偏差與決定。每個 session 的起點與終點。
- `.scratch/<里程碑>/spec.md`：該里程碑的目標、範圍、共同規則、驗收與票序；`issues/` 是票，執行單位，狀態在票的 `Status:` 行。
- `GLOSSARY.md`、`docs/adr/`：名詞表與架構決定，由 `/grill-with-docs` 按需建立；命名一律用名詞表的詞。ADR 0001–0007 只描述舊版；新 ADR 的編號規則在 `docs/adr/template.md`。
- `docs/audit/`：上一輪重寫前對舊版的審計快照，凍結。

上一輪重寫（Trellis 流程、`app/`、ADR 0008–0037）封存在 tag `archive/trellis-rewrite-20261106`。它是線索，不是依據：要沿用裡面的事實或做法，先查證，經擁有者確認後寫進 brief。

## 目錄

| 路徑 | 內容 |
| --- | --- |
| `app/` | 新版，獨立的 Flutter 套件，內部目錄照 plan §1.2；指令都在 `app/` 裡跑，閘門是 `dart run tool/check.dart`（完整版，四平台；前置條件見 plan §4），pre-commit 跑其中的 `--quick` |
| `.githooks/` | `pre-commit`：commit 改到 `app/` 時跑 `--quick`。clone 或新 worktree 後執行一次 `git config core.hooksPath .githooks` 啟用 |
| `lib/`、`test/`、`tool/`、`android/`、`windows/`、`assets/`、根目錄 `pubspec.yaml` | 舊版，凍結；規則在 `lib/AGENTS.md` |
| `docs/` | brief、plan、progress、ADR、`docs/research/`、`docs/agents/`、`docs/design/`（新版設計稿）；其餘是舊版的使用者與開發文件 |
| `.scratch/` | 里程碑的 spec 與票 |
| `.github/workflows/` | `ci.yml`、`release.yml` 都屬於舊版 |
| `.claude/skills/` | `verify-legacy-on-device`：舊版緊急修正的實機驗證 |

## 擁有者確認

- 新增或修改 ADR、`GLOSSARY.md`、brief、plan 裡的決定：先把草稿給擁有者看，確認後才寫入。訪談中（`/grill-with-docs`）也一樣。
- 做票時要推翻已定的決定（brief、plan、ADR、spec、先前的偏差）：停下來問擁有者。擁有者同意後，同一個 commit 改文件，並在 progress.md〈偏差與決定〉記一行。

## 每個 session 的流程

工作單位是**票**：`.scratch/<里程碑>/issues/NN-slug.md`，由使用者在新 session 下 `/to-tickets docs/plan.md 拆 <里程碑> 的票` 產生（見〈Skills〉）。一個 session 只做一張票，在自己的分支上做。

1. 讀 `docs/progress.md` 的 session 紀錄與偏差、該里程碑的 spec，再讀票；只讀票列出的 plan / brief 章節，其他按需讀。
2. `/implement <票路徑>`：tdd、定期 typecheck、結尾 `/code-review <開工時的 commit>`、commit。
3. 驗證：plan〈開發環境與閘門〉的全部檢查，也就是在 `app/` 跑 `dart run tool/check.dart` 完整版（涵蓋所有目標平台，含 test）；貼指令輸出。
4. 只在票內的取捨記到票的 `## Comments`；影響架構的另寫 ADR（照〈擁有者確認〉）。
5. 票的 `Status:` 改為 `done`、勾掉驗收條件、code-review 未處理的發現記到票的 `## Comments`；progress.md 加一列 session 紀錄（做了什麼、下一步，細節留在票裡）；驗收票多一步：照 progress.md 開頭的做法封存這個里程碑；commit。
6. 合併：在 main 上 `git merge --no-ff <票分支>`，merge commit 寫 `merge: ticket NN <slug>`，再 push main。不開 PR；擁有者靠 progress.md 與里程碑驗收跟進度。

完成標準：票上每個驗收條件打勾、全部檢查與 test 綠燈、progress.md 已更新、已合併並 push main。缺一就還沒完成。

**所有 session 的結尾**（做票、訪談、寫 plan、里程碑開工都算）：告訴使用者下一步要在新 session 下的完整指令，並把同一句寫進 progress.md 那一列的「下一步」。下一張票是 `/implement <票路徑>`，里程碑做完是 `/to-tickets docs/plan.md 拆 <下一個里程碑> 的票`；要使用者先決定才能繼續時，寫 `等使用者：<要決定什麼>`。

## 事實與查證

- 三個音源的端點、參數、簽名與風控行為，Flutter、套件與各平台框架的行為，只信兩處：brief〈查證過的事實〉，以及現查（context7、官方文件）。brief 沒寫的先查再用，查到的補進 brief 並附來源。
- 現況以指令為準：`git log`、`git status`、測試輸出。progress.md 與 repo 不符時以 repo 為準並修 progress.md。

## 上下文紀律

- 讀大檔案、查文件、跑實驗交給子代理回摘要。
- brief 或 plan 長過 500 行後，只讀任務指到的章節。
- 對話已長或一個任務碰了十幾個檔案：把進度與下一步寫進 progress.md，結束 session。

## 公開 repo 與擁有者的帳號

repo 是公開的。commit、文件、票、fixture、log 摘錄與截圖：

- 不含個人資訊：使用者名稱、email、手機號、帳號名稱、私人歌單的內容。
- cookie、token、簽名網址、API key 的值寫成 `***`。
- 本機路徑用代稱：`<資料目錄>`、`<暫存目錄>`、`<repo>`。
- 不寫 Apple Team ID、裝置 UDID、裝置名稱；簽名設定放 gitignore 的本機檔。

擁有者的帳號：

- 登入由擁有者自己掃 QR 或輸入密碼；agent 只看結果，不輸入、不讀取、不轉述密碼、cookie 值或 token。鑰匙圈與系統授權視窗留給擁有者按。
- 需要擁有者在場的步驟（登入、寫入遠端）開工前先約時間，做到那一步停下等。
- 用真實帳號連線只做最少的操作（搜尋一次、播放一首），不批次、不迴圈：頻繁操作會讓帳號被風控。
- 寫入遠端（歌單、收藏）只動擁有者指定的測試歌單，加入、移除各一次；其他寫入當次問過擁有者才做。

## 舊版

- 凍結：只收緊急修正，不加功能。改舊版前讀 `lib/AGENTS.md`（Claude Code 只在讀到 `lib/` 底下的檔案時才自動載入它，只改 `test/` 等路徑時要自己打開）。
- 舊版的 CI 是 `ci.yml`，每次都要綠；發版是 `release.yml`（`v*` tag）。實機驗證用 `verify-legacy-on-device`。

## Issues

GitHub `1morr/FMP` 的 issue 收外部回報，用 `gh` 處理；工作用的票照〈Agent skills〉。標題與內文用繁體中文（台灣／香港用語），識別符、log、commit、分支與 label 名稱維持英文。

## Skills

- 需求與設計訪談：`/grill-with-docs`（邊問邊寫 `GLOSSARY.md` 與 ADR，照〈擁有者確認〉先給草稿），結論寫回 brief。
- 里程碑開工：入口是使用者在新 session 下 `/to-tickets docs/plan.md 拆 <里程碑> 的票`。這個 session 依序做完三步，第 3 步 commit 後才算完成：
  1. 把 plan〈里程碑任務〉裡它的那一節，依最新的 brief、plan 與上一個里程碑的結果細化成 `.scratch/<里程碑>/spec.md`，plan 那一節縮成一行連結。文件不足以寫出 spec 時，問使用者並補進文件。
  2. 照 skill 提出切法，使用者同意後寫票，每張票寫明「讀：plan §x、brief §y」與驗收條件。最後一張固定是**驗收票** `NN-<里程碑>-acceptance`（由 `check.dart` 的文件檢查守），被其他所有票擋：從開工的 commit 起跑里程碑 code-review、spec〈驗收〉逐條對到證據、乾淨 checkout 跑全部檢查、各票 Comments 沒處理的發現逐條歸到修掉、延後（寫進 plan）或不做，最後封存里程碑。
  3. 票序寫回 spec〈票序〉，progress.md 加一列 session 紀錄。
- 訪談、寫 plan 的 session 收尾在「plan 已更新」。之後的里程碑留在 plan，開工時才有 spec。
- 做票：一張票一個 session，`/implement`；整批跑票：`/1morr:ticket-coordinator`。
- 新功能與修 bug：`mattpocock-skills:tdd`。
- 設計模組邊界（音源、播放、平台層之間）：`mattpocock-skills:codebase-design`。
- 用實驗回答設計問題（平台框架行為、音源回應實測）：`mattpocock-skills:prototype`，結論寫回 brief。實驗腳本留在 `scripts/experiments/`，換版本時要重量。
- 查證外部事實：`mattpocock-skills:research`，輸出放 `docs/research/`，結論摘進 brief〈查證過的事實〉並連結。
- 每張票與里程碑收尾：`mattpocock-skills:code-review`（Spec 軸讀票，Standards 軸讀本檔）；難 bug 或效能退化：`mattpocock-skills:diagnosing-bugs`。
- 改本檔或 progress.md 的流程段：`mattpocock-skills:writing-for-agents`。

## Agent skills

### Issue tracker

Local markdown：票以檔案存在 `.scratch/<里程碑>/issues/`。See `docs/agents/issue-tracker.md`.

### Triage labels

五個預設角色標籤，字串與角色名相同。See `docs/agents/triage-labels.md`.

### Domain docs

Single-context：根目錄 `GLOSSARY.md` + `docs/adr/`。See `docs/agents/domain.md`.
