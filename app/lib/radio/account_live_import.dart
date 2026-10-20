import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fmp/core/core_providers.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/plugins/manifest/plugin_manifest.dart';
import 'package:fmp/plugins/plugin_registry.dart';
import 'package:fmp/radio/radio_service.dart';

/// [AccountLiveImporter.importFromAccount] 的結果：新加進電台清單的，與本來就在清單的房間數。
@immutable
final class AccountLiveImport {
  const AccountLiveImport({required this.added, required this.existing});

  final int added;
  final int existing;
}

final accountLiveImporterProvider = Provider<AccountLiveImporter>(
  AccountLiveImporter.new,
);

/// 從帳號匯入電台（M4 design §7.4、ADR 0032 §決定 3）：把登入帳號在平台上關注的直播間
/// （`libraryLiveRooms`）加進電台清單。
final class AccountLiveImporter {
  AccountLiveImporter(this._ref);

  final Ref _ref;

  /// 呼叫 [pluginId] 的 `libraryLiveRooms`，逐一寫進電台清單（同 `RadioService.addRoom`：用
  /// `LiveRoom` 自己的資料，不另外查 `liveStatus`）。已在清單的房間不改動、只計數。
  ///
  /// 插件不在已啟用的清單裡、沒宣告 `live` 或沒匯出 `libraryLiveRooms` 是 [Unsupported]；
  /// 沒登入是 `AuthRequired`。失敗一律丟 `AppError`；寫到一半失敗時，已寫入的房間留著
  /// （再匯入一次會算成「已在清單」）。
  Future<AccountLiveImport> importFromAccount(String pluginId) async {
    try {
      final plugins = await _ref.read(pluginRegistryProvider.future);
      final plugin = plugins[pluginId];
      if (plugin == null ||
          !plugin.manifest.capabilities.contains(PluginCapability.live) ||
          !plugin.exportsLibraryLiveRooms) {
        throw Unsupported(
          pluginId: pluginId,
          cause: StateError('The source cannot list live rooms of the account'),
          stackTrace: StackTrace.current,
        );
      }
      final rooms = (await plugin.libraryLiveRooms()).rooms;
      final radio = _ref.read(radioServiceProvider);
      var added = 0;
      for (final room in rooms) {
        switch (await radio.addRoom(pluginId, room)) {
          case AddRadioResult.added:
            added++;
          case AddRadioResult.alreadyAdded:
            break;
          case AddRadioResult.unrecognizedUrl:
            // addRoom 不會回這一個（只有網址新增會）。
            throw StateError('addRoom returned unrecognizedUrl');
        }
      }
      final result = AccountLiveImport(
        added: added,
        existing: rooms.length - added,
      );
      // 房間名稱不進 log。
      _ref
          .read(logProvider)
          .info(
            'Imported live rooms from the account',
            tag: 'radio',
            fields: {
              'pluginId': pluginId,
              'added': result.added,
              'existing': result.existing,
            },
          );
      return result;
    } on Object catch (error, stackTrace) {
      Error.throwWithStackTrace(
        AppError.wrap(error, stackTrace, pluginId: pluginId),
        stackTrace,
      );
    }
  }
}
