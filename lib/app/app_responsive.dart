import 'package:flutter/widgets.dart';

/// The application's responsive breakpoints, in one place.
///
/// Every adaptive layout in the app reads its thresholds from here rather than
/// testing raw numbers inline. Two things follow from that: a layout decision is
/// made on the width the widget actually has, not on the device or platform it
/// happens to be running on (so a narrow Windows window is treated exactly like
/// a phone, which is the behaviour that keeps resizing smooth), and changing the
/// breakpoints later updates every screen at once.
///
/// The names describe the *available width*, not the device.
abstract final class AppBreakpoints {
  /// Below this, a layout must be a single column with no fixed side panels.
  static const double compact = 600;

  /// At or above this, two columns and a persistent navigation rail fit.
  static const double medium = 900;

  /// At or above this, three or more dashboard columns are comfortable.
  static const double expanded = 1240;

  /// The narrowest width at which a persistent application sidebar is used.
  ///
  /// This is deliberately lower than [expanded]. A 1366x768 Windows window -
  /// one of the most common office laptops - reports roughly 1350px of client
  /// width, which sits just under [expanded]. Keying the sidebar to [expanded]
  /// therefore made the navigation appear and disappear as the window was
  /// resized or the taskbar moved, which is exactly the "the sidebar
  /// disappeared" behaviour a shell must never have. At 1100px a collapsed
  /// 76px sidebar still leaves over 1000px of content, which is comfortable.
  static const double sidebar = 1100;

  /// The comfortable reading width for forms and prose.
  ///
  /// A form that stretches across a 2560px monitor is hard to read and easy to
  /// get wrong, so long single-column content is centred and capped here.
  static const double formMaxWidth = 560;

  /// The comfortable width for wide data content such as tables and charts.
  static const double contentMaxWidth = 1400;
}

/// Which responsive band a given width falls into.
enum AppWindowSize {
  /// Phones, and a small or half-width Windows window.
  compact,

  /// Tablets, and a normal laptop window.
  medium,

  /// Large monitors.
  expanded;

  /// The band for a specific available width.
  static AppWindowSize of(double width) {
    if (width >= AppBreakpoints.expanded) return AppWindowSize.expanded;
    if (width >= AppBreakpoints.medium) return AppWindowSize.medium;
    return AppWindowSize.compact;
  }

  /// True when the layout has room for more than one column.
  bool get isMultiColumn => this != AppWindowSize.compact;

  /// True when a persistent side navigation is affordable.
  ///
  /// Below this the app uses a drawer instead, because a rail beside a 500px
  /// window would leave the content too narrow to be usable.
  bool get hasSideNavigation => this != AppWindowSize.compact;

  /// How many columns a responsive card grid should use.
  ///
  /// Derived from the band so a grid never has to restate the numbers.
  int gridColumns(int minTileWidth) {
    if (minTileWidth <= 0) return 1;
    switch (this) {
      case AppWindowSize.compact:
        return 1;
      case AppWindowSize.medium:
        return 2;
      case AppWindowSize.expanded:
        return 3;
    }
  }
}

/// Gives a widget the width-based band and the horizontal padding to match it.
class AppResponsive extends StatelessWidget {
  const AppResponsive({
    required this.builder,
    this.maxWidth = AppBreakpoints.contentMaxWidth,
    this.padding,
    this.verticalPadding,
    this.centre = true,
    super.key,
  });

  /// Builds the content for a known width and band.
  final Widget Function(BuildContext context, AppWindowSize size) builder;

  /// The width the content is capped at.
  final double maxWidth;

  /// Extra padding added to the default responsive padding.
  final EdgeInsetsGeometry? padding;

  /// Overrides the default vertical padding.
  final double? verticalPadding;

  /// Whether the content is centred inside [maxWidth].
  ///
  /// True for forms and prose. False for things that should use the full width,
  /// such as a wide data table.
  final bool centre;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = AppWindowSize.of(constraints.maxWidth);
        final gutter = switch (size) {
          AppWindowSize.compact => 16.0,
          AppWindowSize.medium => 24.0,
          AppWindowSize.expanded => 28.0,
        };
        final vertical = verticalPadding ?? gutter;
        final horizontal = EdgeInsets.symmetric(
          horizontal: gutter,
          vertical: vertical,
        );
        final content = Padding(
          padding: padding == null ? horizontal : horizontal.add(padding!),
          child: builder(context, size),
        );
        if (!centre) return content;
        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: content,
          ),
        );
      },
    );
  }
}
