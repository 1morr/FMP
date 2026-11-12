import 'dart:ui' show AppExitResponse;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:fmp/playback/audio_backend.dart';
import 'package:fmp/playback/playback.dart';

/// `main` 用的 [audioBackendProvider]：第一次播放時用 [create] 建後端，
/// App 要結束時（例如 Windows 關視窗）先釋放它再結束。
///
/// 不先釋放的話，media_kit 的 libmpv 執行緒在 Dart VM 關掉後還呼叫 FFI
/// callback，整個行程崩潰（brief 事實 W11）。沒播過就沒有後端，結束時什麼都
/// 不用做。後端只釋放一次。
Override audioBackendOverride(AudioBackend Function() create) =>
    audioBackendProvider.overrideWith((ref) {
      final backend = create();
      Future<void>? disposing;
      Future<void> dispose() => disposing ??= backend.dispose();
      final exit = AppLifecycleListener(
        onExitRequested: () async {
          await dispose();
          return AppExitResponse.exit;
        },
      );
      ref.onDispose(() {
        exit.dispose();
        dispose();
      });
      return backend;
    });
