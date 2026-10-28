import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/app_flavor.dart';

/// iOS 與 macOS 的 App 身分（app/AGENTS.md § App 身分）：prod 的 bundle
/// identifier 是 `com.personal.fmp`，dev 每一項都不同（ADR 0015 §決定 8）。
///
/// CI 跑這個測試的 Linux 沒有 Xcode，所以讀 `Runner.xcodeproj/project.pbxproj`
/// （OpenStep 格式的 plist，這裡照格式解析，不比對字串）、scheme 與 Info.plist
/// 算出每個 flavor 的值。flutter 工具以 flavor 找 scheme，再用
/// `<Debug|Profile|Release>-<flavor>` 這個名稱找 build configuration（不分
/// 大小寫，flutter_tools `lib/src/ios/xcodeproj.dart` 的 `XcodeProjectInfo`）；
/// 解析以最後一組變異案例驗證：違規會被算出來、無關的格式改動不影響結果。
void main() {
  for (final platform in ['ios', 'macos']) {
    group(platform, () {
      final project = XcodeProject.parse(
        File('$platform/Runner.xcodeproj/project.pbxproj').readAsStringSync(),
      );
      final infoPlist = File('$platform/Runner/Info.plist').readAsStringSync();

      test('prod is com.personal.fmp named FMP', () {
        expect(project.bundleIds(AppFlavor.prod), {'com.personal.fmp'});
        expect(project.displayNames(AppFlavor.prod), {'FMP'});
      });

      test('dev differs in every identity value', () {
        expect(project.bundleIds(AppFlavor.dev), {'com.personal.fmp.dev'});
        expect(project.displayNames(AppFlavor.dev), {'FMP Dev'});
      });

      test('the Dart display name matches the Apple display name', () {
        for (final flavor in AppFlavor.values) {
          expect(project.displayNames(flavor), {
            flavor.displayName,
          }, reason: flavor.name);
        }
      });

      test('Info.plist takes the name from APP_DISPLAY_NAME', () {
        expect(plistString(infoPlist, 'CFBundleDisplayName'), displayNameRef);
        if (platform == 'macos') {
          // 選單列的 App 名稱讀 CFBundleName。
          expect(plistString(infoPlist, 'CFBundleName'), displayNameRef);
        }
      });

      test('every target has each flavor configuration on the same base', () {
        expect(project.flavorConfigurationProblems(), isEmpty);
      });

      for (final flavor in AppFlavor.values) {
        test('the ${flavor.name} scheme uses its own configurations', () {
          final scheme = File(
            '$platform/Runner.xcodeproj/xcshareddata/xcschemes/'
            '${flavor.name}.xcscheme',
          ).readAsStringSync();
          expect(schemeConfigurations(scheme), {
            'TestAction': 'Debug-${flavor.name}',
            'LaunchAction': 'Debug-${flavor.name}',
            'ProfileAction': 'Profile-${flavor.name}',
            'AnalyzeAction': 'Debug-${flavor.name}',
            'ArchiveAction': 'Release-${flavor.name}',
          });
        });
      }

      if (platform == 'macos') {
        // ADR 0036 §決定 2、4、7、10。
        test('the app is not sandboxed and has no keychain access group', () {
          for (final name in ['DebugProfile', 'Release']) {
            final keys = plistKeys(
              File('macos/Runner/$name.entitlements').readAsStringSync(),
            );
            expect(keys, isNot(contains(sandboxEntitlement)), reason: name);
            expect(
              keys,
              isNot(contains(keychainGroupsEntitlement)),
              reason: name,
            );
          }
        });

        test('Info.plist keeps one instance and allows plain HTTP media', () {
          expect(plistTrue(infoPlist, 'LSMultipleInstancesProhibited'), isTrue);
          expect(
            plistTrue(infoPlist, 'NSAllowsArbitraryLoadsForMedia'),
            isTrue,
          );
        });

        test('the Podfile maps every flavor configuration to its mode', () {
          expect(
            podfileConfigurations(File('macos/Podfile').readAsStringSync()),
            {
              for (final mode in _modes) ...{
                mode: _podMode(mode),
                for (final flavor in AppFlavor.values)
                  '$mode-${flavor.name}': _podMode(mode),
              },
            },
          );
        });
      }
    });
  }

  group('macOS file mutations', () {
    final entitlements = File('macos/Runner/Release.entitlements')
        .readAsStringSync();
    final info = File('macos/Runner/Info.plist').readAsStringSync();
    final podfile = File('macos/Podfile').readAsStringSync();

    test('a sandbox or keychain group entitlement is found', () {
      for (final key in [sandboxEntitlement, keychainGroupsEntitlement]) {
        final mutated = entitlements.replaceFirst(
          RegExp(r'<dict\s*/>|<dict>'),
          '<dict>\n\t<key>$key</key>\n\t<true/>\n',
        );
        final closed = mutated.contains('</dict>')
            ? mutated
            : mutated.replaceFirst('</plist>', '</dict>\n</plist>');
        expect(plistKeys(closed), contains(key));
      }
    });

    test('a false or missing Info.plist flag is not true', () {
      expect(
        plistTrue(
          info.replaceFirst(
            RegExp(r'(<key>LSMultipleInstancesProhibited</key>\s*)<true/>'),
            r'$1<false/>',
          ),
          'LSMultipleInstancesProhibited',
        ),
        isFalse,
      );
      expect(
        plistTrue('<dict></dict>', 'LSMultipleInstancesProhibited'),
        isFalse,
      );
    });

    test('a flavor configuration dropped from the Podfile is noticed', () {
      final mutated = podfile.replaceFirst(
        RegExp(r"\s*'Release-dev' => :release,"),
        '',
      );
      expect(mutated, isNot(podfile));
      expect(podfileConfigurations(mutated), isNot(contains('Release-dev')));
    });

    test('layout, comments and quoting leave the parsed values unchanged', () {
      final plist = info
          .replaceAll('\t', '    ')
          .replaceAll('<true/>', '<true />')
          .replaceAll(RegExp(r'\n\s*'), '\n  ');
      expect(plistTrue(plist, 'LSMultipleInstancesProhibited'), isTrue);
      expect(plistTrue(plist, 'NSAllowsArbitraryLoadsForMedia'), isTrue);

      final reformatted = podfile
          .replaceAll("'", '"')
          .replaceAll(' => ', '=>')
          .replaceFirst(
            'project "Runner", {',
            '# a comment\nproject "Runner", {',
          );
      expect(reformatted, isNot(podfile));
      expect(
        podfileConfigurations(reformatted),
        podfileConfigurations(podfile),
      );
    });
  });

  group('parser mutations', () {
    final source = File('ios/Runner.xcodeproj/project.pbxproj')
        .readAsStringSync()
        .replaceAll('\r\n', '\n');
    final original = XcodeProject.parse(source);

    test('a dev configuration without the suffix collapses onto prod', () {
      final mutated = source.replaceFirst(
        'PRODUCT_BUNDLE_IDENTIFIER = com.personal.fmp.dev;',
        'PRODUCT_BUNDLE_IDENTIFIER = com.personal.fmp;',
      );
      expect(mutated, isNot(source));
      expect(
        XcodeProject.parse(mutated).bundleIds(AppFlavor.dev),
        contains('com.personal.fmp'),
      );
    });

    test('a flavor configuration missing from one target is reported', () {
      final entry = RegExp(r'\t\t\t\t[0-9A-F]{24} /\* Release-prod \*/,\n');
      final mutated = source.replaceFirst(entry, '');
      expect(mutated, isNot(source));
      expect(
        XcodeProject.parse(mutated).flavorConfigurationProblems(),
        isNotEmpty,
      );
    });

    test('comments, layout and quoting leave the values unchanged', () {
      final reformatted = source
          .replaceFirst(RegExp(r'^//.*\n'), '')
          .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .replaceAll(
            'PRODUCT_BUNDLE_IDENTIFIER = com.personal.fmp.dev;',
            'PRODUCT_BUNDLE_IDENTIFIER="com.personal.fmp.dev" ;',
          )
          .replaceAll('APP_DISPLAY_NAME = FMP;', '"APP_DISPLAY_NAME" = "FMP";');
      expect(reformatted, isNot(source));
      final project = XcodeProject.parse(reformatted);
      for (final flavor in AppFlavor.values) {
        expect(project.bundleIds(flavor), original.bundleIds(flavor));
        expect(project.displayNames(flavor), original.displayNames(flavor));
      }
      expect(project.flavorConfigurationProblems(), isEmpty);
    });

    test('scheme and Info.plist parsing follow the values, not the layout', () {
      const scheme =
          '<Scheme>\n<LaunchAction\n  buildConfiguration = "Debug-dev"\n'
          '  launchStyle = "0">\n</LaunchAction>\n'
          '<ArchiveAction buildConfiguration="Release">\n</ArchiveAction>';
      expect(schemeConfigurations(scheme), {
        'LaunchAction': 'Debug-dev',
        'ArchiveAction': 'Release',
      });
      const plist =
          '<dict><key>CFBundleName</key><string>fmp</string>\n'
          '\t<key>CFBundleDisplayName</key>\n\t<string>Fmp</string></dict>';
      expect(plistString(plist, 'CFBundleDisplayName'), 'Fmp');
    });
  });
}

/// Info.plist 裡指向 build setting 的顯示名稱。
const displayNameRef = r'$(APP_DISPLAY_NAME)';

const _modes = ['Debug', 'Profile', 'Release'];

/// 解析過的 `project.pbxproj`。
final class XcodeProject {
  XcodeProject._(this._objects);

  factory XcodeProject.parse(String source) {
    final root = _PlistParser(source).parse() as Map<String, Object?>;
    return XcodeProject._(root['objects']! as Map<String, Object?>);
  }

  final Map<String, Object?> _objects;

  Map<String, Object?> _object(String id) =>
      _objects[id]! as Map<String, Object?>;

  Iterable<Map<String, Object?>> _ofType(String isa) => _objects.values
      .cast<Map<String, Object?>>()
      .where((object) => object['isa'] == isa);

  /// 一個 configuration list 裡名稱對到的 build configuration。
  Map<String, Map<String, Object?>> _configurations(String listId) => {
    for (final id in _object(listId)['buildConfigurations']! as List<Object?>)
      _object(id! as String)['name']! as String: _object(id as String),
  };

  /// App（`com.apple.product-type.application`）target 的 configuration。
  Map<String, Map<String, Object?>> get _app {
    final targets = _ofType('PBXNativeTarget')
        .where(
          (target) =>
              target['productType'] == 'com.apple.product-type.application',
        )
        .toList();
    expect(targets, hasLength(1), reason: 'one application target');
    return _configurations(targets.single['buildConfigurationList']! as String);
  }

  /// [flavor] 三個模式的 [setting] 值（一律寫在 App target 的 configuration，
  /// 沒寫就是 `null`）。
  Set<String?> _flavorSetting(AppFlavor flavor, String setting) {
    final app = _app;
    return {
      for (final mode in _modes)
        (app['$mode-${flavor.name}']?['buildSettings']
                as Map<String, Object?>?)?[setting]
            as String?,
    };
  }

  Set<String?> bundleIds(AppFlavor flavor) =>
      _flavorSetting(flavor, 'PRODUCT_BUNDLE_IDENTIFIER');

  Set<String?> displayNames(AppFlavor flavor) =>
      _flavorSetting(flavor, 'APP_DISPLAY_NAME');

  /// 每個 configuration list（專案與每個 target）都要有每個 flavor 的三個
  /// configuration，而且 base xcconfig 和同模式的 configuration 相同（Flutter
  /// 的設定從它來）。回傳違反的描述；空的就是沒問題。
  List<String> flavorConfigurationProblems() => [
    for (final MapEntry(key: id, :value) in _objects.entries)
      if ((value! as Map<String, Object?>)['isa'] == 'XCConfigurationList')
        for (final mode in _modes)
          for (final flavor in AppFlavor.values)
            ?_problem(_configurations(id), mode, '$mode-${flavor.name}'),
  ];

  String? _problem(
    Map<String, Map<String, Object?>> configurations,
    String mode,
    String name,
  ) {
    final configuration = configurations[name];
    if (configuration == null) {
      return '$name missing from a list with ${configurations.keys}';
    }
    final base = configurations[mode]?['baseConfigurationReference'];
    final own = configuration['baseConfigurationReference'];
    if (own != base && !_isPodsCounterpart(own, base, mode, name)) {
      return '$name is not based on the same xcconfig as $mode';
    }
    return null;
  }

  /// CocoaPods 給沒有 base xcconfig 的 target（`RunnerTests`）每個 configuration 一份自己的
  /// `Pods-<target>.<configuration 小寫>.xcconfig`：[own] 是 [base] 那一份換成 [name] 的版本也算同一個 base。
  bool _isPodsCounterpart(Object? own, Object? base, String mode, String name) {
    if (own is! String || base is! String) return false;
    final ownPath = _object(own)['path'];
    final basePath = _object(base)['path'];
    if (ownPath is! String || basePath is! String) return false;
    final suffix = '.${mode.toLowerCase()}.xcconfig';
    return basePath.contains('/Pods-') &&
        basePath.endsWith(suffix) &&
        ownPath ==
            '${basePath.substring(0, basePath.length - suffix.length)}'
                '.${name.toLowerCase()}.xcconfig';
  }
}

/// scheme 各動作的 `buildConfiguration`。
Map<String, String> schemeConfigurations(String scheme) => {
  for (final match in RegExp(
    r'<(\w+Action)\b[^>]*?\bbuildConfiguration\s*=\s*"([^"]*)"',
  ).allMatches(scheme))
    match.group(1)!: match.group(2)!,
};

/// XML plist 裡 [key] 的字串值。
String plistString(String plist, String key) {
  final matches = RegExp(
    '<key>${RegExp.escape(key)}</key>\\s*<string>([^<]*)</string>',
  ).allMatches(plist).toList();
  expect(matches, hasLength(1), reason: key);
  return matches.single.group(1)!;
}

const sandboxEntitlement = 'com.apple.security.app-sandbox';
const keychainGroupsEntitlement = 'keychain-access-groups';

/// XML plist（entitlements）裡出現的每個 key。
Set<String> plistKeys(String plist) => {
  for (final match in RegExp(r'<key>\s*([^<]*?)\s*</key>').allMatches(plist))
    match.group(1)!,
};

/// XML plist 裡 [key] 的值是不是 `<true/>`（沒有這個 key 也是否）。
bool plistTrue(String plist, String key) =>
    RegExp('<key>\\s*${RegExp.escape(key)}\\s*</key>\\s*<true\\s*/>')
        .hasMatch(plist);

String _podMode(String mode) => mode == 'Debug' ? 'debug' : 'release';

/// Podfile 的 `project 'Runner', { 'Debug-dev' => :debug, ... }`：configuration 名稱對到 pod 的模式。
Map<String, String> podfileConfigurations(String podfile) {
  final withoutComments = podfile.replaceAll(RegExp(r'#[^\n]*'), '');
  final block = RegExp(r'''project\s+['"]Runner['"]\s*,\s*\{([^}]*)\}''')
      .firstMatch(withoutComments);
  expect(block, isNotNull, reason: 'project Runner block');
  return {
    for (final match in RegExp(
      r'''['"]([\w-]+)['"]\s*=>\s*:(debug|release)''',
    ).allMatches(block!.group(1)!))
      match.group(1)!: match.group(2)!,
  };
}

/// OpenStep 格式（`project.pbxproj`）的 plist：字典、陣列、字串，含註解。
final class _PlistParser {
  _PlistParser(String source)
    : _tokens = [
        for (final match in _token.allMatches(source))
          if (!match.group(0)!.startsWith('/*') &&
              !match.group(0)!.startsWith('//'))
            match.group(0)!,
      ];

  static final _token = RegExp(
    r'/\*.*?\*/|//[^\n]*|"(?:[^"\\]|\\.)*"|[{}();=,]|[^\s{}();=,"]+',
    dotAll: true,
  );

  final List<String> _tokens;
  int _position = 0;

  Object? parse() {
    final value = _value();
    if (_position != _tokens.length) {
      throw FormatException('trailing tokens at $_position');
    }
    return value;
  }

  String _next() => _tokens[_position++];

  void _expect(String token) {
    final actual = _next();
    if (actual != token) {
      throw FormatException('expected $token, got $actual at $_position');
    }
  }

  Object? _value() {
    final token = _next();
    switch (token) {
      case '{':
        final map = <String, Object?>{};
        while (_tokens[_position] != '}') {
          final key = _value()! as String;
          _expect('=');
          map[key] = _value();
          _expect(';');
        }
        _position++;
        return map;
      case '(':
        final list = <Object?>[];
        while (_tokens[_position] != ')') {
          list.add(_value());
          if (_tokens[_position] == ',') _position++;
        }
        _position++;
        return list;
      default:
        if (token.startsWith('"')) {
          return token
              .substring(1, token.length - 1)
              .replaceAllMapped(
                RegExp(r'\\(.)'),
                (match) => switch (match.group(1)!) {
                  'n' => '\n',
                  't' => '\t',
                  final other => other,
                },
              );
        }
        return token;
    }
  }
}
