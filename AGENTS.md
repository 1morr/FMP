# FMP

Flutter 音樂播放器，音源是 Bilibili、YouTube、網易雲音樂。新版從零重做；根目錄的舊版凍結，只收緊急修正。文件是唯一的記憶，對話不是。

## 文件

- `docs/design-brief.md`：需求與決定。決定衝突時以它為準。
- `docs/research/facts-*.md`：查證過的外部事實，每條有編號與來源；索引在 brief〈事實索引〉。
- `ARCHITECTURE.md`：模組地圖、依賴規則、主要依賴、測試策略；〈待決〉是定了方向、細節未定的事。
- `docs/app-development.md`：新版怎麼建置、在各平台實跑驗證、閘門怎麼跑。
- `docs/roadmap.md`：里程碑的順序、狀態與閱讀指引；還沒開工的里程碑各有一小節，開工後縮成一行連到它的 spec；〈不排里程碑〉收沒人接的遺留。
- `docs/progress.md`：進行中里程碑的 session 紀錄。每個 session 的起點與終點。
- `docs/decisions.md`：進行中里程碑的決策紀錄，一條一行，標決定者；驗收後跟著封存。
- `.scratch/<里程碑>/spec.md`：該里程碑的目標、範圍、共同規則、驗收（Agent 驗、使用者試）與票序；`issues/` 是票，執行單位，狀態在票的 `Status:` 行。
- `GLOSSARY.md`、`docs/adr/`：名詞表與架構決定，由 `/grill-with-docs` 按需建立；命名一律用名詞表的詞。ADR 0001–0007 只描述舊版；新 ADR 的編號規則在 `docs/adr/template.md`。
- `docs/audit/`：上一輪重寫前對舊版的審計快照，凍結。

上一輪重寫（Trellis 流程、`app/`、ADR 0008–0037）封存在 tag `archive/trellis-rewrite-20261106`。它是線索，不是依據：要沿用裡面的事實或做法，先查證，經擁有者確認後寫進 brief。

## 目錄

| 路徑 | 內容 |
| --- | --- |
| `app/` | 新版，獨立的 Flutter 套件，內部目錄照 architecture〈目錄結構〉；指令都在 `app/` 裡跑，閘門是 `dart run tool/check.dart`（完整版，四平台；前置條件見 docs/app-development.md〈開發環境與閘門〉），pre-commit 跑其中的 `--quick`；改 drift 資料庫的 schema 照 architecture〈測試策略〉（`dart run drift_dev make-migrations`，閘門會比對快照）；錄製插件契約測試的 fixture、跑 `live` 冒煙測試也照 architecture〈測試策略〉 |
| `.githooks/` | `pre-commit`：commit 改到 `app/` 時跑 `--quick`。clone 或新 worktree 後執行一次 `git config core.hooksPath .githooks` 啟用 |
| `lib/`、`test/`、`tool/`、`android/`、`windows/`、`assets/`、根目錄 `pubspec.yaml` | 舊版，凍結；規則在 `lib/AGENTS.md` |
| `docs/` | brief、roadmap、progress、decisions、`app-development.md`、ADR、`docs/research/`、`docs/agents/`、`docs/design/`（新版設計稿）；其餘是舊版的使用者與開發文件 |
| `.scratch/` | 里程碑的 spec 與票 |
| `scripts/` | `check_docs.py`（文件檢查，`app/` 的快速閘門會跑它，要 Python 3）與它的測試；設計實驗在 `scripts/experiments/` |
| `.github/workflows/` | `ci.yml`、`release.yml` 都屬於舊版 |
| `.claude/skills/` | `verify-legacy-on-device`：舊版緊急修正的實機驗證 |

## 擁有者確認

- brief、`ARCHITECTURE.md`、ADR、`GLOSSARY.md` 裡的決定：草稿先給擁有者看，確認後才寫入；訪談中（`/grill-with-docs`）也一樣。
- 做票時要推翻已定的決定（brief、`ARCHITECTURE.md`、ADR、spec、`docs/decisions.md` 裡的）：停下來問擁有者。同意後，同一個 commit 改文件，並記一條決定。
- 問擁有者決定（對話裡，或 progress.md 的 `等使用者：`）：每題寫成沒讀過票也看得懂的話，依序是背景一句、選項、你的建議、不決定會卡住什麼；票號、函式名、章節號後面跟一句它是什麼。
- 擁有者回「照建議」，只算同意這一則訊息裡列出來的那幾題。
- 每個決定在 `docs/decisions.md` 佔一行並標**決定者**：`（使用者定）` 擁有者自己定的、`（使用者同意）` agent 提議而擁有者同意的、`（Agent 定）` 擁有者沒看過的。做票時在兩種做法之間選了一種，就是一個 `（Agent 定）` 的決定；`/1morr:checkpoint` 會把它們拿給擁有者看。

## 每個 session 的流程

工作單位是**票**：`.scratch/<里程碑>/issues/NN-slug.md`，由里程碑開工的 session 產生（見〈Skills〉）。一個 session 只做一張票，在自己的分支上做。

1. 讀 `docs/progress.md`、`docs/decisions.md` 裡這個里程碑的決定、該里程碑的 spec，再讀票；只讀票列出的架構與 brief 章節，其他按需讀。
2. `/implement <票路徑>`：tdd、定期 typecheck、結尾 `/code-review <開工時的 commit>`、commit。
3. 驗證：docs/app-development.md〈開發環境與閘門〉的全部檢查，也就是在 `app/` 跑 `dart run tool/check.dart` 完整版（涵蓋所有目標平台，含 test）；貼指令輸出。
4. 影響架構的決定另寫 ADR（照〈擁有者確認〉）。
5. 票的 `Status:` 改為 `done`、勾掉驗收條件、code-review 未處理的發現記到票的 `## Comments`；Comments 最後加一行 `Session 紀錄：<做了什麼，一句>`，做票時定的每個選擇各加一行 `決定：<一句>（<決定者>）`；commit。票的分支不改 progress.md 與 decisions.md：平行的票都改它們會互撞。
6. 合併：在 main 上 `git merge --no-ff <票分支>`，merge commit 寫 `merge: ticket NN <slug>`；接著在 main 把票上那兩種行抄進去（progress.md 一列 session 紀錄含下一步、decisions.md 每個決定一條）並 commit，再 push main。協調者（`/1morr:ticket-coordinator`）開的 session 只在自己的分支 commit，這一步留給協調者。不開 PR；擁有者靠 progress.md 與里程碑驗收跟進度。
7. 驗收票被其他所有票擋、不會平行，它自己在分支上改這兩個檔。

完成標準：票上每個驗收條件打勾、全部檢查與 test 綠燈、Comments 有 `Session 紀錄：` 一行、已合併並 push main（協調者開的 session 到已 commit 為止）。缺一就還沒完成。

**所有 session 的結尾**（做票、訪談、寫架構、里程碑開工都算）：告訴使用者下一步要在新 session 下的完整指令，寫 progress.md 的人把同一句寫進那一列的「下一步」。下一張票是 `/implement <票路徑>`，里程碑做完是 `/1morr:checkpoint <剛做完的里程碑>`（回顧上一段、和使用者對齊下一段；它結束時寫 `/to-tickets docs/roadmap.md 拆 <下一個里程碑> 的票`）；要使用者先決定才能繼續時，寫 `等使用者：<要決定什麼>`。

## 事實與查證

- 三個音源的端點、參數、簽名與風控行為，Flutter、套件與各平台框架的行為，只信兩處：`docs/research/facts-*.md` 的〈事實〉段，以及現查（context7、官方文件）。沒寫的先查再用，查到的補進對應主題的檔，給編號、附來源。
- 程式碼、測試與註解要指向文件時，引 ADR 編號或事實編號；brief 的章節號只寫在文件與票裡，節才能搬動（`scripts/check_docs.py` 擋）。
- 現況以指令為準：`git log`、`git status`、測試輸出。progress.md 與 repo 不符時以 repo 為準並修 progress.md。

## 上下文紀律

- 讀大檔案、查文件、跑實驗交給子代理回摘要。
- brief 只讀任務指到的章節。四個檔有字元上限，`scripts/check_docs.py` 強制：本檔 8,000、`ARCHITECTURE.md` 15,000、progress.md 20,000、brief 30,000；超過時搬走或刪掉內容，不靠縮短措辭湊數。
- 對話已長或一個任務碰了十幾個檔案：把進度與下一步寫進 progress.md，結束 session。

## UI

- 照 `docs/design/` 的定稿實作，要偏離先問擁有者。定稿之後才新增或大改的畫面，在那張票的第一步用 `impeccable:impeccable` 出設計，擁有者確認後才實作。
- 做對比版：每一版在自己的 worktree 做，只讀 brief 與 `docs/design/DESIGN.md`，別的版本的設計稿留到擁有者比較時才打開。
- UI 改動實跑驗證，附截圖或讀回的畫面文字。

## 公開 repo 與擁有者的帳號

repo 是公開的。commit、文件、票、fixture、log 摘錄與截圖：

- 不含個人資訊：使用者名稱、email、手機號、帳號名稱、私人歌單的內容。音源上公開內容的作者名稱與標題（例如匿名搜尋結果裡的 UP 主名稱）不算，可以保留。
- cookie、token、簽名網址、API key 的值寫成 `***`。用公開值算出、只對單次請求有效的請求簽名（例如 B 站 WBI 的 `w_rid`）不算，照原樣保留；簽名網址裡純時間戳的有效期參數（`deadline`、`expire` 這類）也不算，照原樣保留，簽名與其他值照樣遮。
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
- 里程碑開工（使用者在新 session 下 `/to-tickets docs/roadmap.md 拆 <里程碑> 的票`）、做驗收票 `NN-<里程碑>-acceptance`：先讀 `docs/agents/milestone.md`，照它的步驟做。之後的里程碑留在 roadmap，開工時才有 spec。
- 做票：一張票一個 session，`/implement`；整批跑票：`/1morr:ticket-coordinator`。
- 新功能與修 bug：`mattpocock-skills:tdd`。
- 設計模組邊界（音源、播放、平台層之間）：`mattpocock-skills:codebase-design`。
- 用實驗回答設計問題（平台框架行為、音源回應實測）：`mattpocock-skills:prototype`，決定寫回 brief，量到的數字寫進 `docs/research/`。實驗腳本留在 `scripts/experiments/`，換版本時要重量。
- 查證外部事實：`mattpocock-skills:research`，輸出放 `docs/research/`，結論寫成對應 `facts-*.md` 的一條事實。
- 每張票與里程碑收尾：`mattpocock-skills:code-review`（Spec 軸讀票，Standards 軸讀本檔）；難 bug 或效能退化：`mattpocock-skills:diagnosing-bugs`。
- 改本檔或 progress.md 的流程段：`mattpocock-skills:writing-for-agents`。

## Agent skills

### Issue tracker

Local markdown：票以檔案存在 `.scratch/<里程碑>/issues/`。See `docs/agents/issue-tracker.md`.

### Triage labels

五個預設角色標籤，字串與角色名相同。See `docs/agents/triage-labels.md`.

### Domain docs

Single-context：根目錄 `GLOSSARY.md` + `docs/adr/`。See `docs/agents/domain.md`.
