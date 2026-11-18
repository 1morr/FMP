#!/usr/bin/env bash
# 票 06b：產生 app/test/support/fragment_template.dart，整合測試合成「像 B 站
# 音訊軌的單檔 fragmented MP4」用的範本：init（ftyp、moov）加一段 5 秒的
# moof＋mdat，內容是 −80 dB 的雜訊（聽不到，但 AAC 照樣花位元，複製出來的
# 檔才夠大，事實 M14 的截短要檔夠大才重現）。要 ffmpeg 與 Python 3。
#
# 用法：scripts/experiments/bilibili-m4s-duration/make_fragment_template.sh
set -euo pipefail
repo=$(git rev-parse --show-toplevel)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
ffmpeg -v error -y -f lavfi -i 'aevalsrc=0.0001*(random(0)*2-1):s=48000:d=12' \
  -ac 1 -c:a aac -b:a 16k -f mp4 \
  -movflags +dash+global_sidx+frag_keyframe -frag_duration 5000000 "$tmp/t.m4s"
python3 - "$tmp/t.m4s" "$repo/app/test/support/fragment_template.dart" <<'PY'
import base64, struct, sys, textwrap
b = open(sys.argv[1], 'rb').read()
off, out, fragments = 0, b'', 0
while off < len(b):
    size, kind = struct.unpack('>I4s', b[off:off + 8])
    kind = kind.decode()
    if kind in ('ftyp', 'moov', 'sidx'):
        out += b[off:off + size]
    if kind == 'moof':
        fragments += 1
    if fragments == 1 and kind in ('moof', 'mdat'):
        out += b[off:off + size]
    off += size
lines = textwrap.wrap(base64.b64encode(out).decode(), 76)
dart = ["// 由 scripts/experiments/bilibili-m4s-duration/make_fragment_template.sh 產生，",
        "// 不要手改。單檔 fragmented MP4 的範本：ftyp、moov、sidx 與第一段 moof＋mdat",
        "// （48 kHz 單聲道 AAC，16 kbps，−80 dB 雜訊，5 秒一段）。",
        "const fragmentTemplateBase64 ="]
dart += [f"    '{l}'" for l in lines[:-1]] + [f"    '{lines[-1]}';"]
open(sys.argv[2], 'w').write('\n'.join(dart) + '\n')
print(f'{len(out)} bytes')
PY
