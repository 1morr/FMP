import 'package:flutter/services.dart';
import 'package:probe_common/probe_common.dart';

/// 候選二：自己的 platform channel，原生端在
/// `macos/Runner/MainFlutterWindow.swift` 的 `NowPlayingChannel`。
Future<void> main() => runProbe(_ChannelBridge());

class _ChannelBridge implements NowPlayingBridge {
  static const _channel = MethodChannel('fmp.exp/now_playing');

  @override
  String get name => 'channel';

  @override
  Future<void> init(PlayerController c) async {
    _channel.setMethodCallHandler((call) async {
      final args = (call.arguments as Map?)?.cast<String, Object?>() ?? const {};
      switch (call.method) {
        case 'play':
          c.logCommand('play');
          await c.play();
        case 'pause':
          c.logCommand('pause');
          await c.pause();
        case 'togglePlayPause':
          c.logCommand('togglePlayPause');
          await c.togglePlayPause();
        case 'next':
          c.logCommand('next');
          await c.next();
        case 'previous':
          c.logCommand('previous');
          await c.previous();
        case 'seek':
          final ms = ((args['seconds']! as num) * 1000).round();
          c.logCommand('seek', ms);
          await c.seek(Duration(milliseconds: ms));
        default:
          c.logCommand('unknown', call.method);
      }
    });
    await _channel.invokeMethod('init');
  }

  @override
  Future<void> setTrack(TrackInfo track) => _channel.invokeMethod('setTrack', {
        'title': track.title,
        'artist': track.artist,
        'album': track.album,
        'duration': track.duration.inMilliseconds / 1000,
        'artPath': track.artPath,
      });

  @override
  Future<void> setPlayback({required bool playing, required Duration position}) =>
      _channel.invokeMethod('setPlayback', {
        'playing': playing,
        'position': position.inMilliseconds / 1000,
      });
}
