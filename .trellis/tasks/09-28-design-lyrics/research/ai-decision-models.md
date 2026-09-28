# AI 決策模型（structured decision / reranker）調查

- 查證日：**2026-09-28**。所有數字（star 數、版本、日期）皆為該日快照。
- 本檔只寫事實與出處。查不到者寫「查不到」；推論者標「推測」。
- 未呼叫任何音樂平台 API。GitHub 一律以 `gh api` / `gh search repos` 直接查，不採信搜尋摘要。
- 本檔不重複 `current-state.md`（FMP 現況）、`prior-art.md`（7 個歌詞產品）、`packages-and-platform.md`（Flutter 桌面/Android/iOS 平台事實）。

## 目錄

- §1 TypeSafe Jev / System One
- §2 Jev 相容的開源決策伺服器
- §3 通用 reranker / cross-encoder
- §4 zero-shot 分類（GLiClass）
- §5 約束解碼與 structured output
- §6 用 OpenAI 相容 `logprobs` 取選項機率
- §7 是否存在多廠商共用的「決策 API」標準
- §8 音樂／歌詞匹配領域的先例
- §9 未確認事項

---

## §1 TypeSafe Jev / System One

### 1.1 產品定位與事實

| 項目 | 值 | 出處 |
|---|---|---|
| 發表日 | 2026-09-15 | `https://typesafe.ai/blog/introducing-system-one-models-and-jev`（官方）；日期亦見 `https://www.width.ai/post/what-is-jev-ai-typesafe` |
| 定位 | System One model；不做字串生成，輸入 program state + typed questions，輸出 typed answers + calibrated probabilities，所有 question 一次平行評 | `https://docs.typesafe.ai/concepts/system-one`、官方 blog |
| 延遲 | 官方稱 end-to-end 70ms–500ms；同一頁對照 frontier model 為 3–329 秒 | `https://typesafe.ai/blog/introducing-system-one-models-and-jev` |
| 訓練方法 | 官方稱 RLCD（Reinforcement Learning for Calibrated Decisions） | 同上；`https://news.lavx.hu/article/typesafe-ai-launches-system-one-models-claims-100x-speed-gains-over-frontier-llms` |
| 價格 | USD 42 / Btok = USD 0.042 / Mtok，**只計 input token，output token 免費** | `https://docs.typesafe.ai/models` |
| 目前模型 | `jev-1.13.0`；alias `jev-latest`（最近穩定版）、`jev-preview`（最近版，不論是否 official）；兩個 alias 目前都指向 `jev-1.13.0` | `https://docs.typesafe.ai/models` |
| 列模型 | `GET /v1/models` 回傳帳號可用的 model 名稱 + 說明 + release date；目前只列 alias，但 versioned ID（如 `jev-1.13.0`）就算不在清單也接受 | 同上 |
| Rate limit | 250,000 tokens/second 與 1,200 requests/minute；超過任一即回 `429`；官方明說此二上限會動態調整、不另行通知；更高上限走 custom / enterprise | 同上 |
| 語言 | 官方原文：「English is the primary training language and where accuracy is currently best.」「Other languages, including CJK scripts, are handled but not equally well; test on your own content before relying on Jev」 | 同上 |
| 資料處理 | 「Jev is not trained on customer requests or responses.」「Jev is not fine-tuned or LoRA-adapted with customer data... the same weights serve every account.」；並指向 Legal 取得 DPA / Privacy Policy / enterprise 的 zero data retention (ZDR) 細節 | 同上 |
| 融資／創辦人 | 第三方報導：seed round 4,000 萬美元、由 DCVC 領投、由 Diogo Almeida 建立（其為 OpenAI RLHF / InstructGPT 共同作者） | `https://www.width.ai/post/what-is-jev-ai-typesafe`、`https://dev.to/valyuai/how-to-use-jev-a-practical-guide-to-typesafes-system-one-model-g5e`（**非官方，未經官方頁面覆核**） |

### 1.2 沒有訓練資料？——以 cookbook 反推「買的是什麼資料」

官方 cookbooks 目錄（`https://docs.typesafe.ai/llms.txt`）共 111 頁，全部是「如何把 state + question 拼出來」的配方，**沒有一頁在講訓練資料來源**。官方 blog 的 FAQ 標題含「Where does our training data come from?」（`https://typesafe.ai/blog/introducing-system-one-models-and-jev`），但本次抓取只取得 FAQ 標題、未取得答案內文 → 訓練資料來源：**查不到**。

### 1.3 HTTP API 形狀（官方 API reference）

出處：`https://docs.typesafe.ai/api`。

- Endpoint：`POST https://api.typesafe.ai/v1/systemone`
- Header：`Authorization: Bearer <API_KEY>`、`Content-Type: application/json`
- Request 三個必填頂層欄位：`model`、`state`（string / object / array）、`questions`（map，key 由呼叫者自訂）
- 三種 question type（`https://docs.typesafe.ai/primitives`）：
  - `noul`（yes/no）
  - `choice`（**最多 255 個選項**）
  - `score`（**2–10 級**）
  - 三者都有 `instructions` 與 `criteria`
- 官方註明：question 的 key **不會送進底層模型、不參與推論**
- Response：`model`（回答的 versioned ID）、`answers`（以 request 的 key 對應）、`usage`（`input_tokens` / `output_tokens`）
- 官方建議：因 alias 會隨新版移動，若 confidence 門檻是對某版本調的，應 pin versioned ID；log 時記下 response 的 `model` 以稽核

**Choice 的 request / response 逐字範例**（出處：`https://docs.typesafe.ai/primitives/choice`）：

```json
{
  "state": "My running shoes arrived in the wrong size. Can I swap them for a size 10?",
  "questions": {
    "department": {
      "type": "choice",
      "instructions": "Which team should handle this?",
      "criteria": {
        "returns": "Exchanges, wrong or damaged items",
        "shipping": "Delivery status, delays, lost packages",
        "billing": "Charges, invoices, payment problems"
      }
    }
  }
}
```

```json
{
  "model": "jev-1.13.0",
  "answers": {
    "department": {
      "type": "choice",
      "choice": "returns",
      "confidence": 1.0,
      "probabilities": {
        "shipping": 0.0,
        "returns": 1.0,
        "billing": 0.0
      }
    }
  },
  "usage": { "input_tokens": 328, "output_tokens": 34 }
}
```

- `criteria` 的 value 官方說可以是 `null`、或自訂欄名的 object / array（沒保留字）
- `choice` 欄位語意：「機率最高的選項」；`probabilities` 語意：「所有選項的完整機率分布，總和為 1」；`confidence` 語意：「由 `probabilities` 分散程度算出的 0–1 值」，分布平均→低、單峰→高（`https://docs.typesafe.ai/confidence`）
- `score` 除 `probabilities` / `confidence` 外另回 `legend`
- Noul 回 0–1 的數字，官方描述為「TypeSafe 對答案為 yes 的機率估計」

**錯誤碼**（出處：`https://docs.typesafe.ai/api`）：

| Code | 官方說明 |
|---|---|
| 401 | Missing or invalid API key. Check the Authorization header. |
| 422 | The request body failed validation |
| 429 | You have exceeded your rate limit. Back off and retry after a short delay. |
| 529 | TypeSafe is temporarily overloaded. Retry after a short delay. |

官方對 429 / 529 的指示是 exponential backoff，並說 client SDK 會自動處理。

### 1.4 SDK（JavaScript / Python）

| 項目 | 值 | 出處 |
|---|---|---|
| npm 套件 | `@typesafe-ai/sdk`，最新 **0.6.0**，license MIT，`engines.node >= 20`，npm 首次 publish 2026-09-12、最後 modified 2026-09-15；說明為 "TypeScript SDK for the TypeSafe API" | `https://registry.npmjs.org/@typesafe-ai/sdk` |
| PyPI 套件 | `typesafe-sdk`，最新 **0.7.2**，`requires_python >= 3.10`，首次上傳 2026-09-09 | `https://pypi.org/pypi/typesafe-sdk/json` |
| 環境變數 | 兩個 SDK 都讀 `TYPESAFE_API_KEY`，預設 model `jev-latest` | `https://docs.typesafe.ai/sdk`、`https://dev.to/valyuai/how-to-use-jev-a-practical-guide-to-typesafes-system-one-model-g5e` |
| Helper | JS SDK 提供 `choice()` / `noul()` / `score()` 建 question，answer 型別由 helper 推導；有 `AsyncTypeSafeClient` 與可設定的 retry policy | 同上；`https://docs.typesafe.ai/sdk/javascript` |
| JS 錯誤類別 | 官方 API docs 列出 `APIConnectionError` / `APITimeoutError` / `APIUserAbortError` / `AuthenticationError` / `BadRequestError` / `InternalServerError` / `NotFoundError` / `PermissionDeniedError` / `RateLimitError` / `UnprocessableEntityError`，另有 `RetryPolicy` / `Logger` / `Fetch` 介面 | `https://docs.typesafe.ai/llms.txt` 所列頁面清單 |
| 瀏覽器支援 | 官方 docs 與 npm metadata 都**沒有**任何 browser / web 支援或 bundle 大小陳述，`engines.node >= 20` → **推測**為 Node 環境；瀏覽器是否可用：**查不到** | — |
| Vercel AI SDK | AI SDK 7（自 7.0.105 起）有 `experimental_evaluate`，TypeSafe 是其 native provider；與 `@typesafe-ai/sdk` 並用需 Node 22+ | `https://flaviocopes.com/jev`（第三方） |
| 其他第三方整合 | LangChain（發表後兩天）、Pydantic AI（`typesafe:jev-latest` provider，可讀 `provider_details` 的 `confidence` / `probabilities` / `scores`）、DeepEval 的 `system_one` / `hybrid` 模式與 JevEval、OpenRouter（改 base URL 即可把既有 TypeSafe client 指向 OpenRouter，回應多回 `id` / `provider` / `usage.cost`） | `https://pydantic.dev/docs/ai/models/typesafe`、`https://deepeval.com/integrations/models/typesafe-ai`、`https://openrouter.ai/docs/guides/community/typesafe-sdk`、`https://www.width.ai/post/what-is-jev-ai-typesafe` |

### 1.5 免費額度與 early access

- 官方 blog 原文：「Our first public model is Jev, available today in **early access**.」
- 官方 blog 另有「working through its waitlist and bringing developers into early access」的敘述（轉述見 `https://news.lavx.hu/article/typesafe-ai-launches-system-one-models-claims-100x-speed-gains-over-frontier-llms`）
- `https://docs.typesafe.ai/models` 上**沒有** free tier、試用額度或 waitlist 申請流程的頁面
- 是否有免費額度、early access 是否需申請與審核：**查不到**（官方 docs 未載；`https://typesafe.ai/legal` 僅指向 DPA / Privacy Policy / ZDR，未見免費方案說明）

### 1.6 隱私與資料保留

- 官方 Privacy Policy 的 Retention 章節只寫概括語句：資料保留「as long as reasonably necessary to provide you with the Services...」，並說使用者要求刪除時會採去識別化或刪除措施，法律要求更長者除外 → **未載明具體天數**（`https://typesafe.ai/legal/privacy-policy`）
- 官方 models 頁：「details on **zero data retention (ZDR) for enterprise customers**」（`https://docs.typesafe.ai/models`）
- ZDR 的具體條件、DPA 條文內容：**查不到**（需進入 `https://typesafe.ai/legal` 下的文件，本次未取得逐字內容）

### 1.7 官方自己示範的兩個「選一個」用法

這兩頁官方 cookbook 是本調查中**最接近「在多個候選中選一個並取得機率」的官方範例**，逐字重點如下。

**Re-ranking**（`https://docs.typesafe.ai/cookbooks/rerank_typesafe`）：

- 流程：先用 BM25 取 30 篇短名單 → 對每個 (query, candidate) 各發一次 **Noul** 問題「Could this candidate passage be from the cited precedent?」
- 每個請求完全獨立：「no request sees another」
- 排序方式：用 Noul 回傳的 0–1 分數降序排（`key=lambda c: -pair_scores[q][c]["noul"]`）
- 規模：40 query × 30 candidate = 1,200 次呼叫，thread pool 12 workers
- 效果：官方稱 top-1 accuracy 由 5% → 18%、top-10 由 38% → 62%
- 官方限制說明：re-ranking「cannot add a passage that fast search did not select」
- 官方對呼叫粒度的建議：一對一問「是為了清楚」，真實應用「would ask several questions about the same pair in one call」，並指向 Parallel questions cookbook 與 Speculative Fan-Out pattern

**Entity alignment**（`https://docs.typesafe.ai/cookbooks/entity_alignment`）——官方示範的是**兩份商品目錄的 metadata 去重**：

- 一次呼叫同時問 4 個問題：1 個 Score（三級：「different product」/「related, but possibly not the same」/「same product」）+ 3 個 Noul（same name? same brewery? same style?）
- 兩個 entity 一起放進同一份 state（`entity_a` / `entity_b`），問題是針對「這一對」
- 官方明確說不用 Noul 比數字：「comparing two numbers is arithmetic; compute it in code if you want to.」（此例是酒精度）
- 文本「passed exactly as published, without pre-processing」，含 HTML entity 與被拆開的撇號都原樣送
- 決策規則：把 score 四捨五入到最近的級別，「The whole decision rule: the nearest level names the outcome.」，官方強調「no threshold you had to fit to your own data」
- 結果分布：450 對中 40 對合併（8.9%）、50 對轉人工（11.1%）、360 對不合併（80.0%）
- 分數實際落點：多數落在 0.25 附近，原因是表面欄位重疊把機率推向中間級；9 對落在合併切點 1.5 的 ±0.1 內、47 對落在人工切點 0.5 附近
- 模糊容錯實例：`c446` 這對的 style 字串為「American Barleywine」vs「Barley Wine」，style Noul 給 0.81，最終判定合併

---

## §2 Jev 相容的開源決策伺服器

以下皆以 `gh api` / `gh search repos` 於 2026-09-28 查得。**共同注意事項**：這些 repo 幾乎都在 2026-09-17～09-27 之間建立，歷史極短、未經第三方審核；star 數是快照，不能當品質證明。

### 2.1 有 Jev wire protocol 相容實作者

**Laya** — `NandhaKishorM/laya`，26,804 stars，Apache-2.0，created 2026-09-18，pushed 2026-09-27。
- 自我描述：「Non-autoregressive System 1 decision engine. Typed choice, score and yes/no decisions over any text in a single forward pass, in 100+ languages, with a router that picks the right checkpoint per request.」
- 其 `docs/http-api.md` 載明 `laya-serve` 直接實作 TypeSafe Jev 的 `/v1/systemone` wire protocol：同一個 path、同一個 `{state, questions}` request、answers 以相同 key 對應；**額外**多出 `routing` 區塊與 `answer_confidence` / `action.act_probability` 欄位
- Auth：`Authorization: Bearer <key>`，以 `LAYA_API_KEY` 環境變數控制（未設則不驗）
- 其他 env：`LAYA_HOST` / `LAYA_PORT` / `LAYA_DEVICE` / `LAYA_PRELOAD` / `LAYA_MODELS` / `LAYA_MAX_CONCURRENT`
- 另有 `GET /health`
- 限制（官方文件列出）：body 2 MiB、`state` 50,000 字元、64 questions、choice 每題 100 選項、score 每題 32 級、總選項數 512、concurrency 16
- 其 encoder 為 ModernBERT / mmBERT 系（非 autoregressive）

**NanoJev** — `TianyuCodings/NanoJev`，2,354 stars，MIT，created 2026-09-17，pushed 2026-09-21。
- 自我描述：「A nano replica of Jev: parallel decisions, dynamic candidates, and an end-to-end training pipeline.」
- 已知事實（前次查證）：Qwen3-0.6B + decision heads；只在 4 個遊戲任務上訓練；需 CUDA

**其他同名／衍生專案**（皆為 `gh search repos` 快照，license 以 API 回傳為準）：

| Repo | stars | license | 一句話自我描述 |
|---|---|---|---|
| `TheoLeeCJ/SemIf-OpenJev` | 4,455 | MIT | Semantic ifs from open models, on a 3090 at home. Independent; not affiliated with Jev or TypeSafe. |
| `razorback16/openjev` | 465 | Apache-2.0 | Open, Jev-compatible System One decision server on DiffusionGemma |
| `ekzhang/openjev-sglang` | 329 | **無 license 檔** | Jev-compatible API endpoint based on open models (prefill-only) |
| `Heman10x-NGU/openJev-verdict-2.0` | 290 | other | Calibrated 151M Non-Autoregressive Decision Engine（自稱勝過 TypeSafe Jev 與 Laya） |
| `kshetrajna12/reflex` | 153 | MIT | A small open decision model: state + typed questions -> calibrated probabilities. A Jev / System One re-creation on Qwen3.5. |
| `SiliconLabAI/OpenJev` | 149 | MIT | OpenSource Jev |
| `IamBusy/OpenJev-Vision` | 38 | Apache-2.0 | Open visual probability research: encode an image once, answer multiple structured questions |
| `zhihz/openjev` | 35 | other | Local bilingual probability decisions from context, questions, and candidate answers. Independent research preview inspired by TypeSafe Jev. |
| `zhangcy122/OpenJev` | 33 | other | Self-evolving cognitive decision engine & TypeSafe Jev alternative… 100% option-order invariance |

> `zhangcy122/OpenJev` 的自我描述提到它同時支援「Open LLMs、Laya (ModernBERT)、commercial Jev」並以 calibrated logprobs 取機率 —— 這是**專案自稱**，未經驗證。

### 2.2 JevHarness（「不自己跑模型，只包一層」的一類）

| Repo | stars | license | 日期 | 說明 |
|---|---|---|---|---|
| `TianyuCodings/JevHarness` | 317 | **無 license 檔**（`gh api` 回 `license: null`） | created 2026-09-21、pushed 同日 | LLM-authored task-specific Jev harnesses with optional full-trajectory reward reflection and GEPA evolution |
| `TypeSafeAI/jev-harness` | 21 | MIT | created 2026-09-22、pushed 2026-09-26 | A custom coding harness for TypeSafe AI's Jev: an LLM proposes, Jev answers narrow questions, code decides, every step leaves a receipt |

- `TypeSafeAI` GitHub org 顯示名稱為 **「TypeSafe Community」**，blog 指向 `https://jev.works`，created 2026-09-18，public_repos 8 → 名稱與公司同名，但 org 自稱 Community；**該 org 與 TypeSafe 公司的官方關係：查不到**（`gh api orgs/TypeSafeAI`）
- 另有數個小型 `jev-harness` / `jev-harness-router` 專案（3–16 stars，多為 MIT），皆為個人或社群專案

---

## §3 通用 reranker / cross-encoder

這一類的形狀是「給一對 (query, document) 回一個 relevance 分數」，**與 Jev 的「一次回一組選項的機率分布」不是同一個東西**。以下參數量取自 Hugging Face `safetensors.total`（即權重元素數，非檔案大小）。

| 模型 | license | 參數量 | downloads | 最後修改 | 出處 |
|---|---|---|---|---|---|
| `BAAI/bge-reranker-v2-m3` | **apache-2.0** | 567,755,777 | 17,069,529 | 2024-06-24 | `https://huggingface.co/api/models/BAAI/bge-reranker-v2-m3` |
| `Alibaba-NLP/gte-reranker-modernbert-base` | **apache-2.0** | 149,605,633 | 2,671,413 | 2025-07-04 | `https://huggingface.co/api/models/Alibaba-NLP/gte-reranker-modernbert-base` |
| `Qwen/Qwen3-Reranker-0.6B` | **apache-2.0** | 595,776,512 | 1,388,973 | 2026-04-16 | `https://huggingface.co/api/models/Qwen/Qwen3-Reranker-0.6B` |
| `mixedbread-ai/mxbai-rerank-base-v2` | **apache-2.0** | — | 29,818 | 2026-04-08 | `https://huggingface.co/api/models/mixedbread-ai/mxbai-rerank-base-v2` |
| `jinaai/jina-reranker-v2-base-multilingual` | **cc-by-nc-4.0** | 278,437,633 | 1,012,943 | 2025-10-21 | `https://huggingface.co/api/models/jinaai/jina-reranker-v2-base-multilingual` |
| `jinaai/jina-reranker-v3` | **cc-by-nc-4.0** | 596,836,352 | 834,931 | 2026-08-10 | `https://huggingface.co/api/models/jinaai/jina-reranker-v3` |

重點事實：

- **Jina 系列兩個 reranker 都是 `cc-by-nc-4.0`（非商用）** —— 這是本次查到的授權裡唯一一組非寬鬆授權。
- BGE / gte / Qwen3 / mxbai 皆 Apache-2.0。
- `sentence-transformers/msmarco-MiniLM-L6-cos-v5`：無 license 標註於 cardData（`gh`/HF API 回 null），downloads 11,831，最後修改 2024-11-05 → **授權查不到**。
- 這六個模型在 HF 上都**沒有** hosted HTTP inference API 的官方保證；要 HTTP 化需自架（HF TEI、vLLM、ONNX Runtime 等）→ **推測**（本次未逐一查各推論框架的支援矩陣）。
- reranker 輸出為單一 relevance scalar，**不是** option 分布；若要拿「選項機率」需自行做 softmax / 正規化並處理分數量尺 → **推測**。
- `PrithivirajDamodaran/FlashRank`：1,006 stars，Apache-2.0，created 2023-12-04，pushed 2026-07-11。自我描述：「Lite & Super-fast re-ranking for your search & retrieval pipelines. Supports SoTA Listwise and Pairwise reranking based on LLMs and cross-encoders」。它是把 reranker ONNX 化、以便在裝置上跑的**函式庫**，不是模型本身（`https://api.github.com/repos/PrithivirajDamodaran/FlashRank`）。
- **本調查未找到任何一份把 reranker 當成「在多個候選歌曲／歌詞中選一個並輸出機率」的現成方案。**

---

## §4 zero-shot 分類（GLiClass）

`knowledgator` 的 GLiClass 系列，官方定位為單次 forward pass 的 zero-shot 分類。

| 模型 | license | 參數量 | downloads | 最後修改 |
|---|---|---|---|---|
| `knowledgator/gliclass-large-v1.0` | **apache-2.0** | 438,111,232 | 534 | 2025-08-12 |
| `knowledgator/gliclass-modern-base-v2.0` | **apache-2.0** | 151,378,176 | 11,463 | 2025-08-12 |

- 出處：`https://huggingface.co/api/models/knowledgator/gliclass-large-v1.0`、`.../knowledgator/gliclass-modern-base-v2.0`
- 前者 HF `pipeline_tag` 為 `zero-shot-classification` → 代表 HF 生態可直接用 pipeline 呼叫，輸出各 label 機率
- 兩個模型都**沒有** hosted HTTP API；要 HTTP 化需自架 → **推測**
- CJK / 多語支援程度：官方 model card 描述**查不到**（本次未取得逐字內容）

---

## §5 約束解碼與 structured output（保證格式，不保證機率）

| 專案 | license | 機制 | 出處 |
|---|---|---|---|
| llama.cpp GBNF grammars | MIT | 以 GBNF 文法約束 sampler | `https://github.com/ggml-org/llama.cpp/blob/master/grammars/README.md`；repo `ggml-org/llama.cpp` pushed 2026-09-27 |
| Ollama structured outputs | MIT（`ollama/ollama`） | `format` 參數吃 JSON schema，Ollama 依 schema 產生 grammar 後交給 llama.cpp | `https://ollama.com/blog/structured-outputs`（2024-12-06 起）、`https://docs.ollama.com/capabilities/structured-outputs` |
| Outlines | Apache-2.0 | structured outputs | `https://api.github.com/repos/dottxt-ai/outlines`，pushed 2026-09-21 |
| XGrammar | Apache-2.0 | Fast, Flexible and Portable Structured Generation | `https://api.github.com/repos/mlc-ai/xgrammar`，pushed 2026-09-27 |
| llguidance | MIT | Super-fast Structured Outputs（`microsoft/llguidance` 會 redirect 到 `guidance-ai/llguidance`） | `https://api.github.com/repos/guidance-ai/llguidance`，pushed 2026-09-25 |
| Instructor | MIT | 以 Pydantic / Zod 型別包 structured output，支援 Ollama 與 OpenAI 相容 endpoint | `https://api.github.com/repos/567-labs/instructor`，13,950 stars，created 2023-06-14，pushed 2026-09-27；`https://python.useinstructor.com/integrations/ollama` |

重點事實：

- **Ollama Cloud 目前不支援 structured outputs**（官方 docs 原文：「Ollama's Cloud currently does not support structured outputs.」）
- Ollama 的 schema→grammar 是送給 llama.cpp 執行；第三方分析指出**模型不會在 prompt 裡看到你給的 schema**（與 tool calling 不同，tool 的 JSON spec 會被注入 system prompt）→ 該分析建議同時把格式寫進 prompt（`https://blog.danielclayton.co.uk/posts/ollama-structured-outputs`，第三方）
- 這一整類**只保證輸出符合 schema，不產生 calibrated probability**；要機率仍需 `logprobs` 或改用 decision model → **推測**

---

## §6 用 OpenAI 相容 `logprobs` 取選項機率

官方文件（OpenAI Cookbook「Using logprobs」）：

- `logprobs`：bool。為 `true` 時回傳 message content 每個 output token 的 log probability
- `top_logprobs`：**0 到 5 的整數**，指定每個 token 位置要回傳多少個最可能的 token 及其 log probability；使用此參數時 `logprobs` 必須為 `true`
- logprob 即 `log(p)`，`p` = 在該位置給定前文的 token 機率
- 官方 cookbook 的示範用例**就是分類**：對 headline 做分類時用 `logprobs=True, top_logprobs=2`，再讀 `response.choices.logprobs.content.top_logprobs`
- 出處：`https://developers.openai.com/cookbook/examples/using_logprobs`

回應物件形狀（社群逐字貼出的回應，非官方頁面）：`logprobs.content[]` 每項含 `token` / `logprob` / `bytes`（UTF-8 位元組的十進位值陣列）/ `top_logprobs[]`；較新的模型在 `top_logprobs[]` 每項另有 `prob` 欄位。出處：`https://community.openai.com/t/logprobs-in-chatcompletion/329471`、`https://community.openai.com/t/how-do-logprobs-work-for-chat-completion-api-for-gpt-4-1/1357590`（**社群貼文，非官方**）

限制與事實：

- `top_logprobs` 上限 5 → 若選項數多於 5，無法用單次呼叫取得完整選項分布 → **推測**（此限制為官方明載；推論是「需分次呼叫或改 prompt 設計」）
- 官方 API reference 曾註明此選項在 `gpt-4-vision-preview` 上不支援（社群貼文引述官方文字）
- 多個 OpenAI 相容服務都實作同一組參數：vLLM（含 `prompt_logprobs` 擴充）、DeepInfra、FuriosaAI 等 → 出處：`https://docs.deepinfra.com/chat/log-probs`、`https://developer.furiosa.ai/latest/en/furiosa_llm/examples/online_chat_completion_logprobs.html`

---

## §7 是否存在多廠商共用的「決策 API」標準

**查不到。**

以 tavily-search（basic）查「standardized decision API specification multiple vendors classification probability protocol」，回傳的都是**工具／API 描述類**協定，與「回傳選項機率」無關：

- OpenAPI / AsyncAPI（API 描述格式）— `https://www.infoq.com/articles/Standardized-Specification-Driven-API-Lifecycle`
- UTCP（Universal Tool Calling Protocol）— tool discovery / tool call 格式，`https://github.com/universal-tool-calling-protocol/utcp-specification`
- MCP（Model Context Protocol）— 工具／資源／prompt 協定
- 其餘為 DDS、Enterprise Ethereum、Klarna Agentic Product Protocol 等不相關領域的標準新聞

事實陳述：目前**沒有**跨廠商的決策 API 標準；形塑事實標準的是 TypeSafe 自己的 `POST /v1/systemone`，並被至少兩方照抄實作（OpenRouter 路由同一形狀並多回 `id` / `provider` / `usage.cost`；Laya 的 `laya-serve` 同 path、同 request、同 answers key）。出處：`https://openrouter.ai/docs/guides/community/typesafe-sdk`、`NandhaKishorM/laya` 的 `docs/http-api.md`。

---

## §8 音樂／歌詞匹配領域的先例

### 8.1 產品面

- 本任務 `prior-art.md` §7.4 已查證的結論：7 個歌詞產品（Namida、Spotube、LX Desktop、LX Mobile、MusicFree、Harmonoid、BetterLyrics）**零個**用 LLM 做歌詞匹配；皆為字串／fuzzy 比對。
- 音樂領域使用 reranker 或 decision model 的**產品級實作**：**查不到**。

### 8.2 學術面（皆為 embedding / retrieval，非 decision model）

| 論文 | arXiv ID | 版本時間 | 主題 |
|---|---|---|---|
| Melody-Lyrics Matching with Contrastive Alignment Loss | 2508.00123v1 | 2025-07-31 | 旋律與歌詞的對比對齊；摘要首句「The connection between music and lyrics is far beyond semantic bonds.」 |
| Leveraging Whisper Embeddings for Audio-based Lyrics Matching | 2510.08176v2 | v2 更新於 2026-02-05 | 以 Whisper embeddings 做 audio-based lyrics matching，主打替代既有 content-based retrieval |

出處：`https://arxiv.org/abs/2508.00123v1`、`https://arxiv.org/abs/2510.08176v2`（以 arXiv API 取得 metadata）。

- 另有大量「metadata fuzzy matching / cross-encoder reranking」的通用教材與業界文章（如 `https://dataladder.com/fuzzy-matching-101`），但都不是音樂或歌詞領域。
- 音樂 metadata 匹配的既有做法仍是 fuzzy matching（`rapidfuzz`）與 S-BERT embeddings；一篇 ACL 2024 NLP4MusA 論文在做 cover song identification 時比較 fuzzy matching 與 S-BERT，結論是 S-BERT 較好、fuzzy matching 只對歌名變體等情況夠用（`https://aclanthology.org/2024.nlp4musa-1.8.pdf`）

### 8.3 最接近的業界樣板（但非音樂領域）

TypeSafe 官方的 entity alignment cookbook（§1.7）就是「兩份商品目錄的 metadata 去重」，含模糊容錯（`American Barleywine` vs `Barley Wine`）。它是本研究找到**唯一**由模型廠商自己示範的「metadata 對不對得上」配方，但**領域是啤酒目錄，不是音樂**。出處：`https://docs.typesafe.ai/cookbooks/entity_alignment`

---

## §9 未確認事項

以下三項是本檔最不確定的事實，皆已在上文標註，集中列出：

1. **OpenRouter 是否為 System One 的正式合作夥伴**：`https://openrouter.ai/docs/guides/community/typesafe-sdk` 的頁面路徑含 `/community/`，且該頁同時描述「指向 OpenRouter 即可計費於 OpenRouter 帳號」；TypeSafe 官方 docs 的 111 頁清單裡**沒有**任何 OpenRouter 頁面 → 只能確認「OpenRouter 有這個能力」，雙方的合作關係性質查不到。
2. **`@typesafe-ai/sdk` 是否能在瀏覽器跑**：npm metadata 只寫 `engines.node >= 20`、README 未提瀏覽器；官方 docs 無 browser 章節 → 未確認。若要在 Flutter Web / 桌面端直接呼叫，這一點是關鍵未知。
3. **各開源 Jev 複刻的實際行為**：`SemIf-OpenJev`（4,455 stars）與 `razorback16/openjev`（465 stars）等高 star 專案的 star 數與描述取自 `gh search repos` 快照，repo 壽命只有 9–11 天，**未執行、未讀其推論程式碼**，其自稱（例如「beating TypeSafe Jev」）一律未經驗證。

### 其他查不到 / 未驗證項

- TypeSafe 訓練資料來源（官方 blog FAQ 有此標題，本次未取得答案內文）
- TypeSafe 是否有免費額度、early access 的申請與審核流程
- TypeSafe ZDR / DPA 的具體條款內容
- Jev 1.13 的官方 benchmark 數字（官方另有 `model-jaggedness/jev-1.13` 頁面，本次未讀）
- GLiClass 的 CJK / 多語能力描述
- 行動端（Android / iOS）上跑本節任一 reranker 或 decision model 的實測數據：**查不到**（本節只查了模型大小與授權，未查 ONNX / llama.cpp 在行動裝置的支援矩陣）
