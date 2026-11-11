// 實驗用（可丟棄）：M0 票 04。flutter_inappwebview 6.1.5 開一個公開網頁，
// 載入完成時讀回 document.title，寫成 JSON 檔並印出 `PROBE_FILE <路徑>`，
// run.sh 依路徑取回存到 results/。App 不自己結束：畫面要留著給 run.sh 截圖。

// run.sh 從 stdout／logcat 讀 PROBE_FILE、PROBE_RESULT，所以要用 print。
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

const _url = 'https://example.com/';

void main() => runApp(const ProbeApp());

class ProbeApp extends StatelessWidget {
  const ProbeApp({super.key});

  @override
  Widget build(BuildContext context) =>
      const MaterialApp(debugShowCheckedModeBanner: false, home: ProbePage());
}

class ProbePage extends StatefulWidget {
  const ProbePage({super.key});

  @override
  State<ProbePage> createState() => _ProbePageState();
}

class _ProbePageState extends State<ProbePage> {
  String _status = 'PROBE loading $_url';
  bool _reported = false;

  Future<void> _report(Map<String, Object?> result) async {
    if (_reported) return;
    _reported = true;
    final json = {
      'platform': Platform.operatingSystem,
      'url': _url,
      ...result,
      'at': DateTime.now().toUtc().toIso8601String(),
    };
    final out = File('${Directory.systemTemp.path}/inappwebview-probe.json');
    await out.writeAsString(const JsonEncoder.withIndent('  ').convert(json));
    print('PROBE_RESULT ${jsonEncode(json)}');
    print('PROBE_FILE ${out.path}');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Column(
        children: [
          Container(
            width: double.infinity,
            color: Colors.amber,
            padding: const EdgeInsets.all(8),
            child: Text(_status, key: const Key('status')),
          ),
          Expanded(
            child: InAppWebView(
              initialUrlRequest: URLRequest(url: WebUri(_url)),
              onLoadStop: (controller, url) async {
                final title = await controller.evaluateJavascript(
                  source: 'document.title',
                );
                final ua = await controller.evaluateJavascript(
                  source: 'navigator.userAgent',
                );
                setState(() => _status = 'PROBE loaded: $title');
                await _report({
                  'ok': true,
                  'loadedUrl': url?.toString(),
                  'title': title,
                  'userAgent': ua,
                });
              },
              onReceivedError: (controller, request, error) async {
                if (request.isForMainFrame != true) return;
                setState(() => _status = 'PROBE error: ${error.description}');
                await _report({
                  'ok': false,
                  'error': '${error.type} ${error.description}',
                });
              },
            ),
          ),
        ],
      ),
    ),
  );
}
