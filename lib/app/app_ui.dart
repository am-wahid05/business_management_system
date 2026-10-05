import 'package:flutter/material.dart';

import 'app_theme.dart';

class AppSectionHeader extends StatelessWidget {
  const AppSectionHeader({
    required this.title,
    this.subtitle,
    this.action,
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
              ],
            ],
          ),
        ),
        ?action,
      ],
    );
  }
}

class AppPageHeader extends StatelessWidget {
  const AppPageHeader({
    required this.title,
    this.subtitle,
    this.action,
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 560;
          final heading = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.headlineMedium),
              if (subtitle != null) ...[
                const SizedBox(height: 6),
                Text(subtitle!, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ],
          );
          if (action == null) return heading;
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [heading, const SizedBox(height: 14), action!],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: heading),
              const SizedBox(width: 16),
              action!,
            ],
          );
        },
      ),
    );
  }
}

class AppPanel extends StatelessWidget {
  const AppPanel({
    required this.child,
    this.padding = const EdgeInsets.all(20),
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(padding: padding, child: child),
  );
}

class AppKpiCard extends StatelessWidget {
  const AppKpiCard({
    required this.label,
    required this.value,
    required this.icon,
    this.tint,
    super.key,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final color = tint ?? Theme.of(context).colorScheme.primary;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(label, style: Theme.of(context).textTheme.labelLarge),
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              value,
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

class AppStatusPill extends StatelessWidget {
  const AppStatusPill({
    required this.label,
    required this.icon,
    this.color,
    super.key,
  });

  final String label;
  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tone = color ?? Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: tone),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: tone,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    required this.title,
    required this.message,
    this.icon = Icons.inbox_outlined,
    this.action,
    super.key,
  });

  final String title;
  final String message;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Column(
        children: [
          Icon(icon, size: 34, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 10),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    );
  }
}

class AppErrorState extends StatelessWidget {
  const AppErrorState({
    required this.title,
    required this.message,
    this.onRetry,
    super.key,
  });

  final String title;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppPanel(
      child: Column(
        children: [
          Icon(Icons.cloud_off_outlined, size: 34, color: scheme.error),
          const SizedBox(height: 10),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 5),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Try again'),
            ),
          ],
        ],
      ),
    );
  }
}

class AppSkeleton extends StatefulWidget {
  const AppSkeleton({this.width, this.height = 16, this.radius = 8, super.key});

  final double? width;
  final double height;
  final double radius;

  @override
  State<AppSkeleton> createState() => _AppSkeletonState();
}

class _AppSkeletonState extends State<AppSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = Color.lerp(
      scheme.surfaceContainerHighest,
      scheme.primaryContainer,
      0.18,
    )!;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => ShaderMask(
        blendMode: BlendMode.srcATop,
        shaderCallback: (bounds) {
          final start = -1.5 + (_controller.value * 3);
          return LinearGradient(
            begin: Alignment(start, 0),
            end: Alignment(start + 1.1, 0),
            colors: [base, Color.lerp(base, Colors.white, 0.65)!, base],
          ).createShader(bounds);
        },
        child: Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: base,
            borderRadius: BorderRadius.circular(widget.radius),
          ),
        ),
      ),
    );
  }
}

class AppKpiSkeleton extends StatelessWidget {
  const AppKpiSkeleton({super.key});

  @override
  Widget build(BuildContext context) => const AppPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            AppSkeleton(width: 92),
            AppSkeleton(width: 36, height: 36, radius: 10),
          ],
        ),
        SizedBox(height: 20),
        AppSkeleton(width: 110, height: 27),
      ],
    ),
  );
}

class AppTableSkeleton extends StatelessWidget {
  const AppTableSkeleton({this.rows = 5, super.key});

  final int rows;

  @override
  Widget build(BuildContext context) => AppPanel(
    child: Column(
      children: List.generate(
        rows,
        (index) => Padding(
          padding: EdgeInsets.only(bottom: index == rows - 1 ? 0 : 16),
          child: Row(
            children: const [
              Expanded(child: AppSkeleton(height: 18)),
              SizedBox(width: 24),
              AppSkeleton(width: 90, height: 18),
            ],
          ),
        ),
      ),
    ),
  );
}

class AppChartSkeleton extends StatelessWidget {
  const AppChartSkeleton({this.height = 220, super.key});

  final double height;

  @override
  Widget build(BuildContext context) => AppPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AppSkeleton(width: 170, height: 18),
        const SizedBox(height: 22),
        SizedBox(
          height: height,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: const [
              AppSkeleton(width: 24, height: 82, radius: 7),
              AppSkeleton(width: 24, height: 136, radius: 7),
              AppSkeleton(width: 24, height: 104, radius: 7),
              AppSkeleton(width: 24, height: 174, radius: 7),
              AppSkeleton(width: 24, height: 122, radius: 7),
              AppSkeleton(width: 24, height: 154, radius: 7),
            ],
          ),
        ),
      ],
    ),
  );
}

class AppProfileSkeleton extends StatelessWidget {
  const AppProfileSkeleton({super.key});

  @override
  Widget build(BuildContext context) => const AppPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            AppSkeleton(width: 56, height: 56, radius: 28),
            SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppSkeleton(width: 170, height: 18),
                  SizedBox(height: 10),
                  AppSkeleton(width: 230, height: 14),
                ],
              ),
            ),
          ],
        ),
        SizedBox(height: 22),
        AppSkeleton(height: 52),
        SizedBox(height: 12),
        AppSkeleton(height: 52),
      ],
    ),
  );
}

class AppLoadingList extends StatelessWidget {
  const AppLoadingList({this.rows = 5, super.key});

  final int rows;

  @override
  Widget build(BuildContext context) => Column(
    children: List.generate(
      rows,
      (index) => Padding(
        padding: EdgeInsets.only(bottom: index == rows - 1 ? 0 : 10),
        child: AppPanel(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: const [
              AppSkeleton(width: 42, height: 42, radius: 12),
              SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppSkeleton(width: 180),
                    SizedBox(height: 9),
                    AppSkeleton(width: 260, height: 13),
                  ],
                ),
              ),
              SizedBox(width: 20),
              AppSkeleton(width: 76),
            ],
          ),
        ),
      ),
    ),
  );
}

class AppGridSkeleton extends StatelessWidget {
  const AppGridSkeleton({this.rows = 7, this.columns = 5, super.key});

  final int rows;
  final int columns;

  @override
  Widget build(BuildContext context) => AppPanel(
    padding: EdgeInsets.zero,
    child: Column(
      children: [
        Row(
          children: List.generate(
            columns,
            (index) => Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: AppSkeleton(height: 16),
              ),
            ),
          ),
        ),
        const Divider(height: 1),
        ...List.generate(
          rows,
          (row) => Column(
            children: [
              Row(
                children: List.generate(
                  columns,
                  (column) => Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: AppSkeleton(
                        width: column == 0 ? 110 : 76,
                        height: 18,
                      ),
                    ),
                  ),
                ),
              ),
              if (row != rows - 1) const Divider(height: 1),
            ],
          ),
        ),
      ],
    ),
  );
}

/// The split layout shared by every screen in the sign-in / sign-up family.
///
/// A desktop window gets a calm brand panel beside the form. A narrow window
/// drops the panel entirely and centres a width-capped, scrollable form, so a
/// small window never shows a squeezed two-column layout, a clipped form, or a
/// tall branding block pushing the submit button below the fold.
///
/// Nothing here is a card on purpose. Wrapping a form in a floating card adds
/// a border and a shadow around something that is already a distinct, centred
/// column, which is what makes a login screen read as a template.
class AppAuthBrandPanel extends StatelessWidget {
  const AppAuthBrandPanel({
    required this.child,
    this.companyName,
    this.supportingText,
    super.key,
  });

  /// The form, or any other content, shown on the right (or alone).
  final Widget child;

  /// Shown as the brand panel heading when there is one.
  final String? companyName;

  /// A short line under the brand heading.
  final String? supportingText;

  /// The width below which the brand panel is dropped.
  static const double _twoColumnBreakpoint = 880;

  /// The comfortable width for a single auth form.
  static const double _formMaxWidth = 430;

  @override
  Widget build(BuildContext context) {
    final name = companyName?.trim();
    final hasName = name != null && name.isNotEmpty;
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= _twoColumnBreakpoint;
        // On a narrow window the brand panel is dropped, so the company name
        // moves above the form instead. The user must always be able to see
        // which company they are signing in to, at any window size, and it
        // must appear exactly once so it is never read as two things.
        final area = _FormArea(
          wide: wide,
          child: !wide && hasName
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _CompanyIdentityChip(name: name),
                    const SizedBox(height: 18),
                    child,
                  ],
                )
              : child,
        );
        if (!wide) return area;
        return Row(
          children: [
            Expanded(flex: 5, child: _brandPanel(context)),
            Expanded(flex: 6, child: area),
          ],
        );
      },
    );
  }

  Widget _brandPanel(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final name = companyName?.trim();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 56, vertical: 48),
      // A single quiet wash rather than a two-stop gradient, which reads as
      // decoration without ever competing with the form.
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [scheme.primary, AppTheme.primaryDark],
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(15),
            ),
            child: const Icon(
              Icons.grass_outlined,
              color: Colors.white,
              size: 30,
            ),
          ),
          const SizedBox(height: 30),
          Text(
            (name == null || name.isEmpty)
                ? 'Business Management System'
                : name,
            style: Theme.of(context).textTheme.displaySmall
                ?.copyWith(color: Colors.white, height: 1.15),
          ),
          const SizedBox(height: 14),
          Text(
            supportingText ?? 'Suppliers, receiving, products, reports and company operations in one workspace.',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Colors.white.withValues(alpha: 0.82),
              height: 1.55,
            ),
          ),
          const SizedBox(height: 34),
          const Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _BrandPoint(icon: Icons.people_outline, label: 'Suppliers'),
              _BrandPoint(icon: Icons.scale_outlined, label: 'Receiving'),
              _BrandPoint(icon: Icons.insights_outlined, label: 'Reports'),
            ],
          ),
          const SizedBox(height: 34),
          Row(
            children: [
              Icon(
                Icons.verified_user_outlined,
                size: 17,
                color: Colors.white.withValues(alpha: 0.8),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Company-scoped and secure',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withValues(alpha: 0.8),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BrandPoint extends StatelessWidget {
  const _BrandPoint({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: Colors.white.withValues(alpha: 0.9)),
          const SizedBox(width: 7),
          Text(
            label,
            style: const TextStyle(
              fontSize: 13.5,
              color: Colors.white,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

/// The company name shown above an auth form when the brand panel is not on
/// screen.
///
/// Keeps the signed-in-to company visible on a narrow window without inventing
/// a second brand panel, and without ever naming a default company that the
/// user has not actually selected.
class _CompanyIdentityChip extends StatelessWidget {
  const _CompanyIdentityChip({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: scheme.primaryContainer,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(Icons.grass_outlined, size: 20, color: scheme.primary),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

/// Centres, width-caps and scrolls the auth form so it behaves the same on a
/// phone, a half-width window and a 2560px monitor.
class _FormArea extends StatelessWidget {
  const _FormArea({required this.wide, required this.child});

  final bool wide;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: wide ? 48 : 24,
            vertical: wide ? 40 : 28,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppAuthBrandPanel._formMaxWidth,
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// The heading block every auth form starts with.
///
/// Shared so Login, Sign Up, Forgot Password and the password screens cannot
/// drift into different title sizes and different vertical rhythms.
class AppAuthHeader extends StatelessWidget {
  const AppAuthHeader({
    required this.title,
    required this.subtitle,
    this.showMark = true,
    super.key,
  });

  final String title;
  final String subtitle;

  /// Whether to show the product mark above the title.
  ///
  /// Set false where the brand panel already shows the identity, so the same
  /// name is not printed twice on one screen.
  final bool showMark;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showMark) ...[
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(Icons.grass_outlined, color: scheme.primary, size: 25),
          ),
          const SizedBox(height: 18),
        ],
        Text(
          title,
          style: Theme.of(context).textTheme.headlineMedium
              ?.copyWith(height: 1.2),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.5),
        ),
      ],
    );
  }
}

/// An inline, readable error panel.
///
/// Replaces the bare red [Text] an error used to be rendered as: the message is
/// now in a tinted panel with an icon, so it is legible, cannot be mistaken for
/// a field's own validation, and never shows a raw exception.
class AppAuthError extends StatelessWidget {
  const AppAuthError(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.error.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 19, color: scheme.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.45,
                color: scheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AppBarChart extends StatelessWidget {
  const AppBarChart({required this.items, this.valueSuffix = ' kg', super.key});

  final List<AppChartItem> items;
  final String valueSuffix;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty)
      return const AppEmptyState(
        title: 'No data available',
        message: 'There are no records for this period.',
        icon: Icons.bar_chart_outlined,
      );
    final maximum = items
        .map((item) => item.value)
        .reduce((left, right) => left > right ? left : right);
    final safeMaximum = maximum <= 0 ? 1.0 : maximum;
    return Column(
      children: items.map((item) {
        final fraction = (item.value / safeMaximum).clamp(0.0, 1.0);
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            children: [
              SizedBox(
                width: 76,
                child: Text(
                  item.label,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    minHeight: 10,
                    value: fraction,
                    backgroundColor: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 100,
                child: Text(
                  '${item.value.toStringAsFixed(item.decimals)}$valueSuffix',
                  textAlign: TextAlign.right,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class AppLineChart extends StatelessWidget {
  const AppLineChart({required this.items, this.height = 220, super.key});

  final List<AppChartItem> items;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const AppEmptyState(
        title: 'No trend data',
        message: 'Receiving activity will appear here when records exist.',
        icon: Icons.show_chart_outlined,
      );
    }
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _AppLineChartPainter(
          items: items,
          axisColor: Theme.of(context).colorScheme.outline,
          lineColor: Theme.of(context).colorScheme.primary,
          labelColor: Theme.of(context).colorScheme.onSurfaceVariant,
          textStyle: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    );
  }
}

class _AppLineChartPainter extends CustomPainter {
  _AppLineChartPainter({
    required this.items,
    required this.axisColor,
    required this.lineColor,
    required this.labelColor,
    required this.textStyle,
  });

  final List<AppChartItem> items;
  final Color axisColor;
  final Color lineColor;
  final Color labelColor;
  final TextStyle? textStyle;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 8.0;
    const right = 8.0;
    const top = 12.0;
    const bottom = 30.0;
    final chart = Rect.fromLTRB(
      left,
      top,
      size.width - right,
      size.height - bottom,
    );
    final maximum = items.fold<double>(
      0,
      (value, item) => value > item.value ? value : item.value,
    );
    final safeMaximum = maximum <= 0 ? 1.0 : maximum;
    final gridPaint = Paint()
      ..color = axisColor.withValues(alpha: 0.35)
      ..strokeWidth = 1;
    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fillPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          lineColor.withValues(alpha: 0.22),
          lineColor.withValues(alpha: 0.01),
        ],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(chart)
      ..style = PaintingStyle.fill;

    for (var index = 0; index < 4; index++) {
      final y = chart.top + (chart.height * index / 3);
      canvas.drawLine(Offset(chart.left, y), Offset(chart.right, y), gridPaint);
    }

    final points = <Offset>[];
    for (var index = 0; index < items.length; index++) {
      final x = items.length == 1
          ? chart.center.dx
          : chart.left + (chart.width * index / (items.length - 1));
      final y =
          chart.bottom - ((items[index].value / safeMaximum) * chart.height);
      points.add(Offset(x, y.clamp(chart.top, chart.bottom).toDouble()));
    }
    if (points.isEmpty) return;
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var index = 1; index < points.length; index++) {
      path.lineTo(points[index].dx, points[index].dy);
    }
    final area = Path.from(path)
      ..lineTo(points.last.dx, chart.bottom)
      ..lineTo(points.first.dx, chart.bottom)
      ..close();
    canvas.drawPath(area, fillPaint);
    canvas.drawPath(path, linePaint);

    final dotPaint = Paint()..color = lineColor;
    for (var index = 0; index < points.length; index++) {
      canvas.drawCircle(points[index], 5, Paint()..color = Colors.white);
      canvas.drawCircle(points[index], 3, dotPaint);
      _paintLabel(
        canvas,
        items[index].label,
        points[index].dx,
        chart.bottom + 8,
        size.width,
      );
    }
  }

  void _paintLabel(
    Canvas canvas,
    String label,
    double x,
    double y,
    double width,
  ) {
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: textStyle?.copyWith(color: labelColor),
      ),
      maxLines: 1,
      ellipsis: 'â€¦',
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 72);
    final left = (x - painter.width / 2)
        .clamp(0.0, width - painter.width)
        .toDouble();
    painter.paint(canvas, Offset(left, y));
  }

  @override
  bool shouldRepaint(covariant _AppLineChartPainter oldDelegate) =>
      oldDelegate.items != items || oldDelegate.lineColor != lineColor;
}

class AppChartItem {
  const AppChartItem(this.label, this.value, {this.decimals = 1});

  final String label;
  final double value;
  final int decimals;
}
