import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar/isar.dart';

import '../../../core/constants/ui_constants.dart';
import '../../../i18n/strings.g.dart';
import '../../../providers/database/database_catalog.dart';
import '../../../providers/database/database_provider.dart';

/// 数据库查看页面
class DatabaseViewerPage extends ConsumerStatefulWidget {
  const DatabaseViewerPage({super.key});

  @override
  ConsumerState<DatabaseViewerPage> createState() => _DatabaseViewerPageState();
}

class _DatabaseViewerPageState extends ConsumerState<DatabaseViewerPage> {
  String _selectedCollectionName = fmpDatabaseCollections.first.name;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(t.databaseViewer.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: t.databaseViewer.refresh,
            onPressed: () => setState(() {}),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // 集合选择器
          _buildCollectionSelector(),
          const Divider(height: 1),
          // 数据列表
          Expanded(
            child: _buildDataView(),
          ),
        ],
      ),
    );
  }

  Widget _buildCollectionSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ScrollConfiguration(
        // 允许鼠标拖拽滚动（桌面端支持）
        behavior: ScrollConfiguration.of(context).copyWith(
          dragDevices: {
            PointerDeviceKind.touch,
            PointerDeviceKind.mouse,
            PointerDeviceKind.trackpad,
          },
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: fmpDatabaseCollections.map((collection) {
              final isSelected = collection.name == _selectedCollectionName;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text(collection.name),
                  selected: isSelected,
                  onSelected: (selected) {
                    if (selected) {
                      setState(() => _selectedCollectionName = collection.name);
                    }
                  },
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildDataView() {
    final dbAsync = ref.watch(databaseProvider);

    return dbAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) =>
          Center(child: Text(t.databaseViewer.loadFailed(error: e.toString()))),
      data: (isar) => _buildCollectionData(isar),
    );
  }

  Widget _buildCollectionData(Isar isar) {
    FmpDatabaseCollection? selected;
    for (final collection in fmpDatabaseCollections) {
      if (collection.name == _selectedCollectionName) {
        selected = collection;
        break;
      }
    }

    if (selected == null) {
      return Center(child: Text(t.databaseViewer.unknownCollection));
    }

    return _DatabaseCollectionListView(
      isar: isar,
      collection: selected,
    );
  }
}

class _DatabaseCollectionListView extends StatelessWidget {
  const _DatabaseCollectionListView({
    required this.isar,
    required this.collection,
  });

  final Isar isar;
  final FmpDatabaseCollection collection;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Object>>(
      future: collection.query(isar),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Text(
              t.databaseViewer.loadFailed(error: snapshot.error.toString()),
            ),
          );
        }

        final items = snapshot.data ?? const <Object>[];
        return _buildList(
          context,
          itemCount: items.length,
          headerText: t.databaseViewer.recordCount(count: items.length),
          itemBuilder: (index) {
            final item = items[index];
            return _DataCard(
              title: collection.title(item),
              subtitle: collection.subtitle(item),
              sections: collection.sections(item),
            );
          },
        );
      },
    );
  }
}

/// 构建列表
Widget _buildList(
  BuildContext context, {
  required int itemCount,
  required String headerText,
  required Widget Function(int index) itemBuilder,
}) {
  if (itemCount == 0) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.inbox_outlined,
            size: 64,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            t.databaseViewer.noData,
            style: TextStyle(color: Theme.of(context).colorScheme.outline),
          ),
        ],
      ),
    );
  }

  return Column(
    children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        width: double.infinity,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Text(
          headerText,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
      Expanded(
        child: ListView.builder(
          padding: const EdgeInsets.all(8),
          itemCount: itemCount,
          itemBuilder: (context, index) => itemBuilder(index),
        ),
      ),
    ],
  );
}

/// 数据卡片
class _DataCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<DatabaseViewerSection> sections;

  const _DataCard({
    required this.title,
    required this.subtitle,
    required this.sections,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            color: colorScheme.outline,
            fontSize: 12,
          ),
        ),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: sections.map((section) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Section 标题
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        borderRadius: AppRadius.borderRadiusSm,
                      ),
                      child: Text(
                        section.title,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                    // Section 数据
                    ...section.data.entries.map((entry) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4, left: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 180,
                              child: Text(
                                '${entry.key}:',
                                style: TextStyle(
                                  color: colorScheme.primary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            Expanded(
                              child: SelectableText(
                                entry.value,
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                    const SizedBox(height: 12),
                  ],
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}
