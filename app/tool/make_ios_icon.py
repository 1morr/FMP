#!/usr/bin/env python3
# 產生 iOS 的 App 圖示（ADR 0037 §決定 4）：iOS 要 1024 的不透明方圖，圓角由系統裁，所以不畫圓角與陰影；
# 白底上放 FMP 的圖示來源，大小比例同 macOS 的圖示（824/1024）。輸出單一尺寸的 AppIcon.appiconset
# （Xcode 14 起支援）：`Icon-App-1024x1024@1x.png` 與 `Contents.json`，舊的多尺寸檔刪掉。
#
# 第三個參數是啟動畫面的 `LaunchImage.imageset`（`LaunchScreen.storyboard` 在 `systemBackgroundColor` 上置中放它）：
# 圖示來源的字形（去掉透明邊）縮成 96pt，1x／2x／3x 各一張。來源字形是黑色，深色模式的底是黑的，所以另產一組
# 白色字形（同形狀）放進 `appearances: luminosity: dark`。要 Pillow。
#
#   python3 tool/make_ios_icon.py ../assets/icon/app_icon.png ios/Runner/Assets.xcassets/AppIcon.appiconset \
#       ios/Runner/Assets.xcassets/LaunchImage.imageset
import json
import os
import sys
from PIL import Image

src, out_dir, launch_dir = sys.argv[1], sys.argv[2], sys.argv[3]
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

# 啟動畫面：字形裁掉透明邊，縮成 96pt 見方（來源字形近似正方）。
LAUNCH_PT = 96
art = Image.open(src).convert('RGBA')
art = art.crop(art.getchannel('A').getbbox())
side = max(art.size)
square = Image.new('RGBA', (side, side), (0, 0, 0, 0))
square.alpha_composite(art, ((side - art.width) // 2, (side - art.height) // 2))
white = Image.new('RGBA', square.size, (255, 255, 255, 255))
white.putalpha(square.getchannel('A'))
for old in os.listdir(launch_dir):
    if old.endswith('.png'):
        os.remove(os.path.join(launch_dir, old))
images = []
for scale in (1, 2, 3):
    px = LAUNCH_PT * scale
    for variant, glyph in (('', square), ('-dark', white)):
        fname = f'LaunchImage{variant}@{scale}x.png'
        glyph.resize((px, px), Image.LANCZOS).save(os.path.join(launch_dir, fname), optimize=True)
        entry = {'filename': fname, 'idiom': 'universal', 'scale': f'{scale}x'}
        if variant:
            entry['appearances'] = [{'appearance': 'luminosity', 'value': 'dark'}]
        images.append(entry)
with open(os.path.join(launch_dir, 'Contents.json'), 'w') as f:
    json.dump({'images': images, 'info': {'author': 'xcode', 'version': 1}}, f, indent=2)
    f.write('\n')
