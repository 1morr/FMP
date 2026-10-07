import 'dart:async';

import 'package:smtc_windows/smtc_windows.dart' as smtc;

import 'package:fmp/platform/media_controls/media_controls.dart';

/// Windows 的系統媒體控制（design §8.4）：以 `smtc_windows` 接 SMTC，也就是
/// 媒體鍵與音量浮層的媒體卡片。
///
/// SMTC 不支援 seek（宣告 `supportsSeek: false`），timeline 也不會自己前進，
/// 位置由 `NowPlayingPublisher` 依 `positionRefresh` 重推。
///
/// 還沒按播放的 [MediaPhase.idle] 呼叫 `disableSmtc`，媒體卡片不顯示；套件沒有
/// 「關閉」以外的隱藏方式（`closed` 狀態仍會留著卡片），所以用停用。
final class WindowsSystemMediaControls implements SystemMediaControls {
  /// 接上 [_smtc]；它必須是停用的（`SMTCWindows(enabled: false)`），第一次推到
  /// 有曲目的內容才啟用。
  WindowsSystemMediaControls(this._smtc) {
    _buttons = _smtc.buttonPressStream.listen((button) {
      final command = mediaCommandOf(button);
      if (command != null && !_commands.isClosed) _commands.add(command);
    });
  }

  /// 載入 Rust 端並建 SMTC（要在 `runApp` 前呼叫；失敗時丟出，由
  /// `AppPlatform.withMediaControls` 改宣告為沒有）。一開始是停用的：第一次推到
  /// 有曲目的內容才顯示。
  static Future<WindowsSystemMediaControls> init() async {
    await smtc.SMTCWindows.initialize();
    return WindowsSystemMediaControls(smtc.SMTCWindows(enabled: false));
  }

  final smtc.SMTCWindows _smtc;
  final _commands = StreamController<MediaCommand>.broadcast();
  late final StreamSubscription<smtc.PressedButton> _buttons;

  bool _enabled = false;
  smtc.MusicMetadata? _metadata;
  smtc.SMTCConfig? _config;
  smtc.PlaybackTimeline? _timeline;
  smtc.PlaybackStatus? _status;

  @override
  Stream<MediaCommand> get commands => _commands.stream;

  @override
  Future<void> publish(NowPlaying nowPlaying) async {
    if (nowPlaying.phase == MediaPhase.idle) {
      if (_enabled) {
        _enabled = false;
        // 下次顯示時要重新推全部，不拿停用前的值去比對。
        _metadata = _config = _timeline = _status = null;
        await _smtc.clearMetadata();
        await _smtc.disableSmtc();
      }
      return;
    }
    if (!_enabled) {
      _enabled = true;
      await _smtc.enableSmtc();
    }
    final metadata = smtcMetadataOf(nowPlaying);
    if (metadata != _metadata) {
      if (smtcClearsMetadata(_metadata, metadata)) {
        await _smtc.clearMetadata();
      }
      _metadata = metadata;
      await _smtc.updateMetadata(metadata);
    }
    final config = smtcConfigOf(nowPlaying);
    if (config != _config) {
      _config = config;
      await _smtc.updateConfig(config);
    }
    final timeline = smtcTimelineOf(nowPlaying);
    if (timeline != _timeline) {
      _timeline = timeline;
      await _smtc.updateTimeline(timeline);
    }
    final status = smtcStatusOf(nowPlaying);
    if (status != _status) {
      _status = status;
      await _smtc.setPlaybackStatus(status);
    }
  }

  @override
  Future<void> dispose() async {
    await _buttons.cancel();
    await _commands.close();
    await _smtc.dispose();
  }
}

/// SMTC 的曲目資料。封面只在能轉成合法網址時帶（[smtcThumbnailOf]）。
smtc.MusicMetadata smtcMetadataOf(NowPlaying nowPlaying) => smtc.MusicMetadata(
  title: nowPlaying.title,
  artist: nowPlaying.uploader,
  thumbnail: smtcThumbnailOf(nowPlaying.artworkUrl),
);

/// 推 [next] 之前要不要先清掉 SMTC 上的資料：套件的 `updateMetadata` 只設不是
/// `null` 的欄位，上一首有、這一首沒有的（上傳者、封面）不清就一直留著。
bool smtcClearsMetadata(
  smtc.MusicMetadata? previous,
  smtc.MusicMetadata next,
) =>
    previous != null &&
    ((previous.artist != null && next.artist == null) ||
        (previous.thumbnail != null && next.thumbnail == null));

/// 封面的 `https` 網址；沒有或不合法時為 `null`。
///
/// `smtc_windows` 以 `Uri::CreateUri(..).unwrap()` 讀 `thumbnail`
/// （`rust/src/internal/smtc_internal.rs`），不合法的字串會讓 Rust 端 panic，
/// 所以交出前一律用 [Uri.tryParse] 重新驗過，只收 host 不空的 `https`。
/// [Uri] 接受任何連接埠，`CreateUri` 超過 65535 就失敗，所以另外擋；空白、非
/// ASCII 與括號在 [Uri.toString] 已是百分比編碼，`CreateUri` 收得下（以
/// `windows` 0.58 實測，2026-10-07）。
/// 不交快取檔的 `file:///`：未封裝 App 的 SMTC 讀不到（2026-10-07 實測）。
/// 這張圖由 Windows 自己下載，不經 App 的媒體 client（見 `app/AGENTS.md`）。
String? smtcThumbnailOf(Uri? artworkUrl) {
  if (artworkUrl == null) return null;
  final text = artworkUrl.toString();
  final parsed = Uri.tryParse(text);
  if (parsed == null ||
      parsed.scheme != 'https' ||
      parsed.host.isEmpty ||
      parsed.port > 65535) {
    return null;
  }
  return text;
}

/// 位置與時長。時長未知時 `endTimeMs` 為 0；位置不超過時長。
smtc.PlaybackTimeline smtcTimelineOf(NowPlaying nowPlaying) {
  final end = nowPlaying.duration?.inMilliseconds ?? 0;
  final position = nowPlaying.position.inMilliseconds;
  return smtc.PlaybackTimeline(
    startTimeMs: 0,
    endTimeMs: end,
    positionMs: end > 0 && position > end ? end : position,
  );
}

/// 播放狀態：載入與緩衝是 `changing`，其餘依 [NowPlaying.playing]；
/// [MediaPhase.idle] 不顯示（`closed`，實際上由停用處理）。
smtc.PlaybackStatus smtcStatusOf(NowPlaying nowPlaying) =>
    switch (nowPlaying.phase) {
      MediaPhase.idle => smtc.PlaybackStatus.closed,
      MediaPhase.loading ||
      MediaPhase.buffering => smtc.PlaybackStatus.changing,
      MediaPhase.ready =>
        nowPlaying.playing
            ? smtc.PlaybackStatus.playing
            : smtc.PlaybackStatus.paused,
    };

/// 按鈕依 [NowPlaying.controls] 啟用。有曲目時停止也啟用：沒啟用的話系統送的
/// 停止指令不會轉給 App（實測），控制器把它當暫停（`MediaStop`）。快轉、倒轉不
/// 啟用。
smtc.SMTCConfig smtcConfigOf(NowPlaying nowPlaying) => smtc.SMTCConfig(
  playEnabled: nowPlaying.controls.contains(MediaControl.play),
  pauseEnabled: nowPlaying.controls.contains(MediaControl.pause),
  nextEnabled: nowPlaying.controls.contains(MediaControl.next),
  prevEnabled: nowPlaying.controls.contains(MediaControl.previous),
  stopEnabled: nowPlaying.phase != MediaPhase.idle,
  fastForwardEnabled: false,
  rewindEnabled: false,
);

/// SMTC 按鍵對應的指令；沒有對應的（快轉、錄音、頻道）為 `null`。
MediaCommand? mediaCommandOf(smtc.PressedButton button) => switch (button) {
  smtc.PressedButton.play => const MediaPlay(),
  smtc.PressedButton.pause => const MediaPause(),
  smtc.PressedButton.next => const MediaNext(),
  smtc.PressedButton.previous => const MediaPrevious(),
  smtc.PressedButton.stop => const MediaStop(),
  _ => null,
};
