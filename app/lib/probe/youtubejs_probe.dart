// PROBE ONLY (branch probe/youtubejs, never merged). Throwaway trigger for the
// YouTube.js feasibility probe (owner decision 3, ADR 0014 §決定 10): once the
// dev entry has installed the `youtubejs-probe` plugin, run search -> resolve ->
// play through a throwaway backend (just_audio on Android, media_kit on Windows)
// and log timings/memory with tag `probe` (lands in logs/fmp.jsonl).
// ignore_for_file: fmp_lints/fmp_layer_imports — throwaway probe
// ignore_for_file: fmp_lints/fmp_platform_checks — throwaway probe
import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart' as ja;
import 'package:material_ui/material_ui.dart';
import 'package:media_kit/media_kit.dart' as mk;

import 'package:fmp/core/core_providers.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/plugins/install/dev_plugin_entry.dart';
import 'package:fmp/plugins/manifest/plugin_file.dart';
import 'package:fmp/plugins/plugin_registry.dart';
import 'package:fmp/plugins/source_dto.dart';
import 'package:fmp/plugins/source_plugin.dart';

const probePluginId = 'youtubejs-probe';

/// Set by main() right before runApp, to measure app start -> plugin ready.
final probeClock = Stopwatch()..start();

abstract class _Backend {
  Future<void> play(Uri url);
  Future<void> seek(Duration to);
  Duration get position;
  Duration? get duration;
  String get state;
  Future<void> stop();
}

final class _JustAudio implements _Backend {
  final _p = ja.AudioPlayer();
  @override
  Future<void> play(Uri url) async {
    await _p.setUrl(url.toString());
    unawaited(_p.play());
  }

  @override
  Future<void> seek(Duration to) => _p.seek(to);

  @override
  Duration get position => _p.position;
  @override
  Duration? get duration => _p.duration;
  @override
  String get state =>
      '${_p.playerState.processingState.name}/playing=${_p.playing}';
  @override
  Future<void> stop() => _p.dispose();
}

final class _MediaKit implements _Backend {
  _MediaKit(void Function(String) out) {
    mk.MediaKit.ensureInitialized();
    _p = mk.Player(
      configuration: const mk.PlayerConfiguration(logLevel: mk.MPVLogLevel.v),
    );
    _p.stream.log.listen((l) {
      if (l.prefix == 'ffmpeg' || l.prefix == 'stream' || l.prefix == 'cplayer' ||
          l.level == 'error' || l.level == 'warn' || l.prefix.startsWith('ao')) {
        out(
          'mpv ${l.level} ${l.prefix}: '
          '${l.text.trim().replaceAll(RegExp(r'\?[^ ]*'), '?***')}',
        );
      }
    });
    _p.stream.error.listen(
      (e) => out('mpv error: ${e.replaceAll(RegExp(r'\?[^ ]*'), '?***')}'),
    );
  }
  late final mk.Player _p;
  @override
  Future<void> play(Uri url) => _p.open(mk.Media(url.toString()));
  @override
  Future<void> seek(Duration to) => _p.seek(to);
  @override
  Duration get position => _p.state.position;
  @override
  Duration? get duration => _p.state.duration;
  @override
  String get state =>
      'playing=${_p.state.playing} buffering=${_p.state.buffering} '
      'audio=${_p.state.audioParams.format}/${_p.state.audioParams.sampleRate}Hz '
      'device=${_p.state.audioDevice.name}';
  @override
  Future<void> stop() => _p.dispose();
}

class YoutubeJsProbePanel extends ConsumerStatefulWidget {
  const YoutubeJsProbePanel({super.key});

  @override
  ConsumerState<YoutubeJsProbePanel> createState() => _State();
}

class _State extends ConsumerState<YoutubeJsProbePanel> {
  final _lines = <String>[];
  bool _started = false;
  _Backend? _backend;

  void _out(String line) {
    ref.read(logProvider).info('FMP_PROBE $line', tag: 'probe');
    if (mounted) setState(() => _lines.add(line));
  }

  int get _rssMb => ProcessInfo.currentRss ~/ (1024 * 1024);

  static const _emptyPlugin = '''
/* ==FMP Plugin==
{"id": "probe-empty", "name": "Empty", "version": "1", "author": "FMP",
 "apiVersion": 1, "capabilities": ["search"], "allowedHosts": []}
==/FMP Plugin== */
export function search() { return { items: [], hasMore: false }; }
''';

  /// Isolate spawn + QuickJS + module evaluation, no network (Innertube is lazy).
  Future<void> _loadBench() async {
    final loader = ref.read(scriptPluginLoaderProvider);
    final path = ref.read(devPluginPathProvider)!;
    final probe = PluginFile.parse(await File(path).readAsString());
    final empty = PluginFile.parse(_emptyPlugin);
    for (final (name, file) in [('empty', empty), ('youtubejs', probe)]) {
      final times = <int>[];
      final rssBefore = _rssMb;
      final open = <SourcePlugin>[];
      for (var i = 0; i < 3; i++) {
        final sw = Stopwatch()..start();
        open.add(await loader.load(file));
        times.add(sw.elapsedMilliseconds);
      }
      final rssAfter = _rssMb;
      for (final p in open) {
        p.close();
      }
      _out(
        'loadBench $name ms=$times rss +${rssAfter - rssBefore}MB for 3 '
        'runtimes (${rssBefore}MB -> ${rssAfter}MB)',
      );
    }
  }

  Future<void> _run(SourcePlugin plugin) async {
    final log = ref.read(logProvider);
    final platform = Platform.isAndroid ? 'android' : 'windows';
    _out(
      'platform=$platform plugin ready at ${probeClock.elapsedMilliseconds}ms '
      'after main, rss=${_rssMb}MB',
    );
    final sw = Stopwatch();
    try {
      await _loadBench();
      sw.start();
      final page = await plugin.search(SearchQuery(keyword: 'rick astley'));
      _out(
        'search ms=${sw.elapsedMilliseconds} items=${page.items.length} '
        'rss=${_rssMb}MB',
      );
      sw.reset();
      final page2 = await plugin.search(SearchQuery(keyword: 'lofi'));
      _out('search#2 ms=${sw.elapsedMilliseconds} items=${page2.items.length}');
      final target = page.items.firstWhere(
        (t) =>
            (t.duration?.inSeconds ?? 0) > 60 &&
            (t.duration?.inSeconds ?? 0) < 900,
      );
      _out('target ${target.sourceId} "${target.title}" ${target.duration}');
      sw.reset();
      final candidates = await plugin.resolveStream(
        StreamRequest(
          sourceId: target.sourceId,
          formats: [
            StreamFormat(container: 'mp4', codec: 'aac'),
            StreamFormat(container: 'webm', codec: 'opus'),
          ],
        ),
      );
      final c = candidates.first;
      _out(
        'resolve ms=${sw.elapsedMilliseconds} n=${candidates.length} '
        'first=${c.container}/${c.codec}@${c.bitrate} host=${c.url.host} '
        'rss=${_rssMb}MB',
      );
      final backend = _backend = Platform.isAndroid ? _JustAudio() : _MediaKit(_out);
      sw.reset();
      await backend.play(c.url);
      _out('backend opened ms=${sw.elapsedMilliseconds}');
      // Token-free ANDROID_VR URLs 403 past ~60 s of media since 2026-08-26, so
      // seek to 70 % of the track to prove the whole file is served.
      for (var i = 0; i < 16; i++) {
        await Future<void>.delayed(const Duration(seconds: 1));
        if (i == 6) {
          final total = backend.duration ?? target.duration ?? Duration.zero;
          final to = total * 0.7;
          await backend.seek(to);
          _out('seek to ${to.inSeconds}s');
        }
        _out(
          't+${i + 1}s position=${backend.position.inMilliseconds}ms '
          'duration=${backend.duration?.inSeconds}s ${backend.state}',
        );
      }
      _out('rss after 16s playback=${_rssMb}MB');
    } on AppError catch (e) {
      log.report('probe failed', e, tag: 'probe');
      _out('FAILED ${e.typeName} (see log)');
    } on Object catch (e, st) {
      log.error('probe failed', tag: 'probe', error: e, stackTrace: st);
      _out('FAILED $e');
    }
  }

  @override
  void dispose() {
    unawaited(_backend?.stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final install = ref.watch(devPluginInstallProvider);
    if (install case AsyncData(value: final SourcePlugin plugin)
        when !_started && plugin.manifest.id == probePluginId) {
      _started = true;
      unawaited(Future.microtask(() => _run(plugin)));
    }
    return SizedBox(
      width: 600,
      height: 360,
      child: ListView(
        children: [for (final l in _lines) Text(l, style: const TextStyle(fontSize: 11))],
      ),
    );
  }
}
