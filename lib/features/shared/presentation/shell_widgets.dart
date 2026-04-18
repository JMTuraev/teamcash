import 'package:flutter/material.dart';

import 'package:teamcash/app/theme/teamcash_icons.dart';
import 'package:teamcash/core/models/dashboard_models.dart';

class AppBackdrop extends StatelessWidget {
  const AppBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFF3F5EF), Color(0xFFEAF1EA), Color(0xFFF7F3EC)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -120,
            right: -10,
            child: _BackdropOrb(
              size: 320,
              color: const Color(0xFF1F5EFF),
              opacity: 0.12,
            ),
          ),
          Positioned(
            top: 150,
            left: -70,
            child: _BackdropOrb(
              size: 250,
              color: const Color(0xFF26B68A),
              opacity: 0.12,
            ),
          ),
          Positioned(
            bottom: -120,
            right: 12,
            child: _BackdropOrb(
              size: 280,
              color: const Color(0xFFFF9E69),
              opacity: 0.10,
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: _BackdropGridPainter()),
            ),
          ),
          Positioned(
            top: 84,
            right: -30,
            child: Transform.rotate(
              angle: -0.22,
              child: Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(48),
                  border: Border.all(
                    color: Color(0xFFFFFFFF).withValues(alpha: 0.42),
                  ),
                ),
              ),
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
            child: Container(
              width: width,
              height: height,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFDFCF8), Color(0xFFF0F5EC)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(38),
                border: Border.all(
                  color: const Color(0xFFFFFFFF).withValues(alpha: 0.8),
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x2A16345A),
                    blurRadius: 54,
                    offset: Offset(0, 28),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(34),
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    borderRadius: BorderRadius.circular(34),
                    border: Border.all(color: const Color(0xFFE1E7D9)),
                  ),
                  child: Stack(
                    children: [
                      Positioned(
                        top: -120,
                        left: -80,
                        child: _BackdropOrb(
                          size: 220,
                          color: const Color(0xFF1F5EFF),
                          opacity: 0.08,
                        ),
                      ),
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                          child: Row(
                            children: [
                              Text(
                                '9:41',
                                style: Theme.of(context).textTheme.labelLarge
                                    ?.copyWith(
                                      fontSize: 12,
                                      color: const Color(0xFF4E5B69),
                                    ),
                              ),
                              const Spacer(),
                              Container(
                                width: 74,
                                height: 24,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF142033),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                              ),
                              const Spacer(),
                              const Icon(
                                TeamCashIcons.signal,
                                size: 14,
                                color: Color(0xFF4E5B69),
                              ),
                              const SizedBox(width: 6),
                              const Icon(
                                TeamCashIcons.wifi,
                                size: 14,
                                color: Color(0xFF4E5B69),
                              ),
                              const SizedBox(width: 6),
                              const Icon(
                                TeamCashIcons.battery,
                                size: 16,
                                color: Color(0xFF4E5B69),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Positioned.fill(
                        top: 34,
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
          colors: [Color(0xFF163E9E), Color(0xFF1F5EFF), Color(0xFF26B68A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(32),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33163E9E),
            blurRadius: 36,
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
                color: Colors.white.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            left: 22,
            right: 22,
            top: 18,
            child: Container(
              height: 1,
              color: Colors.white.withValues(alpha: 0.14),
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
                        icon: icon ?? TeamCashIcons.premium,
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
    this.icon = TeamCashIcons.info,
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
        gradient: LinearGradient(
          colors: [
            color.withValues(alpha: 0.94),
            Colors.white.withValues(alpha: 0.86),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.75)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x141C3458),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
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
            child: Icon(icon, size: 20, color: const Color(0xFF1F5EFF)),
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
            shadowColor: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: onPressed,
              child: SizedBox(
                width: 48,
                height: 48,
                child: Icon(icon, color: const Color(0xFF243B63)),
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
        color: const Color(0xFFF0F4EC),
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
                    color: item.value == value
                        ? Colors.white
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: item.value == value
                        ? const [
                            BoxShadow(
                              color: Color(0x141A365C),
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
                          ? const Color(0xFF1F5EFF)
                          : const Color(0xFF7C8792),
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
            color: selected ? const Color(0xFF6474FF) : const Color(0xFFD7DCF4),
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
    color: Colors.white.withValues(alpha: 0.90),
    borderRadius: BorderRadius.circular(28),
    border: Border.all(color: const Color(0xFFE1E7D9)),
    boxShadow: const [
      BoxShadow(
        color: Color(0x14193256),
        blurRadius: 30,
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
        icon: TeamCashIcons.trendUp,
      ),
      MetricTrendDirection.down => (
        color: const Color(0xFFE56874),
        icon: TeamCashIcons.trendDown,
      ),
      MetricTrendDirection.neutral => (
        color: const Color(0xFF8189AB),
        icon: TeamCashIcons.trendFlat,
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

class _BackdropGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final majorPaint = Paint()
      ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.11)
      ..strokeWidth = 1;
    final minorPaint = Paint()
      ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.05)
      ..strokeWidth = 1;

    for (double x = 0; x < size.width; x += 84) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), majorPaint);
    }
    for (double y = 20; y < size.height; y += 84) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), majorPaint);
    }
    for (double x = 42; x < size.width; x += 84) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), minorPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
