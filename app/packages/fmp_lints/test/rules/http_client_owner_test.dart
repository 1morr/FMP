import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:fmp_lints/src/rules/http_client_owner.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import '../support/rule_test_base.dart';

void main() {
  defineReflectiveSuite(() => defineReflectiveTests(HttpClientOwnerTest));
}

@reflectiveTest
class HttpClientOwnerTest extends FmpRuleTest {
  @override
  AnalysisRule createRule() => HttpClientOwner();

  @override
  void addStubPackages() {
    newPackage('dio').addFile('lib/dio.dart', '''
class Dio {
  Dio([Object? options]);
  Dio.withAdapter(Object adapter);
}
class DioOptions {}
''');
  }

  // 報

  Future<void> test_constructedOutsideNetwork() =>
      assertLints('lib/plugins/host_api.dart', '''
import 'package:dio/dio.dart';

final a = [!Dio!]();
final b = [!Dio.withAdapter!](Object());
''');

  // 不報

  Future<void> test_insideNetwork() =>
      assertLints('lib/core/network/http.dart', '''
import 'package:dio/dio.dart';

final a = Dio();
''');

  Future<void> test_inTests() =>
      assertLints('test/core/network/http_test.dart', '''
import 'package:dio/dio.dart';

final a = Dio();
''');

  Future<void> test_nearMisses() => assertLints('lib/plugins/host_api.dart', '''
import 'package:dio/dio.dart';

// Dio()
final options = DioOptions();
Dio? client;
const text = 'Dio()';
''');
}
