import 'package:flutter/material.dart';

import 'package:teamcash/core/models/dashboard_models.dart';

class AppBackdrop extends StatelessWidget {
  const AppBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFF8F9FF), Color(0xFFF4F6FF), Color(0xFFF6FCFB)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -120,
            right: -60,
            child: _BackdropOrb(
              size: 280,
              color: const Color(0xFF6678FF),
              opacity: 0.14,
            ),
          ),
          Positioned(
            top: 180,
            left: -90,
            child: _BackdropOrb(
              size: 220,
              color: const Color(0xFF76DCCA),
              opacity: 0.10,
            ),
          ),
          Positioned(
            bottom: -100,
            right: 20,
            child: _BackdropOrb(
              size: 240,
              color: const Color(0xFFE8A9C0),
              opacity: 0.08,
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class MobileAppFrame extends StatelessWidget {
  const MobileAppFrame({
    super.key,
    required this.child,
    this.maxWidth = 430,
    this.maxHeight = 900,
    this.padding = const EdgeInsets.all(10),
  });

  final Widget child;
  final double maxWidth;
  final double maxHeight;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.clamp(320.0, maxWidth).toDouble();
        final availableHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : maxHeight;
        final height = availableHeight.clamp(640.0, maxHeight).toDouble();

        return Center(
          child: Padding(
            padding: padding,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(34),
              child: Container(
                width: width,
                height: height,
                decoration: BoxDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  borderRadius: BorderRadius.circular(34),
                  border: Border.all(color: const Color(0xFFE3E7F6)),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x22424EA5),
                      blurRadius: 44,
                      offset: Offset(0, 24),
                    ),
                  ],
                ),
                child: Stack(
                  children: [
                    Positioned(
                      top: 10,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Container(
                          width: 110,
                          height: 26,
                          decoration: BoxDecoration(
                            color: const Color(0xFF111426),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      top: 20,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 18, 12, 12),
                        child: child,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    required this.child,
    this.padding = const EdgeInsets.all(22),
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: _panelDecoration(),
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.titleLarge),
                      if (subtitle case final subtitleText?) ...[
                        const SizedBox(height: 8),
                        Text(subtitleText, style: theme.textTheme.bodyMedium),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) ...[const SizedBox(width: 12), trailing!],
              ],
            ),
            const SizedBox(height: 20),
            child,
          ],
        ),
      ),
    );
  }
}

class HeroSummaryCard extends StatelessWidget {
  const HeroSummaryCard({
    super.key,
    required this.eyebrow,
    required this.title,
    this.badge,
    this.supporting,
    this.footer,
    this.action,
    this.icon,
  });

  final String eyebrow;
  final String title;
  final String? badge;
  final Widget? supporting;
  final Widget? footer;
  final Widget? action;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF6678FF), Color(0xFF725CFF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(32),
        boxShadow: const [
          BoxShadow(
            color: Color(0x336678FF),
            blurRadius: 32,
            offset: Offset(0, 18),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            top: -28,
            right: -14,
            child: Container(
              width: 146,
              height: 146,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            bottom: -38,
            right: 72,
            child: Container(
              width: 112,
              height: 112,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            eyebrow,
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: Colors.white.withValues(alpha: 0.78),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            title,
                            style: theme.textTheme.displaySmall?.copyWith(
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (badge != null)
                      _HeroBadge(
                        label: badge!,
                        icon: icon ?? Icons.workspace_premium_outlined,
                      ),
                  ],
                ),
                if (supporting != null) ...[
                  const SizedBox(height: 18),
                  supporting!,
                ],
                if (action != null) ...[const SizedBox(height: 22), action!],
                if (footer != null) ...[const SizedBox(height: 16), footer!],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class MetricGrid extends StatelessWidget {
  const MetricGrid({super.key, required this.metrics});

  final List<DashboardMetric> metrics;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 14,
      runSpacing: 14,
      children: metrics
          .map(
            (metric) =>
                SizedBox(width: 220, child: _MetricTile(metric: metric)),
          )
          .toList(),
    );
  }
}

class InfoBanner extends StatelessWidget {
  const InfoBanner({
    super.key,
    required this.title,
    required this.message,
    this.color = const Color(0xFFEEF2FF),
    this.icon = Icons.info_outline,
  });

  final String title;
  final String message;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.75)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.88),
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 20, color: const Color(0xFF4956B8)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(message, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  final String label;
  final Color backgroundColor;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: foregroundColor,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class SurfaceIconButton extends StatelessWidget {
  const SurfaceIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.hasDot = false,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final bool hasDot;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip ?? '',
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Material(
            color: Colors.white.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: onPressed,
              child: SizedBox(
                width: 48,
                height: 48,
                child: Icon(icon, color: const Color(0xFF414C8F)),
              ),
            ),
          ),
          if (hasDot)
            Positioned(
              right: 10,
              top: 10,
              child: Container(
                width: 9,
                height: 9,
                decoration: const BoxDecoration(
                  color: Color(0xFFFF786E),
                  shape: BoxShape.circle,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class QuickActionTile extends StatelessWidget {
  const QuickActionTile({
    super.key,
    required this.icon,
    required this.label,
    required this.tint,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final Color tint;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Ink(
          width: 112,
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
          decoration: _panelDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: tint.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(16),
                ),
                alignment: Alignment.center,
                child: Icon(icon, color: tint),
              ),
              const SizedBox(height: 18),
              Text(label, style: Theme.of(context).textTheme.titleSmall),
            ],
          ),
        ),
      ),
    );
  }
}

class SegmentedChoice<T> extends StatelessWidget {
  const SegmentedChoice({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final T value;
  final List<SegmentedChoiceItem<T>> items;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F5FF),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          for (final item in items)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(item.value),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: item.value == value ? Colors.white : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: item.value == value
                        ? const [
                            BoxShadow(
                              color: Color(0x12414B98),
                              blurRadius: 18,
                              offset: Offset(0, 6),
                            ),
                          ]
                        : null,
                  ),
                  child: Text(
                    item.label,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: item.value == value
                          ? const Color(0xFF4A57A9)
                          : const Color(0xFF8A92B3),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class SegmentedChoiceItem<T> {
  const SegmentedChoiceItem({required this.value, required this.label});

  final T value;
  final String label;
}

class PagerDots extends StatelessWidget {
  const PagerDots({super.key, required this.count, required this.activeIndex});

  final int count;
  final int activeIndex;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (index) {
        final selected = index == activeIndex;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: selected ? 20 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: selected
                ? const Color(0xFF6474FF)
                : const Color(0xFFD7DCF4),
            borderRadius: BorderRadius.circular(999),
          ),
        );
      }),
    );
  }
}

class CompactStatTile extends StatelessWidget {
  const CompactStatTile({
    super.key,
    required this.label,
    required this.value,
    required this.tint,
    required this.icon,
  });

  final String label;
  final String value;
  final Color tint;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 18, color: tint),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF7E86A7),
                  ),
                ),
                const SizedBox(height: 2),
                Text(value, style: Theme.of(context).textTheme.titleSmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

BoxDecoration _panelDecoration() {
  return BoxDecoration(
    color: Colors.white.withValues(alpha: 0.94),
    borderRadius: BorderRadius.circular(28),
    border: Border.all(color: const Color(0xFFE4E8F7)),
    boxShadow: const [
      BoxShadow(
        color: Color(0x15444EA4),
        blurRadius: 28,
        offset: Offset(0, 16),
      ),
    ],
  );
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.metric});

  final DashboardMetric metric;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trend = switch (metric.trendDirection) {
      MetricTrendDirection.up => (
        color: const Color(0xFF1EAF88),
        icon: Icons.trending_up_rounded,
      ),
      MetricTrendDirection.down => (
        color: const Color(0xFFE56874),
        icon: Icons.trending_down_rounded,
      ),
      MetricTrendDirection.neutral => (
        color: const Color(0xFF8189AB),
        icon: Icons.trending_flat_rounded,
      ),
    };

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _panelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            metric.label,
            style: theme.textTheme.labelLarge?.copyWith(
              color: const Color(0xFF7C84A5),
            ),
          ),
          const SizedBox(height: 10),
          Text(metric.value, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(trend.icon, size: 18, color: trend.color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  metric.detail,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: trend.color,
                    fontWeight: FontWeight.w700,
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

class _BackdropOrb extends StatelessWidget {
  const _BackdropOrb({
    required this.size,
    required this.color,
    required this.opacity,
  });

  final double size;
  final Color color;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color.withValues(alpha: opacity),
              color.withValues(alpha: 0),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroBadge extends StatelessWidget {
  const _HeroBadge({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(color: Colors.white),
          ),
        ],
      ),
    );
  }
}
