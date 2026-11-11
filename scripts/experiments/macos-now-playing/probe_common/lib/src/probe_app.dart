import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

import 'bridge.dart';

/// 啟動實驗 App：產生三首測試曲目（正弦波 WAV 與單色封面），載入第一首並開始播放。
Future<void> runProbe(NowPlayingBridge bridge) async {
  WidgetsFlutterBinding.ensureInitialized();
  final dir = Directory(
    '${(await getTemporaryDirectory()).path}/macos-now-playing-${bridge.name}',
  );
  await dir.create(recursive: true);
  final log = File('${dir.path}/events.jsonl');
  if (log.existsSync()) log.deleteSync();
  // run.py 從 stdout 找這一行，取回結果檔。
  stdout.writeln('PROBE_FILE ${log.path}');

  final tracks = await _makeTracks(dir);
  final probe = _Probe(bridge, tracks, log);
  runApp(_ProbeApp(probe));
  await probe.start();
}

/// `--dart-define=AUTOPLAY=false`：載入第一首但不播放（模擬重啟後不自動播放，brief §6）。
const _autoplay = bool.fromEnvironment('AUTOPLAY', defaultValue: true);
const _artBase = String.fromEnvironment('ART_BASE');

const _toneHz = [440.0, 554.37, 659.25];
const _colors = [Color(0xFFD9480F), Color(0xFF2B8A3E), Color(0xFF1864AB)];
const _trackSeconds = 40;

Future<List<TrackInfo>> _makeTracks(Directory dir) async {
  final tracks = <TrackInfo>[];
  for (var i = 0; i < _toneHz.length; i++) {
    final audio = File('${dir.path}/track-$i.wav');
    await audio.writeAsBytes(_sineWav(_toneHz[i], _trackSeconds));
    final art = File('${dir.path}/art-$i.png');
    await art.writeAsBytes(await _artPng(_colors[i], '${i + 1}'));
    tracks.add(
      TrackInfo(
        index: i,
        title: 'FMP 實驗曲目 ${i + 1}',
        artist: '測試音源 ${_toneHz[i].round()} Hz',
        album: 'macOS Now Playing 實驗',
        duration: const Duration(seconds: _trackSeconds),
        audioPath: audio.path,
        artPath: art.path,
        artUrl: _artBase.isEmpty ? null : '$_artBase/art-$i.png',
      ),
    );
  }
  return tracks;
}

/// 單聲道 16-bit PCM WAV；每秒開頭有 0.1 秒靜音，聽得出 seek 前後的節拍。
Uint8List _sineWav(double hz, int seconds) {
  const rate = 22050;
  final n = rate * seconds;
  final b = ByteData(44 + n * 2);
  void ascii(int o, String s) {
    for (var k = 0; k < s.length; k++) {
      b.setUint8(o + k, s.codeUnitAt(k));
    }
  }

  ascii(0, 'RIFF');
  b.setUint32(4, 36 + n * 2, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  b.setUint32(16, 16, Endian.little);
  b.setUint16(20, 1, Endian.little);
  b.setUint16(22, 1, Endian.little);
  b.setUint32(24, rate, Endian.little);
  b.setUint32(28, rate * 2, Endian.little);
  b.setUint16(32, 2, Endian.little);
  b.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  b.setUint32(40, n * 2, Endian.little);
  for (var s = 0; s < n; s++) {
    final silent = (s % rate) < rate ~/ 10;
    final v = silent ? 0.0 : math.sin(2 * math.pi * hz * s / rate) * 0.25;
    b.setInt16(44 + s * 2, (v * 32767).round(), Endian.little);
  }
  return b.buffer.asUint8List();
}

Future<Uint8List> _artPng(Color color, String label) async {
  const size = 512.0;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(const Rect.fromLTWH(0, 0, size, size), Paint()..color = color);
  final tp = TextPainter(
    text: TextSpan(
      text: label,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 360,
        fontWeight: FontWeight.bold,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(canvas, Offset((size - tp.width) / 2, (size - tp.height) / 2));
  final image = await recorder.endRecording().toImage(size.toInt(), size.toInt());
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

class _Event {
  _Event(this.kind, this.name, this.detail) : at = DateTime.now();
  final DateTime at;
  final String kind;
  final String name;
  final Object? detail;

  Map<String, Object?> toJson() => {
        't': at.toIso8601String(),
        'kind': kind,
        'name': name,
        if (detail != null) 'detail': detail,
      };

  @override
  String toString() =>
      '${at.toIso8601String().substring(11, 23)}  $kind  $name${detail == null ? '' : '  $detail'}';
}

class _Probe implements PlayerController {
  _Probe(this.bridge, this.tracks, this.logFile);

  final NowPlayingBridge bridge;
  final List<TrackInfo> tracks;
  final File logFile;
  final player = AudioPlayer();
  final events = ValueNotifier<List<_Event>>(const []);
  final current = ValueNotifier<int>(0);
  bool _lastPlaying = false;

  void _record(String kind, String name, [Object? detail]) {
    final e = _Event(kind, name, detail);
    events.value = [e, ...events.value.take(199)];
    final line = jsonEncode(e.toJson());
    stdout.writeln('NP $line');
    logFile.writeAsStringSync('$line\n', mode: FileMode.append, flush: true);
  }

  Future<void> start() async {
    await player.setVolume(0.15);
    player.playerStateStream.listen((s) {
      if (s.processingState == ProcessingState.completed) {
        _record('player', 'completed', current.value);
        unawaited(next());
        return;
      }
      if (s.playing != _lastPlaying) {
        _lastPlaying = s.playing;
        unawaited(_sync());
      }
    });
    await bridge.init(this);
    _record('probe', 'started', {'candidate': bridge.name, 'autoplay': _autoplay, 'artBase': _artBase});
    await _load(0);
    if (_autoplay) {
      await play();
    } else {
      await _sync();
    }
  }

  Future<void> _load(int i) async {
    current.value = i;
    await player.setFilePath(tracks[i].audioPath);
    await bridge.setTrack(tracks[i]);
    _record('sent', 'setTrack', tracks[i].title);
  }

  Future<void> _sync() async {
    final playing = player.playing;
    final pos = player.position;
    await bridge.setPlayback(playing: playing, position: pos);
    _record('sent', 'setPlayback', {'playing': playing, 'positionMs': pos.inMilliseconds});
  }

  @override
  void logCommand(String command, [Object? detail]) =>
      _record('received', command, detail);

  @override
  Future<void> play() async {
    unawaited(player.play());
    await _sync();
  }

  @override
  Future<void> pause() async {
    await player.pause();
    await _sync();
  }

  @override
  Future<void> togglePlayPause() => player.playing ? pause() : play();

  @override
  Future<void> next() => _skip(1);

  @override
  Future<void> previous() => _skip(-1);

  Future<void> _skip(int delta) async {
    final wasPlaying = player.playing || player.processingState == ProcessingState.completed;
    await _load((current.value + delta) % tracks.length);
    if (wasPlaying) unawaited(player.play());
    await _sync();
  }

  @override
  Future<void> seek(Duration position) async {
    await player.seek(position);
    await _sync();
  }
}

class _ProbeApp extends StatelessWidget {
  const _ProbeApp(this.probe);
  final _Probe probe;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('候選：${probe.bridge.name}', style: const TextStyle(fontSize: 20)),
              ValueListenableBuilder(
                valueListenable: probe.current,
                builder: (_, i, _) => Text('曲目：${probe.tracks[i].title}'),
              ),
              StreamBuilder(
                stream: probe.player.positionStream,
                builder: (_, snap) => Text(
                  '播放中：${probe.player.playing}　進度：${(snap.data ?? Duration.zero).inSeconds} 秒',
                ),
              ),
              Wrap(
                spacing: 8,
                children: [
                  ElevatedButton(onPressed: probe.previous, child: const Text('上一首')),
                  ElevatedButton(onPressed: probe.togglePlayPause, child: const Text('播放／暫停')),
                  ElevatedButton(onPressed: probe.next, child: const Text('下一首')),
                  ElevatedButton(
                    onPressed: () => probe.seek(const Duration(seconds: 30)),
                    child: const Text('seek 30 秒'),
                  ),
                ],
              ),
              const Divider(),
              Expanded(
                child: ValueListenableBuilder(
                  valueListenable: probe.events,
                  builder: (_, list, _) => ListView(
                    children: [
                      for (final e in list)
                        Text(
                          e.toString(),
                          style: TextStyle(
                            fontFamily: 'Menlo',
                            fontSize: 12,
                            color: e.kind == 'received' ? Colors.red : null,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
