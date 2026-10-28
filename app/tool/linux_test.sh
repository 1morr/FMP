#!/usr/bin/env bash
# 在 Mac 上，用 OrbStack 的 x86_64 Ubuntu 跑 app/ 的 flutter test（和 CI 的 ubuntu-latest 同架構）。
# macOS 主機載不到插件執行環境的 QuickJS 與 libisar，完整套件在 Mac 本機跑不起來
# （.trellis/tasks/archive/2026-10/10-24-ui-legacy-parity/research/mac-environment.md）。
#
#   tool/linux_test.sh setup          建立機器、裝 CI 同版的 Flutter（一次）
#   tool/linux_test.sh [參數...]      同步工作區後跑 flutter test [參數...]
#
# 工作區（含未提交的改動）以 rsync 複製到機器自己的檔案系統再跑，不共用 .dart_tool 與 build。
# 副本裡的 app/ios、app/macos 換成 HEAD 的內容：Mac 上建置時 CocoaPods 改的檔案不提交，會讓
# apple_identity_test 變紅。所以改 Xcode 專案的 PR 要先 commit 再用這支跑。
# 機器掛著整個 /Users（可寫），所以副本不帶 .git、對真的 repo 只做 git archive（唯讀）：
# 在 worktree 裡跑時 .git 是指回主 repo 的檔案，在副本裡跑 git checkout 會寫到真的 index。
set -euo pipefail

machine="${FMP_LINUX_MACHINE:-fmp-ci}"
repo="$(cd "$(dirname "$0")/../.." && pwd)"
version="$(sed -n "s/^ *APP_FLUTTER_VERSION: '\(.*\)'.*/\1/p" "$repo/.github/workflows/ci.yml")"
if [ -z "$version" ]; then
  echo "APP_FLUTTER_VERSION not found in .github/workflows/ci.yml" >&2
  exit 1
fi
command -v orb >/dev/null || { echo "OrbStack (orb) is not installed" >&2; exit 1; }

if [ "${1:-}" = "setup" ]; then
  # 不用 grep -q：它一配到就結束，pipefail 下 orb 收到 SIGPIPE 會被當成沒找到。
  if ! orb list -q | grep -x "$machine" >/dev/null; then
    orb create --arch amd64 ubuntu:noble "$machine"
  fi
  orb -m "$machine" bash -s -- "$version" <<'EOF'
set -euo pipefail
version="$1"
sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
  git curl unzip xz-utils zip libglu1-mesa cmake rsync >/dev/null
if [ ! -d ~/flutter ]; then
  git clone -q -b "$version" --depth 1 https://github.com/flutter/flutter.git ~/flutter
  cd ~/flutter
  git remote set-branches origin stable
  git fetch -q --depth 1 origin stable
  git checkout -q -b stable "$version"
  git branch -q --set-upstream-to=origin/stable stable
fi
~/flutter/bin/flutter --disable-analytics >/dev/null 2>&1 || true
~/flutter/bin/flutter --version | sed -n 1p
EOF
  exit 0
fi

orb -m "$machine" bash -s -- "$repo" "$version" "$@" <<'EOF'
set -euo pipefail
repo="$1"; version="$2"; shift 2
export PATH="$HOME/flutter/bin:$PATH"
have="$(flutter --version 2>/dev/null | sed -n 's/^Flutter \([^ ]*\).*/\1/p')"
if [ "$have" != "$version" ]; then
  echo "Flutter $have in the machine, CI uses $version: rerun with 'setup' after removing ~/flutter" >&2
  exit 1
fi
mkdir -p ~/fmp
rsync -a --delete \
  --exclude /.git --exclude /.claude/worktrees/ \
  --exclude build/ --exclude .dart_tool/ --exclude Pods/ \
  "$repo/" ~/fmp/
rm -rf ~/fmp/app/ios ~/fmp/app/macos
git -C "$repo" archive HEAD -- app/ios app/macos | tar -x -C ~/fmp
cd ~/fmp/app
flutter pub get >/dev/null
flutter test "$@"
EOF
