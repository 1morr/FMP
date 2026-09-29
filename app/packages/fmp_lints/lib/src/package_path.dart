import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:path/path.dart' as p;

/// 檔案在所屬 package 內的相對路徑，一律以 `/` 分隔，例如 `lib/ui/foo.dart`。
///
/// 規則的允許清單都寫成這種路徑；Windows 的 `\` 在這裡轉掉，規則本身不碰
/// 分隔符。
extension type const PackagePath(String value) {
  /// 目前正在分析的檔案；不在任何 package 內時為 `null`。
  static PackagePath? of(RuleContext context) {
    final file = context.currentUnit?.file;
    final root = context.package?.root;
    if (file == null || root == null) return null;
    return relative(file.path, root.path, file.provider.pathContext);
  }

  /// [filePath] 相對 [rootPath] 的位置；不在 [rootPath] 之下時為 `null`。
  static PackagePath? relative(
    String filePath,
    String rootPath,
    p.Context pathContext,
  ) {
    if (!pathContext.isWithin(rootPath, filePath)) return null;
    return PackagePath(
      pathContext
          .split(pathContext.relative(filePath, from: rootPath))
          .join('/'),
    );
  }

  /// 是否在 [directory]（例如 `lib/ui`，不帶結尾斜線）之內，含子目錄。
  bool isIn(String directory) =>
      value == directory || value.startsWith('$directory/');

  /// 是否在 [directories] 任一個之內。
  bool isInAny(Iterable<String> directories) => directories.any(isIn);

  bool get isInLib => isIn('lib');

  bool get isInTest => isIn('test');

  /// 從這個檔案以相對 URI [relativeUri] 指到的位置。
  ///
  /// 跳出 package 根目錄（含 `/` 開頭的絕對路徑）時為 `null`。
  PackagePath? resolve(String relativeUri) {
    if (relativeUri.startsWith('/')) return null;
    final joined = p.posix.normalize(
      p.posix.join(p.posix.dirname(value), relativeUri),
    );
    if (joined == '..' || joined.startsWith('../')) return null;
    return PackagePath(joined);
  }
}
