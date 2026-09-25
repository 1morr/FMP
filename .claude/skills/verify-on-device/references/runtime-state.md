# Reading and setting up app state

Read when the question is about state rather than pixels, when a precondition
cannot be reached through the UI, or when playback needs media and every source
is blocked.

## Reading state

- **Prefer the VM Service over screenshots.** `getInstances` + `getObject` on a
  live object answers "what is the controller's state" in one call, as text, and
  sees what is off-screen. Recipes, including why `evaluate` does not work over
  HTTP: `docs/development.md` § 執行期除錯. Reach for pixels only for layout.
- **The VM Service URI scrolls out of the terminal tail.** Read it with
  `orca terminal read --cursor 0 --limit 5000`. It is a local debug credential:
  quote the port and purpose only.
- **`dumpsys media_session` is the cheapest continuous playback probe on
  Android.** Grep for `state=PLAYING(3), position=`; position is in ms and
  advances monotonically, so polling it shows continuity and the wrap at a
  track or loop boundary without touching the UI.

## Setting up a precondition

- **Write what the UI cannot reach with `ext.isar.editProperty`.** Example: the
  download directory can only be chosen through the Android SAF picker, which
  ignores synthetic taps; writing `Settings.customDownloadDir` sets up the
  precondition without faking the thing being verified.
- **A DB edit under a running app is not durable.** App writers race you (the
  queue is saved every 10 s), so reading the new value back proves nothing. Kill
  the process right after the edit, or make the change through the app's UI.
  Restoring the play queue only stuck when done through the queue page's clear
  button and the mini player's loop toggle.

## Getting media to play when every source is blocked

All three sources can be unavailable at once on a dev machine (Bilibili
`playurl` answering HTTP 412, YouTube demanding sign-in, nothing downloaded).
`Track.audioUrl` does not rescue you — the reuse cache in
`stream_resolution_service.dart` also requires an in-memory entry.

What works offline: `_inspectLocalFiles` plays the first
`Track.allDownloadPaths` entry that exists on disk, with no playlist-id match and
no network. Generate a long near-silent WAV, point one track's
`playlistInfo[].downloadPath` at it, and playback is real, local and silent.
Save the original `playlistInfo` first and restore it afterwards.

**Orphan cleanup deletes tracks you swap out of the queue.** `QueueManager` runs
`TrackRepository.deleteOrphanTracks` ~10 s after start, excluding only the
current queue: a track in no playlist and no longer queued is gone.
