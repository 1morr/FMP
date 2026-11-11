#!/usr/bin/env bash
# 實驗用：經輔助使用 API 讀與操作 macOS 選單列的「正在播放」面板（macOS 27）。
#
#   ./np-panel.sh open                 打開面板（選單列的 com.apple.menuextra.now-playing）
#   ./np-panel.sh state                印出面板內容：文字、按鈕、進度條、有沒有封面
#   ./np-panel.sh press <previous|toggle|next>
#   ./np-panel.sh seek <秒>            設定進度條的值
#   ./np-panel.sh shot <檔案.png>      截面板那一塊（需要「螢幕錄製」權限）
#   ./np-panel.sh close
#
# macOS 15.4 起第三方讀不到 MediaRemote 的 Now Playing（事實 M9），但面板本身是
# ControlCenter 的視窗，呼叫端有「輔助使用」權限就讀得到。只看得到系統選為 Now Playing
# 的那一個 App（最近播放的那個），所以實驗時不要讓別的 App 播放。
set -euo pipefail

cmd=${1:?open | state | press | seek | shot | close}

panel_open() {
  osascript -e 'tell application "System Events" to tell (first process whose name is "ControlCenter") to return (count of windows) > 0'
}

open_panel() {
  if [[ $(panel_open) == true ]]; then return; fi
  osascript >/dev/null <<'EOF'
tell application "System Events" to tell (first process whose name is "MenuBarAgent")
  repeat with g in (every group of menu bar 1)
    repeat with mi in (every menu bar item of g)
      if (value of attribute "AXIdentifier" of mi) is "com.apple.menuextra.now-playing" then
        perform action "AXPress" of mi
        return
      end if
    end repeat
  end repeat
  error "選單列沒有 now-playing 項目（沒有 App 在 Now Playing，或選單列設定把它關掉了）"
end tell
EOF
  sleep 1
}

case $cmd in
  open) open_panel ;;
  close)
    if [[ $(panel_open) == true ]]; then
      osascript -e 'tell application "System Events" to key code 53' # Escape
    fi
    ;;
  state)
    open_panel
    osascript <<'EOF'
tell application "System Events" to tell (first process whose name is "ControlCenter")
  set g to UI element 1 of UI element 1 of window 1
  set txtList to {}
  set btnList to {}
  set sliderText to ""
  set hasImage to false
  repeat with e in (UI elements of g)
    set r to role of e
    if r is "AXStaticText" then
      set end of txtList to (value of e as text)
    else if r is "AXButton" then
      set end of btnList to (value of attribute "AXIdentifier" of e as text)
    else if r is "AXSlider" then
      set sliderText to (value of e as text) & "/" & (value of attribute "AXMaxValue" of e as text)
    else if r is "AXImage" then
      set hasImage to true
    end if
  end repeat
  set AppleScript's text item delimiters to " | "
  return "text: " & (txtList as text) & linefeed & "buttons: " & (btnList as text) & linefeed & "slider: " & sliderText & linefeed & "image: " & hasImage
end tell
EOF
    ;;
  press)
    open_panel
    case ${2:?previous | toggle | next} in
      previous) want='backward.fill' ;;
      next) want='forward.fill' ;;
      toggle) want='TOGGLE' ;;
      *) echo "unknown button: $2" >&2; exit 2 ;;
    esac
    osascript - "$want" <<'EOF'
on run argv
  set want to item 1 of argv
  tell application "System Events" to tell (first process whose name is "ControlCenter")
    repeat with e in (UI elements of UI element 1 of UI element 1 of window 1)
      if role of e is "AXButton" then
        set ident to value of attribute "AXIdentifier" of e as text
        if ident is want or (want is "TOGGLE" and ident is in {"play.fill", "pause.fill"}) then
          perform action "AXPress" of e
          return "pressed " & ident
        end if
      end if
    end repeat
  end tell
  error "找不到按鈕 " & want
end run
EOF
    ;;
  seek)
    open_panel
    osascript - "${2:?秒}" <<'EOF'
on run argv
  tell application "System Events" to tell (first process whose name is "ControlCenter")
    repeat with e in (UI elements of UI element 1 of UI element 1 of window 1)
      if role of e is "AXSlider" then
        set value of e to ((item 1 of argv) as real)
        return "slider set to " & (item 1 of argv)
      end if
    end repeat
  end tell
  error "找不到進度條"
end run
EOF
    ;;
  shot)
    open_panel
    read -r x y w h < <(osascript -e 'tell application "System Events" to tell (first process whose name is "ControlCenter") to tell UI element 1 of UI element 1 of window 1
set {px, py} to position
set {sw, sh} to size
return (px as text) & " " & (py as text) & " " & (sw as text) & " " & (sh as text)
end tell' | tr -d ',')
    screencapture -x -R"$x,$y,$w,$h" "${2:?檔案.png}"
    echo "saved ${2}"
    ;;
  *) echo "unknown command: $cmd" >&2; exit 2 ;;
esac
