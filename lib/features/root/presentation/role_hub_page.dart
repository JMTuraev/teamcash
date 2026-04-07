import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:teamcash/app/app.dart';
import 'package:teamcash/app/bootstrap/firebase_bootstrap.dart';
import 'package:teamcash/core/models/app_role.dart';
import 'package:teamcash/core/session/session_controller.dart';
import 'package:teamcash/features/shared/presentation/shell_widgets.dart';

class RoleHubPage extends ConsumerWidget {
  const RoleHubPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(appSnapshotProvider);
    final firebaseStatus = ref.watch(firebaseStatusProvider);
    final session = ref.watch(currentSessionProvider);
    final theme = Theme.of(context);

    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFFCFAF6), Color(0xFFF4EEE3), Color(0xFFE8F1EE)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1240),
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Container(
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      color: const Color(0xFF153C36),
                      borderRadius: BorderRadius.circular(32),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Private cashback tandems for trusted business groups',
                          style: theme.textTheme.displaySmall?.copyWith(
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'This foundation keeps the core product rules intact: group-bound cashback, transferable client lots, unanimous group entry, shadow wallets by phone, and server-authoritative ledger actions.',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: const Color(0xFFD9E2EC),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: const [
                            _PillarChip(label: 'Shadow wallet claim by phone'),
                            _PillarChip(
                              label: 'Client transfer and pending gift',
                            ),
                            _PillarChip(label: 'Multi-client shared checkout'),
                            _PillarChip(label: 'Unanimous tandem approval'),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  InfoBanner(
                    title:
                        firebaseStatus.mode == FirebaseBootstrapMode.connected
                        ? 'Firebase runtime connected'
                        : 'Preview runtime active',
                    message: firebaseStatus.message,
                    color:
                        firebaseStatus.mode == FirebaseBootstrapMode.connected
                        ? const Color(0xFFE7F5EF)
                        : const Color(0xFFFFF2D8),
                  ),
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: AppRole.values
                        .map(
                          (role) => _RoleCard(
                            role: role,
                            firebaseStatus: firebaseStatus,
                            sessionRole: session?.role,
                            statsLine: switch (role) {
                              AppRole.owner =>
                                '${snapshot.owner.businesses.length} businesses • ${snapshot.owner.staffMembers.length} staff accounts',
                              AppRole.staff =>
                                '${snapshot.staff.dashboardMetrics.length} operator metrics • ${snapshot.staff.recentTransactions.length} live actions',
                              AppRole.client =>
                                '${snapshot.client.storeDirectory.length} stores • ${snapshot.client.walletLots.length} wallet lots',
                            },
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 20),
                  const SectionCard(
                    title: 'Audit Snapshot',
                    subtitle:
                        'What the repository looked like before this foundation pass.',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _AuditLine(
                          'Reusable',
                          'Flutter workspace, platform folders, Git history, and Android Firebase JSON were already present.',
                        ),
                        _AuditLine(
                          'Missing',
                          'Production app structure, Firebase runtime bootstrap, backend source, Firestore rules, and any domain implementation were absent.',
                        ),
                        _AuditLine(
                          'Risk found',
                          'Android app ID did not match the checked-in Firebase config, and web Firebase options were not configured for Chrome development.',
                        ),
                        _AuditLine(
                          'Current stance',
                          'Chrome work continues through preview-safe seeded data while the backend contract and UI surfaces are established.',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
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
    final theme = Theme.of(context);
    final actionLabel = _buildActionLabel();

    return SizedBox(
      width: 390,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(role.label, style: theme.textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(
                role.summary,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: const Color(0xFF52606D),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                statsLine,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: const Color(0xFF1B5E52),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                role.navigationLabel,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF52606D),
                ),
              ),
              const SizedBox(height: 20),
              FilledButton(
                key: ValueKey('role-action-${role.name}'),
                onPressed: () => _handleAction(context),
                child: Text(actionLabel),
              ),
            ],
          ),
        ),
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

class _PillarChip extends StatelessWidget {
  const _PillarChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white24),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _AuditLine extends StatelessWidget {
  const _AuditLine(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: RichText(
        text: TextSpan(
          style: theme.textTheme.bodyLarge,
          children: [
            TextSpan(
              text: '$label: ',
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            TextSpan(
              text: value,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: const Color(0xFF52606D),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
