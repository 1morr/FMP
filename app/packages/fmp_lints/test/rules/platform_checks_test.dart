import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:fmp_lints/src/rules/platform_checks.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import '../support/rule_test_base.dart';

void main() {
  defineReflectiveSuite(() => defineReflectiveTests(PlatformChecksTest));
}

@reflectiveTest
class PlatformChecksTest extends FmpRuleTest {
  @override
  AnalysisRule createRule() => PlatformChecks();

  @override
  void addStubPackages() {
    newPackage('flutter').addFile('lib/foundation.dart', '''
enum TargetPlatform { android, windows }
TargetPlatform get defaultTargetPlatform => TargetPlatform.android;
''');
  }

  // 報

  Future<void> test_platformChecksOutsidePlatform() =>
      assertLints('lib/playback/controller.dart', '''
import 'dart:io';
import 'dart:io' as io;

import 'package:flutter/foundation.dart';

bool a() => Platform.[!isAndroid!];
bool b() => io.Platform.[!isWindows!];
String c() => Platform.[!operatingSystem!];
bool d() => [!defaultTargetPlatform!] == [!TargetPlatform!].android;
[!TargetPlatform!]? e;
''');

  // 不報

  Future<void> test_insidePlatform() =>
      assertLints('lib/platform/audio_backend/audio_backend.dart', '''
import 'dart:io';

import 'package:flutter/foundation.dart';

bool a() => Platform.isAndroid;
bool b() => defaultTargetPlatform == TargetPlatform.windows;
''');

  Future<void> test_outsideLib() => assertLints('test/platform/x_test.dart', '''
import 'dart:io';

bool a() => Platform.isWindows;
''');

  Future<void> test_nearMisses() =>
      assertLints('lib/playback/controller.dart', '''
import 'dart:io';

class Device {
  bool isAndroid = false;
}

// Platform.isAndroid
const text = 'defaultTargetPlatform';
bool a(Device platform) => platform.isAndroid;
String b() => Platform.localHostname;
''');
}
