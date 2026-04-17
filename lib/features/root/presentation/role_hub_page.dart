import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:teamcash/app/app.dart';
import 'package:teamcash/app/bootstrap/firebase_bootstrap.dart';
import 'package:teamcash/core/models/app_role.dart';
import 'package:teamcash/core/models/workspace_models.dart';
import 'package:teamcash/core/session/session_controller.dart';
import 'package:teamcash/features/shared/presentation/shell_widgets.dart';

class RoleHubPage extends ConsumerWidget {
  const RoleHubPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                _HeroCopy(
                  statsLine:
                      '${snapshot.directory.length} trusted businesses • ${snapshot.client.walletLots.length} wallet lots',
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: _RolePanel(
                    firebaseStatus: firebaseStatus,
                    sessionRole: session?.role,
                    snapshot: snapshot,
                  ),
                ),
                const SizedBox(height: 14),
                InfoBanner(
                  title: firebaseStatus.mode ==
                          FirebaseBootstrapMode.connected
                      ? 'Connected Firebase runtime'
                      : 'Preview runtime active',
                  message: firebaseStatus.message,
                  color: firebaseStatus.mode ==
                          FirebaseBootstrapMode.connected
                      ? const Color(0xFFE8FBF4)
                      : const Color(0xFFFFF3DF),
                  icon: firebaseStatus.mode ==
                          FirebaseBootstrapMode.connected
                      ? Icons.cloud_done_outlined
                      : Icons.visibility_outlined,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HeroCopy extends StatelessWidget {
  const _HeroCopy({required this.statsLine});

  final String statsLine;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF6576FF), Color(0xFF7F65FF)],
            ),
            borderRadius: BorderRadius.circular(18),
          ),
          alignment: Alignment.center,
          child: const Icon(Icons.link_rounded, size: 28, color: Colors.white),
        ),
        const SizedBox(height: 14),
        Text(
          'TeamCash',
          style: theme.textTheme.displaySmall?.copyWith(fontSize: 28),
        ),
        const SizedBox(height: 4),
        Text(
          'Earn together. Spend smarter.',
          style: theme.textTheme.titleSmall?.copyWith(
            color: const Color(0xFF6A7394),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Private cashback tandems for trusted business groups',
          style: theme.textTheme.titleSmall?.copyWith(fontSize: 15),
        ),
        const SizedBox(height: 6),
        Text(
          'Fast role entry, no landing-page scan.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Chip(label: Text(statsLine)),
            const Chip(label: Text('No scroll')),
          ],
        ),
      ],
    );
  }
}

class _RolePanel extends StatelessWidget {
  const _RolePanel({
    required this.firebaseStatus,
    required this.sessionRole,
    required this.snapshot,
  });

  final FirebaseBootstrapResult firebaseStatus;
  final AppRole? sessionRole;
  final AppWorkspaceSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFF),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: const Color(0xFFE4E8F7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Choose your role',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 4),
          Text(
            'Open the role surface you need right now.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 10),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: 338,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: AppRole.values
                      .map(
                        (role) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _RoleCard(
                            role: role,
                            firebaseStatus: firebaseStatus,
                            sessionRole: sessionRole,
                            statsLine: switch (role) {
                              AppRole.owner =>
                                '${snapshot.owner.businesses.length} businesses • ${snapshot.owner.staffMembers.length} staff accounts',
                              AppRole.staff =>
                                '${snapshot.staff.dashboardMetrics.length} metrics • ${snapshot.staff.recentTransactions.length} recent actions',
                              AppRole.client =>
                                '${snapshot.client.storeDirectory.length} partners • ${snapshot.client.walletLots.length} wallet lots',
                            },
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.role,
    required this.statsLine,
    required this.firebaseStatus,
    required this.sessionRole,
  });

  final AppRole role;
  final String statsLine;
  final FirebaseBootstrapResult firebaseStatus;
  final AppRole? sessionRole;

  @override
  Widget build(BuildContext context) {
    final palette = _paletteForRole(role);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE4E8F7)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: palette.background,
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: Icon(palette.icon, color: palette.foreground, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(role.label, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(
                  statsLine,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF5A65AF),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 118,
            child: FilledButton(
              key: ValueKey('role-action-${role.name}'),
              onPressed: () => _handleAction(context),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 10,
                ),
                visualDensity: VisualDensity.compact,
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(_buildActionLabel()),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _buildActionLabel() {
    if (sessionRole == role) {
      return 'Open ${role.label} Surface';
    }

    if (firebaseStatus.mode == FirebaseBootstrapMode.preview) {
      return 'Open ${role.label} Surface';
    }

    return switch (role) {
      AppRole.owner => 'Sign In as Owner',
      AppRole.staff => 'Sign In as Staff',
      AppRole.client => 'Verify Client Phone',
    };
  }

  Future<void> _handleAction(BuildContext context) async {
    if (sessionRole == role) {
      context.go(role.routePath);
      return;
    }

    if (firebaseStatus.mode == FirebaseBootstrapMode.preview) {
      final container = ProviderScope.containerOf(context, listen: false);
      await container
          .read(appSessionControllerProvider.notifier)
          .continueInPreview(role);
      if (context.mounted) {
        context.go(role.routePath);
      }
      return;
    }

    context.go('/sign-in/${role.name}');
  }
}

({IconData icon, Color background, Color foreground}) _paletteForRole(
  AppRole role,
) {
  return switch (role) {
    AppRole.client => (
      icon: Icons.person_outline_rounded,
      background: const Color(0xFFE9EDFF),
      foreground: const Color(0xFF5D6BFF),
    ),
    AppRole.owner => (
      icon: Icons.storefront_outlined,
      background: const Color(0xFFFFF1E2),
      foreground: const Color(0xFFF29C38),
    ),
    AppRole.staff => (
      icon: Icons.badge_outlined,
      background: const Color(0xFFE8FBF4),
      foreground: const Color(0xFF2CB991),
    ),
  };
}
