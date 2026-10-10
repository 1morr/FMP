import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 系統的檔案對話框（ADR 0009 §決定 6）。目前只有選檔（從檔案安裝插件，ADR 0030
/// §決定 8）；存檔與選資料夾跟著用到它們的 PR 加（design §12.4、§12.5）。實作有
/// Android 與 Windows（`file_picker_dialogs.dart`），由 `platform.dart` 組裝。
abstract interface class FileDialogs {
  /// 讓使用者選一個副檔名是 [extension]（不含點，例如 `js`）的檔案，讀出內容。
  /// 使用者取消時回 `null`。
  Future<PickedFile?> pickFile({required String extension});
}

/// 使用者選的檔案。
@immutable
final class PickedFile {
  const PickedFile({required this.name, required this.bytes});

  /// 檔名（含副檔名，不含路徑）。
  final String name;
  final Uint8List bytes;
}

/// 平台的檔案對話框；平台沒有這個能力時為 `null`。`main()` 以
/// `AppPlatform.fileDialogs` override；沒 override 就讀會拋錯。
final fileDialogsProvider = Provider<FileDialogs?>(
  (ref) => throw UnimplementedError(
    'fileDialogsProvider is overridden by main() with the platform '
    'implementation',
  ),
);
