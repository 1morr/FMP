import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// `app/` 用獨立套件 `material_ui`，不 import 框架內凍結的設計系統函式庫
/// （app/AGENTS.md § Material）。M1 PR 3 的 `fmp_lints` 接手後刪掉本檔。
void main() {
  test('lib/ and test/ import no in-framework design library', () {
    final offenders = <String>[
      for (final directory in ['lib', 'test'])
        for (final file in Directory(directory).listSync(recursive: true))
          if (file is File && file.path.endsWith('.dart'))
            for (final uri in frameworkDesignImports(file.readAsStringSync()))
              '${p.normalize(file.path)}: $uri',
    ];
    expect(offenders, isEmpty);
  });

  group('mutations', () {
    test('an import or export of the frozen libraries is reported', () {
      expect(
        frameworkDesignImports(
          "import 'package:flutter/material.dart';\n"
          'import "package:flutter/cupertino.dart" as c;\n'
          "  export 'package:flutter/material.dart' show Colors;\n",
        ),
        [
          'package:flutter/material.dart',
          'package:flutter/cupertino.dart',
          'package:flutter/material.dart',
        ],
      );
    });

    test('the standalone packages, other flutter libraries and comments '
        'are not', () {
      expect(
        frameworkDesignImports(
          "import 'package:material_ui/material_ui.dart';\n"
          'import "package:flutter/widgets.dart";\n'
          "// import 'package:flutter/material.dart';\n"
          "/// See package:flutter/material.dart for the frozen copy.\n",
        ),
        isEmpty,
      );
    });
  });
}

final _directive = RegExp(
  r'''^\s*(?:import|export)\s+['"](package:flutter/(?:material|cupertino)\.dart)['"]''',
  multiLine: true,
);

/// [source] 裡 import／export 框架內 Material 或 Cupertino 的 URI。
List<String> frameworkDesignImports(String source) => [
  for (final match in _directive.allMatches(source)) match.group(1)!,
];
