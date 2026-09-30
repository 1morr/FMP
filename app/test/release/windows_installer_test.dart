import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `windows/installer/fmp.iss` 與舊版安裝檔相容的幾項（檔頭註解標「閘門」的那些；
/// ADR 0008 §決定 3、ADR 0022 §決定 4）。Inno Setup 在 CI 的 Linux 上沒有，這裡
/// 解析腳本；最後一組變異證明違規會被抓到、無關的寫法差異不影響結果。
void main() {
  final script = File('windows/installer/fmp.iss')
      .readAsStringSync()
      .replaceAll('\r\n', '\n');

  test('the script keeps the legacy installer identity', () {
    expect(installerProblems(script), isEmpty);
  });

  test('the script is UTF-8 with a BOM', () {
    // 沒有 BOM 時 ISCC 以 ANSI 讀，中文註解會變成亂碼。
    expect(File('windows/installer/fmp.iss').readAsBytesSync().take(3), [
      0xEF,
      0xBB,
      0xBF,
    ]);
  });

  group('mutations', () {
    String mutate(String from, String to) {
      expect(script, contains(from), reason: 'the mutation did not apply');
      return script.replaceFirst(from, to);
    }

    const appId = 'AppId=BAF6CE8D-E1C8-4C29-AE0B-EDE98D5F8FAA';

    test('red on an AppId in braces or another AppId', () {
      expect(
        installerProblems(
          mutate(appId, 'AppId={{BAF6CE8D-E1C8-4C29-AE0B-EDE98D5F8FAA}'),
        ),
        [
          'AppId is {{BAF6CE8D-E1C8-4C29-AE0B-EDE98D5F8FAA}, expected '
              '$legacyAppId',
        ],
      );
      expect(installerProblems(mutate('$appId\n', '')), [
        'AppId is null, expected $legacyAppId',
      ]);
    });

    test('red on another install location or privilege', () {
      expect(
        installerProblems(
          mutate(
            '\nPrivilegesRequired=lowest\n',
            '\nPrivilegesRequired=admin\n',
          ),
        ),
        ['PrivilegesRequired is admin, expected lowest'],
      );
      expect(
        installerProblems(
          mutate(
            r'DefaultDirName={autopf}\FMP',
            r'DefaultDirName={autopf}\fmp2',
          ),
        ),
        [r'DefaultDirName is {autopf}\fmp2, expected {autopf}\FMP'],
      );
    });

    test('red on a shortcut without the AppUserModelID', () {
      expect(
        installerProblems(
          mutate(
            r'Name: "{autodesktop}\FMP"; Filename: "{app}\fmp.exe"; '
                r'AppUserModelID: "com.personal.fmp"; ',
            r'Name: "{autodesktop}\FMP"; Filename: "{app}\fmp.exe"; ',
          ),
        ),
        [r'the shortcut {autodesktop}\FMP has AppUserModelID null'],
      );
    });

    test('red on a launch that skips silent installs', () {
      expect(
        installerProblems(
          mutate(
            'Flags: nowait postinstall',
            'Flags: nowait postinstall skipifsilent',
          ),
        ),
        [r'[Run] {app}\fmp.exe skips silent installs'],
      );
    });

    test('not red on case, spacing, quoting and comments', () {
      final respelled =
          mutate(
                appId,
                '; the legacy id\nappid = BAF6CE8D-E1C8-4C29-AE0B-EDE98D5F8FAA',
              )
              .replaceFirst(
                '\nPrivilegesRequired=lowest\n',
                '\nprivilegesrequired = Lowest\n',
              )
              .replaceFirst(
                r'AppUserModelID: "com.personal.fmp"; Tasks',
                r'Tasks: desktopicon ;appusermodelid:"com.personal.fmp";Tasks',
              )
              .replaceFirst('[Icons]', '[icons]');
      expect(respelled, isNot(script));
      expect(installerProblems(respelled), isEmpty);
    });
  });
}

/// 舊版的 AppId（舊專案 `pubspec.yaml` 的 `inno_bundle.id`，inno_bundle 寫成
/// `AppId=<id>`，不加大括號）。
const legacyAppId = 'BAF6CE8D-E1C8-4C29-AE0B-EDE98D5F8FAA';

/// 回傳違反的條目。Inno Setup 的區段名、指示名、參數名都不分大小寫。
List<String> installerProblems(String iss) {
  final sections = <String, List<String>>{};
  var current = '';
  for (final raw in iss.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith(';') || line.startsWith('#')) continue;
    final header = RegExp(r'^\[(\w+)\]$').firstMatch(line);
    if (header != null) {
      current = header.group(1)!.toLowerCase();
      continue;
    }
    (sections[current] ??= []).add(line);
  }

  final setup = {
    for (final line in sections['setup'] ?? const <String>[])
      if (line.indexOf('=') case final i when i > 0)
        line.substring(0, i).trim().toLowerCase(): line.substring(i + 1).trim(),
  };
  final problems = <String>[];
  void expectSetup(String name, String expected, {bool ignoreCase = false}) {
    final actual = setup[name.toLowerCase()];
    final same = ignoreCase
        ? actual?.toLowerCase() == expected.toLowerCase()
        : actual == expected;
    if (!same) problems.add('$name is $actual, expected $expected');
  }

  expectSetup('AppId', legacyAppId);
  expectSetup('PrivilegesRequired', 'lowest', ignoreCase: true);
  expectSetup('DefaultDirName', r'{autopf}\FMP');

  final icons = (sections['icons'] ?? const []).map(_entry).toList();
  if (icons.isEmpty) problems.add('no shortcuts');
  for (final icon in icons) {
    final id = icon['appusermodelid'];
    if (id != 'com.personal.fmp') {
      problems.add('the shortcut ${icon['name']} has AppUserModelID $id');
    }
  }
  for (final run in (sections['run'] ?? const []).map(_entry)) {
    final flags = (run['flags'] ?? '').toLowerCase().split(RegExp(r'\s+'));
    if (flags.contains('skipifsilent')) {
      problems.add('[Run] ${run['filename']} skips silent installs');
    }
  }
  return problems;
}

/// `Name: "value"; Other: value` 形式的一筆；參數名轉小寫、值去掉引號。
Map<String, String> _entry(String line) => {
  for (final match in RegExp(
    r'(\w+)\s*:\s*("(?:[^"]|"")*"|[^;]*)',
  ).allMatches(line))
    match.group(1)!.toLowerCase(): _unquote(match.group(2)!.trim()),
};

String _unquote(String value) =>
    value.length >= 2 && value.startsWith('"') && value.endsWith('"')
    ? value.substring(1, value.length - 1).replaceAll('""', '"')
    : value;
