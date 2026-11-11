// 實驗用（可丟棄）：啟動就跑 fjs 的全部測項，見 ../README.md。
import 'package:fjs/fjs.dart';
import 'package:probe_common/probe_app.dart';
import 'package:probe_fjs/fjs_probe.dart';

void main() => runProbeApp(
  slug: 'fjs',
  setUp: () async {
    await LibFjs.init();
    return FjsProbe();
  },
);
