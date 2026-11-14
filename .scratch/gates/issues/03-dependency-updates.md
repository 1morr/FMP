# 03: 依賴更新

Status: ready-for-agent
Blocked by: None
讀: spec〈共同規則〉；docs/development.md〈閘門〉

## What to build

`.github/dependabot.yml` 現在只管舊版的根目錄與 GitHub Actions，新版的依賴沒人提醒更新。加兩個條目：`/app`（pub）與 `/app/plugins`（npm），每週一次。分組照舊版條目已經踩過的坑：0.x 的直接依賴不併進 minor-and-patch 群組（Dependabot 把 0.9 → 0.10 當 minor，pub 當破壞性變更）。舊版的 `test/workflows/dependabot_group_static_rule_test.dart` 會讀這個檔，加條目後它要照樣過；它只該檢查舊版的條目。push 之後 Dependabot 會在 repo 開 PR，push 前照 `AGENTS.md`〈擁有者確認〉先問擁有者。

## 驗收

- [ ] `dependabot.yml` 有 `/app`（pub）與 `/app/plugins`（npm）兩個條目，`app/pubspec.yaml` 裡 0.x 的直接依賴都排除在 minor-and-patch 群組外。
- [ ] 新條目漏了一個 0.x 的直接依賴時，有一條測試會紅（新寫的，放在 `app/test/` 或 `scripts/tests/`）。
- [ ] 舊版的 `flutter test test/workflows/` 照樣通過。
- [ ] `docs/development.md`〈閘門〉的「依賴更新」換成 `.github/dependabot.yml`。
- [ ] 全部檢查綠燈（`dart run tool/check.dart` 完整版）。

## Comments
