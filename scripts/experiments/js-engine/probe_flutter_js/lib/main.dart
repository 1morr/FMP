// 實驗用（可丟棄）：啟動就跑 flutter_js 的全部測項，見 ../README.md。
import 'package:probe_common/probe_app.dart';
import 'package:probe_flutter_js/flutter_js_probe.dart';

void main() =>
    runProbeApp(slug: 'flutter_js', setUp: () async => FlutterJsProbe());
