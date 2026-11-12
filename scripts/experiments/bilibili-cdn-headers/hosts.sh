#!/usr/bin/env bash
# 票 11 的 403 調查：B 站 playurl 給的主網址與 backupUrl 是不是不同 CDN、各自
# 檢不檢查 User-Agent 與 Referer。匿名，1 次 pagelist、1 次 playurl，再對最高
# 頻寬音訊軌的每個網址各發 4 個 1 KB Range 請求；只印主機與狀態。
#
# 用法：scripts/experiments/bilibili-cdn-headers/hosts.sh [bvid]
set -euo pipefail

bvid="${1:-BV1xx411c7mD}"
browser='Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36'
exo='just_audio/1 (Linux;Android 17) ExoPlayerLib/1.4.1'
coremedia='AppleCoreMedia/1.0.0.23A341 (iPhone; U; CPU OS 27_1 like Mac OS X; zh_tw)'
uuid=$(uuidgen | tr a-f A-F)
cookie="buvid3=${uuid}infoc; buvid4=${uuid}; b_nut=$(date +%s); _uuid=${uuid}; buvid_fp=${uuid}"
api() {
  curl -sS --compressed -A "$browser" -H 'Referer: https://www.bilibili.com/' \
    -H 'Origin: https://www.bilibili.com' -b "$cookie" "$1"
}
cid=$(api "https://api.bilibili.com/x/player/pagelist?bvid=$bvid" |
  python3 -c 'import json,sys; print(json.load(sys.stdin)["data"][0]["cid"])')
api "https://api.bilibili.com/x/player/playurl?bvid=$bvid&cid=$cid&fnval=16" |
  python3 -c '
import json, sys
audio = max(json.load(sys.stdin)["data"]["dash"]["audio"], key=lambda a: a["bandwidth"])
for u in [audio["baseUrl"], *(audio.get("backupUrl") or [])]:
    print(u)' |
  while read -r url; do
    echo "== $(python3 -c 'import sys, urllib.parse as u; print(u.urlsplit(sys.argv[1]).netloc)' "$url")"
    for case in "referer+exo|$exo|1" "referer+coremedia|$coremedia|1" "referer+browser|$browser|1" "browser, no referer|$browser|0"; do
      IFS='|' read -r name ua ref <<<"$case"
      args=(-sS -o /dev/null -w '%{http_code}' -A "$ua" -r 0-1023)
      [[ $ref == 1 ]] && args+=(-H 'Referer: https://www.bilibili.com')
      echo "  $name: $(curl "${args[@]}" "$url")"
    done
  done
