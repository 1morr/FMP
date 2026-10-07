import 'dart:async';

import 'package:fmp/platform/media_controls/media_controls.dart';

/// 記下每次 `publish` 的假平台實作；[gate] 設了就停在那裡直到完成，用來
/// 檢查推送不重疊。
final class FakeMediaControls implements SystemMediaControls {
  final published = <NowPlaying>[];
  final _commands = StreamController<MediaCommand>.broadcast();
  Completer<void>? gate;
  var running = 0;
  var maxRunning = 0;
  Object? failWith;

  @override
  Stream<MediaCommand> get commands => _commands.stream;

  void send(MediaCommand command) => _commands.add(command);

  @override
  Future<void> publish(NowPlaying nowPlaying) async {
    running++;
    if (running > maxRunning) maxRunning = running;
    published.add(nowPlaying);
    await gate?.future;
    running--;
    if (failWith case final error?) throw error;
  }

  @override
  Future<void> dispose() => _commands.close();
}
