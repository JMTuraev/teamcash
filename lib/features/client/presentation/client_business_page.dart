part of 'client_shell.dart';

class ClientBusinessPage extends ConsumerWidget {
  const ClientBusinessPage({super.key, required this.businessId});

  final String businessId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final previewClient = ref.watch(appSnapshotProvider).client;
    final session = ref.watch(currentSessionProvider);
    final clientAsync = ref.watch(clientWorkspaceProvider);
    final canRunLiveWorkspace =
        session?.role == AppRole.client &&
        session?.isPreview == false &&
        (session?.customerId?.isNotEmpty ?? false);

    if (canRunLiveWorkspace && clientAsync.isLoading && !clientAsync.hasValue) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(child: Center(child: CircularProgressIndicator())),
      );
    }

    if (canRunLiveWorkspace && clientAsync.hasError && !clientAsync.hasValue) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                clientAsync.error.toString(),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      );
    }

    final client = canRunLiveWorkspace
        ? clientAsync.requireValue
        : previewClient;
    final store = client.storeDirectory
        .where((entry) => entry.id == businessId)
        .cast<BusinessDirectoryEntry?>()
        .firstWhere((entry) => entry != null, orElse: () => null);

    if (store == null) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 12),
              _BusinessPageBackButton(onTap: () => context.pop()),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  'Business not found.',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              const Spacer(),
            ],
          ),
        ),
      );
    }

    final teamBusinesses = _teamBusinessesForStore(
      store,
      client.storeDirectory,
    );
    final coverImageUrl = _businessMediaUrl(store);
    final fallbackAssetPath = _mockBusinessPhotoAsset(store);
    final logoImageUrl = store.logoUrl.trim().isNotEmpty
        ? store.logoUrl.trim()
        : coverImageUrl;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            SizedBox(
              height: 348,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        bottom: Radius.circular(36),
                      ),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          _BusinessVisualSurface(
                            mediaUrl: coverImageUrl,
                            mockAssetPath: fallbackAssetPath,
                          ),
                          DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.black.withValues(alpha: 0.18),
                                  Colors.black.withValues(alpha: 0.26),
                                  Colors.black.withValues(alpha: 0.52),
                                ],
                                stops: const [0, 0.45, 1],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    top: 12,
                    left: 16,
                    child: _BusinessPageBackButton(onTap: () => context.pop()),
                  ),
                  Positioned(
                    left: 20,
                    right: 20,
                    bottom: 18,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Container(
                          width: 96,
                          height: 96,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 4),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x22000000),
                                blurRadius: 18,
                                offset: Offset(0, 8),
                              ),
                            ],
                          ),
                          child: ClipOval(
                            child: _BusinessVisualSurface(
                              mediaUrl: logoImageUrl,
                              mockAssetPath: fallbackAssetPath,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(
                              store.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.headlineMedium
                                  ?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.9,
                                    shadows: const [
                                      Shadow(
                                        color: Color(0x40000000),
                                        blurRadius: 10,
                                        offset: Offset(0, 2),
                                      ),
                                    ],
                                  ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
              child: Row(
                children: [
                  Expanded(
                    child: _BusinessHeaderMetric(
                      icon: TeamCashIcons.person,
                      value: '${_mockEarnedClientsCount(store)}',
                      label: 'Clients',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _BusinessHeaderMetric(
                      icon: TeamCashIcons.hub,
                      value: '${teamBusinesses.length + 1}',
                      label: 'Team businesses',
                    ),
                  ),
                ],
              ),
            ),
            const Expanded(child: SizedBox.expand()),
          ],
        ),
      ),
    );
  }
}

class _BusinessHeaderMetric extends StatelessWidget {
  const _BusinessHeaderMetric({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FC),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _clientInactive.withValues(alpha: 0.10)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: _clientActiveBlue),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: const Color(0xFF111111),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _clientInactive.withValues(alpha: 0.72),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BusinessPageBackButton extends StatelessWidget {
  const _BusinessPageBackButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Ink(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.84),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            TeamCashIcons.back,
            size: 20,
            color: Color(0xFF111111),
          ),
        ),
      ),
    );
  }
}
