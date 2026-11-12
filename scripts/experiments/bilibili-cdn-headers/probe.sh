#!/usr/bin/env bash
# 重驗 brief 事實 M5 的「B 站 CDN 回的 Content-Type」與 F4 的「媒體 CDN 要
# Referer」（M0 票 11）。匿名，共 5 個請求：pagelist、playurl（同 bilibili
# 插件的 resolveStream，事實 F21），再對選到的音訊網址各發一次帶 Referer、
# 不帶 Referer、帶 Referer 加 AVPlayer 的 User-Agent 的 1 KB Range 請求，只印狀態與回應 header，不印網址的 query。
#
# 用法：scripts/experiments/bilibili-cdn-headers/probe.sh [bvid]
set -euo pipefail

bvid="${1:-BV1xx411c7mD}"
ua='Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36'
uuid=$(uuidgen | tr a-f A-F)
cookie="buvid3=${uuid}infoc; buvid4=${uuid}; b_nut=$(date +%s); _uuid=${uuid}; buvid_fp=${uuid}"
api() {
  curl -sS --compressed -A "$ua" -H 'Referer: https://www.bilibili.com/' \
    -H 'Origin: https://www.bilibili.com' -b "$cookie" "$1"
}

cid=$(api "https://api.bilibili.com/x/player/pagelist?bvid=$bvid" |
  python3 -c 'import json,sys; print(json.load(sys.stdin)["data"][0]["cid"])')
url=$(api "https://api.bilibili.com/x/player/playurl?bvid=$bvid&cid=$cid&fnval=16" |
  python3 -c '
import json, sys
audio = json.load(sys.stdin)["data"]["dash"]["audio"]
print(max(audio, key=lambda a: a["bandwidth"])["baseUrl"])')
echo "cdn: $(python3 -c 'import sys, urllib.parse as u; p = u.urlsplit(sys.argv[1]); print(p.scheme + "://" + p.netloc + p.path)' "$url")"

probe() {
  echo "--- $1"
  shift
  curl -sS -o /dev/null -D - -A "$ua" -r 0-1023 "$@" "$url" |
    grep -iE '^(HTTP/|content-type|content-range|content-length|accept-ranges)' |
    tr -d '\r'
}
probe 'with Referer: https://www.bilibili.com' -H 'Referer: https://www.bilibili.com'
probe 'without Referer'
probe 'with Referer, AVPlayer-like User-Agent' -H 'Referer: https://www.bilibili.com' \
  -A 'AppleCoreMedia/1.0.0.23A341 (iPhone; U; CPU OS 27_1 like Mac OS X; zh_tw)'
