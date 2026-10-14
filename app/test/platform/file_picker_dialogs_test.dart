import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/platform/files/file_picker_dialogs.dart';

/// 換掉 `file_picker` 的平台實作：記下收到的篩選、回傳 [file]（`null` 是取消）。
final class _FakePicker extends FilePickerPlatform {
  _FakePicker(this.file);

  final PlatformFile? file;
  FileType? type;
  List<String>? extensions;

  @override
  Future<PlatformFile?> pickFile({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    this.type = type;
    extensions = allowedExtensions;
    return file;
  }
}

/// 換掉 `file_picker` 的選資料夾：回傳 [result]（`null` 是取消）。
final class _FakeDirectoryPicker extends FilePickerPlatform {
  _FakeDirectoryPicker(this.result);

  final String? result;

  @override
  Future<String?> getDirectoryPath({
    String? dialogTitle,
    String? initialDirectory,
    AndroidOptions androidOptions = const AndroidOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async => result;
}

/// 換掉 `file_picker` 的存檔：記下收到的檔名、內容與 MIME，回傳 [result]（`null` 是取消）。
final class _FakeSaver extends FilePickerPlatform {
  _FakeSaver(this.result);

  final Uri? result;
  String? fileName;
  Uint8List? bytes;
  String? mimeType;

  @override
  Future<Uri?> saveFile({
    String? dialogTitle,
    required String fileName,
    required Uint8List bytes,
    String mimeType = 'application/octet-stream',
    String? initialDirectory,
    Function(FilePickerStatus)? onFileSaving,
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    this.fileName = fileName;
    this.bytes = bytes;
    this.mimeType = mimeType;
    return result;
  }
}

/// 只有名稱與內容的檔案；其他成員這裡用不到。
final class _File extends PlatformFile {
  _File(this.name, this.text);

  @override
  final String name;
  final String text;

  @override
  Future<Uint8List> readAsBytes() async =>
      Uint8List.fromList(utf8.encode(text));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late FilePickerPlatform original;
  setUp(() => original = FilePickerPlatform.instance);
  tearDown(() => FilePickerPlatform.instance = original);

  test('asks for the extension and reads the chosen file', () async {
    final fake = _FakePicker(_File('plugin.js', 'export {};'));
    FilePickerPlatform.instance = fake;

    final picked = await const FilePickerDialogs().pickFile(extension: 'js');

    expect(fake.type, FileType.custom);
    expect(fake.extensions, ['js']);
    expect(picked?.name, 'plugin.js');
    expect(utf8.decode(picked!.bytes), 'export {};');
  });

  test('picks a directory and a cancelled dialog is null', () async {
    FilePickerPlatform.instance = _FakeDirectoryPicker(r'C:\plugins');
    expect(await const FilePickerDialogs().pickDirectory(), r'C:\plugins');

    FilePickerPlatform.instance = _FakeDirectoryPicker(null);
    expect(await const FilePickerDialogs().pickDirectory(), isNull);
  });

  test('a cancelled dialog is null', () async {
    FilePickerPlatform.instance = _FakePicker(null);

    expect(await const FilePickerDialogs().pickFile(extension: 'js'), isNull);
  });

  test(
    'saves the bytes under the name and MIME type and returns the place',
    () async {
      final fake = _FakeSaver(Uri.file('/fake/fmp-logs.zip'));
      FilePickerPlatform.instance = fake;

      final saved = await const FilePickerDialogs().saveFile(
        name: 'fmp-logs.zip',
        bytes: Uint8List.fromList([1, 2, 3]),
        mimeType: 'application/zip',
      );

      expect(saved, Uri.file('/fake/fmp-logs.zip'));
      expect(fake.fileName, 'fmp-logs.zip');
      expect(fake.bytes, [1, 2, 3]);
      expect(fake.mimeType, 'application/zip');
    },
  );

  test('a cancelled save dialog is null', () async {
    FilePickerPlatform.instance = _FakeSaver(null);

    expect(
      await const FilePickerDialogs().saveFile(
        name: 'x.zip',
        bytes: Uint8List(0),
        mimeType: 'application/zip',
      ),
      isNull,
    );
  });
}
