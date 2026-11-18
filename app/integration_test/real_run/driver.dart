import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/main.dart' as app;
import 'package:fmp/playback/audio_backend.dart';
import 'package:fmp/playback/playback.dart';
import 'package:fmp/ui/home/home_page.dart';

import '../../test/support/scratch_data.dart';

/// 實跑驅動（docs/development.md〈實跑驅動〉）：在真的平台上開真的 App、打真的
/// 音源，用 `tester` 在 Flutter 裡點擊與打字（系統游標不動），每一步請系統的
/// 截圖工具截 App 視窗，並讀回畫面上的文字。
///
/// 情境檔是 `integration_test/real_run/*_run.dart`：不是 `_test.dart`，完整閘門
/// 與零聯網守門都不收它（architecture〈測試策略〉），由 `tool/real_run.dart`
/// 指名執行。截圖交給誰由那支工具帶的 dart-define 決定：
///
/// - `FMP_REAL_RUN_HOST`：Mac 上的截圖服務（`tool/src/real_run_host.dart`），
///   macOS、iOS 模擬器、Android 模擬器（經 `adb reverse`）。
/// - `FMP_REAL_RUN_DIR` 加 `FMP_REAL_RUN_SHOT_PS1`：Windows。App 就在 `winpc`
///   的桌面工作階段裡，直接跑 `shot.ps1 -AppPid` 截自己的視窗，檔案存在那個目錄。
class RealRun {
  RealRun._(this.tester, this._capture);

  final WidgetTester tester;
  final _Capture _capture;
  int _steps = 0;

  /// 開 App（`main.dart`，真的音源），等到首頁出現，先截一張
  /// `01-launch`：啟動後還沒動過視窗的樣子（票 05d）。
  ///
  /// App 的資料用隔離的目錄（`FMP_SCRATCH_DATA`，[useScratchData]），開 App
  /// 前先清空，不碰 dev 版的資料庫、log 與快取；沒帶就不跑，免得刪到真的資料。
  /// [keepData] 時不清空，接著上一個情境留下的資料開，像重開 App。
  /// [wrapAudioBackend] 包住這個平台的音訊後端（`runFmp`）。
  static Future<RealRun> launch(
    WidgetTester tester, {
    bool keepData = false,
    AudioBackend Function(AudioBackend backend)? wrapAudioBackend,
  }) async {
    final run = RealRun._(tester, _Capture.fromEnvironment());
    await useScratchData(
      fresh: !keepData,
      howToRun:
          'Real runs keep their data apart from the dev app: run this file '
          'with `dart run tool/real_run.dart` (docs/development.md〈實跑驅動〉).',
    );
    await app.runFmp(wrapAudioBackend: wrapAudioBackend);
    await run.waitFor(find.byType(HomePage));
    await run.step('launch');
    return run;
  }

  /// 不開真的 App，只接上截圖：情境自己 `pumpWidget`（例如假的搜尋狀態、
  /// 不聯網），每一步照樣用系統工具截圖並讀回。截畫面的各種狀態用，不是
  /// 實跑的主要流程，沒有 `01-launch`。
  static RealRun attach(WidgetTester tester) =>
      RealRun._(tester, _Capture.fromEnvironment());

  /// 一邊 pump 一邊真的等，直到 [finder] 找得到東西；超過 [timeout] 就讓測試
  /// 失敗。不用 `pumpAndSettle`：畫面上可能有不停的動畫。
  Future<void> waitFor(
    Finder finder, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (finder.evaluate().isEmpty && DateTime.now().isBefore(deadline)) {
      await _settle(const Duration(milliseconds: 100));
    }
    expect(finder, findsWidgets);
  }

  /// 一邊 pump 一邊真的等，直到播放狀態（`playbackProvider`）是 [status]；
  /// 超過 [timeout] 就讓測試失敗。
  Future<void> waitForStatus(
    PlaybackStatus status, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    // 從最上層的 Navigator 拿：哪一頁在前面都在它底下。
    final container = ProviderScope.containerOf(
      tester.element(find.byType(Navigator).first),
    );
    final deadline = DateTime.now().add(timeout);
    while (container.read(playbackProvider)?.status != status &&
        DateTime.now().isBefore(deadline)) {
      await _settle(const Duration(milliseconds: 100));
    }
    expect(container.read(playbackProvider)?.status, status);
  }

  /// 記下一步：截圖存成 `NN-<name>.png`，讀回的文字（[readBack]）存成
  /// `NN-<name>.txt`，也印到輸出。[within] 只讀那一塊，省略時讀整個畫面。
  /// 回傳讀回的每一行。
  Future<List<String>> step(String name, {Finder? within}) async {
    final file = '${(++_steps).toString().padLeft(2, '0')}-$name';
    // 讓這一幀真的畫上螢幕，動畫跑完一段，再請系統截圖。
    await _settle(const Duration(milliseconds: 800));
    final lines = readBack(tester, within);
    await tester.runAsync(() async {
      await _capture.shot(file);
      await _capture.text(file, '${lines.join('\n')}\n');
    });
    // ignore: avoid_print -- 讀回的文字也留在實跑的輸出裡，不必開檔就看得到。
    print('[real run] $file\n  ${lines.join('\n  ')}');
    return lines;
  }

  /// 請宿主做一件系統的事（`tool/real_run_system.sh` 的 [action]，例如
  /// `background`、`notification`、`tap Pause`），記成一步 `NN-<name>`：
  /// 讀回的文字存成 `.txt`，要截系統畫面的動作存成 `.png`。不 pump：App 在
  /// 背景時不出幀，pump 會卡住。只有 macOS、iOS、Android（Windows 跳過）。
  Future<String> system(
    String name,
    String action, [
    List<String> args = const [],
  ]) async {
    final file = '${(++_steps).toString().padLeft(2, '0')}-$name';
    final text = await tester.runAsync(
      () => _capture.system(file, action, args),
    );
    // ignore: avoid_print -- 讀回的文字也留在實跑的輸出裡。
    print(
      '[real run] $file ($action ${args.join(' ')})\n  '
      '${text!.trim().split('\n').join('\n  ')}',
    );
    return text;
  }

  Future<void> _settle(Duration duration) async {
    final until = DateTime.now().add(duration);
    do {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
    } while (DateTime.now().isBefore(until));
  }
}

/// 畫面上看得到的文字，照元件樹的順序一行一個：每個 [RichText]（[Text]
/// 也是畫成它）有大小、和視窗有交集才算；圖示字型的字（Unicode 私用區）
/// 略過。[within] 只讀那一塊，省略時讀整個畫面。實跑每一步的讀回用它。
List<String> readBack(WidgetTester tester, [Finder? within]) {
  final paragraphs = within == null
      ? find.byType(RichText)
      : find.descendant(of: within, matching: find.byType(RichText));
  final view = tester.view;
  final screen = Offset.zero & (view.physicalSize / view.devicePixelRatio);
  return [
    for (final element in paragraphs.evaluate())
      if (element.renderObject case final RenderBox box
          when box.attached &&
              box.hasSize &&
              !box.size.isEmpty &&
              MatrixUtils.transformRect(
                box.getTransformTo(null),
                Offset.zero & box.size,
              ).overlaps(screen))
        if ((element.widget as RichText).text.toPlainText().trim()
            case final text when text.isNotEmpty && !_iconGlyphs(text))
          text,
  ];
}

bool _iconGlyphs(String text) =>
    text.runes.every((r) => r >= 0xE000 && r <= 0xF8FF);

/// 截圖與文字交給誰（[RealRun] 的說明）。
sealed class _Capture {
  factory _Capture.fromEnvironment() {
    const host = String.fromEnvironment('FMP_REAL_RUN_HOST');
    const dir = String.fromEnvironment('FMP_REAL_RUN_DIR');
    const shotPs1 = String.fromEnvironment('FMP_REAL_RUN_SHOT_PS1');
    if (host.isNotEmpty) return _HostCapture(Uri.parse(host));
    if (dir.isNotEmpty && shotPs1.isNotEmpty) {
      return _LocalCapture(Directory(dir), shotPs1);
    }
    throw StateError(
      'Real runs take their screenshots with the system tools: run this file '
      'with `dart run tool/real_run.dart` (docs/development.md〈實跑驅動〉).',
    );
  }

  Future<void> shot(String name);
  Future<void> text(String name, String body);
  Future<String> system(String name, String action, List<String> args);
}

final class _HostCapture implements _Capture {
  _HostCapture(this.host);

  final Uri host;

  @override
  Future<void> shot(String name) => _send(
    'GET',
    host.replace(path: '/shot', queryParameters: {'name': name, 'pid': '$pid'}),
  );

  @override
  Future<void> text(String name, String body) => _send(
    'POST',
    host.replace(path: '/text', queryParameters: {'name': name}),
    body: body,
  );

  @override
  Future<String> system(String name, String action, List<String> args) => _send(
    'GET',
    host.replace(
      path: '/system',
      queryParameters: {
        'name': name,
        'action': action,
        'arg': args,
        'pid': '$pid',
      },
    ),
  );

  Future<String> _send(String method, Uri uri, {String body = ''}) async {
    final client = HttpClient();
    try {
      final request = await client.openUrl(method, uri);
      request.add(utf8.encode(body));
      final response = await request.close();
      final reply = await utf8.decodeStream(response);
      if (response.statusCode != HttpStatus.ok) {
        throw StateError('$method $uri: ${response.statusCode} $reply');
      }
      return reply;
    } finally {
      client.close();
    }
  }
}

final class _LocalCapture implements _Capture {
  _LocalCapture(this.dir, this.shotPs1);

  final Directory dir;
  final String shotPs1;

  @override
  Future<void> shot(String name) async {
    dir.createSync(recursive: true);
    final out = '${dir.path}/$name.png';
    final result = await Process.run('powershell.exe', [
      '-NoProfile',
      '-ExecutionPolicy',
      'Bypass',
      '-File',
      shotPs1,
      '-AppPid',
      '$pid',
      '-Out',
      out,
    ]);
    if (result.exitCode != 0 || !File(out).existsSync()) {
      throw StateError(
        'shot.ps1 -AppPid $pid failed (${result.exitCode}): '
        '${result.stdout}${result.stderr}',
      );
    }
  }

  @override
  Future<void> text(String name, String body) async {
    dir.createSync(recursive: true);
    File('${dir.path}/$name.txt').writeAsStringSync(body);
  }

  @override
  Future<String> system(String name, String action, List<String> args) =>
      throw UnsupportedError(
        'System actions are not wired up on Windows yet (Windows is skipped '
        'for now, docs/decisions.md).',
      );
}
