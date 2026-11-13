# 里程碑：規劃、開工與驗收

寫 plan 的 session、里程碑開工的 session、做驗收票的 session 照這份做。其餘的票照 `AGENTS.md`〈每個 session 的流程〉。

## 寫 plan 與 roadmap

在 brief 訪談之後、第一個里程碑開工之前，一個 session 做完。這個 session 不寫 spec、不拆票。

1. 讀 brief 全文。〈待決〉裡會影響架構或順序的，先問使用者定下來。
2. 寫 `docs/plan.md` 各節，照它檔頭的寫法；技術選型先查成熟產品與套件的現況，說明採用了誰的做法。
3. 寫 `docs/roadmap.md`：里程碑表，每個里程碑一小節（目標、範圍要點、驗收的方向）。M0 是 tracer bullet；有 UI 的專案把設計稿排成一個只產出文件的階段。
4. 每節的草稿先給使用者看，確認後才寫入（`AGENTS.md`〈使用者確認〉）。

完成條件：brief 的每個功能都落在某個里程碑或 roadmap〈不排里程碑〉；`python3 scripts/check_docs.py` 通過；progress.md 加了一列，「下一步」是 `/to-tickets docs/roadmap.md 拆 M0 的票`。

## 開工

入口是使用者在新 session 下 `/to-tickets docs/roadmap.md 拆 <里程碑> 的票`。依序做完三步，第 3 步 commit 後才算完成：

1. **spec**：把 roadmap 裡它的那一節，依最新的 brief、plan 與上一個里程碑的結果細化成 `.scratch/<里程碑>/spec.md`，段落是〈目標〉〈範圍〉〈共同規則〉〈驗收〉〈票序〉。roadmap 那一節縮成一行連結，里程碑表的狀態改成「進行中」。文件不足以寫出 spec 時，問使用者並補進文件。
   - 〈驗收〉分兩組，各用 `###` 標題：**Agent 驗**是測試、指令輸出、截圖對得到的；**使用者試**是使用者親手用才知道的（手感、聲音、真實帳號、實機），每條寫明怎麼啟動、試什麼。沒有就寫「無」和理由。
2. **票**：照 `/to-tickets` 提出切法，使用者同意後寫票，每張票寫明「讀：plan §x、brief §y」與驗收條件。最後一張固定是驗收票 `NN-<里程碑>-acceptance`，被其他所有票擋。
3. **收尾**：票序寫回 spec〈票序〉，progress.md 加一列 session 紀錄，「下一步」寫第一張票的指令。

## 驗收票

依序做，前一步成立才做下一步：

1. 從里程碑開工的 commit 起跑 `mattpocock-skills:code-review`。
2. spec〈驗收〉的 Agent 驗逐條對到證據；在乾淨的 checkout 跑全部檢查。
3. 各票 Comments 沒處理的發現逐條歸位：修掉、延後（寫進 roadmap 接手的那個里程碑的小節，沒人接的進〈不排里程碑〉）或不做。
4. **使用者試**：把啟動方式與 spec 的使用者試清單給使用者，progress.md 的「下一步」寫 `等使用者：試用 <里程碑>`，結束 session。使用者回覆後在新 session 接著做這張票：
   - 不滿意的項目各開一張修復票（`NNb-<slug>`，排在驗收票之前），修完再請使用者試。
   - 使用者要 agent 代測：照做，並記一條偏差（使用者定），寫明哪幾項沒有人親手試過。
   - 使用者說可以了才往下。
5. **封存**：照 progress.md〈寫法與封存〉。搬完逐列比對，這個里程碑的每一列 session 紀錄、每一條偏差都在 `docs/archive/<里程碑>.md` 裡。

完成條件：spec〈驗收〉每一條都有證據或使用者的回覆；每個發現都歸了位；progress.md 只剩下一個里程碑的列。
