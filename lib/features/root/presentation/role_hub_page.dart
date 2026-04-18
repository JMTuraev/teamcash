import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:teamcash/app/app.dart';
import 'package:teamcash/app/bootstrap/firebase_bootstrap.dart';
import 'package:teamcash/app/theme/teamcash_icons.dart';
import 'package:teamcash/core/models/app_role.dart';
import 'package:teamcash/core/models/workspace_models.dart';
import 'package:teamcash/core/session/app_session.dart';
import 'package:teamcash/core/session/session_controller.dart';
import 'package:teamcash/features/shared/presentation/shell_widgets.dart';

class RoleHubPage extends ConsumerStatefulWidget {
  const RoleHubPage({super.key});

  @override
  ConsumerState<RoleHubPage> createState() => _RoleHubPageState();
}

class _RoleHubPageState extends ConsumerState<RoleHubPage> {
  late AppRole _selectedRole;

  @override
  void initState() {
    super.initState();
    final session = ref.read(currentSessionProvider);
    _selectedRole = session?.role ?? AppRole.client;
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = ref.watch(appSnapshotProvider);
    final firebaseStatus = ref.watch(firebaseStatusProvider);
    final session = ref.watch(currentSessionProvider);

    return Scaffold(
      body: AppBackdrop(
        child: SafeArea(
          child: MobileAppFrame(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _HubHeader(firebaseStatus: firebaseStatus),
                if (session != null) ...[
                  const SizedBox(height: 12),
                  _ContinueCard(session: session),
                ],
                const SizedBox(height: 12),
                Expanded(
                  child: Column(
                    children: [
                      for (final role in AppRole.values) ...[
                        Expanded(
                          flex: _selectedRole == role ? 7 : 2,
                          child: _RoleAccordionPanel(
                            role: role,
                            selected: _selectedRole == role,
                            menu: _menuForRole(role, snapshot),
                            sessionRole: session?.role,
                            stat: _compactStatForRole(role, snapshot),
                            onSelect: () {
                              setState(() {
                                _selectedRole = role;
                              });
                            },
                          ),
                        ),
                        if (role != AppRole.values.last)
                          const SizedBox(height: 8),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HubHeader extends StatelessWidget {
  const _HubHeader({required this.firebaseStatus});

  final FirebaseBootstrapResult firebaseStatus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: const LinearGradient(
              colors: [Color(0xFF5976FF), Color(0xFF7967FF)],
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x1F5A68FF),
                blurRadius: 24,
                offset: Offset(0, 12),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: const Icon(TeamCashIcons.brand, color: Colors.white, size: 24),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('TeamCash', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 2),
              Text('No scroll menu', style: theme.textTheme.bodySmall),
            ],
          ),
        ),
        StatusPill(
          label: firebaseStatus.mode == FirebaseBootstrapMode.connected
              ? 'Live'
              : 'Preview',
          backgroundColor:
              firebaseStatus.mode == FirebaseBootstrapMode.connected
              ? const Color(0xFFDDF8EF)
              : const Color(0xFFFFE8CE),
          foregroundColor:
              firebaseStatus.mode == FirebaseBootstrapMode.connected
              ? const Color(0xFF158467)
              : const Color(0xFFB36B00),
        ),
      ],
    );
  }
}

class _ContinueCard extends StatelessWidget {
  const _ContinueCard({required this.session});

  final AppSession session;

  @override
  Widget build(BuildContext context) {
    final palette = _paletteForRole(session.role);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: palette.background.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: palette.background),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: Icon(
              TeamCashIcons.role(session.role),
              color: palette.foreground,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Continue ${session.role.label}',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                Text(
                  session.isPreview ? 'Preview session' : session.displayName,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          FilledButton(
            onPressed: () => context.go(session.routePath),
            style: FilledButton.styleFrom(
              backgroundColor: palette.foreground,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            child: const Text('Open'),
          ),
        ],
      ),
    );
  }
}

class _RoleAccordionPanel extends StatelessWidget {
  const _RoleAccordionPanel({
    required this.role,
    required this.selected,
    required this.menu,
    required this.sessionRole,
    required this.stat,
    required this.onSelect,
  });

  final AppRole role;
  final bool selected;
  final _WorkspaceMenu menu;
  final AppRole? sessionRole;
  final String stat;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final palette = _paletteForRole(role);
    final isCurrent = sessionRole == role;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(26),
        onTap: onSelect,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(
              color: selected ? palette.foreground : const Color(0xFFE2E7F1),
              width: selected ? 1.4 : 1,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x12193256),
                blurRadius: 18,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: selected
              ? _ExpandedRolePanel(
                  menu: menu,
                  sessionRole: sessionRole,
                  palette: palette,
                )
              : Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: palette.background,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        menu.icon,
                        color: palette.foreground,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            role.label,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            stat,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    StatusPill(
                      label: isCurrent ? 'Open' : 'Menu',
                      backgroundColor: palette.background,
                      foregroundColor: palette.foreground,
                    ),
                    const SizedBox(width: 6),
                    Icon(TeamCashIcons.chevronRight, color: palette.foreground),
                  ],
                ),
        ),
      ),
    );
  }
}

class _ExpandedRolePanel extends StatelessWidget {
  const _ExpandedRolePanel({
    required this.menu,
    required this.sessionRole,
    required this.palette,
  });

  final _WorkspaceMenu menu;
  final AppRole? sessionRole;
  final ({IconData icon, Color background, Color foreground}) palette;

  @override
  Widget build(BuildContext context) {
    final isCurrent = sessionRole == menu.role;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: palette.background,
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: Icon(menu.icon, color: palette.foreground),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    menu.title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 2),
                  Text(menu.stat, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            Icon(TeamCashIcons.chevronDown, color: palette.foreground),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () => _handlePrimaryAction(context),
                style: FilledButton.styleFrom(
                  backgroundColor: palette.foreground,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                icon: Icon(
                  isCurrent ? menu.icon : TeamCashIcons.login,
                  size: 18,
                ),
                label: Text(isCurrent ? 'Open' : 'Login'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _openPreview(context),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                icon: const Icon(TeamCashIcons.preview, size: 18),
                label: const Text('Preview'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Expanded(
          child: Column(
            children: [
              for (final entry in menu.links.asMap().entries) ...[
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      bottom: entry.key == menu.links.length - 1 ? 0 : 8,
                    ),
                    child: _MenuLinkButton(
                      link: entry.value,
                      tint: palette.foreground,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  void _handlePrimaryAction(BuildContext context) {
    if (sessionRole == menu.role) {
      context.go(menu.baseRoute);
      return;
    }

    context.go('/sign-in/${menu.role.name}');
  }

  Future<void> _openPreview(BuildContext context) async {
    final container = ProviderScope.containerOf(context, listen: false);
    await container
        .read(appSessionControllerProvider.notifier)
        .continueInPreview(menu.role);
    if (context.mounted) {
      context.go(menu.baseRoute);
    }
  }
}

class _MenuLinkButton extends StatelessWidget {
  const _MenuLinkButton({required this.link, required this.tint});

  final _WorkspaceLink link;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: () => context.go(link.route),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        side: BorderSide(color: tint.withValues(alpha: 0.18)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      child: Row(
        children: [
          Icon(link.icon, size: 18, color: tint),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              link.label,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(color: const Color(0xFF20304B)),
            ),
          ),
          Icon(TeamCashIcons.chevronRight, color: tint),
        ],
      ),
    );
  }
}

class _WorkspaceMenu {
  const _WorkspaceMenu({
    required this.role,
    required this.icon,
    required this.title,
    required this.stat,
    required this.baseRoute,
    required this.links,
  });

  final AppRole role;
  final IconData icon;
  final String title;
  final String stat;
  final String baseRoute;
  final List<_WorkspaceLink> links;
}

class _WorkspaceLink {
  const _WorkspaceLink({
    required this.label,
    required this.icon,
    required this.route,
  });

  final String label;
  final IconData icon;
  final String route;
}

_WorkspaceMenu _menuForRole(AppRole role, AppWorkspaceSnapshot snapshot) {
  return switch (role) {
    AppRole.owner => _WorkspaceMenu(
      role: role,
      icon: TeamCashIcons.storefront,
      title: 'Owner',
      stat: '${snapshot.owner.businesses.length} businesses',
      baseRoute: '/owner',
      links: const [
        _WorkspaceLink(
          label: 'Businesses',
          icon: TeamCashIcons.storefront,
          route: '/owner?tab=businesses',
        ),
        _WorkspaceLink(
          label: 'Dashboard',
          icon: TeamCashIcons.dashboard,
          route: '/owner?tab=dashboard',
        ),
        _WorkspaceLink(
          label: 'Staffs',
          icon: TeamCashIcons.badge,
          route: '/owner?tab=staff',
        ),
      ],
    ),
    AppRole.staff => _WorkspaceMenu(
      role: role,
      icon: TeamCashIcons.badge,
      title: 'Staff',
      stat: '${snapshot.staff.recentTransactions.length} actions',
      baseRoute: '/staff',
      links: const [
        _WorkspaceLink(
          label: 'Dashboard',
          icon: TeamCashIcons.dashboard,
          route: '/staff?tab=dashboard',
        ),
        _WorkspaceLink(
          label: 'Scan',
          icon: TeamCashIcons.scan,
          route: '/staff?tab=scan',
        ),
        _WorkspaceLink(
          label: 'Profile',
          icon: TeamCashIcons.profile,
          route: '/staff?tab=profile',
        ),
      ],
    ),
    AppRole.client => _WorkspaceMenu(
      role: role,
      icon: TeamCashIcons.walletLinked,
      title: 'Client',
      stat: '${snapshot.client.walletLots.length} lots',
      baseRoute: '/client',
      links: const [
        _WorkspaceLink(
          label: 'Stores',
          icon: TeamCashIcons.stores,
          route: '/client?tab=stores',
        ),
        _WorkspaceLink(
          label: 'Wallet',
          icon: TeamCashIcons.wallet,
          route: '/client?tab=wallet',
        ),
        _WorkspaceLink(
          label: 'Activity',
          icon: TeamCashIcons.activity,
          route: '/client?tab=activity',
        ),
        _WorkspaceLink(
          label: 'Profile',
          icon: TeamCashIcons.profile,
          route: '/client?tab=profile',
        ),
      ],
    ),
  };
}

String _compactStatForRole(AppRole role, AppWorkspaceSnapshot snapshot) {
  return switch (role) {
    AppRole.owner => '${snapshot.owner.businesses.length} businesses',
    AppRole.staff => '${snapshot.staff.recentTransactions.length} actions',
    AppRole.client => '${snapshot.client.walletLots.length} lots',
  };
}

({IconData icon, Color background, Color foreground}) _paletteForRole(
  AppRole role,
) {
  return switch (role) {
    AppRole.client => (
      icon: TeamCashIcons.person,
      background: const Color(0xFFE9EDFF),
      foreground: const Color(0xFF5D6BFF),
    ),
    AppRole.owner => (
      icon: TeamCashIcons.storefront,
      background: const Color(0xFFFFF1E2),
      foreground: const Color(0xFFF29C38),
    ),
    AppRole.staff => (
      icon: TeamCashIcons.badge,
      background: const Color(0xFFE8FBF4),
      foreground: const Color(0xFF2CB991),
    ),
  };
}
