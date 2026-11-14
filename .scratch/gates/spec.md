# gates 閘門補齊

不是里程碑的工作，2026-11-15 同步 project-init 時開出。`docs/development.md`〈閘門〉裡新版缺的三列各一張票；排在 M1 之後（roadmap 里程碑表）。

## 目標

新版（`app/`）補上密鑰掃描、依賴漏洞與依賴更新三道閘門。做完時〈閘門〉表的每一列都是指令或設定檔，沒有「待定」。

## 範圍

### 做

- 密鑰掃描：每次 commit 都掃（含只改舊版的 commit），完整閘門也掃。
- 依賴漏洞：掃 `app/pubspec.lock` 與 `app/plugins/package-lock.json`，接進完整閘門。
- 依賴更新：Dependabot 涵蓋 `app/`（pub）與 `app/plugins/`（npm）。

### 不做

- 新版的 GitHub Actions（`app-release.yml` 是 M5 的事）。
- 舊版（根目錄）的依賴與它的 Dependabot 設定，除了加新條目時不能弄壞舊版的測試。

## 共同規則

- **工具**：照 `AGENTS.md`〈事實與查證〉查當前 stable 的用法再寫指令，版本與安裝方式寫進 `docs/development.md`〈開發環境與閘門〉的「環境」。
- **缺工具不靜默跳過**：hook 或閘門找不到工具時失敗，並印出安裝指令。
- **閘門表**：每張票做完，把〈閘門〉表裡自己那一列的「待定」換成指令或設定檔，〈開發環境與閘門〉補上跑在哪一步。
- **舊版不受影響**：舊版的 `ci.yml` 照舊要綠，`test/workflows/` 的測試照舊要過。

## 驗收

### Agent 驗

- 〈閘門〉表沒有「待定」，`python3 scripts/check_docs.py` 通過。
- 每道新閘門各造一次違規（假的 token、有已知漏洞的版本），證明它會紅；還原後綠。

### 使用者試

無：三道都是開發用的閘門，使用者拿到的 App 沒有改動。

## 票序

1. `01-secret-scan`：密鑰掃描。
2. `02-dependency-audit`：依賴漏洞。
3. `03-dependency-updates`：依賴更新。

三張互不阻擋，可以平行。
