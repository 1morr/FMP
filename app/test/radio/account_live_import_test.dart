import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/core_providers.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/logging/log.dart';
import 'package:fmp/core/logging/log_record.dart';
import 'package:fmp/core/redaction/redactor.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/domain/radio.dart';
import 'package:fmp/plugins/plugin_registry.dart';
import 'package:fmp/plugins/source_dto.dart';
import 'package:fmp/plugins/source_plugin.dart';
import 'package:fmp/radio/account_live_import.dart';

import '../playback/fake_source_plugin.dart';
import '../support/memory_database.dart';

// 從帳號匯入電台（M4 PR 15，design §7.4）：`libraryLiveRooms` → `RadioRepository.add`，
// 不呼叫 `liveStatus`。插件是假的，資料庫是記憶體內的真的。

LiveRoom _room(
  String roomId, {
  String title = 'Room',
  LiveRoomStatus status = LiveRoomStatus.live,
}) => LiveRoom(
  roomId: roomId,
  title: title,
  hostName: 'Host',
  status: status,
  online: 3,
);

/// 宣告 `live` 與 `libraryRead`；[rooms] 或 [error] 給了才算匯出 `libraryLiveRooms`。
/// `liveStatus` 一呼叫就丟：匯入不該查它。
FakeSourcePlugin _plugin({
  String id = 'bili',
  bool live = true,
  List<LiveRoom>? rooms,
  Object? error,
}) {
  final plugin = FakeSourcePlugin(
    (_) => const [],
    id: id,
    live: live,
    libraryRead: true,
  );
  if (rooms != null || error != null) {
    plugin.onLibraryLiveRooms = () {
      if (error != null) throw error;
      return LibraryLiveRooms(rooms: rooms!);
    };
  }
  plugin.onLiveStatus = (_) =>
      throw StateError('liveStatus must not be called');
  return plugin;
}

final class _Env {
  _Env(List<SourcePlugin> plugins) {
    log = Log(redactor: Redactor(), minimumLevel: LogLevel.debug);
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        logProvider.overrideWithValue(log),
        pluginRegistryProvider.overrideWithBuild(
          (ref, notifier) => {
            for (final plugin in plugins) plugin.manifest.id: plugin,
          },
        ),
      ],
    );
    addTearDown(container.dispose);
  }

  final database = memoryDatabase();
  late final Log log;
  late final ProviderContainer container;

  Future<AccountLiveImport> import([String pluginId = 'bili']) =>
      container.read(accountLiveImporterProvider).importFromAccount(pluginId);

  Future<List<(String, String)>> stations() async => [
    for (final s in await container.read(radioRepositoryProvider).list())
      (s.pluginId, s.roomId),
  ];
}

void main() {
  test('adds every room, with the data the room already carries', () async {
    final plugin = _plugin(
      rooms: [
        _room('1', title: 'One'),
        _room('2', title: 'Two', status: LiveRoomStatus.offline),
      ],
    );
    final env = _Env([plugin]);

    final result = await env.import();

    expect((result.added, result.existing), (2, 0));
    final stations = await env.container.read(radioRepositoryProvider).list();
    expect(
      [for (final s in stations) (s.roomId, s.title, s.hostName)],
      [('1', 'One', 'Host'), ('2', 'Two', 'Host')],
    );
    // LiveRoom 已有顯示資料：狀態直接存，不另外查 liveStatus（處理函式一呼叫就丟）。
    expect(
      [for (final s in stations) s.liveStatus],
      [RadioLiveStatus.live, RadioLiveStatus.offline],
    );
    expect(plugin.libraryLiveRoomsCalls, 1);
    expect(plugin.liveStatusQueries, isEmpty);
  });

  test('rooms already in the list are counted, not changed or '
      'duplicated', () async {
    final plugin = _plugin(rooms: [_room('1'), _room('2'), _room('3')]);
    final env = _Env([plugin]);
    await env.container
        .read(radioRepositoryProvider)
        .add(
          pluginId: 'bili',
          roomId: '2',
          title: 'Mine',
          addedAt: DateTime.utc(2026, 10, 1),
        );

    final first = await env.import();
    final second = await env.import();

    expect((first.added, first.existing), (2, 1));
    expect((second.added, second.existing), (0, 3));
    expect(await env.stations(), [('bili', '2'), ('bili', '1'), ('bili', '3')]);
    final kept = (await env.container.read(radioRepositoryProvider).list())
        .firstWhere((s) => s.roomId == '2');
    expect(kept.title, 'Mine');
  });

  test('the same room id under another plugin is another station', () async {
    final env = _Env([
      _plugin(rooms: [_room('1')]),
      _plugin(id: 'other', rooms: [_room('1')]),
    ]);

    await env.import();
    final other = await env.import('other');

    expect((other.added, other.existing), (1, 0));
    expect(await env.stations(), [('bili', '1'), ('other', '1')]);
  });

  test('an empty account adds nothing', () async {
    final env = _Env([_plugin(rooms: const [])]);

    final result = await env.import();

    expect((result.added, result.existing), (0, 0));
    expect(await env.stations(), isEmpty);
  });

  test('logs the plugin id and the counts, never a room name', () async {
    final env = _Env([
      _plugin(rooms: [_room('1', title: 'Secret room name')]),
    ]);

    await env.import();

    final record = env.log.history.singleWhere((r) => r.tag == 'radio');
    expect(record.fields, {'pluginId': 'bili', 'added': 1, 'existing': 0});
    expect(
      env.log.history.map((r) => r.toJsonLine()).join('\n'),
      isNot(contains('Secret room name')),
    );
  });

  group('failures are AppError and nothing is written', () {
    test('AuthRequired from the plugin keeps its type', () async {
      final env = _Env([_plugin(error: AuthRequired(pluginId: 'bili'))]);

      await expectLater(env.import(), throwsA(isA<AuthRequired>()));
      expect(await env.stations(), isEmpty);
    });

    test('NetworkError from the plugin keeps its type', () async {
      final env = _Env([_plugin(error: NetworkError(pluginId: 'bili'))]);

      await expectLater(env.import(), throwsA(isA<NetworkError>()));
    });

    test('a non-AppError is wrapped as UnexpectedError', () async {
      final env = _Env([_plugin(error: StateError('boom'))]);

      await expectLater(env.import(), throwsA(isA<UnexpectedError>()));
    });

    test('an unknown plugin is Unsupported', () async {
      final env = _Env([_plugin(rooms: const [])]);

      await expectLater(env.import('nope'), throwsA(isA<Unsupported>()));
    });

    test('a plugin without live is Unsupported', () async {
      final env = _Env([
        _plugin(live: false, rooms: [_room('1')]),
      ]);

      await expectLater(env.import(), throwsA(isA<Unsupported>()));
      expect(await env.stations(), isEmpty);
    });

    test('a plugin that does not export libraryLiveRooms is '
        'Unsupported', () async {
      final env = _Env([_plugin()]);

      await expectLater(env.import(), throwsA(isA<Unsupported>()));
    });
  });

  test('a write failing midway keeps the rooms already written; importing '
      'again counts them as existing', () async {
    final env = _Env([
      _plugin(rooms: [_room('1'), _room('2'), _room('3')]),
    ]);
    // 第二個房間寫不進去。
    await env.database.customStatement(
      'CREATE TRIGGER boom BEFORE INSERT ON radio_stations '
      "WHEN NEW.room_id = '2' "
      "BEGIN SELECT RAISE(ABORT, 'boom'); END",
    );

    await expectLater(env.import(), throwsA(isA<AppError>()));
    expect(await env.stations(), [('bili', '1')]);
    expect(env.log.history.where((r) => r.tag == 'radio'), isEmpty);

    await env.database.customStatement('DROP TRIGGER boom');
    final again = await env.import();

    expect((again.added, again.existing), (2, 1));
    expect(await env.stations(), [('bili', '1'), ('bili', '2'), ('bili', '3')]);
  });
}
