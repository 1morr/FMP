import 'dart:convert';
import 'dart:io';

/// 碰共用裝置的指令帶的環境變數（完整閘門與包裝指令都加）：讓它們順手
/// 叫起來的 adb server 不開 mDNS。platform-tools 37.0.1 的 adb server 會被
/// 區網的 mDNS 封包弄當（brief 事實 K15）。只在 server 啟動時有作用，不影響
/// 已經在跑的 server。
const sharedDeviceEnvironment = {'ADB_MDNS': '0'};

/// 共用裝置鎖（plan §4）：`winpc` 的 `C:\fmp-wt`、iOS 與
/// Android 模擬器、macOS 上的 `com.personal.fmp.dev` 同一時間只給一個
/// worktree 用。
///
/// 鎖是 [file] 上的 OS 檔案鎖（Dart 的 [RandomAccessFile.lock]，POSIX 是
/// fcntl）。持有的行程結束（含 `kill -9`、當掉）時 OS 會放掉它，不會留下
/// 永久的鎖。持有者是誰另外寫在 [holderFile]，等待的一方印出來。
///
/// 可重入：持有者開的行程（例如完整閘門呼叫的 `sync.sh`）用
/// [heldByAncestor] 確認鎖在祖先手上，不再自己拿。完整閘門與包裝指令
/// `tool/device_lock.dart` 都用這把鎖。
///
/// fcntl 鎖屬於整個行程：同一個行程裡另外打開 [file] 再關掉，鎖就會被放掉。
/// 所以 [file] 除了持鎖的 handle 之外不碰，持有者資訊放另一個檔。
class DeviceLock {
  DeviceLock(this.file, {required this.worktree});

  /// [dir] 所在 repo 的鎖，放在 git common dir（所有 worktree 共用的 `.git`）
  /// 底下。
  factory DeviceLock.forRepo(Directory dir) {
    String git(List<String> args) {
      final result = Process.runSync('git', args, workingDirectory: dir.path);
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

  /// 持有者所在的 worktree，寫進持有者資訊。
  final String worktree;

  File get holderFile => File('${file.path}.holder');

  RandomAccessFile? _handle;

  bool get isHeld => _handle != null;

  /// 鎖是否在這個行程的祖先手上：持有者資訊的 pid 是祖先行程，而且鎖確實
  /// 被佔著（持有者被 `kill -9` 時資訊檔會留著）。只看祖先關係，不看環境
  /// 變數，所以偽造不了；持有者死掉後留下的孤兒行程也不算。
  ///
  /// 會打開再關掉 [file]，所以不能在持有這把鎖的行程裡呼叫（fcntl 會放掉鎖）。
  Future<bool> heldByAncestor() async {
    if (isHeld) throw StateError('heldByAncestor() would release this lock');
    final holder = _readHolder()?.pid;
    if (holder == null || !await _isAncestor(holder)) return false;
    final probe = await file.open(mode: FileMode.append);
    try {
      await probe.lock(FileLock.exclusive);
      await probe.unlock();
      return false;
    } on FileSystemException catch (error) {
      if (_heldElsewhere.contains(error.osError?.errorCode)) return true;
      rethrow;
    } finally {
      await probe.close();
    }
  }

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

  /// 沿著父行程往上找 [candidate]（`ps -o ppid=`，macOS 與 Linux 都有）。
  static Future<bool> _isAncestor(int candidate) async {
    var current = pid;
    for (var depth = 0; depth < 64; depth++) {
      final result = await Process.run('ps', ['-o', 'ppid=', '-p', '$current']);
      final parent = int.tryParse('${result.stdout}'.trim());
      if (parent == null || parent <= 1) return false;
      if (parent == candidate) return true;
      current = parent;
    }
    return false;
  }

  String _describeHolder() {
    final holder = _readHolder();
    if (holder == null) {
      return 'an unknown process (no readable ${holderFile.path})';
    }
    final (:worktree, :pid, :started) = holder;
    return 'worktree $worktree, pid $pid, since $started';
  }

  /// 讀不到時回 null：持有者剛拿到鎖、還沒寫完資訊，或資訊檔被手動刪了。
  ({String worktree, int pid, String started})? _readHolder() {
    try {
      final {
        'worktree': String worktree,
        'pid': int pid,
        'started': String started,
      } = jsonDecode(holderFile.readAsStringSync()) as Map<String, dynamic>;
      return (worktree: worktree, pid: pid, started: started);
    } on Object {
      return null;
    }
  }
}
