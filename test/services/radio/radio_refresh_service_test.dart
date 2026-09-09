import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/radio_station.dart';
import 'package:fmp/data/repositories/radio_repository.dart';
import 'package:fmp/data/sources/bilibili_exception.dart';
import 'package:fmp/services/radio/radio_refresh_service.dart';
import 'package:fmp/services/radio/radio_source.dart';

import '../../support/pump_until.dart';

/// 電台輪詢對 Bilibili 風控的兩條煞車（#95）：被擋的那一輪停下並退避，
/// App 在背景時不輪詢。時間由測試自己推進，定時器本身不參與。
void main() {
  const interval = Duration(minutes: 5);
  late _Clock clock;
  late _ScriptedRadioSource source;
  late _Repository repository;
  late RadioRefreshService service;

  setUp(() async {
    clock = _Clock(DateTime(2026, 9, 10, 12));
    source = _ScriptedRadioSource();
    repository = _Repository([
      _station(id: 1, sourceId: '101'),
      _station(id: 2, sourceId: '202'),
      _station(id: 3, sourceId: '303'),
    ]);
    service = RadioRefreshService(
      radioSource: source,
      refreshInterval: interval,
      now: clock.now,
    );
    addTearDown(service.dispose);
    // setRepository 會立刻跑第一輪；等它結束，每條測試都從乾淨狀態開始。
    // 定時器本身在測試裡不參與，時間到了直接呼叫 tick()。
    service.setRepository(repository);
    await service.refreshAll();
    source.calls.clear();
  });

  test('a clean round asks every station and leaves no backoff', () async {
    await service.refreshAll();

    expect(source.calls, ['101', '202', '303']);
    expect(service.backoffUntil, isNull);
    expect(service.isStationLive(1), isTrue);
  });

  test('a risk-controlled round stops at that station and keeps its last '
      'known status', () async {
    source.rateLimitFrom = '202';

    await service.refreshAll();

    expect(source.calls, ['101', '202'], reason: '303 must not be asked');
    expect(
      service.isStationLive(2),
      isTrue,
      reason: 'risk control is not the same as going offline',
    );
    expect(service.backoffUntil, clock.now().add(interval * 2));
  });

  test('ticks inside the backoff window do nothing; the first tick after it '
      'refreshes', () async {
    source.rateLimitFrom = '101';
    await service.refreshAll();
    source.calls.clear();

    clock.advance(interval);
    service.tick();
    await drainEventQueue(reason: 'a tick inside the backoff must stay idle');
    expect(source.calls, isEmpty);

    clock.advance(interval);
    service.tick();
    await pumpUntil(
      () => source.calls.isNotEmpty,
      reason: 'the first tick after the backoff should refresh',
    );
  });

  test('consecutive risk-controlled rounds double the backoff and cap at '
      '30 minutes', () async {
    source.rateLimitFrom = '101';
    final expected = [
      interval * 2,
      interval * 4,
      RadioRefreshService.maxBackoff,
      RadioRefreshService.maxBackoff,
    ];
    for (final delay in expected) {
      final start = clock.now();
      await service.refreshAll();
      expect(service.backoffUntil, start.add(delay));
      clock.advance(delay);
    }
  });

  test('a clean round after backoff resets the ladder', () async {
    source.rateLimitFrom = '101';
    await service.refreshAll();
    await service.refreshAll();
    clock.advance(RadioRefreshService.maxBackoff);

    source.rateLimitFrom = null;
    await service.refreshAll();
    expect(service.backoffUntil, isNull);

    source.rateLimitFrom = '101';
    await service.refreshAll();
    expect(service.backoffUntil, clock.now().add(interval * 2));
  });

  test('paused service ignores ticks; resume refreshes only when a full '
      'interval has passed', () async {
    service.pause();
    clock.advance(interval * 3);
    service.tick();
    await drainEventQueue(reason: 'a paused service must not refresh');
    expect(source.calls, isEmpty);

    // 回前景時距上一輪已經三個間隔，補跑一輪。
    service.resume();
    await pumpUntil(
      () => source.calls.length == 3,
      reason: 'resume after a stale interval should refresh every station',
    );
    source.calls.clear();

    // 才剛刷新完又切背景再回來，不該多打一輪。
    service.pause();
    clock.advance(const Duration(seconds: 30));
    service.resume();
    await drainEventQueue(reason: 'a fresh resume must not add a round');
    expect(source.calls, isEmpty);
  });

  test('manual refreshAll bypasses both the backoff and the pause', () async {
    source.rateLimitFrom = '101';
    await service.refreshAll();
    source.calls.clear();
    source.rateLimitFrom = null;
    service.pause();

    await service.refreshAll();

    expect(source.calls, ['101', '202', '303']);
  });
}

RadioStation _station({required int id, required String sourceId}) {
  return RadioStation()
    ..id = id
    ..sourceId = sourceId
    ..title = 'Station $sourceId'
    ..url = 'https://live.bilibili.com/$sourceId';
}

class _Clock {
  _Clock(this._current);

  DateTime _current;

  DateTime now() => _current;

  void advance(Duration by) => _current = _current.add(by);
}

/// 依 sourceId 決定回答還是拋風控。設了 [rateLimitFrom] 之後，那一台開始拋。
class _ScriptedRadioSource extends RadioSource {
  final List<String> calls = [];
  String? rateLimitFrom;

  @override
  Future<LiveRoomInfo> getLiveInfo(RadioStation station) async {
    calls.add(station.sourceId);
    if (station.sourceId == rateLimitFrom) {
      throw const BilibiliApiException(
        numericCode: -412,
        message: 'risk control',
      );
    }
    return LiveRoomInfo(title: station.title, isLive: true);
  }
}

class _Repository extends Fake implements RadioRepository {
  _Repository(this.stations);

  final List<RadioStation> stations;

  @override
  Future<List<RadioStation>> getAll() async => List.of(stations);

  @override
  Future<int> save(RadioStation station) async => station.id;
}
