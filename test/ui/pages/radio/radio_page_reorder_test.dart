import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/radio_station.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/i18n/strings.g.dart';
import 'package:fmp/services/radio/radio_controller.dart';
import 'package:fmp/ui/pages/radio/radio_page.dart';
import 'package:reorderable_grid_view/reorderable_grid_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'RadioPage restores station order when reorder persistence fails',
    (tester) async {
      final controller = _FailingReorderRadioController([
        _buildStation(id: 1, title: 'Alpha', sortOrder: 0),
        _buildStation(id: 2, title: 'Bravo', sortOrder: 1),
        _buildStation(id: 3, title: 'Charlie', sortOrder: 2),
      ]);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.binding.setSurfaceSize(const Size(180, 900));
      LocaleSettings.setLocale(AppLocale.en);

      await tester.pumpWidget(
        TranslationProvider(
          child: ProviderScope(
            overrides: [
              radioControllerProvider.overrideWith((ref) => controller),
            ],
            child: const MaterialApp(home: RadioPage()),
          ),
        ),
      );

      await tester.pump();

      expect(_stationOrder(tester), ['Alpha', 'Bravo', 'Charlie']);

      await tester.tap(find.byIcon(Icons.swap_vert));
      await tester.pump();

      final grid = tester.widget<ReorderableGridView>(
        find.byType(ReorderableGridView),
      );
      grid.onReorder(0, 2);

      await tester.pump();
      expect(
        _stationOrder(tester),
        ['Bravo', 'Charlie', 'Alpha'],
        reason: 'reorder mode should apply the optimistic local order first',
      );

      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();

      expect(_stationOrder(tester), ['Alpha', 'Bravo', 'Charlie']);
    },
  );
}

class _FailingReorderRadioController extends RadioController {
  _FailingReorderRadioController(List<RadioStation> stations)
    : super.forLoading() {
    state = RadioState(stations: stations);
  }

  @override
  Future<void> reorderStations(List<int> newOrder) async {
    await Future<void>.delayed(const Duration(milliseconds: 1));
    throw StateError('persist failed');
  }

  @override
  void updateStationsOrder(List<RadioStation> orderedStations) {
    state = state.copyWith(stations: orderedStations);
  }
}

RadioStation _buildStation({
  required int id,
  required String title,
  required int sortOrder,
}) {
  return RadioStation()
    ..id = id
    ..url = 'https://example.com/$id'
    ..title = title
    ..sourceType = SourceType.bilibili
    ..sourceId = '$id'
    ..sortOrder = sortOrder;
}

List<String> _stationOrder(WidgetTester tester) {
  final titles = ['Alpha', 'Bravo', 'Charlie'];
  final positions = <String, double>{
    for (final title in titles) title: tester.getTopLeft(find.text(title)).dy,
  };
  final ordered = positions.entries.toList()
    ..sort((a, b) => a.value.compareTo(b.value));
  return ordered.map((entry) => entry.key).toList();
}
