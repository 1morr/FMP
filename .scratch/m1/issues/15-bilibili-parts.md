# 15: B 站分 P

Status: done
Blocked by: 09、14
讀: brief §5.1、§5.3、§6；`GLOSSARY.md`〈分 P〉；ADR 0039；`docs/design/search.html`（B 站多 P 展開）、`docs/design/DESIGN.md` §4.1；事實 F1、F21；spec〈共同規則〉

## What to build

多 P 影片在搜尋結果帶分 P 數的標示，可以展開列出每個分 P。`listParts` 插件能力（bilibili 實作，介面寫回 ADR 0039）列出一支影片的分 P，每個分 P 是一首曲目（id 照 brief §5.3）。點父列時整組當成一首臨時播放，播完整組才回佇列；點單一分 P 只臨時播放那一個。選單可以把單一分 P 或整組加入佇列；整組進佇列時是一首還是拆成每個分 P，由這張票定，記成一條決定。

M1 主要流程的 integration_test 寫在這張：搜尋、加入佇列、臨時播放一組分 P、整組播完回到佇列原本那首，四平台都跑（串流指向假 CDN）。

## 驗收

- [x] `listParts`：契約測試有 fixture，`live` 冒煙測試加一條，ADR 0039 補了介面。
- [x] 整組臨時播放有單元測試：播完整組才回佇列；組內上一首、下一首在組內移動；回佇列時照常倒退。
- [x] 展開分 P 的截圖和 `search.html` 對得上。
- [x] M1 主要流程的 integration_test 四平台通過。（macOS、iOS、Android；Windows 跳過）
- [x] 四平台實跑：展開一支多 P 影片、臨時播放整組，讀回畫面。（照 spec〈共同規則〉縮成 macOS＋Android；音訊後端的修正另由閘門的 `parts_test` 在 macOS、iOS、Android 跑；Windows 跳過）
- [x] 全部檢查綠燈（`dart run tool/check.dart` 完整版）。（`--skip-windows`）

## Comments

決定：B 站多 P 的「下一首播放」「加入佇列」（選單與多選）拆成每個分 P，依序加進佇列，不做「一組」的佇列列（使用者同意）
決定：ADR 0039 的 `listParts` 與搜尋結果的 `partCount` 照草稿寫入（使用者同意）
決定：測試接縫五層：插件契約與 bilibili、宿主 `Plugin.listParts`、佇列控制器、搜尋頁 widget、M1 主要流程 integration_test（協調者代答）（Agent 定）
決定：搜尋結果沒有分 P 數，bilibili 每頁多打一次 `fav/resource/infos` 批次取（事實 F27）；失敗或被限流時照常回結果、不標分 P 數（協調者代答）（Agent 定）
決定：插件沒有 log API，不為此加宿主 API；infos 失敗靠宿主網路層的請求 log（協調者代答）（Agent 定）
決定：infos 只吞 `PluginError`；`aid` 不是正整數的不放進請求，回應的 `page` 不是 ≥1 的整數當沒有；pagelist 某筆沒有合格的 `page` 算解析失敗（Agent 定）
決定：分 P 沿用父列的作者與封面，不沿用播放數；分 P 標題照 B 站的 `part`（常自帶編號前綴），空的才寫 `P<n>`（Agent 定）
決定：整組臨時播放是 `TemporaryPlay` 帶整組與目前第幾個，單獨一首是只有一個的組；`QueueController.playGroupTemporarily` 開始（Agent 定）
決定：組內第一個按上一首、最後一個按下一首就回佇列；沒有佇列可回時上一首、下一首只在組內能按（Agent 定）
決定：組內正在播的分 P 播不了就跳組內下一個（算跳過、連續失敗照算），最後一個播不了回佇列（Agent 定）
決定：整組時預載組內的下一個，最後一個預載要回去的佇列那首（Agent 定）
決定：佇列頁卡片的「下一首播放」在整組時，把正在播的與組內還沒播的一起排到原本那首後面，聲音不中斷（Agent 定）
決定：列分 P 失敗時提示原因；點父列退回只播第一段（父列就是 P1），佇列的動作不做，展開就收起（Agent 定）
決定：父列收起時正在播任一個分 P 就標成目前曲目，展開時改由分 P 列標；分 P 列的鍵另外加 `part`，免得和父列（同一首 P1）撞（Agent 定）
決定：桌面分 P 列雙擊播放、右鍵或 ⋮ 開選單、不參與選取，選取底色不跨過展開的分 P 列相接；手機多選時分 P 列點了沒反應（Agent 定）
決定：桌面的展開箭頭在雙擊範圍裡，改用按下就認領的點擊，不等雙擊逾時（Agent 定）
決定：選單摘要的「n 個分 P 全部套用」：手機 sheet 接在作者後面，平板與桌面的選單取代作者（照稿的 `srhMenuHead`）（Agent 定）
決定：展開後分 P 還在列時箭頭換成轉圈，不畫骨架列（Agent 定）
決定：just_audio 後端的 seek 先等「自己接過去後移掉播過那項」做完，不等其他清單修改（包 HLS 的預載要抓索引）（Agent 定）
決定：riverpod 3.5.0 的 `ref.exists` 已棄用、替代的 `provider.exist` 還沒有，先用並在同處註明（Agent 定）
決定：照稿截圖另開 `search_parts_states_run.dart`（同時 override `partsProvider` 與 `playbackProvider`），桌面以右鍵代替 ⋮（Agent 定）
決定：實跑 `parts_run.dart` 先用選單把另一個結果加進佇列再展開、整組播放、按下一首、看佇列頁，比 spec 的「播一首」多解析（Agent 定）
根因：自己接到預載那項後，後端馬上 `removeAudioSourceAt(0)` 移掉播過那項，移除還沒做完就 `seek`，macOS 的 AVQueuePlayer 會停在 0:00 不前進（事實 K34）。整組分 P 播完回佇列倒退 10 秒時碰到；修之前 `integration_test/parts_test.dart` 在 macOS 連跑三次都停在 0:00（紅），修後綠，閘門在 macOS、iOS、Android 都綠
實跑讀回（2026-11-19；截圖在 `<repo>/app/build/real_run-parts*/`，不進 repo）：`parts_run.dart` 真 B 站搜「陈楚生 高品质音乐合集」：第一個帶小標的是「精选【陈楚生】高品质音乐合集【分p系列】」標「51P」；展開列出 P1「1 远山如昨 - 陈楚生」3:31 到 P51；點父列後迷你播放器「1 远山如昨 - 陈楚生｜臨時｜…｜0:00 / 3:30」；按下一首「2 有没有人告诉你 - 陈楚生｜臨時」（log：用預載的那條）；佇列頁有臨時播放卡片。macOS 與 Android（英文介面，小標寫 Temp）各一次
截圖比對（和 `search.html` 同狀態並排看過）：`search_parts_states_run.dart` 不聯網，macOS 寬版與中寬度、Android 窄版，各在深淺色截收起、展開、P2 正在播與父列選單；對不上的修了（桌面分 P 列的 P 編號與標題差 10、桌面選單摘要被截斷）。手機時長欄比稿靠右約 12，是共用曲目列的事，不在這張改
聯網次數：插件 fixture 錄 5 案例共 9 個請求、live 冒煙 1 次（search 2 次＋infos 2 次、pagelist 3 次、playurl 1 次）；查證 3 次（search、infos、pagelist 各一）；實跑 macOS 3 輪（前兩輪情境寫錯）、Android 1 輪，每輪 search 1、infos 1、pagelist 7、playurl 4；都沒被限流
log：宿主網路層每個插件請求記 `GET <網址> -> <狀態>`，但那是 debug 級，release 版不記；連線失敗才記 warning。所以 release 版的 HTTP 412 限流，以及回 200 但內容是風控碼或解析不了的 infos 回應，都沒有紀錄
閘門：第一次 `native tests macos` 的第一個案例 0.000 秒就失敗（測試行程沒連上），其餘案例換了行程都過，原因不明；integration_test 三平台當時都綠。照「說不出原因的重試不收」整個閘門重跑一次，全綠（`--skip-windows`）
iOS 只跑了完整閘門（含 `parts_test`）：實跑的手機平台用 Android（spec〈共同規則〉macOS 加一個手機）
Windows 跳過：沒有建置、integration_test 與實跑。補驗看：(1) 完整閘門 Windows 步驟（新的 `parts_test`）；(2) media_kit 後端自己接到預載那項（連接兩首）後馬上 seek，會不會停在 0:00（just_audio 在 macOS 會，事實 K34；這張只修了 just_audio）；(3) 桌面表格的分 P：› 箭頭點下立刻展開、「3P」、分 P 列雙擊只播那段、右鍵選單摘要「B站 · n 個分 P 全部套用」；(4) `search_parts_states_run.dart` 與 `parts_run.dart` 實跑
code-review 未處理：① 搜尋列為分 P 多了四個欄位（分 P 數、展開、列中、切換），兩種列各一份，靠 `onToggleParts!` 約定，可包成一個型別。② 佇列控制器組內移動的判斷寫了三處（下一首、上一首、播完）。③ `playTemporarily` 只是轉呼叫 `playGroupTemporarily`，動作執行器仍分單首與整組兩支。④ `hasParts` 每次由呼叫端自己查 manifest。⑤ `PartsToggle` 用一個 `touch` 旗標分兩種外觀。⑥ 契約測試的 listParts 檢查空清單與重複 id，宿主已經會丟解析失敗，對 bilibili 永遠不觸發（留給別的插件）。⑦ 同屬臨時播放的舊寫法：其他失敗分支沒比對失敗的是不是正在播的那首（組內那支已補）
Session 紀錄：2026-11-19 B 站分 P：`listParts` 插件能力與搜尋結果的分 P 數、整組臨時播放、搜尋頁展開分 P 與拆成每個分 P 加入佇列、M1 主要流程 integration_test，修 macOS 連接兩首後馬上 seek 停在 0:00；macOS＋Android 實跑與三種寬度深淺色截圖比對；完整閘門 --skip-windows 綠
變更：Added｜搜尋｜B 站多 P 影片在搜尋結果標分 P 數（例如「3P」），可以展開列出每個分 P 與時長
變更：Added｜臨時播放｜點多 P 影片就把整組當成一首臨時播放：一段播完接下一段，上一首、下一首在組內移動，整組播完才回到佇列原本那首、倒退後接著播；點單一分 P 只播那一段
變更：Added｜佇列｜多 P 影片的「下一首播放」「加入佇列」（選單與多選）把每個分 P 依序加進佇列，選單頂端寫「n 個分 P 全部套用」
變更：Fixed｜播放控制｜macOS 上一首播完自己接到下一首後馬上跳到某個位置（例如整組分 P 播完回到佇列、倒退 10 秒）時，不再卡在 0:00 不動
