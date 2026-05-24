# Desktop / Windows Integration Security Review

Scope: `desktop_multi_window`, `tray_manager`, `hotkey_manager`, lyrics popup,
Windows plugin registration, cross-window channel use, global hotkey handling,
and desktop lifecycle paths.

Reviewed against `AGENTS.md`, `lib/services/AGENTS.md`,
`lib/services/audio/AGENTS.md`, `lib/ui/AGENTS.md`,
`docs/reviews/security/instruction-document-corpus.md`,
`docs/reviews/security/threat-model.md`, and
`.serena/memories/refactoring_lessons.md`. Descriptive claims below were checked
against current code rather than accepted as documentation-only facts.

## Valid findings

### 1. Imported hotkey config can capture bare system-wide keys

Severity: Medium stability risk.

`HotkeyBinding.isConfigured` only requires `key != null`, and JSON
deserialization accepts an empty `modifiers` list. The normal settings UI
requires at least one modifier before saving a recorded hotkey, but backup
restore writes the raw `hotkeyConfig` string from the imported backup on
Windows. That creates a bypass around the UI guard: a crafted backup can enable
global hotkeys and register `A`, `Space`, arrow keys, or another bare key as a
system-scope hotkey.

Evidence:

- `lib/services/backup/backup_service.dart:650` imports
  `enableGlobalHotkeys` from backup on Windows.
- `lib/services/backup/backup_service.dart:660` imports `hotkeyConfig` from
  backup on Windows without normalizing it through `HotkeyConfig`.
- `lib/providers/hotkey_config_provider.dart:29` loads persisted
  `settings.hotkeyConfig`.
- `lib/providers/hotkey_config_provider.dart:31` deserializes with
  `HotkeyConfig.fromJsonString`.
- `lib/providers/hotkey_config_provider.dart:72` applies that state to
  `WindowsDesktopService`.
- `lib/data/models/hotkey_config.dart:44` defines configured as `key != null`.
- `lib/data/models/hotkey_config.dart:70` converts any configured binding to a
  `HotKey`.
- `lib/data/models/hotkey_config.dart:75` sets `HotKeyScope.system`.
- `lib/data/models/hotkey_config.dart:92` accepts `modifiers` as an optional
  list defaulting to empty.
- `lib/services/platform/windows_desktop_service.dart:303` uses the loaded
  config when syncing hotkeys.
- `lib/services/platform/windows_desktop_service.dart:313` registers every
  configured binding with `hotKeyManager.register`.
- `lib/ui/pages/settings/settings_page.dart:1938` shows the UI-only guard:
  recorded hotkeys are saved only when `_modifiers.isNotEmpty`.

Attack or failure scenario:

A user imports a backup file from an untrusted source or a manually edited
backup. The backup sets `enableGlobalHotkeys=true` and a `hotkeyConfig` binding
with a valid `keyId` but `modifiers: []`. On the next provider load, FMP
registers that key globally. The result can be system-wide input capture for a
common key, unexpected playback/window actions while typing in other apps, and a
confusing recovery path because the settings UI never allowed creating that
state directly.

Recommended fix:

Normalize and validate `HotkeyConfig` at every untrusted boundary, not just in
the recording dialog. At minimum, make `HotkeyBinding.isConfigured` require
`key != null && modifiers.isNotEmpty`, reject or clear modifierless bindings in
`HotkeyBinding.fromJson`, and run backup `hotkeyConfig` through this normalized
model before persisting it. Consider rejecting single bare modifier keys and
known disruptive system keys explicitly.

### 2. Concurrent lyrics popup opens can create orphan sub-windows

Severity: Low stability risk.

`LyricsWindowService.open()` checks `_controller` before creating the child
window, but it does not serialize lifecycle operations or mark an open as
pending before awaiting `WindowController.create`. The toolbar button awaits
`service.open()` but remains callable while the async operation is in flight.
Two rapid open calls can therefore pass the initial `_controller == null` checks
and create multiple lyrics windows. Only the last controller is retained, so an
earlier window can become orphaned while still sharing the bidirectional
`lyrics_sync` channel and sending playback or style commands.

Evidence:

- `lib/services/lyrics/lyrics_window_service.dart:33` reports open state from
  `_controller != null && !_isHidden`.
- `lib/services/lyrics/lyrics_window_service.dart:76` starts `open()` with no
  lifecycle lock or pending-open flag.
- `lib/services/lyrics/lyrics_window_service.dart:80` and
  `lib/services/lyrics/lyrics_window_service.dart:92` only handle already
  retained controllers.
- `lib/services/lyrics/lyrics_window_service.dart:108` awaits
  `WindowController.create` before `_controller` is assigned.
- `lib/services/lyrics/lyrics_window_service.dart:119` starts one
  `onWindowsChanged` subscription after creation.
- `lib/services/lyrics/lyrics_window_service.dart:332` checks only the retained
  `_controller!.windowId` when deciding whether the popup was closed.
- `lib/ui/widgets/track_detail_panel.dart:582` uses an async button handler.
- `lib/ui/widgets/track_detail_panel.dart:593` awaits `service.open()` without
  disabling or coalescing concurrent opens.

Attack or failure scenario:

A user double-clicks the lyrics popup button during startup or while the child
engine is slow to initialize. Two child engines can be created. The service
retains only the later `WindowController`; closing or hiding from the main UI
does not necessarily control the orphan. The orphan can continue sending
`playPause`, `next`, `previous`, seek, offset, or style messages over the shared
`lyrics_sync` channel, causing confusing playback changes and leaking lifecycle
state until process exit.

Recommended fix:

Serialize lyrics-window lifecycle operations in `LyricsWindowService`. A simple
approach is a private `_lifecycleOperation` chain or `_opening` future that
coalesces concurrent `open()` calls. Set the pending state before
`WindowController.create`, clear it in `finally`, and make `close()` / `destroy()`
wait for or cancel any pending open. The UI button can also disable itself while
an open/close operation is pending, but the service should own the invariant.

## Checked and safe items

- Main-window plugin registration still uses the generated registrant, including
  `desktop_multi_window`, `hotkey_manager_windows`, `tray_manager`, and
  `window_manager`: `windows/flutter/generated_plugin_registrant.cc:21`,
  `windows/flutter/generated_plugin_registrant.cc:30`,
  `windows/flutter/generated_plugin_registrant.cc:38`, and
  `windows/flutter/generated_plugin_registrant.cc:42`.
- Sub-window registration is selective and excludes `tray_manager` and
  `hotkey_manager_windows`: `windows/runner/flutter_window.cpp:22` through
  `windows/runner/flutter_window.cpp:40`. The callback is installed for
  `desktop_multi_window` child creation at `windows/runner/flutter_window.cpp:66`.
- The lyrics child window enters a separate Dart entrypoint before the main app
  initializes credentials, database providers, tray, hotkeys, or update services:
  `lib/main.dart:43` and `lib/main.dart:46`.
- Normal lyrics popup close is hide-instead-of-destroy:
  `lib/services/lyrics/lyrics_window_service.dart:146` through
  `lib/services/lyrics/lyrics_window_service.dart:150`. App teardown performs
  real destroy from the desktop service at
  `lib/services/platform/windows_desktop_service.dart:66`.
- Lyrics popup playback commands are routed back through `AudioController`, not
  directly to the backend: `lib/ui/widgets/track_detail_panel.dart:255` through
  `lib/ui/widgets/track_detail_panel.dart:264`.
- Tray and global hotkey playback commands also route through `AudioController`:
  `lib/providers/windows_desktop_provider.dart:31` through
  `lib/providers/windows_desktop_provider.dart:39`.
- Hotkey sync operations are serialized, which addresses the previously
  documented provider race between settings and custom hotkey config:
  `lib/services/platform/windows_desktop_service.dart:286` through
  `lib/services/platform/windows_desktop_service.dart:288`.
- Windows update ZIP extraction uses a destination guard against absolute paths,
  drive-prefixed paths, and `..` traversal before writing extracted entries:
  `lib/services/update/update_service.dart:189` through
  `lib/services/update/update_service.dart:213`.

## Evidence

Code paths reviewed:

- Plugin registration: `windows/runner/flutter_window.cpp`,
  `windows/flutter/generated_plugin_registrant.cc`.
- Main and child entrypoints: `lib/main.dart`, `lib/ui/windows/lyrics_window.dart`.
- Lyrics window lifecycle/channel: `lib/services/lyrics/lyrics_window_service.dart`,
  `lib/ui/widgets/track_detail_panel.dart`.
- Tray and hotkeys: `lib/services/platform/windows_desktop_service.dart`,
  `lib/providers/windows_desktop_provider.dart`,
  `lib/providers/desktop_settings_provider.dart`,
  `lib/providers/hotkey_config_provider.dart`,
  `lib/data/models/hotkey_config.dart`,
  `lib/ui/pages/settings/settings_page.dart`.
- Update lifecycle and Windows script path: `lib/services/update/update_service.dart`.
- Backup import path affecting hotkeys:
  `lib/services/backup/backup_service.dart`.

External dependency spot checks used only to validate documentation claims:

- `tray_manager-0.2.4/windows/tray_manager_plugin.cpp:32` stores a file-scope
  `channel`, and `tray_manager-0.2.4/windows/tray_manager_plugin.cpp:92`
  overwrites it on registration.
- `window_manager-0.4.3/windows/window_manager_plugin.cpp:35` stores a
  file-scope `channel`, and
  `window_manager-0.4.3/windows/window_manager_plugin.cpp:98` overwrites it on
  registration.
- `hotkey_manager_windows-0.2.0/windows/hotkey_manager_windows_plugin.cpp:18`
  creates method channel as a local variable, and
  `hotkey_manager_windows-0.2.0/windows/hotkey_manager_windows_plugin.h:17`
  stores registrar/event state per plugin instance rather than in a file-scope
  channel.
- `hotkey_manager_windows-0.2.0/windows/hotkey_manager_windows_plugin.cpp:104`
  calls Win32 `RegisterHotKey` with whatever modifier set the Dart side
  supplies.

No product code was modified during this review.

## Attack or failure scenario

The two valid scenarios are:

- A crafted or untrusted backup imports modifierless system hotkeys, causing FMP
  to capture common keys globally and trigger playback/window actions while the
  user works in other applications.
- A rapid double-open of the lyrics popup creates multiple child engines sharing
  the same channel name, leaving at least one window outside the service's
  retained lifecycle state.

No externally reachable cross-window command injection path was found. The
lyrics channel is created by app-owned windows, and the reviewed command
handlers route to expected app controls. The realistic issue is lifecycle
confusion from duplicate app-created child windows, not arbitrary external IPC.

## Recommended fix

Prioritize the hotkey import normalization because it crosses a user-controlled
file boundary and affects system-wide input. Then add a lifecycle serialization
guard around the lyrics popup service. Both fixes should be covered by focused
tests:

- A `HotkeyConfig.fromJsonString` test where `modifiers: []` is rejected or
  cleared.
- A backup restore test proving imported hotkey config is normalized before
  persistence.
- A unit-level or fake-controller test that concurrent `LyricsWindowService.open`
  calls coalesce to one create operation.

## Instruction docs accuracy notes

- `lib/services/AGENTS.md:110` through `lib/services/AGENTS.md:112` and
  `.serena/memories/refactoring_lessons.md:58` correctly require selective
  sub-window registration, and the current code follows that requirement.
- The stated rationale is partly stale for `hotkey_manager_windows`.
  `tray_manager` and `window_manager` do use file-scope static channels in the
  checked dependency versions, but `hotkey_manager_windows-0.2.0` does not show
  the same static channel pattern. Keeping it excluded from sub-windows is still
  the safer policy because global hotkey ownership and WM_HOTKEY handling should
  remain main-window-only, but the docs should avoid saying `hotkey_manager`
  currently overwrites the main window via a global static C++ channel unless the
  dependency changes.
- The documentation claim that the lyrics popup uses an independent Flutter
  engine and hide-instead-of-destroy lifecycle matches code for the normal close
  path: `lib/main.dart:45`,
  `lib/services/lyrics/lyrics_window_service.dart:108`, and
  `lib/services/lyrics/lyrics_window_service.dart:149`.
