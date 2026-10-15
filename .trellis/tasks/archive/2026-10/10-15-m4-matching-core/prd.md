# M4 PR 16 匹配核心與繁簡字表

> M4 的 PR 16（`../10-15-m4-library-sync/implement.md` § 16；M4b，但計畫允許在 M4a 期間先做）。設計在 `../10-15-m4-library-sync/design.md` §8.1、§8.2、§2.2（`externalPackageOwners`）；決定在 ADR 0019 §決定 6 與 M4 的更正（繁簡改用 OpenCC 字表的純 Dart 對照，§17 第 1 條）。

## 做什麼

- 依賴：`unorm_dart`、`string_similarity`（加之前到 pub.dev API 核對 `latest` stable；與 design §15 不同時在回報說明）；`fmp_layer_imports` 的 `externalPackageOwners` 把兩者歸給 `lib/core/matching/`（雙向變異測試、`tool/lint_sentinel.dart`、`app/AGENTS.md` § Lint 表）。
- `lib/core/matching/`（純函式，不 import `data/`、`plugins/`）：正規化（NFKC → 小寫 → 繁簡 → 去裝飾標點與空白 → 括號內容另比）、標題分、歌手分、時長門檻與分數、總分、`score`、`rank`（穩定排序），照 design §8.1。權重與門檻以手寫語料校準後寫死。
- **繁簡字表**：`app/tool/opencc/TSCharacters.txt`（OpenCC `data/dictionary/TSCharacters.txt`，釘開工當天 `master` 的 commit，檔頭註明來源網址、commit、Apache-2.0）、同目錄放 OpenCC 的 `LICENSE`（有 `NOTICE` 一併放）；`app/tool/opencc/generate_ts_characters.dart` 產生 `lib/core/matching/ts_characters.g.dart`（`const Map<int, int>`、產生檔頭寫來源 commit）；授權全文一併輸出成常數。
- `lib/app/licenses.dart`：啟動時以 `LicenseRegistry.addLicense` 登記 OpenCC 的 Apache-2.0。
- 文件：`app/AGENTS.md`（§ Lint、新的匹配一節：只寫查不到的契約與閘門）、相關 spec。

## 驗收

- 測試：ADR 0019 §如何確認的評分案例（全半形、繁簡、括號、時長門檻、多歌手；自動與手動重搜同分）；語料（約 50 對，手寫，真實的公開歌名與上傳標題，不連網）全綠；重新產生的字表等於已提交的；已知字對（`週→周`、`倫→伦`、`乾→干`、`著→着`）與簡體字不變；授權登記含 `OpenCC` 與 `Apache License`；lint 雙向變異。
- `dart format`、`dart analyze --fatal-infos`、`flutter analyze`、`flutter test`；`packages/fmp_lints/` 的 `dart test`；`dart run tool/lint_sentinel.dart`。
- 沒有使用者看得到的改動：不做實機驗證。
