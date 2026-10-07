import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

/// 系統媒體控制要的 Android manifest 設定（design §8.3）。
///
/// 以 XML 解析斷言，不比對字串：屬性的順序、縮排與註解改了不影響結果。最後一組
/// 變異案例證明這一點（缺一項會紅、改格式不會紅）。`MainActivity` 的兩個覆寫沒有
/// 自動閘門，在實機驗（app/AGENTS.md § 平台層）。
void main() {
  final manifest = File('android/app/src/main/AndroidManifest.xml')
      .readAsStringSync();

  test('the media playback permissions are requested', () {
    expect(permissions(manifest), containsAll(mediaPermissions));
  });

  test('POST_NOTIFICATIONS is not declared', () {
    // 媒體工作階段的通知不受 Android 13 通知權限限制；M6 的下載通知才需要。
    expect(permissions(manifest), isNot(contains(postNotifications)));
  });

  test('the audio_service service is an exported mediaPlayback service', () {
    final service = element(manifest, 'service', audioService);
    expect(service, isNotNull);
    expect(service!.getAttribute('android:exported'), 'true');
    expect(
      service.getAttribute('android:foregroundServiceType'),
      'mediaPlayback',
    );
    expect(intentActions(service), contains(mediaBrowserService));
  });

  test(
    'the media button receiver is exported and listens for MEDIA_BUTTON',
    () {
      final receiver = element(manifest, 'receiver', mediaButtonReceiver);
      expect(receiver, isNotNull);
      expect(receiver!.getAttribute('android:exported'), 'true');
      expect(intentActions(receiver), contains(mediaButton));
    },
  );

  group('parser mutations', () {
    const permission =
        '<uses-permission android:name="android.permission.WAKE_LOCK"/>';

    test('a missing or commented-out permission is caught', () {
      expect(manifest, contains(permission));
      for (final mutated in [
        manifest.replaceFirst(permission, ''),
        manifest.replaceFirst(permission, '<!-- $permission -->'),
      ]) {
        expect(permissions(mutated), isNot(containsAll(mediaPermissions)));
      }
    });

    test('a declared POST_NOTIFICATIONS is caught', () {
      final mutated = manifest.replaceFirst(
        permission,
        '$permission<uses-permission android:name="$postNotifications"/>',
      );
      expect(permissions(mutated), contains(postNotifications));
    });

    test('a changed service attribute is caught', () {
      final mutated = manifest.replaceFirst(
        'android:foregroundServiceType="mediaPlayback"',
        'android:foregroundServiceType="dataSync"',
      );
      expect(mutated, isNot(manifest));
      expect(
        element(
          mutated,
          'service',
          audioService,
        )!.getAttribute('android:foregroundServiceType'),
        'dataSync',
      );
    });

    test('a removed intent filter action is caught', () {
      final mutated = manifest.replaceFirst(
        '<action android:name="$mediaBrowserService"/>',
        '',
      );
      expect(mutated, isNot(manifest));
      expect(
        intentActions(element(mutated, 'service', audioService)!),
        isNot(contains(mediaBrowserService)),
      );
    });

    test('reordering attributes, reindenting and comments change nothing', () {
      final reformatted = manifest
          .replaceFirstMapped(
            RegExp(
              r'<service\s+android:name="([^"]*)"\s+'
              r'android:foregroundServiceType="([^"]*)"\s+'
              r'android:exported="([^"]*)"',
            ),
            (m) =>
                '<service android:exported="${m[3]}" '
                'android:foregroundServiceType="${m[2]}" '
                'android:name="${m[1]}"',
          )
          .replaceAll('    ', '\t')
          .replaceAll('<uses-permission', '<!-- note --><uses-permission');
      expect(reformatted, isNot(manifest));
      expect(permissions(reformatted), permissions(manifest));
      final before = element(manifest, 'service', audioService)!;
      final after = element(reformatted, 'service', audioService)!;
      for (final name in [
        'android:exported',
        'android:foregroundServiceType',
      ]) {
        expect(
          after.getAttribute(name),
          before.getAttribute(name),
          reason: name,
        );
      }
      expect(intentActions(after), intentActions(before));
      expect(element(reformatted, 'receiver', mediaButtonReceiver), isNotNull);
    });
  });
}

const audioService = 'com.ryanheise.audioservice.AudioService';
const mediaButtonReceiver = 'com.ryanheise.audioservice.MediaButtonReceiver';
const mediaBrowserService = 'android.media.browse.MediaBrowserService';
const mediaButton = 'android.intent.action.MEDIA_BUTTON';
const postNotifications = 'android.permission.POST_NOTIFICATIONS';
const mediaPermissions = [
  'android.permission.WAKE_LOCK',
  'android.permission.FOREGROUND_SERVICE',
  'android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK',
];

/// `<application>` 之外的 `<uses-permission>`（`<manifest>` 的直接子元素）。
Set<String> permissions(String manifest) => {
  for (final element in XmlDocument.parse(
    manifest,
  ).rootElement.findElements('uses-permission'))
    ?element.getAttribute('android:name'),
};

/// `<application>` 底下 `android:name` 為 [name] 的 [tag] 元素。
XmlElement? element(String manifest, String tag, String name) {
  final application = XmlDocument.parse(manifest).rootElement
      .findElements('application')
      .single;
  for (final candidate in application.findElements(tag)) {
    if (candidate.getAttribute('android:name') == name) return candidate;
  }
  return null;
}

Set<String> intentActions(XmlElement component) => {
  for (final filter in component.findElements('intent-filter'))
    for (final action in filter.findElements('action'))
      ?action.getAttribute('android:name'),
};
