import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import 'package:fmp/platform/files/files.dart';

/// [FileDialogs] 的實作，Android、Windows 與 macOS 共用：各平台的差異都在 `file_picker`
/// 的原生端（Android 走 SAF 的 `ACTION_OPEN_DOCUMENT`，Windows 是系統的開檔對話框）。
final class FilePickerDialogs implements FileDialogs {
  const FilePickerDialogs();

  @override
  Future<PickedFile?> pickFile({
    required String extension,
    int? maxBytes,
  }) async {
    // 副檔名篩選在 Android 是轉成 MIME（`MimeTypeMap`），在 Windows 是對話框的
    // 檔案類型；兩邊都只是篩選，選到的內容由呼叫端照格式驗證。
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: [extension],
    );
    if (file == null) return null;
    // 大小在選檔結果裡時（不必讀檔就知道）先擋，免得把很大的檔讀進記憶體。
    final size = file.lengthSync();
    if (maxBytes != null && size != null && size > maxBytes) {
      throw PickedFileTooLarge(name: file.name, size: size, maxBytes: maxBytes);
    }
    return PickedFile(name: file.name, bytes: await file.readAsBytes());
  }

  @override
  Future<Uri?> saveFile({
    required String name,
    required Uint8List bytes,
    required String mimeType,
  }) => FilePicker.saveFile(fileName: name, bytes: bytes, mimeType: mimeType);

  @override
  Future<String?> pickDirectory() => FilePicker.getDirectoryPath();
}
