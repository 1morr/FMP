#!/usr/bin/env python3
# 產生 macOS 的 App 圖示（ADR 0036）：以 Apple 的 macOS 圖示格線（1024 畫布、824 圓角矩形、圓角約 185、
# 淡陰影）把 FMP 的圖示來源放在白底圓角矩形上，輸出 AppIcon.appiconset 的七個尺寸。要 Pillow。
#
#   python3 tool/make_macos_icon.py ../assets/icon/app_icon.png macos/Runner/Assets.xcassets/AppIcon.appiconset
import sys
from PIL import Image, ImageDraw, ImageFilter
src, out_dir = sys.argv[1], sys.argv[2]
S = 4  # 超取樣，圓角邊緣才平滑
canvas, box, radius = 1024 * S, 824 * S, 185 * S
off = (canvas - box) // 2
base = Image.new('RGBA', (canvas, canvas), (0, 0, 0, 0))
# 淡陰影（同 Apple 範本：往下、柔和）
shadow = Image.new('RGBA', (canvas, canvas), (0, 0, 0, 0))
ImageDraw.Draw(shadow).rounded_rectangle((off, off + 10 * S, off + box, off + box + 10 * S), radius, fill=(0, 0, 0, 70))
shadow = shadow.filter(ImageFilter.GaussianBlur(14 * S))
base.alpha_composite(shadow)
ImageDraw.Draw(base).rounded_rectangle((off, off, off + box, off + box), radius, fill=(255, 255, 255, 255))
glyph = Image.open(src).convert('RGBA').resize((box, box), Image.LANCZOS)
base.alpha_composite(glyph, (off, off))
master = base.resize((1024, 1024), Image.LANCZOS)
for size in (16, 32, 64, 128, 256, 512, 1024):
    master.resize((size, size), Image.LANCZOS).save(f'{out_dir}/app_icon_{size}.png', optimize=True)
