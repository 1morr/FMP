import 'dart:convert';
import 'dart:io';

/// 完整版閘門的共用裝置鎖（plan §4）：`winpc` 的 `C:\fmp-wt`、iOS 與
/// Android 模擬器、macOS 上的 `com.personal.fmp.dev` 同一時間只給一個
/// worktree 用。
///
/// 鎖是 [file] 上的 OS 檔案鎖（Dart 的 [RandomAccessFile.lock]，POSIX 是
/// fcntl）。持有的行程結束（含 `kill -9`、當掉）時 OS 會放掉它，不會留下
/// 永久的鎖。持有者是誰另外寫在 [holderFile]，等待的一方印出來。
///
/// fcntl 鎖屬於整個行程：同一個行程裡另外打開 [file] 再關掉，鎖就會被放掉。
/// 所以 [file] 除了持鎖的 handle 之外不碰，持有者資訊放另一個檔。
class DeviceLock {
  DeviceLock(this.file, {required this.worktree});

  /// 鎖放在 git common dir（所有 worktree 共用的 `.git`）底下。
  factory DeviceLock.forRepo(Directory app) {
    String git(List<String> args) {
      final result = Process.runSync('git', args, workingDirectory: app.path);
      if (result.exitCode != 0) {
        throw ProcessException(
          'git',
          args,
          '${result.stderr}',
          result.exitCode,
        );
      }
      return (result.stdout as String).trim();
    }

    final common = git([
      'rev-parse',
      '--path-format=absolute',
      '--git-common-dir',
    ]);
    return DeviceLock(
      File('$common/$fileName'),
      worktree: git(['rev-parse', '--show-toplevel']),
    );
  }

  static const fileName = 'fmp-device.lock';

  /// 非阻塞上鎖時「別人持有」的 errno：macOS 的 EAGAIN（35）；Linux 的
  /// EAGAIN（11）與 EACCES（13）。其他錯誤照常拋出。
  static const _heldElsewhere = {35, 11, 13};

  final File file;

  /// 這個閘門所在的 worktree，寫進持有者資訊。
  final String worktree;

  File get holderFile => File('${file.path}.holder');

  RandomAccessFile? _handle;

  bool get isHeld => _handle != null;

  /// 取得鎖；別人持有時先在 [out] 印出持有者，再等到它放掉。
  Future<void> acquire(StringSink out) async {
    if (_handle != null) return;
    final handle = await file.open(mode: FileMode.append);
    try {
      await handle.lock(FileLock.exclusive);
    } on FileSystemException catch (error) {
      if (!_heldElsewhere.contains(error.osError?.errorCode)) {
        await handle.close();
        rethrow;
      }
      out.writeln(
        'Waiting for the shared-device lock ${file.path}, '
        'held by ${_describeHolder()}',
      );
      await handle.lock(FileLock.blockingExclusive);
    }
    _handle = handle;
    holderFile.writeAsStringSync(
      jsonEncode({
        'worktree': worktree,
        'pid': pid,
        'started': DateTime.now().toIso8601String(),
      }),
    );
    out.writeln('Holding the shared-device lock ${file.path}');
  }

  Future<void> release() async {
    final handle = _handle;
    if (handle == null) return;
    _handle = null;
    if (holderFile.existsSync()) holderFile.deleteSync();
    await handle.unlock();
    await handle.close();
  }

  String _describeHolder() {
    try {
      final {
        'worktree': String worktree,
        'pid': int pid,
        'started': String started,
      } = jsonDecode(holderFile.readAsStringSync()) as Map<String, dynamic>;
      return 'worktree $worktree, pid $pid, since $started';
    } on Object {
      // 持有者剛拿到鎖、還沒寫完資訊，或資訊檔被手動刪了。
      return 'an unknown process (no readable ${holderFile.path})';
    }
  }
}
