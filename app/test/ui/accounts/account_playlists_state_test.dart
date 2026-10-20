import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/core_providers.dart';
import 'package:fmp/core/logging/log.dart';
import 'package:fmp/core/logging/log_record.dart';
import 'package:fmp/core/redaction/redactor.dart';
import 'package:fmp/plugins/plugin_registry.dart';
import 'package:fmp/plugins/source_dto.dart';
import 'package:fmp/ui/accounts/account_playlists_state.dart';

import '../../playback/fake_source_plugin.dart';
import '../../support/pump_until.dart';

// 帳號歌單的讀取（M4 PR 13）：離開頁面（provider 釋放）之後不再抓剩下的頁。

LibraryPlaylistPage _page(int n, {String? cursor}) => LibraryPlaylistPage(
  playlists: [
    LibraryPlaylist(playlistId: 'p$n', title: 'List $n', writable: false),
  ],
  cursor: cursor,
);

void main() {
  test('stops asking for pages once the provider is disposed', () async {
    final plugin = FakeSourcePlugin((_) => const [], libraryRead: true);
    final first = Completer<LibraryPlaylistPage>();
    plugin.onLibraryPlaylists = (query) =>
        query.cursor == null ? first.future : _page(2);
    final container = ProviderContainer(
      overrides: [
        logProvider.overrideWithValue(
          Log(redactor: Redactor(), minimumLevel: LogLevel.warning),
        ),
        pluginRegistryProvider.overrideWithBuild(
          (ref, notifier) => {plugin.manifest.id: plugin},
        ),
      ],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(
      accountPlaylistsProvider(plugin.manifest.id),
      (_, _) {},
    );
    await pumpUntil(() => plugin.libraryPlaylistQueries.length == 1);

    // 第一頁回來前離開頁面。
    subscription.close();
    await settle();
    first.complete(_page(1, cursor: 'next'));
    await settle();

    expect(plugin.libraryPlaylistQueries, hasLength(1));
  });

  test('a page that stays open reads every page', () async {
    final plugin = FakeSourcePlugin((_) => const [], libraryRead: true);
    plugin.onLibraryPlaylists = (query) =>
        query.cursor == null ? _page(1, cursor: 'next') : _page(2);
    final container = ProviderContainer(
      overrides: [
        logProvider.overrideWithValue(
          Log(redactor: Redactor(), minimumLevel: LogLevel.warning),
        ),
        pluginRegistryProvider.overrideWithBuild(
          (ref, notifier) => {plugin.manifest.id: plugin},
        ),
      ],
    );
    addTearDown(container.dispose);

    final all = await container.read(
      accountPlaylistsProvider(plugin.manifest.id).future,
    );

    expect([for (final p in all) p.playlistId], ['p1', 'p2']);
  });
}
