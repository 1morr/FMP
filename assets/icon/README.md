# App 圖示資源

此目錄保存 FMP 的應用圖示來源檔，供 Flutter launcher icon 與 Windows 安裝包使用。

## 目前檔案

| 檔案 | 用途 |
|------|------|
| `app_icon.png` | Flutter launcher icon 的主要來源圖 |
| `app_icon_bg.png` | README 與展示用圖示 |

## 更新圖示

圖示建議使用 PNG、sRGB 色彩空間，來源尺寸至少 `1024 x 1024`。替換圖示後執行：

```bash
flutter pub get
dart run flutter_launcher_icons
```

如果 Windows 安裝包圖示也有變更，請確認 `windows/runner/resources/app_icon.ico` 與 Release 產物同步更新。
