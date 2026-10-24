import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 播放頁（根 Navigator 上的 route，不在外殼的 `Shortcuts` 之下）請外殼切到佇列目的地：
/// Ctrl+Q 在播放頁開著時，先關播放頁再切過去（ADR 0035 §決定 7）。
///
/// 外殼在 `initState` 把 [handler] 接上（同 `OpenAccounts`）；沒有外殼時什麼都不做。
final openQueueProvider = Provider<OpenQueue>((ref) => OpenQueue());

final class OpenQueue {
  void Function()? handler;

  void call() => handler?.call();
}
