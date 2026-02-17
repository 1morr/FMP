import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/ui_constants.dart';
import '../../../../core/services/image_loading_service.dart';
import '../../../../data/models/track.dart';
import '../../../../i18n/strings.g.dart';
import '../../../../providers/playlist_provider.dart';

/// 封面選擇結果
class CoverPickerResult {
  /// 選擇的封面 URL（可能是歌曲封面 URL 或用戶輸入的 URL）
  final String? coverUrl;

  /// 是否使用默認封面（清除自定義封面）
  final bool useDefault;

  const CoverPickerResult({this.coverUrl, this.useDefault = false});

  /// 使用默認封面
  const CoverPickerResult.useDefault()
      : coverUrl = null,
        useDefault = true;

  /// 使用指定的封面 URL
  const CoverPickerResult.custom(this.coverUrl) : useDefault = false;
}

/// 封面選擇器對話框
class CoverPickerDialog extends ConsumerStatefulWidget {
  /// 歌單 ID（用於獲取歌單內的歌曲）
  final int playlistId;

  /// 當前封面 URL
  final String? currentCoverUrl;

  const CoverPickerDialog({
    super.key,
    required this.playlistId,
    this.currentCoverUrl,
  });

  @override
  ConsumerState<CoverPickerDialog> createState() => _CoverPickerDialogState();
}

class _CoverPickerDialogState extends ConsumerState<CoverPickerDialog>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _urlController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 標題
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      t.library.coverPicker.title,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Tab 切換
            TabBar(
              controller: _tabController,
              tabs: [
                Tab(text: t.library.coverPicker.trackCovers),
                Tab(text: t.library.coverPicker.networkUrl),
              ],
            ),

            // Tab 內容
            Flexible(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildTrackCoversTab(context),
                  _buildUrlTab(context),
                ],
              ),
            ),

            // 使用默認按鈕
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(
                        context, const CoverPickerResult.useDefault());
                  },
                  icon: const Icon(Icons.restore),
                  label: Text(t.library.coverPicker.useDefault),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 構建歌曲封面網格
  Widget _buildTrackCoversTab(BuildContext context) {
    final state = ref.watch(playlistDetailProvider(widget.playlistId));

    if (state.isLoading && state.tracks.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.error != null && state.tracks.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(t.library.loadFailedWithError(error: state.error.toString())),
        ),
      );
    }

    if (state.tracks.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(t.library.coverPicker.noTracks),
        ),
      );
    }

    // 過濾出有封面的歌曲並去重
    final tracksWithCovers = <Track>[];
    final seenUrls = <String>{};
    for (final track in state.tracks) {
      final url = track.thumbnailUrl;
      if (url != null && url.isNotEmpty && !seenUrls.contains(url)) {
        seenUrls.add(url);
        tracksWithCovers.add(track);
      }
    }

    if (tracksWithCovers.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(t.library.coverPicker.noCoverAvailable),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 100,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
      ),
      itemCount: tracksWithCovers.length,
      itemBuilder: (context, index) {
        final track = tracksWithCovers[index];
        final isSelected = track.thumbnailUrl == widget.currentCoverUrl;

        return _CoverGridItem(
          imageUrl: track.thumbnailUrl!,
          isSelected: isSelected,
          onTap: () {
            Navigator.pop(
              context,
              CoverPickerResult.custom(track.thumbnailUrl),
            );
          },
        );
      },
    );
  }

  /// 構建 URL 輸入 Tab
  Widget _buildUrlTab(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // URL 輸入框
          TextField(
            controller: _urlController,
            decoration: InputDecoration(
              labelText: t.library.coverPicker.imageUrl,
              hintText: 'https://example.com/image.jpg',
              prefixIcon: const Icon(Icons.link),
              suffixIcon: _urlController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        setState(() {
                          _urlController.clear();
                        });
                      },
                    )
                  : null,
            ),
            onChanged: (value) {
              setState(() {});
            },
          ),

          const SizedBox(height: 16),

          // 預覽區域
          Expanded(
            child: _urlController.text.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.image_outlined,
                          size: 64,
                          color: colorScheme.outline,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          t.library.coverPicker.urlPreviewHint,
                          style: TextStyle(color: colorScheme.outline),
                        ),
                      ],
                    ),
                  )
                : Center(
                    child: ClipRRect(
                      borderRadius: AppRadius.borderRadiusLg,
                      child: ImageLoadingService.loadImage(
                        networkUrl: _urlController.text,
                        placeholder: const ImagePlaceholder.track(),
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
          ),

          const SizedBox(height: 16),

          // 確認按鈕
          FilledButton(
            onPressed: _urlController.text.isEmpty
                ? null
                : () {
                    final url = _urlController.text.trim();
                    if (url.isNotEmpty) {
                      Navigator.pop(context, CoverPickerResult.custom(url));
                    }
                  },
            child: Text(t.library.coverPicker.useThisCover),
          ),
        ],
      ),
    );
  }
}

/// 封面網格項
class _CoverGridItem extends StatelessWidget {
  final String imageUrl;
  final bool isSelected;
  final VoidCallback onTap;

  const _CoverGridItem({
    required this.imageUrl,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.borderRadiusLg,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: AppRadius.borderRadiusLg,
            border: isSelected
                ? Border.all(color: colorScheme.primary, width: 3)
                : null,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(isSelected ? AppRadius.sm : AppRadius.md),
            child: Stack(
              fit: StackFit.expand,
              children: [
                ImageLoadingService.loadImage(
                  networkUrl: imageUrl,
                  placeholder: const ImagePlaceholder.track(),
                  fit: BoxFit.cover,
                  width: 100,
                  height: 100,
                  targetDisplaySize: 80,
                ),
                if (isSelected)
                  Container(
                    color: colorScheme.primary.withValues(alpha: 0.3),
                    child: Center(
                      child: Icon(
                        Icons.check_circle,
                        color: colorScheme.onPrimary,
                        size: 32,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
