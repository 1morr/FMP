#!/usr/bin/env python3
# 產生 iOS 的 App 圖示（ADR 0037 §決定 4）：iOS 要 1024 的不透明方圖，圓角由系統裁，所以不畫圓角與陰影；
# 白底上放 FMP 的圖示來源，大小比例同 macOS 的圖示（824/1024）。輸出單一尺寸的 AppIcon.appiconset
# （Xcode 14 起支援）：`Icon-App-1024x1024@1x.png` 與 `Contents.json`，舊的多尺寸檔刪掉。要 Pillow。
#
#   python3 tool/make_ios_icon.py ../assets/icon/app_icon.png ios/Runner/Assets.xcassets/AppIcon.appiconset
import json
import os
import sys
from PIL import Image

src, out_dir = sys.argv[1], sys.argv[2]
canvas, box = 1024, 824
off = (canvas - box) // 2
base = Image.new('RGBA', (canvas, canvas), (255, 255, 255, 255))
glyph = Image.open(src).convert('RGBA').resize((box, box), Image.LANCZOS)
base.alpha_composite(glyph, (off, off))
name = 'Icon-App-1024x1024@1x.png'
for old in os.listdir(out_dir):
    if old.endswith('.png') and old != name:
        os.remove(os.path.join(out_dir, old))
base.convert('RGB').save(os.path.join(out_dir, name), optimize=True)  # RGB：沒有 alpha 通道，App Store 與系統都要求
contents = {
    'images': [{'filename': name, 'idiom': 'universal', 'platform': 'ios', 'size': '1024x1024'}],
    'info': {'author': 'xcode', 'version': 1},
}
with open(os.path.join(out_dir, 'Contents.json'), 'w') as f:
    json.dump(contents, f, indent=2)
    f.write('\n')
