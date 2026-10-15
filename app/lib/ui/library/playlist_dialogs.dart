import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/data/repositories/playlist_repository.dart';
import 'package:fmp/domain/track_info.dart';
import 'package:fmp/plugins/plugin_artwork.dart';
import 'package:fmp/plugins/plugin_registry.dart';
import 'package:fmp/ui/i18n/ui_locale.dart';
import 'package:fmp/ui/library/playlist_cover.dart';
import 'package:fmp/ui/theme/app_layout.dart';
import 'package:fmp/ui/theme/app_tokens.dart';

/// 歌單對話框填的內容。[artwork] 空＝封面用第一首的。
typedef PlaylistInput = ({
  String name,
  String? description,
  List<TrackArtwork> artwork,
});

/// 建立（[editing] 為空）或編輯歌單的對話框（M4 design §10.5）：名稱（必填）、描述、封面。
/// 按「建立」／「儲存」回傳填的內容（名稱去掉空白後不能是空的），取消回 `null`。
///
/// 封面預設是第一首歌的封面；「自訂」照舊版填圖片網址，「使用預設」清回。自訂的網址要屬於
/// 某個已安裝且啟用的插件的允許網域（之後經那個插件的媒體 client 讀，見 [PlaylistCover]），
/// 否則寫明原因、不能送出；宿主不讀任意網址（ADR 0012 §決定 1）。編輯時沒改過的自訂封面
/// 照舊保留，不再檢查（那個插件之後被停用也改得了名稱）。
Future<PlaylistInput?> showPlaylistDialog(
  BuildContext context, {
  PlaylistOverview? editing,
}) => showDialog<PlaylistInput>(
  context: context,
  builder: (_) => _PlaylistDialog(editing: editing),
);

/// 自訂封面網址的檢查結果。
enum _CoverCheck {
  /// 還沒填。
  empty,

  /// 不是 `https` 網址。
  invalid,

  /// 不屬於任何已安裝且啟用的插件。
  notFromSource,
  ok,
}

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

  /// 打開時的封面（編輯時是歌單現在的）。
  late final List<TrackArtwork> _initialArtwork =
      widget.editing?.playlist.artwork ?? const [];
  late final _coverUrl = TextEditingController(
    text: _initialArtwork.isEmpty ? null : '${_initialArtwork.first.url}',
  );
  final _coverFocus = FocusNode();

  /// 選了「自訂」。
  late var _custom = _initialArtwork.isNotEmpty;

  /// 名稱欄改過：之後清空才說它是必填（剛打開的空欄不先報錯）。
  var _nameTouched = false;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _coverUrl.dispose();
    _coverFocus.dispose();
    super.dispose();
  }

  /// 網址欄還是打開時的自訂封面。
  bool get _coverUnchanged =>
      _initialArtwork.isNotEmpty &&
      _coverUrl.text.trim() == '${_initialArtwork.first.url}';

  _CoverCheck _checkCover() {
    final text = _coverUrl.text.trim();
    if (text.isEmpty) return _CoverCheck.empty;
    if (_coverUnchanged) return _CoverCheck.ok;
    final url = Uri.tryParse(text);
    if (url == null || url.scheme != 'https' || url.host.isEmpty) {
      return _CoverCheck.invalid;
    }
    final plugins = ref.read(pluginRegistryProvider).value?.values ?? const [];
    return pluginForArtwork(plugins, url) == null
        ? _CoverCheck.notFromSource
        : _CoverCheck.ok;
  }

  /// 送出時的封面；自訂而網址不行時是 `null`。
  List<TrackArtwork>? get _artwork {
    if (!_custom) return const [];
    if (_checkCover() != _CoverCheck.ok) return null;
    if (_coverUnchanged) return _initialArtwork;
    return [TrackArtwork(url: Uri.parse(_coverUrl.text.trim()))];
  }

  bool get _valid => _name.text.trim().isNotEmpty && _artwork != null;

  void _submit() {
    final artwork = _artwork;
    if (!_valid || artwork == null) return;
    Navigator.of(context).pop<PlaylistInput>((
      name: _name.text,
      description: _description.text,
      artwork: artwork,
    ));
  }

  void _chooseCustom() {
    setState(() => _custom = true);
    _coverFocus.requestFocus();
  }

  void _useDefault() => setState(() {
    _custom = false;
    _coverUrl.clear();
  });

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider).library;
    // 插件清單變了（啟用、停用）時重新檢查網址。
    ref.watch(pluginRegistryProvider);
    final theme = Theme.of(context);
    final spacing = AppTokens.of(context).spacing;
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
                  errorText: _nameTouched && _name.text.trim().isEmpty
                      ? t.nameRequired
                      : null,
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
            ListenableBuilder(
              listenable: _coverUrl,
              builder: (context, _) {
                final check = _custom ? _checkCover() : _CoverCheck.ok;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        PlaylistCover(
                          artwork: _custom ? (_artwork ?? const []) : const [],
                          // 自訂而網址還不行時是佔位圖，不是第一首的封面。
                          firstTrack: _custom
                              ? null
                              : widget.editing?.firstTrack,
                          size: AppLayout.playlistCoverPreview,
                        ),
                        SizedBox(width: spacing.x4),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(t.cover, style: theme.textTheme.titleSmall),
                              Text(
                                _custom ? t.coverCustom : t.coverDefault,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (_custom)
                          TextButton(
                            onPressed: _useDefault,
                            child: Text(t.coverUseDefault),
                          )
                        else
                          TextButton(
                            onPressed: _chooseCustom,
                            child: Text(t.coverChooseCustom),
                          ),
                      ],
                    ),
                    if (_custom) ...[
                      SizedBox(height: spacing.x2),
                      TextField(
                        controller: _coverUrl,
                        focusNode: _coverFocus,
                        keyboardType: TextInputType.url,
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: InputDecoration(
                          labelText: t.coverUrl,
                          errorText: switch (check) {
                            _CoverCheck.empty || _CoverCheck.ok => null,
                            _CoverCheck.invalid => t.coverInvalidUrl,
                            _CoverCheck.notFromSource => t.coverNotFromSource,
                          },
                        ),
                      ),
                    ],
                  ],
                );
              },
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
          listenable: Listenable.merge([_name, _coverUrl]),
          builder: (context, _) => FilledButton(
            onPressed: _valid ? _submit : null,
            child: Text(widget.editing == null ? t.create : t.save),
          ),
        ),
      ],
    );
  }
}
