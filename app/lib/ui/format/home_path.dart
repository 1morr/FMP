/// [path] 在家目錄 [home] 底下時把那一段換成 `~`（M3 design §12.4：畫面與截圖不帶使用者
/// 名稱）。比對不分大小寫、`/` 與 `\` 都算分隔：家目錄只有 Windows 有，它的路徑不分大小寫。
/// 只比對整段目錄名稱（`C:\Users\a` 不吃掉 `C:\Users\ab\…` 的前綴）。
String homeRelativePath(String path, String? home) {
  if (home == null) return path;
  final base = home.replaceFirst(RegExp(r'[\\/]+$'), '');
  if (base.isEmpty || path.length < base.length) return path;
  if (path.substring(0, base.length).toLowerCase() != base.toLowerCase()) {
    return path;
  }
  final rest = path.substring(base.length);
  if (rest.isEmpty) return '~';
  return rest.startsWith('/') || rest.startsWith(r'\') ? '~$rest' : path;
}
