import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';

/// Riverpod 3 把 `Ref` 改成 sealed class，測試不能再自己實作一份 fake。
/// 官方替代路徑是從一個真的 [ProviderContainer] 取出一個真的 `Ref`，
/// 需要替換相依時交給 `overrides`，而不是覆寫 `read`。
final _refProbeProvider = Provider<Ref>((ref) => ref);

/// 一個真的 `Ref`，外加持有它的 container 以便測試結束時釋放。
///
/// container 必須活得比 `ref` 久 —— 一旦 container 被 dispose，
/// 從它拿到的 `Ref` 就會拋 `UnmountedRefException`。
class TestRefHandle {
  TestRefHandle(this.container, this.ref);

  final ProviderContainer container;
  final Ref ref;

  void dispose() => container.dispose();
}

TestRefHandle createTestRef({List<Override> overrides = const []}) {
  final container = ProviderContainer(overrides: overrides);
  return TestRefHandle(container, container.read(_refProbeProvider));
}
