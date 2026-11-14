# 02: 依賴漏洞

Status: ready-for-agent
Blocked by: None
讀: spec〈共同規則〉；docs/development.md〈閘門〉〈開發環境與閘門〉

## What to build

新版用到的套件有已知漏洞時，閘門要擋下來。用 osv-scanner 一次掃 `app/pubspec.lock` 與 `app/plugins/package-lock.json`，接進 `dart run tool/check.dart` 完整版（要連網，不放 `--quick`）。現在就有的漏洞逐條看：能升級的升級，不能的寫進 osv-scanner 的忽略設定並附理由與到期日。

## 驗收

- [ ] 完整版多一步依賴漏洞掃描，涵蓋兩個 lockfile，現在的 repo 上是綠的（或每條忽略都有理由與到期日）。
- [ ] 把一個套件暫時改成有已知漏洞的版本時這一步會紅，還原後綠。
- [ ] 找不到 osv-scanner 時，這一步失敗並印出安裝指令。
- [ ] `docs/development.md`〈閘門〉的「依賴漏洞」換成指令或設定檔，「環境」記 osv-scanner 版本。
- [ ] 全部檢查綠燈（`dart run tool/check.dart` 完整版）。

## Comments
