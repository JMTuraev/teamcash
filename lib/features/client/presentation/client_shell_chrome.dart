part of 'client_shell.dart';

class _ClientTopBar extends StatelessWidget {
  const _ClientTopBar({
    required this.greeting,
    required this.clientName,
    required this.onOpenNotifications,
    required this.unreadNotificationsCount,
    this.onSignOut,
  });

  final String greeting;
  final String clientName;
  final VoidCallback onOpenNotifications;
  final int unreadNotificationsCount;
  final VoidCallback? onSignOut;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF6678FF), Color(0xFF7F65FF)],
            ),
            borderRadius: BorderRadius.circular(18),
          ),
          alignment: Alignment.center,
          child: const Icon(Icons.link_rounded, color: Colors.white),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$greeting 👋',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF8A91B1),
                ),
              ),
              const SizedBox(height: 2),
              Text(clientName, style: Theme.of(context).textTheme.titleLarge),
            ],
          ),
        ),
        SurfaceIconButton(
          icon: Icons.search_rounded,
          onPressed: () {},
          tooltip: 'Search',
        ),
        const SizedBox(width: 10),
        SurfaceIconButton(
          icon: Icons.notifications_none_rounded,
          onPressed: onOpenNotifications,
          tooltip: 'Notifications',
          hasDot: unreadNotificationsCount > 0,
        ),
        if (onSignOut != null) ...[
          const SizedBox(width: 10),
          SurfaceIconButton(
            icon: Icons.logout_rounded,
            onPressed: onSignOut,
            tooltip: 'Sign out',
          ),
        ],
      ],
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: Colors.white.withValues(alpha: 0.82)),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.white.withValues(alpha: 0.74),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(color: Colors.white),
            ),
          ],
        ),
      ],
    );
  }
}
