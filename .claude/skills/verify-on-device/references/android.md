# Android 模擬器

驗證 dev flavor：applicationId `com.personal.fmp.dev`、activity `com.personal.fmp.MainActivity`。
**不要碰 `com.personal.fmp`**（舊版，模擬器上有它的測試資料），也不要安裝 prod APK。

## 模擬器

```bash
"$ANDROID_HOME/emulator/emulator.exe" -list-avds
```

以分離的程序啟動（放在會結束的背景工作裡，模擬器會被一起關掉）：

```powershell
Start-Process -FilePath "$env:ANDROID_HOME\emulator\emulator.exe" -ArgumentList "-avd","<AVD>" -PassThru
```

```bash
adb wait-for-device shell 'while [[ -z $(getprop sys.boot_completed) ]]; do sleep 1; done; echo BOOTED'
```

`-no-audio` 啟動的模擬器不輸出聲音，回報要寫明；看播放改用 log 與 `dumpsys`。模擬器的音訊跑得
比實際時間快（約 1.7 倍），不要拿它的數字當播放時長或交接間隙的實測。

## 建置、安裝、啟動

在 `app/`：

```bash
flutter build apk --flavor dev --debug
adb install -r build/app/outputs/flutter-apk/app-dev-debug.apk
adb shell am start -n com.personal.fmp.dev/com.personal.fmp.MainActivity
```

### 帶開發入口的參數

dev 入口（`--fmp-dev-plugin=`、`--fmp-dev-playback`，見 `runtime-state.md`）以 intent extra
`dart_entrypoint_args` 傳進來。`--esal` 的值是**以逗號分隔的陣列**，所以多個參數用逗號接起來，
參數值本身不能含逗號：

```bash
MSYS_NO_PATHCONV=1 adb shell am start -n com.personal.fmp.dev/com.personal.fmp.MainActivity \
  --esal dart_entrypoint_args --fmp-dev-playback
```

用 `--fmp-dev-plugin=` 時，App 要讀得到插件檔：先推到 `/data/local/tmp`（App 讀不到），再以
`run-as` 複製進 App 的私有目錄：

```bash
MSYS_NO_PATHCONV=1 adb push <插件.js 的本機路徑> /data/local/tmp/x.js
MSYS_NO_PATHCONV=1 adb shell "run-as com.personal.fmp.dev sh -c 'mkdir -p files && cp /data/local/tmp/x.js files/x.js'"
MSYS_NO_PATHCONV=1 adb shell rm /data/local/tmp/x.js
MSYS_NO_PATHCONV=1 adb shell am start -n com.personal.fmp.dev/com.personal.fmp.MainActivity \
  --esal dart_entrypoint_args --fmp-dev-plugin=/data/data/com.personal.fmp.dev/files/x.js,--fmp-dev-playback=bilibili:<BV 號>
```

用 `adb shell mkdir` 建的目錄屬於 `shell`，App 寫不進去（`errno = 13`）；一律用 `run-as`。
要重新帶參數，先 `adb shell am force-stop com.personal.fmp.dev`（只停 dev）。

## 觀察

- **語意樹**：`PYTHONIOENCODING=utf-8 python .claude/skills/verify-on-device/scripts/ax_flatten.py --limit 30`。
  預設經 `orca emulator ax`；沒有 Orca 時加 `--adb`，改讀
  `adb exec-out uiautomator dump /dev/tty`（直接輸出到 stdout，裝置上不留檔）。Flutter 的語意經
  uiautomator 變成節點：多數文字在 `content-desc`，少數（例如身分頁的資料目錄）在 `text`，
  腳本兩個都讀。`norm=` 餵 `orca emulator tap <x> <y>`，`center=` 餵 `adb shell input tap <x> <y>`。
- **log**：`adb logcat -s flutter`（debug build 的 console log）。結構化的 log 在 App 的
  `files/logs/fmp.jsonl`：`adb shell run-as com.personal.fmp.dev cat files/logs/fmp.jsonl`。
- **截圖**：`adb exec-out screencap -p > <檔>`，存到 session 暫存目錄，不進 repo；貼進回報前確認不含
  個人資訊。`orca screenshot` 回傳內嵌 base64，很耗 context。
- **音訊焦點**（改播放或後端時）：播放中與交接前後重複下面這條，最新一筆一直是
  `requestAudioFocus`、沒有 abandon 後又重新 request；`dumpsys audio` 的 `Audio Focus stack`
  最上面是 `com.personal.fmp.dev`（`AUDIOFOCUS_GAIN`）。播完之後焦點仍在（just_audio 不主動放）：

  ```bash
  PID=$(adb shell pidof com.personal.fmp.dev)
  adb shell dumpsys audio | grep -E "(request|abandon)AudioFocus\(\) from uid/pid [0-9]+/$PID "
  ```

## 陷阱

- 首次點進文字欄位時 Gboard 的教學可能搶走 `adb shell input text`，預設語言也可能是注音而不提交字元；
  截圖確認後切英文再打。
- `adb shell input text` 不能輸入中日韓文字；中文輸入用 `integration_test` 的 `enterText`。
- 根路由按 Back 會結束 App；要放背景用 `adb shell input keyevent 3`（HOME）。
- `force-stop` 會讓 `flutter run` 斷線（之後熱重載按鍵全部無聲無效）；要冷啟動就關掉那個 run 重開。
- 模擬器卡死（畫面不動、`ax` 是 0 個節點）時，以 `-no-snapshot-load` 重開。
- 模擬器的 DNS 不快取，第一次連線多約 1 秒；測錯誤路徑關網路：
  `adb shell svc wifi disable && adb shell svc data disable`（驗完開回來）。
