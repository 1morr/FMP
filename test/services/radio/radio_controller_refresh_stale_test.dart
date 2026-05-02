import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/radio_station.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/repositories/radio_repository.dart';
import 'package:fmp/services/radio/radio_controller.dart';
import 'package:fmp/services/radio/radio_refresh_service.dart';
import 'package:fmp/services/radio/radio_source.dart';
import 'package:isar/isar.dart';

import '../../support/fakes/fake_audio_service.dart';

void main() {
  setUpAll(() {
    RadioRefreshService.instance = RadioRefreshService(
      radioSource: _CompletingRadioSource(),
      refreshInterval: const Duration(days: 1),
    );
  });

  tearDownAll(() {
    RadioRefreshService.instance.dispose();
  });

  test('refreshStationInfo ignores stale viewer count after station changes',
      () async {
    final source = _CompletingRadioSource();
    final controller = RadioController(
      _FakeRef(),
      _FakeRadioRepository(),
      source,
      FakeAudioService(),
    );
    addTearDown(controller.dispose);

    final stationA = _station(id: 1, sourceId: '101', title: 'Station A');
    final stationB = _station(id: 2, sourceId: '202', title: 'Station B');
    controller.setSeedState(RadioState(
      currentStation: stationA,
      viewerCount: 10,
    ));

    final refreshFuture = controller.refreshStationInfo();
    await pumpEventQueue(times: 2);
    expect(source.calls, ['101']);

    controller.setSeedState(RadioState(
      currentStation: stationB,
      viewerCount: 20,
    ));
    source.complete('101', 99);
    await refreshFuture;

    expect(controller.state.currentStation, same(stationB));
    expect(controller.state.viewerCount, 20);
  });

  test('refreshAll coalesces overlapping refresh requests', () async {
    final source = _CompletingLiveInfoSource();
    final repository = _RefreshAllRadioRepository();
    final service = RadioRefreshService(
      radioSource: source,
      refreshInterval: const Duration(days: 1),
    );
    addTearDown(service.dispose);

    service.setRepository(repository);
    await _pumpUntil(
      () => repository.getAllCalls == 1,
      reason: 'initial setRepository refresh should run with no stations',
    );

    repository.stations = [
      _station(id: 1, sourceId: '101', title: 'Original Station'),
    ];

    final oldRefresh = service.refreshAll();
    await _pumpUntil(
      () => source.liveInfoCalls.length == 1,
      reason: 'old refresh should request live info',
    );

    final newRefresh = service.refreshAll();
    expect(identical(newRefresh, oldRefresh), isTrue);
    expect(source.liveInfoCalls, hasLength(1));

    source.completeLiveInfo(
      0,
      const LiveRoomInfo(
        title: 'New Station',
        thumbnailUrl: 'https://example.com/new.jpg',
        hostName: 'New Host',
        isLive: true,
      ),
    );
    await newRefresh;
    expect(service.isStationLive(1), isTrue);
    expect(repository.savedStations.single.title, 'New Station');
  });
}

RadioStation _station({
  required int id,
  required String sourceId,
  required String title,
}) {
  return RadioStation()
    ..id = id
    ..url = 'https://live.bilibili.com/$sourceId'
    ..sourceType = SourceType.bilibili
    ..sourceId = sourceId
    ..title = title;
}

Future<void> _pumpUntil(
  bool Function() condition, {
  required String reason,
  Duration timeout = const Duration(seconds: 2),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  if (!condition()) fail(reason);
}

extension on RadioController {
  void setSeedState(RadioState state) {
    this.state = state;
  }
}

class _CompletingRadioSource extends RadioSource {
  final calls = <String>[];
  final _completers = <String, Completer<int?>>{};

  @override
  Future<int?> getHighEnergyUserCount(RadioStation station) {
    calls.add(station.sourceId);
    return _completers
        .putIfAbsent(station.sourceId, Completer<int?>.new)
        .future;
  }

  void complete(String sourceId, int? count) {
    _completers[sourceId]!.complete(count);
  }
}

class _CompletingLiveInfoSource extends RadioSource {
  final liveInfoCalls = <String>[];
  final _liveInfoCompleters = <Completer<LiveRoomInfo>>[];

  @override
  Future<LiveRoomInfo> getLiveInfo(RadioStation station) {
    liveInfoCalls.add(station.sourceId);
    final completer = Completer<LiveRoomInfo>();
    _liveInfoCompleters.add(completer);
    return completer.future;
  }

  void completeLiveInfo(int index, LiveRoomInfo info) {
    _liveInfoCompleters[index].complete(info);
  }
}

class _FakeRef extends Fake implements Ref {}

class _FakeRadioRepository extends Fake implements RadioRepository {
  @override
  Future<List<RadioStation>> getAll() async => [];

  @override
  Stream<List<RadioStation>> watchAll() => const Stream.empty();
}

class _RefreshAllRadioRepository extends Fake implements RadioRepository {
  List<RadioStation> stations = [];
  final savedStations = <RadioStation>[];
  int getAllCalls = 0;

  @override
  Future<List<RadioStation>> getAll() async {
    getAllCalls++;
    return stations.map(_copyStation).toList();
  }

  @override
  Future<int> save(RadioStation station) async {
    savedStations.add(_copyStation(station));
    return station.id;
  }
}

RadioStation _copyStation(RadioStation station) {
  return RadioStation()
    ..id = station.id
    ..url = station.url
    ..sourceType = station.sourceType
    ..sourceId = station.sourceId
    ..title = station.title
    ..thumbnailUrl = station.thumbnailUrl
    ..hostName = station.hostName;
}

class _FakeIsar extends Fake implements Isar {}
