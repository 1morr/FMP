import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/data/repositories/playlist_repository.dart';
import 'package:fmp/ui/artwork/artwork_image.dart';
import 'package:fmp/ui/i18n/ui_locale.dart';
import 'package:fmp/ui/theme/app_layout.dart';
import 'package:fmp/ui/theme/app_tokens.dart';

/// 歌單對話框填的內容。
typedef PlaylistInput = ({String name, String? description});

/// 建立（[editing] 為空）或編輯歌單的對話框（M4 design §10.5）：名稱（必填）、描述、封面。
/// 按「建立」／「儲存」回傳填的內容（名稱去掉空白後不能是空的），取消回 `null`。
///
/// 封面目前一律是第一首歌的封面（「自訂」以圖片網址、「使用預設」等它的讀取路徑定了再加），
/// 對話框只顯示它。
Future<PlaylistInput?> showPlaylistDialog(
  BuildContext context, {
  PlaylistOverview? editing,
}) => showDialog<PlaylistInput>(
  context: context,
  builder: (_) => _PlaylistDialog(editing: editing),
);

class _PlaylistDialog extends ConsumerStatefulWidget {
  const _PlaylistDialog({this.editing});

  final PlaylistOverview? editing;

  @override
  ConsumerState<_PlaylistDialog> createState() => _PlaylistDialogState();
}

class _PlaylistDialogState extends ConsumerState<_PlaylistDialog> {
  late final _name = TextEditingController(text: widget.editing?.playlist.name);
  late final _description = TextEditingController(
    text: widget.editing?.playlist.description,
  );

  /// 名稱欄改過：之後清空才說它是必填（剛打開的空欄不先報錯）。
  var _nameTouched = false;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  bool get _valid => _name.text.trim().isNotEmpty;

  void _submit() {
    if (!_valid) return;
    Navigator.of(context)
        .pop<PlaylistInput>((name: _name.text, description: _description.text));
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider).library;
    final theme = Theme.of(context);
    final spacing = AppTokens.of(context).spacing;
    final first = widget.editing?.firstTrack;
    return AlertDialog(
      title: Text(widget.editing == null ? t.createTitle : t.editTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListenableBuilder(
              listenable: _name,
              builder: (context, _) => TextField(
                controller: _name,
                autofocus: true,
                textInputAction: TextInputAction.next,
                onChanged: (_) => _nameTouched = true,
                decoration: InputDecoration(
                  labelText: t.name,
                  errorText: _nameTouched && !_valid ? t.nameRequired : null,
                ),
              ),
            ),
            SizedBox(height: spacing.x4),
            TextField(
              controller: _description,
              minLines: 1,
              maxLines: 4,
              decoration: InputDecoration(labelText: t.description),
            ),
            SizedBox(height: spacing.x4),
            Row(
              children: [
                ArtworkImage(
                  pluginId: first?.sourceTypeId ?? '',
                  artwork: first?.artwork ?? const [],
                  size: AppLayout.playlistCoverPreview,
                ),
                SizedBox(width: spacing.x4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t.cover, style: theme.textTheme.titleSmall),
                      Text(
                        t.coverDefault,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(t.cancel),
        ),
        ListenableBuilder(
          listenable: _name,
          builder: (context, _) => FilledButton(
            onPressed: _valid ? _submit : null,
            child: Text(widget.editing == null ? t.create : t.save),
          ),
        ),
      ],
    );
  }
}
