import 'package:flutter/material.dart';

class AppSectionHeader extends StatelessWidget {
  const AppSectionHeader({required this.title, this.subtitle, this.action, super.key});

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

class AppKpiCard extends StatelessWidget {
  const AppKpiCard({required this.label, required this.value, required this.icon, this.tint, super.key});

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
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(label, style: Theme.of(context).textTheme.labelLarge),
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, color: color, size: 20),
              ),
            ]),
            const SizedBox(height: 18),
            Text(value, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

class AppStatusPill extends StatelessWidget {
  const AppStatusPill({required this.label, required this.icon, this.color, super.key});

  final String label;
  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tone = color ?? Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: tone.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 14, color: tone), const SizedBox(width: 6), Text(label, style: TextStyle(color: tone, fontWeight: FontWeight.w600, fontSize: 12))]),
    );
  }
}

class AppEmptyState extends StatelessWidget {
  const AppEmptyState({required this.title, required this.message, this.icon = Icons.inbox_outlined, super.key});

  final String title;
  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Column(children: [
        Icon(icon, size: 34, color: Theme.of(context).colorScheme.outline),
        const SizedBox(height: 10),
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(message, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
      ]),
    );
  }
}

class AppBarChart extends StatelessWidget {
  const AppBarChart({required this.items, this.valueSuffix = ' kg', super.key});

  final List<AppChartItem> items;
  final String valueSuffix;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const AppEmptyState(title: 'No data available', message: 'There are no records for this period.', icon: Icons.bar_chart_outlined);
    final maximum = items.map((item) => item.value).reduce((left, right) => left > right ? left : right);
    final safeMaximum = maximum <= 0 ? 1.0 : maximum;
    return Column(
      children: items.map((item) {
        final fraction = (item.value / safeMaximum).clamp(0.0, 1.0);
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(children: [
            SizedBox(width: 76, child: Text(item.label, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall)),
            Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(minHeight: 10, value: fraction, backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest))),
            const SizedBox(width: 12),
            SizedBox(width: 100, child: Text('${item.value.toStringAsFixed(item.decimals)}$valueSuffix', textAlign: TextAlign.right, style: Theme.of(context).textTheme.labelLarge)),
          ]),
        );
      }).toList(),
    );
  }
}

class AppChartItem {
  const AppChartItem(this.label, this.value, {this.decimals = 1});

  final String label;
  final double value;
  final int decimals;
}
