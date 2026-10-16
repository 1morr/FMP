import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/data/repositories/playlist_repository.dart';
import 'package:fmp/domain/playlist.dart';
import 'package:fmp/domain/track_info.dart';
import 'package:fmp/i18n/strings.g.dart';
import 'package:fmp/library/playlist_service.dart';
import 'package:fmp/plugins/plugin_artwork.dart';
import 'package:fmp/plugins/plugin_registry.dart';
import 'package:fmp/ui/i18n/ui_locale.dart';
import 'package:fmp/ui/library/playlist_cover.dart';
import 'package:fmp/ui/theme/app_layout.dart';
import 'package:fmp/ui/theme/app_tokens.dart';

/// 匯入歌單自動刷新間隔的選項（小時；另有「不啟用」＝空，M4 design §10.5）。
const playlistRefreshIntervalChoices = [1, 6, 12, 24, 48, 72, 168];

/// 歌單對話框填的內容。[artwork] 空＝封面用第一首的。[useRemote] 是匯入歌單按了「使用遠端的」
/// 的欄位（其餘欄位的覆寫旗標由 `PlaylistService.editImported` 依有沒有改過決定）。
/// [refreshIntervalHours] 只有編輯匯入歌單時有意義（空＝不啟用），其他情況是 `null`。
typedef PlaylistInput = ({
  String name,
  String? description,
  List<TrackArtwork> artwork,
  Set<ImportedField> useRemote,
  int? refreshIntervalHours,
});

/// 建立（[editing] 為空）或編輯歌單的對話框（M4 design §10.5）：名稱（必填）、描述、封面。
/// 按「建立」／「儲存」回傳填的內容（名稱去掉空白後不能是空的），取消回 `null`。
///
/// 封面預設是第一首歌的封面；「自訂」照舊版填圖片網址，「使用預設」清回。自訂的網址要屬於
/// 某個已安裝且啟用的插件的允許網域（之後經那個插件的媒體 client 讀，見 [PlaylistCover]），
/// 否則寫明原因、不能送出；宿主不讀任意網址（ADR 0012 §決定 1）。編輯時沒改過的自訂封面
/// 照舊保留，不再檢查（那個插件之後被停用也改得了名稱）。
///
/// 編輯匯入歌單時給 [remote]：已被本機覆寫的欄位（名稱、描述、封面）下面多一顆「使用遠端的」，
/// 按了之後下一次刷新把遠端的值寫回來（design §10.5）；改過的欄位送出時自動算成覆寫。同時多一個
/// 「自動刷新」間隔的選單（[playlistRefreshIntervalChoices] 或不啟用）。
Future<PlaylistInput?> showPlaylistDialog(
  BuildContext context, {
  PlaylistOverview? editing,
  PlaylistRemote? remote,
}) => showDialog<PlaylistInput>(
  context: context,
  builder: (_) => _PlaylistDialog(editing: editing, remote: remote),
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
  const _PlaylistDialog({this.editing, this.remote});

  final PlaylistOverview? editing;
  final PlaylistRemote? remote;

  @override
  ConsumerState<_PlaylistDialog> createState() => _PlaylistDialogState();
}

class _PlaylistDialogState extends ConsumerState<_PlaylistDialog> {
  late final _name = TextEditingController(text: widget.editing?.playlist.name);
  late final _description = TextEditingController(
    text: widget.editing?.playlist.description,
  );

  /// 編輯 Mix 歌單：只有名稱（沒有描述、封面、自動刷新）。
  late final bool _mix = widget.editing?.playlist.kind == PlaylistKind.mix;

  /// 打開時的封面（編輯時是歌單現在的）。
  late final List<TrackArtwork> _initialArtwork =
      widget.editing?.playlist.artwork ?? const [];
  late final _coverUrl = TextEditingController(
    text: _initialArtwork.isEmpty ? null : '${_initialArtwork.first.url}',
  );
  final _coverFocus = FocusNode();

  /// 選了「自訂」。
  late var _custom = _initialArtwork.isNotEmpty;

  /// 自動刷新間隔（小時，空＝不啟用）；只有匯入歌單用得到。
  late int? _refreshInterval = widget.remote?.refreshIntervalHours;

  /// 按了「使用遠端的」的欄位；之後再改那個欄位就取消（改過的值要留）。
  final _useRemote = <ImportedField>{};

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
      useRemote: {..._useRemote},
      refreshIntervalHours: widget.remote == null ? null : _refreshInterval,
    ));
  }

  /// [field] 下面的「使用遠端的」：只有匯入歌單、而且這個欄位被本機覆寫過才有；按了之後改成
  /// 說明下一次刷新會怎樣。
  Widget _remoteRow(ImportedField field, bool overridden) {
    if (widget.remote == null || !overridden) return const SizedBox.shrink();
    final t = ref.read(translationsProvider).library;
    final theme = Theme.of(context);
    if (_useRemote.contains(field)) {
      return Padding(
        padding: EdgeInsets.only(top: AppTokens.of(context).spacing.x1),
        child: Text(
          t.useRemoteHint,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return Align(
      alignment: AlignmentDirectional.centerEnd,
      child: TextButton(
        onPressed: () => setState(() => _useRemote.add(field)),
        child: Text(t.useRemote),
      ),
    );
  }

  /// 改了 [field]：之前按的「使用遠端的」作廢。
  void _edited(ImportedField field) {
    if (_useRemote.contains(field)) setState(() => _useRemote.remove(field));
  }

  void _chooseCustom() {
    _useRemote.remove(ImportedField.artwork);
    setState(() => _custom = true);
    _coverFocus.requestFocus();
  }

  void _useDefault() => setState(() {
    _useRemote.remove(ImportedField.artwork);
    _custom = false;
    _coverUrl.clear();
  });

  String _intervalLabel(Translations t, int? hours) => switch (hours) {
    null => t.library.refreshIntervalOff,
    1 => t.library.refreshEveryHour,
    24 => t.library.refreshEveryDay,
    final h when h % 24 == 0 => t.library.refreshEveryDays(count: h ~/ 24),
    final h => t.library.refreshEveryHours(count: h),
  };

  Widget _intervalField(Translations t) {
    // 目前的值不在選項裡（例如以前存的）時也列出來、依大小排在中間，才選得到它。
    final choices = {
      ...playlistRefreshIntervalChoices,
      ?_refreshInterval,
    }.toList()..sort();
    return DropdownButtonFormField<int?>(
      initialValue: _refreshInterval,
      isExpanded: true,
      decoration: InputDecoration(labelText: t.library.refreshInterval),
      items: [
        DropdownMenuItem(child: Text(_intervalLabel(t, null))),
        for (final hours in choices)
          DropdownMenuItem(value: hours, child: Text(_intervalLabel(t, hours))),
      ],
      onChanged: (hours) => setState(() => _refreshInterval = hours),
    );
  }

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
                onChanged: (_) {
                  _nameTouched = true;
                  _edited(ImportedField.name);
                },
                decoration: InputDecoration(
                  labelText: t.name,
                  errorText: _nameTouched && _name.text.trim().isEmpty
                      ? t.nameRequired
                      : null,
                ),
              ),
            ),
            _remoteRow(
              ImportedField.name,
              widget.remote?.nameOverridden == true,
            ),
            if (!_mix) ...[
              SizedBox(height: spacing.x4),
              TextField(
                controller: _description,
                minLines: 1,
                maxLines: 4,
                onChanged: (_) => _edited(ImportedField.description),
                decoration: InputDecoration(labelText: t.description),
              ),
              _remoteRow(
                ImportedField.description,
                widget.remote?.descriptionOverridden == true,
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
                            artwork: _custom
                                ? (_artwork ?? const [])
                                : const [],
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
                                Text(
                                  t.cover,
                                  style: theme.textTheme.titleSmall,
                                ),
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
                          onChanged: (_) => _edited(ImportedField.artwork),
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
                      _remoteRow(
                        ImportedField.artwork,
                        widget.remote?.artworkOverridden == true,
                      ),
                    ],
                  );
                },
              ),
            ],
            if (widget.remote != null) ...[
              SizedBox(height: spacing.x4),
              _intervalField(ref.watch(translationsProvider)),
            ],
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
