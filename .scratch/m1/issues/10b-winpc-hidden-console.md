# 10b: winpc 跑建置與測試時不跳出主控台視窗

Status: ready-for-agent
Blocked by: None
讀: `app/tool/winpc/run_task.sh`、`build.ps1`、`test.ps1`、`shot.ps1`；`docs/development.md`〈Windows〉與〈實跑驅動〉；spec〈共同規則〉

2026-11-18 協調者插票（擁有者同意）：擁有者在 winpc 上看到，完整閘門與實跑時會跳出 PowerShell 的主控台視窗。來源是 `run_task.sh` 用 `schtasks /IT` 建的排程工作：它在桌面工作階段跑 `powershell.exe -File …`，系統就替它開一個主控台。工作必須在桌面工作階段跑，因為 integration_test 與實跑要開 FMP 視窗，所以這張票只把主控台藏起來，FMP 的視窗照常開。排在 10 之後、11 之前。

## What to build

讓 `run_task.sh` 建的排程工作不顯示主控台。下面幾種做法要查證、實測後選一種，並說明理由：
- `conhost.exe --headless powershell.exe …`：不會閃，要確認 winpc 的 Windows 版本支援。
- `powershell.exe -WindowStyle Hidden`：會閃一下。
- 經 `wscript` 包一層。

要照舊的：
- `build.log`、`test.log`、`shot.log` 的內容。
- `exit <階段>=<退出碼>` 與 `=== done`。
- 排程工作結束的判斷。
- `/TR` 的 261 字上限：加了字之後，情境檔名的長度建議要跟著改。

做完更新 `docs/development.md`〈Windows〉。

## 驗收

- [ ] 持鎖在 winpc 跑一輪 `build.ps1`、一個 integration_test、一個實跑情境：過程中沒有主控台視窗出現。驗證方式是在 winpc 桌面工作階段每 200ms 列一次可見的頂層視窗，比對沒有 `ConsoleWindowClass` 或 PowerShell 視窗，不靠截圖或擁有者目視。三個 log 和以前一樣有 `exit …=0` 與 `=== done`。
- [ ] 排程工作中途失敗時，`run_task.sh` 照樣回非零、log 照樣讀得回：手動造一個會失敗的 ps1 確認，這一步不 commit。
- [ ] 全部檢查綠燈（`dart run tool/check.dart` 完整版）。

## Comments
