import 'package:file_picker/file_picker.dart';

import 'package:fmp/platform/files/files.dart';

/// [FileDialogs] 的實作，Android 與 Windows 共用：兩個平台的差異都在 `file_picker`
/// 的原生端（Android 走 SAF 的 `ACTION_OPEN_DOCUMENT`，Windows 是系統的開檔對話框）。
final class FilePickerDialogs implements FileDialogs {
  const FilePickerDialogs();

  @override
  Future<PickedFile?> pickFile({required String extension}) async {
    // 副檔名篩選在 Android 是轉成 MIME（`MimeTypeMap`），在 Windows 是對話框的
    // 檔案類型；兩邊都只是篩選，選到的內容由呼叫端照格式驗證。
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: [extension],
    );
    if (file == null) return null;
    return PickedFile(name: file.name, bytes: await file.readAsBytes());
  }
}
