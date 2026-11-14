# 01: 密鑰掃描

Status: ready-for-agent
Blocked by: None
讀: spec〈共同規則〉；docs/development.md〈閘門〉〈開發環境與閘門〉

## What to build

repo 是公開的，token、cookie、密碼一旦 commit 進去就等於外流。用 gitleaks 在每次 commit 前掃 staged 的改動（含只改舊版的 commit），完整閘門再掃一次整個工作樹。`.githooks/pre-commit` 現在只改舊版時會提早結束，掃描要放在那之前。fixture 裡照 `AGENTS.md`〈公開 repo〉遮成 `***` 的值、公開的請求簽名不該被當成密鑰；誤報用 gitleaks 的設定檔排除，不關掉整條規則。

## 驗收

- [ ] `.githooks/pre-commit` 每次 commit 都跑 gitleaks；staged 一個假的 token 時 commit 被擋，拿掉後放行。
- [ ] `dart run tool/check.dart` 完整版多一步密鑰掃描，現在的 repo 上是綠的。
- [ ] 找不到 gitleaks 時，hook 與閘門都失敗並印出安裝指令。
- [ ] `docs/development.md`〈閘門〉的「密鑰掃描」換成指令或設定檔，「環境」記 gitleaks 版本。
- [ ] 全部檢查綠燈（`dart run tool/check.dart` 完整版）。

## Comments
