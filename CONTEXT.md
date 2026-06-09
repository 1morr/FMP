# FMP Context

FMP is a cross-platform music player that resolves tracks from Bilibili,
YouTube, and Netease sources. This context records project-specific language for
source auth and media handoff decisions.

## Language

**Source Auth Context**:
A policy concept that decides which source credentials may be used for a
specific source operation. It is distinct from account login and credential
storage.
_Avoid_: auth helper, header utility, account service

**Media Handoff**:
The transition from a resolved stream URL to the audio or download backend,
including redirect checks and source-specific media headers.
_Avoid_: playback URL helper, download header helper

**Stream Resolution Auth**:
Credentials used while asking a source adapter to resolve or refresh a stream
URL. This is broader than media request credentials and may include Bilibili or
YouTube auth that must not be sent to media/CDN requests.
_Avoid_: media auth, playback headers

**Auth For Play**:
The user setting that gates credentials for stream resolution, playback handoff,
download, track detail, and auth-aware metadata/detail service paths. Existing
`SourceManager.parseUrl()` / `refreshAudioUrl()` capability helpers remain
unauthenticated unless a future auth-aware overload is added. Auth For Play does
not control playlist import, playlist refresh, or search.
_Avoid_: import auth, search auth

**Media Request Credentials**:
Credentials that are allowed on the actual audio byte request. In current FMP
policy, only allowlisted HTTPS Netease media hosts may receive Netease cookies.
_Avoid_: stream auth, source auth

## Example Dialogue

Developer: "This download needs Stream Resolution Auth so Netease can return a
playable URL."

Reviewer: "That does not mean the isolate can send all source auth to the media
host. Media Request Credentials still have to pass the Netease allowlist."

Developer: "The Source Auth Context will return the resolution auth for the
source adapter, then Media Handoff will recompute headers for each redirect
hop."
