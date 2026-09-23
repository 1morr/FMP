import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../support/dart_source.dart';

void main() {
  group('UI consistency static rules', () {
    test('only the semantic image widgets reach the low-level image APIs', () {
      final calls = <String, Set<String>>{};
      for (final entity in Directory('lib/ui').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final found = imageApiCalls(entity.readAsStringSync());
        if (found.isNotEmpty) {
          calls[entity.path.replaceAll(r'\', '/')] = found;
        }
      }

      expect(
        calls,
        equals(_imageApiOwners),
        reason:
            'UI pages pass a semantic variant to a widget under '
            'lib/ui/widgets/images/; only those widgets pick a size tier or '
            'call the loader. Update _imageApiOwners in this file when a '
            'widget there changes what it calls.',
      );
    });

    test('ListTile leading values do not directly use Row', () {
      final offenders = <String>[];

      for (final entity in Directory('lib/ui').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;

        final source = entity.readAsStringSync();
        if (listTileLeadingRowOffenders(source).isNotEmpty) {
          offenders.add(entity.path.replaceAll('\\', '/'));
        }
      }

      expect(offenders, isEmpty);
    });
  });

  group('the ui consistency detectors', () {
    test('a synthesised violation is caught', () {
      const listTile = '''
ListTile(
  leading: Row(children: [Icon(Icons.album), SizedBox(width: 4)]),
  title: Text(track.title),
)
''';
      const image = '''
Widget build(BuildContext context) {
  final avatar = Image.network(user.avatarUrl);
  return ImageLoadingService
      .loadImage(
    url,
    targetDisplaySize: ImageTargetSizes.thumbnail,
  );
}
''';

      expect(listTileLeadingRowOffenders(listTile), hasLength(1));
      expect(imageApiCalls(image), {
        'Image.network',
        'loadImage',
        'ImageTargetSizes',
      });
      expect(
        imageApiCalls('final cover = CachedNetworkImage(imageUrl: url);'),
        {'CachedNetworkImage'},
      );
    });

    test('a violation written in a comment does not count', () {
      const listTile = '''
// 不要寫成 ListTile(leading: Row(...))，leading 的寬度由 ListTile 自己算。
ListTile(leading: TrackThumbnail(track: track), title: Text(track.title))
''';
      const image = '''
/// 頁面不呼叫 ImageLoadingService.loadImage(，也不傳
/// targetDisplaySize: ImageTargetSizes.thumbnail —— 那是圖片元件的事。
PlaylistCoverImage(variant: PlaylistCoverVariant.card)
await ImageLoadingService.clearNetworkCache();
final icon = Image.asset('assets/icon.png');
''';

      expect(listTileLeadingRowOffenders(listTile), isEmpty);
      expect(imageApiCalls(image), isEmpty);
    });
  });
}

/// `lib/ui/widgets/images/` 的語義化圖片元件 → 它們碰的低階圖片 API。
///
/// 頁面只傳 variant；檔位（`ImageTargetSizes`）由元件選，DPR 感知的 URL 檔位與
/// 解碼尺寸由 `ImageLoadingService` 算。頁面自己挑檔位或直接載圖就是 #107 那種
/// 問題的來源。
const _imageApiOwners = <String, Set<String>>{
  'lib/ui/widgets/images/avatar_image.dart': {'loadAvatar', 'ImageTargetSizes'},
  'lib/ui/widgets/images/playlist_cover_image.dart': {
    'loadImage',
    'ImageTargetSizes',
  },
  'lib/ui/widgets/images/radio_cover_image.dart': {
    'loadImage',
    'imageProviderCandidates',
    'precacheImageCandidates',
    'ImageTargetSizes',
  },
  'lib/ui/widgets/images/recent_play_cover_image.dart': {
    'loadImage',
    'ImageTargetSizes',
  },
  'lib/ui/widgets/images/track_thumbnail.dart': {
    'loadImage',
    'imageProviderCandidates',
    'ImageTargetSizes',
  },
};

final _imageApiPatterns = <String, RegExp>{
  for (final method in const [
    'loadImage',
    'loadAvatar',
    'imageProviderCandidates',
    'precacheImageCandidates',
  ])
    method: RegExp(r'\bImageLoadingService\s*\.\s*' + method + r'\s*\('),
  'Image.network': RegExp(r'\bImage\s*\.\s*network\s*\('),
  'Image.file': RegExp(r'\bImage\s*\.\s*file\s*\('),
  for (final type in const [
    'CachedNetworkImage',
    'CachedNetworkImageProvider',
    'NetworkImage',
    'FileImage',
  ])
    type: RegExp(r'\b' + type + r'\s*\('),
  'ImageTargetSizes': RegExp(r'\bImageTargetSizes\b'),
};

/// [source] 在註解之外碰了哪些低階圖片 API。
Set<String> imageApiCalls(String source) {
  final code = stripDartComments(source);
  return {
    for (final MapEntry(key: name, value: pattern) in _imageApiPatterns.entries)
      if (pattern.hasMatch(code)) name,
  };
}

/// `ListTile` 的 `leading` 直接塞一個 `Row`。
///
/// `leading` 的寬度由 `ListTile` 自己算，`Row` 會撐到約束外，在窄視窗溢出。
final _listTileLeadingRowPattern = RegExp(
  r'ListTile\s*\([\s\S]*?leading:\s*Row\s*\(',
);

List<String> listTileLeadingRowOffenders(String source) =>
    _listTileLeadingRowPattern
        .allMatches(stripDartComments(source))
        .map((match) => match.group(0)!)
        .toList();
