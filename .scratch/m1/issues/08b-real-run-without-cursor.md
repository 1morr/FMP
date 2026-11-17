# 08b: 實跑不搶擁有者的游標

Status: ready-for-agent
Blocked by: None
讀: `docs/development.md`〈平台〉四節的「實跑」與〈開發環境與閘門〉；`ARCHITECTURE.md`〈測試策略〉（integration_test、零聯網）；`app/tool/winpc/shot.ps1`；`app/test/architecture/integration_test_guard_test.dart`；票 05b、05d、08 的 Comments（實跑怎麼點的）；spec〈共同規則〉

2026-11-17 協調者插票（擁有者定）：實跑時 Windows 用 `shot.ps1` 的 `-Click`、`-TypeAt`（`SetCursorPos` 加 `SendInput`），macOS 用 CGEvent，會把擁有者正在用的游標移走。擁有者定兩點：實跑優先用不碰游標的方式驅動 App；真滑鼠只留給 Flutter 看不到的原生視窗行為。四平台用同一套做法。排在 08 之後、09 之前。

## What to build

- **實跑驅動**：用 integration_test 在 Flutter 裡送點擊與輸入（系統游標不動），打真的音源（匿名，照 spec〈共同規則〉的聯網規則），每一步截圖或讀回畫面文字，存到 `<暫存目錄>`。四平台同一個情境檔、同一種跑法（`flutter test <檔> -d <裝置>`，Windows 經 `tool/winpc/run_task.sh`）。這張票提供：
  - 骨架，以及截圖與讀回的輔助。
  - 指令。
  - 一個範例情境：啟動後不動視窗先截一張，搜一次，播一首，進佇列頁讀回順序。

  之後每張票照它寫自己的情境，例如加幾首、開隨機、讀回佇列。
- **零聯網守門**：`integration_test/` 的每個檔都要裝 no-network guard，由 `test/architecture/integration_test_guard_test.dart` 守著。實跑驅動要聯網，放在哪、閘門怎麼不跑到它、守門測試怎麼改，選一種並說明理由。動到 ARCHITECTURE〈測試策略〉的話，先用 AskUserQuestion 給擁有者看草稿。
- **規則寫進 `docs/development.md`**：實跑一律先用這個驅動，平台工具只用在 Flutter 看不到的原生行為：
  - 桌面：拖頂列、雙擊縮放、Snap Layouts、拉邊緣、紅綠燈。用真滑鼠：Windows 是 `SendInput`，macOS 是 CGEvent。
  - 手機：系統手勢、軟鍵盤、系統媒體控制。用 simctl、adb、`orca emulator`，這些不動 Mac 的游標。

  各平台的「實跑」段改成先寫驅動、再列例外。`shot.ps1` 的 `-Click`／`-TypeAt` 留給例外用，或者沒人用就刪掉。
- 截圖照舊要包含「啟動後不動視窗先截一張」（票 05d 的教訓）。integration_test 開視窗時一樣會搶前景，這點不在這張票的範圍。

## 驗收

- [ ] 範例情境在四平台各跑一次，截圖和讀回的文字對得上。跑的過程中 Mac 與 `winpc` 的游標位置不變：跑前、跑後各讀一次游標座標比對，Mac 用 `CGEventGetLocation`、winpc 用 `GetCursorPos`。
- [ ] 完整閘門不跑實跑驅動；零聯網守門照舊擋得住其他沒裝 guard 的 integration_test 檔：手動造一個違規確認會紅，這一步不 commit。
- [ ] `docs/development.md` 的規則與四平台指令已更新；提到實跑方式的其他文件（spec〈共同規則〉、AGENTS.md）一致。
- [ ] 全部檢查綠燈（`dart run tool/check.dart` 完整版）。

## Comments
