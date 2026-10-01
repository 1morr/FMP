# sandbox 實跑計畫（PR 13b 做什麼 §4）

目的：在私人 repo `1morr/fmp-release-sandbox` 用臨時金鑰把 `app-release.yml` 完整跑一次
（擁有者決定 4），證明 FMP 裡的同一份 workflow 在 M9 加上 push 觸發後能發版。結果寫進
`research/sandbox-run.md`。

前提：本分支的改動已經 commit（sandbox 推的是 commit，不是工作目錄）。

## 1. 建 repo 與設定

```sh
gh repo create 1morr/fmp-release-sandbox --private --disable-wiki
# 發版 PR 由 GITHUB_TOKEN 開，要允許 Actions 建 PR；預設權限維持唯讀，
# workflow 的每個 job 自己宣告 permissions。
gh api -X PUT repos/1morr/fmp-release-sandbox/actions/permissions/workflow \
  -f default_workflow_permissions=read -F can_approve_pull_request_reviews=true
```

## 2. 臨時金鑰與 secrets

在 repo 以外的暫存目錄做，用完刪檔；密碼只用英數字（寫進 Java properties，`\` 會被當成跳脫）。

```sh
tmp="$(mktemp -d)"
pw="$(head -c 32 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 24)"
keytool -genkeypair -keystore "$tmp/sandbox.keystore" -storetype PKCS12 \
  -alias sandbox -keyalg RSA -keysize 2048 -validity 7 \
  -dname "CN=FMP Release Sandbox" -storepass "$pw" -keypass "$pw"
# 記下憑證的 SHA-256（不是秘密），之後核對 APK 的簽名者
keytool -list -v -keystore "$tmp/sandbox.keystore" -storepass "$pw" | grep 'SHA256:'
base64 -w0 "$tmp/sandbox.keystore" | gh secret set KEYSTORE_BASE64 -R 1morr/fmp-release-sandbox
printf '%s' "$pw" | gh secret set KEYSTORE_PASSWORD -R 1morr/fmp-release-sandbox
printf '%s' "$pw" | gh secret set KEY_PASSWORD -R 1morr/fmp-release-sandbox
printf '%s' sandbox | gh secret set KEY_ALIAS -R 1morr/fmp-release-sandbox
rm -rf "$tmp"; unset pw
```

Windows 的 Git Bash 沒有 `base64 -w0` 時用 `base64 | tr -d '\n'`。

## 3. 推入內容（兩個 sandbox 專屬 commit）

```sh
git switch -c sandbox feat/app-release-workflow
git remote add sandbox https://github.com/1morr/fmp-release-sandbox.git
```

**commit A**：刪掉 `.github/workflows/ci.yml` 與 `release.yml`（私人 repo 的 Actions 分鐘數要算，
ci.yml 的 macOS job 是 10 倍計費；release.yml 在 sandbox 用不到），以及 `.github/dependabot.yml`
（不然 sandbox 封存前每週會收到 Dependabot 的 PR）。訊息例：
`chore: drop workflows the sandbox does not run`。推上去：`git push sandbox sandbox:main`
（完整歷史、不帶 tag；`bootstrap-sha` 1857fa4b 因此存在）。這時沒有 workflow 會跑。

**模擬舊版的 release**（讓 sandbox 像 FMP：release-please 要略過 v1.x，publish 的
`--latest` 要把 latest 從 v1.11.0 換成 v2.0.0）：

```sh
gh release create v1.11.0 -R 1morr/fmp-release-sandbox \
  --target 1857fa4b0f8c93a706d6b1df05121c01a880ca14 --title v1.11.0 --notes "legacy stand-in"
```

**commit B**：`.github/workflows/app-release.yml` 只改觸發條件，其他一個字都不動：

```yaml
on:
  workflow_dispatch:
  push:
    branches: [main]
```

訊息例：`ci: trigger the app release on push to main`（`ci:` 不進 CHANGELOG）。
`git push sandbox sandbox:main`。

## 4. 跑與核對

1. **commit B 觸發的 run**：`release-please` job 成功並開出發版 PR；其他四個 job 都是 skipped
   （證明「輸出為否時不建置」）。發版 PR 應該：
   - 標題含 2.0.0（`release-as`），標籤 `autorelease: pending`；
   - 只改 `app/pubspec.yaml`（`version: 2.0.0`，沒有 `+`）、新建 `app/CHANGELOG.md`、
     `.release-please-manifest.json`（`"app": "2.0.0"`）；
   - CHANGELOG 只收 1857fa4b 之後動到 `app/` 的 commit，沒有 commit A、B。
2. **合併發版 PR**（merge commit，同 FMP）。觸發的 run 應該：
   - release-please 建 tag `v2.0.0` 與草稿 release（run 中途到 Releases 頁看得到草稿）；
   - build-android、build-windows、verify、publish 全部成功；
   - 結束後 v2.0.0 不是草稿、是 latest，body 是 CHANGELOG 的 2.0.0 段落。
3. **再手動觸發一次**（`gh workflow run app-release.yml -R 1morr/fmp-release-sandbox --ref main`）：
   沒有新 PR、沒有新 release，建置以後的 job 全部 skipped。
4. **下載發佈物核對**（不安裝、不執行任何 prod 產物）：

   ```sh
   gh release download v2.0.0 -R 1morr/fmp-release-sandbox -D assets
   cd assets && ls                      # 11 個檔，名稱照 ADR 0022 §決定 3
   sha256sum -c fmp-v2.0.0-checksums.sha256
   for s in android-arm64-v8a.apk android-universal.apk windows.zip windows-installer.exe; do
     cmp "fmp-v2.0.0-$s" "fmp-latest-$s"; done
   apksigner verify --print-certs fmp-v2.0.0-android-universal.apk   # SHA-256 = 步驟 2 記下的
   aapt2 dump badging fmp-v2.0.0-android-arm64-v8a.apk | head -1     # com.personal.fmp、2000000、2.0.0
   unzip -Z1 fmp-v2.0.0-windows.zip | grep -E '^(fmp.exe|vcruntime140.dll)$'
   gh api repos/1morr/fmp-release-sandbox/releases/latest --jq '.tag_name, (.assets[] | .name + " " + .digest)'
   ```
5. 記錄：兩個 run 的連結、各 job 時間（`gh run view <id> --json jobs --jq '.jobs[] | .name + " " + .startedAt + " " + .completedAt'`）、
   發佈物清單與 digest、遇到的問題與修正。研究檔與 PR 描述不放金鑰、密碼或個人路徑。

## 5. 收尾

```sh
gh repo archive 1morr/fmp-release-sandbox --yes
git switch feat/app-release-workflow && git branch -D sandbox && git remote remove sandbox
```

sandbox 裡為了修 workflow 而改的東西要回到本分支（sandbox 專屬的只有 commit A、B）。

## sandbox 證明不了的

- **正式金鑰**：APK 以臨時金鑰簽，與舊版同一把金鑰簽出來、v1.11.0 在 App 內實際升到 2.0.0
  （Android、Windows 安裝版與免安裝版）是 ADR 0022 §如何確認的「延後實測」，切換 PR 前做。
- **FMP 的 `main` ruleset**：必要檢查 `CI Result`。發版 PR 由 `GITHUB_TOKEN` 開，GitHub 不會為它
  觸發 `ci.yml`，必要檢查永遠等不到結果，M9 合不了發版 PR（除非以管理員略過）。M9 要決定：
  release-please 改用 GitHub App／PAT 的 token，或允許略過。sandbox 沒有 ruleset，看不到這個問題。
- **FMP 的 repo 設定**：「允許 Actions 建 PR」在 FMP 還沒開，M9 開自動觸發時一起開。
- **真正的舊版 release 與 tag**：sandbox 只有一個沒有 asset 的 v1.11.0 替身。
- **SmartScreen、Mark of the Web、真實安裝**：不安裝 prod 產物，安裝檔只驗 PE 標頭。
- **失敗後的補救**（草稿留著、修好後下一個 patch 版照常發）：依 release-please 的行為推論，這次
  不實測；想測可以在合併發版 PR 前把某個 secret 刪掉，讓 build-android 失敗再補回重跑。
