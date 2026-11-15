> 2026-11-15 M1 票 04（玻璃元件）的量測，寫完凍結。事實 K21 引用本檔。

# 「輕量」玻璃的模糊值：Windows 量測

問題：設定「玻璃效果」選「輕量」時，所有玻璃改用 `liquid_glass_easy` 的 lite glass（standard 級）。它的模糊值要選多少，才看起來仍是模糊玻璃、又比折射級快？`docs/design/DESIGN.md` 原本有三種說法並存：§1.1 一般玻璃 16、§1.4 standard 18、§1.4「降級時模糊半徑不能比折射級大」（來自 M0 的推測：lite 用 16 時比用 5 的 lens 慢，沒做同半徑的對照）。

## 做法

- 工具：`scripts/experiments/glass/` 的 probe（M0 票 05b），加三個候選 `lge-lite-5`、`lge-lite-10`、`lge-lite-18`（lite glass，模糊 5、10、18），和折射級 `lge-lens`（預模糊 5）與實心 `solid` 一起跑。指令：`VARIANTS=lge-lens,lge-lite-5,lge-lite-10,lge-lite-18,solid APP_ARGS=--plain ./run-windows.sh`，跑 3 次。
- 情境同 M0：1500 列的列表上浮著 5 個玻璃，以 2000 px/s 捲 8 秒（先捲 1 秒暖機不記），記 FrameTiming 的 raster 時間。
- 環境：`winpc`，Windows 11（Build 26200），Flutter 3.47.5，profile，Impeller（`isShaderFilterSupported` = true），160 Hz（預算 6.2 ms），DPR 1.5，`liquid_glass_easy` 5.2.0。
- 結果：`scripts/experiments/glass/results/windows-lite-run{1,2,3}.json`；對照圖 `results/windows-lite-sheet.jpg`（第 1 次的截圖）。

## 結果

raster 時間（ms），p50／p99；`python3 summarize.py results/windows-lite-run<n>.json` 印出完整表。

| 候選 | 第 1 次 | 第 2 次 | 第 3 次 | > 16.7 ms 的幀（3 次合計） |
| --- | --- | --- | --- | --- |
| lge-lens（折射，模糊 5） | 2.7／3.7 | 3.0／10.8＊ | 2.9／7.8＊ | 0 |
| lge-lite-5 | 3.5／4.7 | 3.6／10.5＊ | 3.6／4.8 | 0 |
| lge-lite-10 | 3.5／4.4 | 3.9／13.2＊ | 3.6／4.7 | 1 |
| lge-lite-18 | 3.6／4.7 | 3.6／4.7 | 3.6／4.7 | 0 |
| solid（實心） | 2.0／3.2 | 2.0／3.2 | 2.0／3.2 | 0 |

＊ 第 2、3 次有幾段被 `winpc` 上別的負載打斷：那幾段的幀數只有應有的 40–90%（`frames` 欄，lens 663、lite-10 523），p99 跟著變大。p50 不受影響，三次一致。

觀察：

- **lite glass 的成本和模糊值無關**：5、10、18 的 p50 都是 3.5–3.9 ms，乾淨的那幾次 p99 都是 4.4–4.8 ms。M0 推測的「模糊半徑大所以慢」不成立。
- **lite glass 在 Windows 上比折射級慢**，三個模糊值都是：p50 慢 0.6–0.9 ms。「輕量」在 Windows 不會比「完整」省效能；只有實心（「關閉」）比兩者都快。
- 三者都沒有超過 16.7 ms 的幀（第 2 次 lite-10 的 1 幀落在被打斷的那段），都在 160 Hz 的預算內。
- 這次的數字比 M0（2026-11-12：lens 6.4、lite-16 7.9 ms）小很多，兩者的比例相近；`winpc` 這三天有藍屏與硬體檢查待辦（roadmap〈M1〉），兩次之間的差異原因沒查。

外觀（`results/windows-lite-sheet.jpg`）：

- 模糊 5：條紋還清楚透出來，像磨砂但看得出底下的每一條。
- 模糊 10：條紋只剩淡淡的明暗，看得出是模糊玻璃。
- 模糊 18：完全糊成色塊，和設計稿 `html[data-glass="standard"]` 的 `blur(18px)` 一致。

## 決定

模糊值不影響效能，所以只看外觀選：擁有者 2026-11-15 選 18，和設計稿一致（`DESIGN.md` §1.4）。「輕量」在 Windows 不比「完整」省效能，手機沒量（iOS 只有模擬器、Android 模擬器沒有 GPU 加速）。
