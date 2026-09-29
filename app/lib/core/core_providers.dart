import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fmp/core/logging/log.dart';
import 'package:fmp/core/redaction/redactor.dart';

/// App 唯一的 log 門面（ADR 0011 §決定 1）。`main()` 建立後以 override 注入；
/// 沒 override 就讀會拋錯。
final logProvider = Provider<Log>(
  (ref) => throw UnimplementedError(
    'logProvider is overridden by main() with the app log',
  ),
);

/// 門面用的那一個 [Redactor]（ADR 0011 §決定 3）。插件的遮蔽名單加在它身上，
/// log 才遮得到；所以同樣由 `main()` 注入，不另建實例。
final redactorProvider = Provider<Redactor>(
  (ref) => throw UnimplementedError(
    'redactorProvider is overridden by main() with the log redactor',
  ),
);
