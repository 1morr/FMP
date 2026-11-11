#!/usr/bin/env bash
# 實驗用（M0 票 04，重驗 brief 事實 K8）：從 6.2.0-beta 退回 6.1.5 時 pubspec.lock 的殘留。
# 在暫存目錄複製 probe，依序：升到 beta → 改回 6.1.5 並 pub get → 建 macOS（預期失敗）
# → pub upgrade（預期清不掉）→ pub upgrade --unlock-transitive → 再建（預期成功）。不碰裝置，不必持鎖。
#
#   ./lockfile-repro.sh            BETA=6.2.0-beta.3 可換 beta 版本
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
beta=${BETA:-6.2.0-beta.3}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

(cd "$here/probe" && git ls-files -co --exclude-standard . | tar -cf - -T -) | tar -xf - -C "$work"
cd "$work"
versions() {
  python3 -c '
import re
s = open("pubspec.lock").read()
for m in re.finditer(r"  (flutter_inappwebview\w*):\n(?:.*\n)*?    version: \"([^\"]+)\"", s):
    print("   ", m.group(1), m.group(2))'
}

flutter pub add "flutter_inappwebview:$beta" >/dev/null
echo "== after pub add $beta"; versions
sed -i '' 's/flutter_inappwebview: .*/flutter_inappwebview: 6.1.5/' pubspec.yaml
flutter pub get >/dev/null
echo "== back to 6.1.5 with pub get"; versions
if flutter build macos --debug >build1.log 2>&1; then
  echo "== build: OK (the leftover no longer breaks the build)"
else
  echo "== build: FAILED as K8 says; first errors:"
  grep -m3 'Error:' build1.log | sed 's#.*/pub.dev/#    #' || tail -20 build1.log
fi
flutter pub upgrade flutter_inappwebview >/dev/null
echo "== after pub upgrade flutter_inappwebview (without --unlock-transitive)"; versions
flutter pub upgrade --unlock-transitive flutter_inappwebview >/dev/null
echo "== after pub upgrade --unlock-transitive flutter_inappwebview"; versions
if flutter build macos --debug >build2.log 2>&1; then echo "== build: OK"; else echo "== build: FAILED"; tail -20 build2.log; exit 1; fi
