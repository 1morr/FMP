/// 响应式断点定义
class Breakpoints {
  Breakpoints._();

  /// 手机断点 (< 600dp)
  static const double mobile = 600;

  /// 平板断点 (600 - 1200dp)
  static const double tablet = 1200;

  /// 获取布局类型
  static LayoutType getLayoutType(double width) {
    if (width < mobile) return LayoutType.mobile;
    if (width < tablet) return LayoutType.tablet;
    return LayoutType.desktop;
  }

  /// 是否为手机布局
  static bool isMobile(double width) => width < mobile;

  /// 是否为平板布局
  static bool isTablet(double width) => width >= mobile && width < tablet;

  /// 是否为桌面布局
  static bool isDesktop(double width) => width >= tablet;
}

/// 布局类型枚举
enum LayoutType {
  mobile,
  tablet,
  desktop,
}
