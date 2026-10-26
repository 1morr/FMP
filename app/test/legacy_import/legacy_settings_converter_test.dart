import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/import/import_bundle.dart';
import 'package:fmp/data/repositories/network_settings_repository.dart';
import 'package:fmp/domain/appearance.dart';
import 'package:fmp/domain/legacy_import.dart';
import 'package:fmp/domain/stream_preferences.dart';
import 'package:fmp/legacy_import/legacy_converter.dart';
import 'package:fmp/legacy_import/legacy_settings_converter.dart';
import 'package:fmp/legacy_import/legacy_settings_migration.dart';
import 'package:fmp/legacy_import/legacy_snapshot.dart';

import 'legacy_snapshot_builders.dart';

// 設定的轉換（M5 design §5.9、§1.3）。舊預設取自凍結的舊專案 `lib/data/models/settings.dart`
// 的欄位初始值（行號在各群組標題）；`LegacySettings()` 的建構子預設與它相同，所以
// `LegacySettings()` 就是「什麼都沒改」。型別預設（Isar 對缺欄補的值）：非空 int 是 `-2^63`、
// double 是 NaN、bool 是 false。全是編造資料。

const _minLong = -9223372036854775808;

ImportBundle convertWith(
  LegacySettings settings, {
  LegacyImportSource source = LegacyImportSource.database,
  bool importOutputDevice = false,
  List<LegacySearchHistory> searchHistory = const [],
  List<String> fontChoices = const [],
}) {
  final base = legacySnapshot(settings: settings);
  final snapshot = LegacySnapshot(
    tracks: base.tracks,
    playlists: base.playlists,
    playQueues: base.playQueues,
    playHistory: base.playHistory,
    settings: base.settings,
    searchHistory: searchHistory,
    downloadTasks: base.downloadTasks,
    radioStations: base.radioStations,
    lyricsMatches: base.lyricsMatches,
    lyricsTitleParseCacheCount: 0,
    accounts: base.accounts,
    storedSchemaVersion: 4,
  );
  return const LegacyConverter()
      .convert(
        snapshot,
        source: source,
        now: DateTime.utc(2026, 10, 23),
        importOutputDevice: importOutputDevice,
        fontChoices: fontChoices,
      )
      .bundle;
}

void main() {
  group('nothing changed', () {
    test('an untouched settings row writes only browse_as_logged_in', () {
      final bundle = convertWith(LegacySettings());
      expect(bundle.appearance.themeMode, isNull);
      expect(bundle.appearance.locale, isNull);
      expect(bundle.appearance.seedColor, isNull);
      expect(bundle.appearance.fontFamily, isNull);
      expect(bundle.network, NetworkSettings.empty);
      expect(bundle.playback.audioQuality, isNull);
      expect(bundle.playback.tempPlayRewindSeconds, isNull);
      // 版面是上次的狀態：照舊值寫，包括等於舊預設的值。
      expect(bundle.layout.panelExpanded, isFalse);
      expect(bundle.layout.panelWidth, 412);
      expect(bundle.record.summary.unimportedSettings, isEmpty);
      expect(bundle.browseAsLoggedIn, {
        'bilibili': true,
        'youtube': false,
        'netease': true,
      });
    });

    test('type defaults of a row that lost its columns write nothing', () {
      final bundle = convertWith(
        LegacySettings(
          themeModeIndex: _minLong,
          audioQualityLevelIndex: _minLong,
          audioFormatPriority: '',
          rememberPlaybackPosition: true,
          restartRewindSeconds: _minLong,
          tempPlayRewindSeconds: _minLong,
          playHistoryLimit: _minLong,
          rankingRefreshIntervalMinutes: _minLong,
          radioRefreshIntervalMinutes: _minLong,
          detailPanelWidth: double.nan,
          maxCacheSizeMB: _minLong,
          maxLyricsCacheFiles: _minLong,
          locale: 'xx',
        ),
      );
      expect(bundle.appearance.themeMode, isNull);
      expect(bundle.appearance.locale, isNull);
      expect(bundle.playback.audioQuality, isNull);
      expect(bundle.playback.audioFormatPriority, isNull);
      expect(bundle.playback.tempPlayRewindSeconds, isNull);
      expect(bundle.playback.restartRewindSeconds, isNull);
      expect(bundle.playback.playHistoryLimit, isNull);
      expect(bundle.network, NetworkSettings.empty);
      expect(bundle.layout.panelWidth, isNull);
      expect(bundle.record.summary.unimportedSettings, isEmpty);
    });
  });

  group('theme color and font (primaryColor, fontFamily)', () {
    test('a changed color becomes an opaque seed', () {
      expect(
        convertWith(LegacySettings(primaryColor: 0xFF336699))
            .appearance
            .seedColor,
        const Color(0xFF336699),
      );
      // 舊值的 alpha 不帶進來。
      expect(
        convertWith(LegacySettings(primaryColor: 0x00336699))
            .appearance
            .seedColor,
        const Color(0xFF336699),
      );
    });

    test(
      'the default purple, a missing color and a bad value write nothing',
      () {
        expect(
          convertWith(LegacySettings(primaryColor: 0xFF6750A4))
              .appearance
              .seedColor,
          isNull,
        );
        expect(convertWith(LegacySettings()).appearance.seedColor, isNull);
        expect(
          convertWith(LegacySettings(primaryColor: _minLong))
              .appearance
              .seedColor,
          isNull,
        );
      },
    );

    test('a font in the platform list is imported', () {
      final bundle = convertWith(
        LegacySettings(fontFamily: 'Meiryo'),
        fontChoices: const ['Microsoft JhengHei UI', 'Meiryo'],
      );
      expect(bundle.appearance.fontFamily, 'Meiryo');
    });

    test('a font that is not in the list falls back to the system default', () {
      for (final choices in [
        const ['Microsoft JhengHei UI'],
        const <String>[],
      ]) {
        final bundle = convertWith(
          LegacySettings(fontFamily: 'SimSun'),
          fontChoices: choices,
        );
        expect(bundle.appearance.fontFamily, isNull);
        // 不在清單也不再列為「沒有匯入的設定」。
        expect(bundle.record.summary.unimportedSettings, isEmpty);
      }
    });

    test('a blank font writes nothing', () {
      expect(
        convertWith(
          LegacySettings(fontFamily: ''),
          fontChoices: const [''],
        ).appearance.fontFamily,
        isNull,
      );
    });
  });

  group('appearance (themeModeIndex :224, locale :304)', () {
    test('changed values are written', () {
      expect(
        convertWith(LegacySettings(themeModeIndex: 1)).appearance.themeMode,
        ThemeModeSetting.light,
      );
      expect(
        convertWith(LegacySettings(themeModeIndex: 2)).appearance.themeMode,
        ThemeModeSetting.dark,
      );
      for (final (legacy, expected) in [
        ('zh_TW', LocaleSetting.zhTw),
        ('zh_CN', LocaleSetting.zhCn),
        ('en', LocaleSetting.en),
      ]) {
        expect(
          convertWith(LegacySettings(locale: legacy)).appearance.locale,
          expected,
        );
      }
    });

    test('the default (follow system) and unknown values stay empty', () {
      expect(
        convertWith(LegacySettings(themeModeIndex: 0)).appearance.themeMode,
        isNull,
      );
      expect(
        convertWith(LegacySettings(themeModeIndex: 7)).appearance.themeMode,
        isNull,
      );
      expect(convertWith(LegacySettings()).appearance.locale, isNull);
      expect(
        convertWith(LegacySettings(locale: 'zh-TW')).appearance.locale,
        isNull,
      );
    });
  });

  group('audio (audioQualityLevelIndex :309, audioFormatPriority :313)', () {
    test('changed quality maps to medium or low', () {
      expect(
        convertWith(LegacySettings(audioQualityLevelIndex: 1))
            .playback
            .audioQuality,
        AudioQuality.medium,
      );
      expect(
        convertWith(LegacySettings(audioQualityLevelIndex: 2))
            .playback
            .audioQuality,
        AudioQuality.low,
      );
    });

    test('default and out-of-range quality stay empty', () {
      for (final index in [0, 3, -1]) {
        expect(
          convertWith(LegacySettings(audioQualityLevelIndex: index))
              .playback
              .audioQuality,
          isNull,
          reason: '$index',
        );
      }
    });

    test('format priority: changed, default, unknown', () {
      expect(
        convertWith(LegacySettings(audioFormatPriority: 'aac,opus'))
            .playback
            .audioFormatPriority,
        AudioFormatPriority.aacFirst,
      );
      for (final value in ['opus,aac', '', 'flac']) {
        expect(
          convertWith(LegacySettings(audioFormatPriority: value))
              .playback
              .audioFormatPriority,
          isNull,
          reason: value,
        );
      }
    });
  });

  group('rememberPlaybackPosition (:259), autoScroll (:256)', () {
    test('only the changed value is written', () {
      expect(
        convertWith(LegacySettings(rememberPlaybackPosition: false))
            .playback
            .rememberPosition,
        isFalse,
      );
      expect(convertWith(LegacySettings()).playback.rememberPosition, isNull);
      expect(
        convertWith(LegacySettings(autoScrollToCurrentTrack: true))
            .playback
            .autoScrollToCurrent,
        isTrue,
      );
      expect(
        convertWith(LegacySettings()).playback.autoScrollToCurrent,
        isNull,
      );
    });
  });

  group('rewind seconds (temp :265 default 10, restart :262 default 0)', () {
    test('a value in the options is written as is', () {
      final bundle = convertWith(
        LegacySettings(tempPlayRewindSeconds: 15, restartRewindSeconds: 30),
      );
      expect(bundle.playback.tempPlayRewindSeconds, 15);
      expect(bundle.playback.restartRewindSeconds, 30);
    });

    test('a value outside the options takes the nearest, ties go larger', () {
      // 選項 0／3／5／10／15／30。
      for (final (legacy, expected) in [
        (1, 0),
        (2, 3),
        (4, 5), // 距 3、5 皆 1：等距取大
        (7, 5),
        (8, 10),
        (13, 15),
        (20, 15),
        (100, 30),
      ]) {
        expect(
          convertWith(LegacySettings(tempPlayRewindSeconds: legacy))
              .playback
              .tempPlayRewindSeconds,
          expected,
          reason: '$legacy',
        );
      }
    });

    test('the default and type defaults stay empty', () {
      final bundle = convertWith(
        LegacySettings(tempPlayRewindSeconds: 10, restartRewindSeconds: 0),
      );
      expect(bundle.playback.tempPlayRewindSeconds, isNull);
      expect(bundle.playback.restartRewindSeconds, isNull);
      expect(
        convertWith(LegacySettings(tempPlayRewindSeconds: _minLong))
            .playback
            .tempPlayRewindSeconds,
        isNull,
      );
    });

    test('a value that rounds to the new default is still written', () {
      // 11 不等於舊預設 10，使用者改過；取最接近的選項 10。
      expect(
        convertWith(LegacySettings(tempPlayRewindSeconds: 11))
            .playback
            .tempPlayRewindSeconds,
        10,
      );
    });
  });

  group('playHistoryLimit (:276 default 10000)', () {
    test('uses the PR 3 conversion', () {
      expect(
        convertWith(LegacySettings(playHistoryLimit: 5000))
            .playback
            .playHistoryLimit,
        5000,
      );
      expect(
        convertWith(LegacySettings(playHistoryLimit: 20000))
            .playback
            .playHistoryLimit,
        50000,
      );
      expect(
        convertWith(LegacySettings(playHistoryLimit: 999999))
            .playback
            .playHistoryLimit,
        50000,
      );
    });

    test('default and type default stay empty', () {
      expect(convertWith(LegacySettings()).playback.playHistoryLimit, isNull);
      expect(
        convertWith(LegacySettings(playHistoryLimit: _minLong))
            .playback
            .playHistoryLimit,
        isNull,
      );
    });
  });

  group(
    'refresh intervals (radio :443 default 5, ranking :434 default 60)',
    () {
      test('a value in the options is written as is', () {
        final bundle = convertWith(
          LegacySettings(
            radioRefreshIntervalMinutes: 10,
            rankingRefreshIntervalMinutes: 240,
          ),
        );
        expect(bundle.network.radioStatusIntervalMinutes, 10);
        expect(bundle.network.chartRefreshIntervalMinutes, 240);
      });

      test('zero (off) is a valid changed value', () {
        final bundle = convertWith(
          LegacySettings(
            radioRefreshIntervalMinutes: 0,
            rankingRefreshIntervalMinutes: 0,
          ),
        );
        expect(bundle.network.radioStatusIntervalMinutes, 0);
        expect(bundle.network.chartRefreshIntervalMinutes, 0);
      });

      test('a value outside the options takes the nearest, ties go larger', () {
        // 電台選項 0／1／3／5／10：2 距 1、3 皆 1 取 3；7 距 5、10 為 2、3 取 5；8 取 10。
        for (final (legacy, expected) in [(2, 3), (7, 5), (8, 10), (999, 10)]) {
          expect(
            convertWith(LegacySettings(radioRefreshIntervalMinutes: legacy))
                .network
                .radioStatusIntervalMinutes,
            expected,
            reason: 'radio $legacy',
          );
        }
        // 排行選項 0／30／60／120／240：15 距 0、30 皆 15 取 30；90 距 60、120 皆 30 取 120。
        for (final (legacy, expected) in [(15, 30), (90, 120), (45, 60)]) {
          expect(
            convertWith(LegacySettings(rankingRefreshIntervalMinutes: legacy))
                .network
                .chartRefreshIntervalMinutes,
            expected,
            reason: 'ranking $legacy',
          );
        }
      });

      test('defaults and type defaults stay empty', () {
        final bundle = convertWith(
          LegacySettings(
            radioRefreshIntervalMinutes: 5,
            rankingRefreshIntervalMinutes: _minLong,
          ),
        );
        expect(bundle.network, NetworkSettings.empty);
      });
    },
  );

  group('cache limit is never imported (ADR 0016)', () {
    test('every historical default counts as unchanged', () {
      // 2048 → 128 → 32 是歷代預設，16 是行動裝置全新安裝的初值。
      for (final mb in [2048, 128, 32, 16]) {
        expect(
          convertWith(LegacySettings(maxCacheSizeMB: mb))
              .record
              .summary
              .unimportedSettings,
          isEmpty,
          reason: '$mb',
        );
      }
      expect(
        convertWith(LegacySettings(maxCacheSizeMB: 64))
            .record
            .summary
            .unimportedSettings,
        [UnimportedSetting.cacheLimit],
      );
    });

    test('cacheLimitMebibytes stays empty and the change is listed', () {
      final bundle = convertWith(LegacySettings(maxCacheSizeMB: 512));
      expect(bundle.network.cacheLimitMebibytes, isNull);
      expect(bundle.record.summary.unimportedSettings, [
        UnimportedSetting.cacheLimit,
      ]);
    });
  });

  group('browse_as_logged_in (useAuthForPlay, :76-79)', () {
    LegacySettings withAuth({
      required bool bilibili,
      required bool youtube,
      required bool netease,
    }) => LegacySettings(
      sourceSettings: [
        LegacySourceSettings(
          sourceId: 'bilibili',
          streamPriority: 'audioOnly,muxed',
          useAuthForPlay: bilibili,
        ),
        LegacySourceSettings(
          sourceId: 'youtube',
          streamPriority: 'audioOnly,muxed,hls',
          useAuthForPlay: youtube,
        ),
        LegacySourceSettings(
          sourceId: 'netease',
          streamPriority: 'audioOnly',
          useAuthForPlay: netease,
        ),
      ],
    );

    test('all three sources are written from the old values', () {
      expect(
        convertWith(withAuth(bilibili: false, youtube: true, netease: false))
            .browseAsLoggedIn,
        {'bilibili': false, 'youtube': true, 'netease': false},
      );
    });

    test('values equal to the old defaults are still written', () {
      expect(
        convertWith(withAuth(bilibili: true, youtube: false, netease: true))
            .browseAsLoggedIn,
        {'bilibili': true, 'youtube': false, 'netease': true},
      );
    });

    test(
      'the Bilibili value forced on by the old v3 to v4 step imports as is',
      () {
        // 讀取器對 `schemaVersion < 4` 的列補做舊 migration；v3→v4 把 B 站打開，轉換器照現值寫。
        final settings = withAuth(
          bilibili: false,
          youtube: true,
          netease: false,
        )..schemaVersion = 3;
        replayLegacySettingsMigration(settings);
        expect(convertWith(settings).browseAsLoggedIn, {
          'bilibili': true,
          'youtube': true,
          'netease': false,
        });
      },
    );

    test('a source without an entry takes the old per-source default', () {
      final bundle = convertWith(LegacySettings(sourceSettings: []));
      expect(bundle.browseAsLoggedIn, {
        'bilibili': true,
        'youtube': false,
        'netease': true,
      });
    });
  });

  group('output device (only on Windows)', () {
    final device = LegacySettings(
      preferredAudioDeviceId: 'wasapi/fake-id',
      preferredAudioDeviceName: 'Fake Speakers',
    );

    test('written when the caller says Windows', () {
      final bundle = convertWith(device, importOutputDevice: true);
      expect(bundle.playback.outputDeviceId, 'wasapi/fake-id');
      expect(bundle.playback.outputDeviceName, 'Fake Speakers');
    });

    test('not written otherwise, nor when the id is blank', () {
      final other = convertWith(device);
      expect(other.playback.outputDeviceId, isNull);
      expect(other.playback.outputDeviceName, isNull);
      final blank = convertWith(
        LegacySettings(
          preferredAudioDeviceId: '  ',
          preferredAudioDeviceName: 'Fake Speakers',
        ),
        importOutputDevice: true,
      );
      expect(blank.playback.outputDeviceId, isNull);
      expect(blank.playback.outputDeviceName, isNull);
    });
  });

  group(
    'layout is the actual last state (detailPanelExpanded :240, width :244)',
    () {
      final changed = LegacySettings(
        detailPanelExpanded: true,
        detailPanelWidth: 500,
      );

      test('written for a database source', () {
        final bundle = convertWith(changed);
        expect(bundle.layout.panelExpanded, isTrue);
        expect(bundle.layout.panelWidth, 500);
      });

      test('the panel is not written for a backup source', () {
        final bundle = convertWith(changed, source: LegacyImportSource.backup);
        expect(bundle.layout.panelExpanded, isNull);
        expect(bundle.layout.panelWidth, isNull);
      });

      test('railExpanded is written for both sources (true and false)', () {
        for (final source in LegacyImportSource.values) {
          for (final expanded in [true, false]) {
            expect(
              convertWith(
                LegacySettings(railExpanded: expanded),
                source: source,
              ).layout.railExpanded,
              expanded,
              reason: '$source $expanded',
            );
          }
        }
      });

      test('the width is clamped to the database limit', () {
        expect(
          convertWith(LegacySettings(detailPanelWidth: 5000)).layout.panelWidth,
          1600,
        );
      });

      test('a panel collapsed on purpose (the old default) is written', () {
        final bundle = convertWith(
          LegacySettings(detailPanelExpanded: false, detailPanelWidth: 412),
        );
        expect(bundle.layout.panelExpanded, isFalse);
        expect(bundle.layout.panelWidth, 412);
      });

      test('invalid widths stay empty', () {
        for (final width in [double.nan, double.infinity, 0.0, -3.0]) {
          expect(
            convertWith(LegacySettings(detailPanelWidth: width))
                .layout
                .panelWidth,
            isNull,
            reason: '$width',
          );
        }
      });
    },
  );

  group('settings without a home are listed only when changed', () {
    List<String> listed(LegacySettings s) =>
        convertWith(s).record.summary.unimportedSettings;

    LegacySettings priority(String youtube) => LegacySettings(
      sourceSettings: [
        LegacySourceSettings(
          sourceId: 'bilibili',
          streamPriority: 'audioOnly,muxed',
          useAuthForPlay: true,
        ),
        LegacySourceSettings(
          sourceId: 'youtube',
          streamPriority: youtube,
          useAuthForPlay: false,
        ),
      ],
    );

    test('nothing is listed for the defaults', () {
      expect(listed(LegacySettings()), isEmpty);
      expect(listed(priority('audioOnly,muxed,hls')), isEmpty);
    });

    test('each changed setting is listed with its stable id', () {
      expect(listed(priority('hls,audioOnly')), ['streamPriority']);
      expect(listed(LegacySettings(maxLyricsCacheFiles: 10)), ['cacheLimit']);
      expect(
        listed(LegacySettings(homeRankingSourcePriority: 'netease,youtube')),
        ['homeRanking'],
      );
      expect(listed(LegacySettings(disabledHomeRankingSources: 'youtube')), [
        'homeRanking',
      ]);
      expect(listed(LegacySettings(railExpanded: true)), isEmpty);
    });

    test('blank values do not count as changed', () {
      expect(listed(LegacySettings(fontFamily: '')), isEmpty);
      expect(listed(LegacySettings(homeRankingSourcePriority: '')), isEmpty);
    });

    test('several changes keep a stable order', () {
      expect(
        listed(
          LegacySettings(
            railExpanded: true,
            primaryColor: 1,
            maxCacheSizeMB: 64,
            homeRankingSourcePriority: 'netease,youtube',
          ),
        ),
        ['cacheLimit', 'homeRanking'],
      );
    });
  });

  group('search history', () {
    LegacySearchHistory row(int id, String query, int minute) =>
        LegacySearchHistory(
          id: id,
          query: query,
          timestamp: DateTime.utc(2020, 1, 1, 0, minute),
        );

    List<(String, DateTime)> converted(List<LegacySearchHistory> rows) => [
      for (final e in convertWith(
        LegacySettings(),
        searchHistory: rows,
      ).searchHistory)
        (e.query, e.searchedAt),
    ];

    test('queries are trimmed, blanks dropped, duplicates keep the newest', () {
      expect(
        converted([
          row(1, ' lofi ', 1),
          row(2, '   ', 5),
          row(3, 'lofi', 3),
          row(4, 'jazz', 2),
          row(5, '', 4),
        ]),
        [
          ('lofi', DateTime.utc(2020, 1, 1, 0, 3)),
          ('jazz', DateTime.utc(2020, 1, 1, 0, 2)),
        ],
      );
    });

    test('only the newest 50 are kept', () {
      final entries = converted([
        for (var i = 0; i < 60; i++) row(i, 'q$i', i),
      ]);
      expect(entries.length, 50);
      expect(entries.first.$1, 'q59');
      expect(entries.last.$1, 'q10');
    });

    test('nothing is written when there is no history', () {
      expect(converted(const []), isEmpty);
    });
  });
}
