import 'package:arsip_berita_app/ui/design.dart';
import 'package:flutter/material.dart';
import '../ui/theme.dart';

class StatsHeader extends StatelessWidget {
  final int total;
  final int thisMonth;
  final int mediaCount;
  const StatsHeader({super.key, required this.total, required this.thisMonth, required this.mediaCount});
  @override
  Widget build(BuildContext context) {
    return Row(children: const [
      Expanded(child: _StatTile(label: 'Total Artikel', icon: Icons.newspaper, color: Colors.indigo, valueKey: 'total')),
      SizedBox(width: Spacing.sm),
      Expanded(child: _StatTile(label: 'Bulan Ini', icon: Icons.calendar_today, color: Colors.blueGrey, valueKey: 'month')),
      SizedBox(width: Spacing.sm),
      Expanded(child: _StatTile(label: 'Media', icon: Icons.apartment, color: Colors.teal, valueKey: 'media')),
    ]);
  }
}

class _StatTile extends StatelessWidget {
  final String label; final IconData icon; final Color color; final String valueKey;
  const _StatTile({required this.label, required this.icon, required this.color, required this.valueKey});
  @override
  Widget build(BuildContext context) {
    final inherited = _StatsInherited.of(context);
    final value = switch (valueKey) {
      'total' => inherited.total,
      'month' => inherited.thisMonth,
      _ => inherited.mediaCount,
    };
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: DS.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: DS.border),
      ),
      padding: const EdgeInsets.all(Spacing.lg),
      child: Row(children: [
        Container(
          width: 44, height: 44,
          decoration: BoxDecoration(color: color.withOpacity(.1), borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: color),
        ),
        const SizedBox(width: Spacing.md),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: isDark ? Colors.white70 : null)),
          Text('$value', style: Theme.of(context).textTheme.titleLarge?.copyWith(color: isDark ? Colors.white : null)),
        ]),
      ]),
    );
  }
}

class StatsHeaderContainer extends InheritedWidget {
  final int total; final int thisMonth; final int mediaCount;
  const StatsHeaderContainer({super.key, required super.child, required this.total, required this.thisMonth, required this.mediaCount});
  @override
  bool updateShouldNotify(covariant StatsHeaderContainer oldWidget) => total != oldWidget.total || thisMonth != oldWidget.thisMonth || mediaCount != oldWidget.mediaCount;
}

class _StatsInherited extends InheritedWidget {
  final int total; final int thisMonth; final int mediaCount;
  const _StatsInherited({required this.total, required this.thisMonth, required this.mediaCount, required super.child});
  static _StatsInherited of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<_StatsInherited>()!;
  @override
  bool updateShouldNotify(covariant _StatsInherited oldWidget) => total != oldWidget.total || thisMonth != oldWidget.thisMonth || mediaCount != oldWidget.mediaCount;
}

