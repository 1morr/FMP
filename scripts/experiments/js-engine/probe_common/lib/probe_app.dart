// 實驗用（可丟棄）：probe app 的進入點。啟動就跑全部測項，不需要主機連線
// （`flutter test` 走 adb／VM service，連線一斷就判失敗，但裝置上的 App 其實跑完了）。
//
// 結果三處都有：畫面、log 的 `PROBE_RESULT` 一行、`<暫存目錄>/js-engine-probe-<slug>.json`。
// 跑完就結束行程，讓 run.sh 與 Windows 的排程工作知道做完了。
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'package:probe_common/probe_common.dart';

Future<void> runProbeApp({
  required String slug,
  required Future<Probe> Function() setUp,
}) async {
  WidgetsFlutterBinding.ensureInitialized();
  final status = ValueNotifier<String>('running…');
  runApp(
    MaterialApp(
      home: Scaffold(
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ValueListenableBuilder(
              valueListenable: status,
              builder: (_, s, _) =>
                  SelectableText(s, style: const TextStyle(fontSize: 12)),
            ),
          ),
        ),
      ),
    ),
  );

  Map<String, Object?> report;
  try {
    final probe = await setUp();
    report = await runProbe(
      probe,
      platform:
          '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
    );
  } catch (e, st) {
    report = {'slug': slug, 'setup_error': '$e\n$st'};
    // ignore: avoid_print -- 實驗輸出就是 log
    print('PROBE_RESULT ${jsonEncode(report)}');
  }
  final pretty = const JsonEncoder.withIndent('  ').convert(report);
  status.value = pretty;
  final out = File('${Directory.systemTemp.path}/js-engine-probe-$slug.json');
  await out.writeAsString(pretty);
  // ignore: avoid_print -- 實驗輸出就是 log
  print('PROBE_FILE ${out.path}');
  // 跑完就結束，run.sh 等行程結束或 log 出現 PROBE_FILE 就收結果。
  await Future<void>.delayed(const Duration(seconds: 1));
  exit(0);
}
