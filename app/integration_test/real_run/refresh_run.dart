import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/app/i18n/strings.g.dart';
import 'package:fmp/core/log/log.dart';
import 'package:fmp/domain/audio_stream.dart';
import 'package:fmp/platform/app_data_directory.dart';
import 'package:fmp/platform/log_directory.dart';
import 'package:fmp/playback/audio_backend.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../test/support/local_audio_server.dart';
import '../../test/support/shell.dart';
import 'driver.dart';

/// 票 11 的實跑情境：串流壞掉時重新解析一次。匿名搜一次「lofi」、臨時播放
/// 第一首；第一次載入換成本機假 CDN 的網址（一律回 403，像過期的網址），
/// App 重新解析（再打一次真的 B 站）後播出聲、不跳提示。讀回畫面與 log；
/// log 記的 CDN 主機是插件給的那條（網址是在後端裡換掉的）。
/// 跑法見 docs/development.md〈實跑驅動〉：
///
///     dart run tool/real_run.dart -d macos integration_test/real_run/refresh_run.dart
///
/// 解析兩次，比 spec〈共同規則〉的「播一首」多一次：驗收要的就是重新解析。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a refused stream is resolved again and plays', (tester) async {
    final cdn = (await tester.runAsync(
      () => LocalAudioServer.start(refuse: (_) => true),
    ))!;
    addTearDown(() => tester.runAsync(cdn.close));
    final run = await RealRun.launch(
      tester,
      wrapAudioBackend: (backend) => _FirstLoadRefused(backend, cdn.url()),
    );

    await openSearch(tester);
    await tester.enterText(find.byType(TextField), 'lofi');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    final more = find.byTooltip(t.queue.more);
    await run.waitFor(more);
    await run.step('search');

    await playSearchResult(tester, searchResultAt(0));
    await run.waitFor(
      find.text(t.placeholder.playback.playing),
      timeout: const Duration(seconds: 60),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 5)),
    );
    final screen = await run.step('playing');

    expect(cdn.requests, isNotEmpty);
    expect(cdn.requests.map((r) => r.status), everyElement(403));
    expect(screen.where((line) => line.contains('無法播放')), isEmpty);
    final log = (await tester.runAsync(() async {
      final file = File(
        '${logDirectory(await appDataDirectory()).path}/${Log.fileName}',
      );
      return file.readAsLines();
    }))!;
    final lines = [
      for (final line in log)
        if (line.contains('Playback failed') ||
            line.contains('Resolving the stream') ||
            line.contains('Audio session') ||
            line.contains('mpv options') ||
            line.contains('Playback stalled'))
          line,
    ];
    // ignore: avoid_print -- 讀回的 log 留在實跑的輸出裡，寫進票的 Comments。
    print('[refresh log]\n  ${lines.join('\n  ')}');
    expect(lines.where((l) => l.contains('Playback failed')), hasLength(1));
    expect(
      lines.where((l) => l.contains('Resolving the stream again')),
      hasLength(1),
    );
  });
}

/// 第一次載入改開 [refused]（假 CDN 一律回 403），之後照原樣交給 [_backend]。
/// 換掉的那條不是播放層給的物件，它的狀態播放層不認（只認自己的串流）；
/// 403 在載入時就丟錯，不靠狀態。
class _FirstLoadRefused implements AudioBackend {
  _FirstLoadRefused(this._backend, this.refused);

  final AudioBackend _backend;
  final Uri refused;
  var _loads = 0;

  @override
  AudioBackendState get state => _backend.state;

  @override
  Stream<AudioBackendState> get states => _backend.states;

  @override
  Future<void> load(AudioStream stream) => _backend.load(
    _loads++ == 0
        ? AudioStream(
            url: refused,
            headers: stream.headers,
            expiresAt: stream.expiresAt,
          )
        : stream,
  );

  @override
  Future<void> preload(AudioStream? stream) => _backend.preload(stream);

  @override
  Future<void> play() => _backend.play();

  @override
  Future<void> pause() => _backend.pause();

  @override
  Future<void> seek(Duration position) => _backend.seek(position);

  @override
  Future<void> dispose() => _backend.dispose();
}
