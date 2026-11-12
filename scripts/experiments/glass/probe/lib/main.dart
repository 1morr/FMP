// Experiment (throwaway), M0 ticket 05b: glass candidates over a 1500-row list.
//
// For each variant (VARIANTS, comma separated; default all):
//   1. scene  — list at a fixed offset, glass on top; writes the status file so
//               the driver can screenshot, holds SCENE_HOLD_MS.
//   2. scroll — scrolls the list at constant speed for SCROLL_MS and records
//               FrameTiming (build / raster) while it moves.
// MODE=a11y only reports the accessibility flags and exits the sequence.
//
// Output: `PROBE_RESULT <json>` lines on stdout / logcat, and
// <systemTemp>/glass-probe.json (results) + glass-probe-status.json (phase).
// run.py / windows/probe.ps1 read them; print is intentional.
// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as lgw;

import 'variants.dart';

const _mode = String.fromEnvironment('MODE', defaultValue: 'all');
const _variantsArg = String.fromEnvironment('VARIANTS');
const _sceneHoldMs = int.fromEnvironment('SCENE_HOLD_MS', defaultValue: 4000);
const _scrollMs = int.fromEnvironment('SCROLL_MS', defaultValue: 8000);
const _rows = 1500;
const _rowHeight = 64.0;
const _a11y = MethodChannel('fmpx/a11y');

final _tmp = Directory.systemTemp.path;
final _statusFile = File('$_tmp/glass-probe-status.json');
final _resultFile = File('$_tmp/glass-probe.json');

/// `--plain` (desktop command line): skip liquid_glass_widgets' setup and
/// background scope, to tell whether the package affects the whole app.
bool _plain = false;

Future<void> main(List<String> args) async {
  _plain = args.contains('--plain');
  WidgetsFlutterBinding.ensureInitialized();
  if (_statusFile.existsSync()) _statusFile.deleteSync();
  if (_resultFile.existsSync()) _resultFile.deleteSync();
  try {
    refractProgram = await ui.FragmentProgram.fromAsset('shaders/refract.frag');
  } catch (e) {
    print('refract shader failed to load: $e');
  }
  if (_plain) {
    runApp(const ProbeApp());
    return;
  }
  await lgw.LiquidGlassWidgets.initialize(enablePerformanceMonitor: false);
  runApp(lgw.LiquidGlassWidgets.wrap(
    brightnessResolver: Theme.maybeBrightnessOf,
    child: const ProbeApp(),
  ));
}

class ProbeApp extends StatelessWidget {
  const ProbeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
      home: const ProbePage(),
    );
  }
}

class ProbePage extends StatefulWidget {
  const ProbePage({super.key});

  @override
  State<ProbePage> createState() => _ProbePageState();
}

class _ProbePageState extends State<ProbePage> {
  final _scroll = ScrollController();
  Variant _variant = Variant.solid;
  String _phase = 'start';
  final List<FrameTiming> _timings = [];
  bool _recording = false;

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  void _onTimings(List<FrameTiming> t) {
    if (_recording) _timings.addAll(t);
  }

  Future<Map<String, Object?>> _environment() async {
    final view = View.of(context);
    final display = view.display;
    Object? reduceTransparency;
    try {
      reduceTransparency = await _a11y.invokeMethod<Object?>('reduceTransparency');
    } on MissingPluginException {
      reduceTransparency = 'no channel';
    } on PlatformException catch (e) {
      reduceTransparency = 'error: ${e.message}';
    }
    final features = ui.PlatformDispatcher.instance.accessibilityFeatures;
    return {
      'platform': defaultTargetPlatform.name,
      'os': Platform.operatingSystemVersion,
      'plain': _plain,
      'buildMode': kReleaseMode ? 'release' : (kProfileMode ? 'profile' : 'debug'),
      'shaderFilterSupported': ui.ImageFilter.isShaderFilterSupported,
      'refractProgramLoaded': refractProgram != null,
      'refreshRate': display.refreshRate,
      'devicePixelRatio': view.devicePixelRatio,
      'logicalSize': [
        view.physicalSize.width / view.devicePixelRatio,
        view.physicalSize.height / view.devicePixelRatio,
      ],
      'a11y': {
        'reduceTransparency(native)': reduceTransparency,
        'highContrast': features.highContrast,
        'reduceMotion': features.reduceMotion,
        'disableAnimations': features.disableAnimations,
      },
    };
  }

  void _status(Map<String, Object?> s) {
    _statusFile.writeAsStringSync(jsonEncode(s));
    print('PROBE_STATUS ${jsonEncode(s)}');
  }

  Future<void> _settle(int ms) => Future<void>.delayed(Duration(milliseconds: ms));

  Future<void> _run() async {
    await _settle(1500);
    final env = await _environment();
    print('PROBE_ENV ${jsonEncode(env)}');
    final results = <String, Object?>{'env': env, 'variants': <Map<String, Object?>>[]};
    if (_mode == 'a11y') {
      _finish(results);
      return;
    }
    final variants = _variantsArg.isEmpty
        ? Variant.values
        : _variantsArg.split(',').map(Variant.byId).toList();
    var seq = 0;
    for (final v in variants) {
      seq++;
      setState(() {
        _variant = v;
        _phase = 'scene';
      });
      _scroll.jumpTo(_rowHeight * 3);
      await _settle(2500);
      _status({'phase': 'scene', 'variant': v.id, 'seq': seq});
      await _settle(_sceneHoldMs);

      setState(() => _phase = 'scroll');
      _status({'phase': 'scroll', 'variant': v.id, 'seq': seq});
      // Warm-up scroll (shader compilation, first backdrop reads) not recorded.
      await _scroll.animateTo(_scroll.offset + 1500,
          duration: const Duration(milliseconds: 1000), curve: Curves.linear);
      _timings.clear();
      _recording = true;
      // Constant 2000 px/s: every frame repaints the content under the glass.
      final distance = 2000.0 * _scrollMs / 1000;
      await _scroll.animateTo(_scroll.offset + distance,
          duration: const Duration(milliseconds: _scrollMs), curve: Curves.linear);
      _recording = false;
      await _settle(300); // let the last FrameTiming batch arrive
      final stats = _stats(_timings, env['refreshRate'] as double);
      final r = {'variant': v.id, ...stats};
      (results['variants'] as List).add(r);
      print('PROBE_RESULT ${jsonEncode(r)}');
    }
    _finish(results);
  }

  void _finish(Map<String, Object?> results) {
    _resultFile.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(results));
    _status({'phase': 'done'});
    setState(() => _phase = 'done');
  }

  Map<String, Object?> _stats(List<FrameTiming> t, double refreshRate) {
    double ms(Duration d) => d.inMicroseconds / 1000;
    List<double> sorted(Iterable<double> xs) => xs.toList()..sort();
    double pct(List<double> xs, double p) =>
        xs.isEmpty ? 0 : xs[math.min(xs.length - 1, (xs.length * p).floor())];
    Map<String, double> summary(List<double> xs) => {
          'p50': pct(xs, .5),
          'p90': pct(xs, .9),
          'p99': pct(xs, .99),
          'max': xs.isEmpty ? 0 : xs.last,
        };
    final build = sorted(t.map((f) => ms(f.buildDuration)));
    final raster = sorted(t.map((f) => ms(f.rasterDuration)));
    final budget = refreshRate > 0 ? 1000 / refreshRate : 16.7;
    int over(double limit) =>
        t.where((f) => ms(f.buildDuration) > limit || ms(f.rasterDuration) > limit).length;
    return {
      'frames': t.length,
      'expectedFrames': (_scrollMs / 1000 * (refreshRate > 0 ? refreshRate : 60)).round(),
      'buildMs': summary(build),
      'rasterMs': summary(raster),
      'over16_7ms': over(16.7),
      'budgetMs': budget,
      'overBudget': over(budget),
    };
  }

  Widget _list() => ListView.builder(
        controller: _scroll,
        itemExtent: _rowHeight,
        itemCount: _rows,
        itemBuilder: (context, i) => _Row(index: i),
      );

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    // Phone-width dock centred on wide windows.
    final dockLeft = math.max(0.0, (width - 390) / 2);
    return Scaffold(
      backgroundColor: const Color(0xFF121117),
      body: Stack(
        children: [
          Positioned.fill(
            child: _plain
                ? _list()
                : lgw.LiquidGlassScope(child: lgw.GlassBackgroundSource(child: _list())),
          ),
          // Top bar: a round button and a pill (.gbtn / .gpill).
          Positioned(
            top: 48,
            right: 16,
            child: Row(children: [
              GlassSurface(
                variant: _variant,
                width: 96,
                height: 44,
                radius: 22,
                child: Text(_variant.id, style: const TextStyle(fontSize: 10, color: Colors.white)),
              ),
              const SizedBox(width: 8),
              GlassSurface(
                variant: _variant,
                width: 44,
                height: 44,
                radius: 22,
                child: const Icon(Icons.more_horiz, color: Colors.white),
              ),
            ]),
          ),
          // Phone dock (DESIGN.md §5.1): mini player, nav pill, search button.
          Positioned(
            left: dockLeft + 14,
            bottom: 96,
            child: GlassSurface(
              variant: _variant,
              width: 362,
              height: 56,
              radius: 28,
              child: const Row(children: [
                SizedBox(width: 56),
                Expanded(
                  child: Text('Mini player 曲目標題',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                ),
                Icon(Icons.pause, color: Colors.white),
                SizedBox(width: 12),
                Icon(Icons.skip_next, color: Colors.white),
                SizedBox(width: 16),
              ]),
            ),
          ),
          Positioned(
            left: dockLeft + 14,
            bottom: 24,
            child: GlassSurface(
              variant: _variant,
              width: 290,
              height: 62,
              radius: 31,
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Icon(Icons.home, color: Colors.white),
                  Icon(Icons.library_music, color: Colors.white),
                  Icon(Icons.queue_music, color: Colors.white),
                  Icon(Icons.settings, color: Colors.white),
                ],
              ),
            ),
          ),
          Positioned(
            left: dockLeft + 314,
            bottom: 24,
            child: GlassSurface(
              variant: _variant,
              width: 62,
              height: 62,
              radius: 31,
              child: const Icon(Icons.search, color: Colors.white),
            ),
          ),
          Positioned(
            left: 8,
            top: 48,
            child: Text('$_phase · ${_variant.id}',
                style: const TextStyle(color: Colors.white, fontSize: 12, backgroundColor: Colors.black54)),
          ),
        ],
      ),
    );
  }
}

/// A test-pattern row: saturated hue band, vertical bars and large text, so
/// refraction (bent bars), dispersion (colour fringes) and blur are visible.
class _Row extends StatelessWidget {
  const _Row({required this.index});
  final int index;

  @override
  Widget build(BuildContext context) {
    final hue = (index * 23) % 360;
    final bg = HSVColor.fromAHSV(1, hue.toDouble(), .75, .95).toColor();
    return CustomPaint(
      painter: _BarsPainter(bg),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(children: [
          Container(width: 44, height: 44, color: index.isEven ? Colors.black : Colors.white),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '曲目 ${index.toString().padLeft(4, '0')}  Track title ABC',
              style: TextStyle(
                color: index.isEven ? Colors.black : Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ]),
      ),
    );
  }
}

class _BarsPainter extends CustomPainter {
  _BarsPainter(this.bg);
  final Color bg;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = bg);
    final bar = Paint()..color = const Color(0xFF000000);
    for (var x = 0.0; x < size.width; x += 24) {
      canvas.drawRect(Rect.fromLTWH(x, 0, 3, size.height), bar);
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) => old.bg != bg;
}
