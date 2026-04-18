import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:teamcash/app/app.dart';
import 'package:teamcash/app/theme/teamcash_icons.dart';
import 'package:teamcash/core/models/app_role.dart';
import 'package:teamcash/core/models/business_content_models.dart';
import 'package:teamcash/core/models/business_models.dart';
import 'package:teamcash/core/models/customer_identity_models.dart';
import 'package:teamcash/core/models/notification_models.dart';
import 'package:teamcash/core/models/wallet_models.dart';
import 'package:teamcash/core/models/workspace_models.dart';
import 'package:teamcash/core/session/app_session.dart';
import 'package:teamcash/core/services/account_profile_service.dart';
import 'package:teamcash/core/services/customer_identity_token_service.dart';
import 'package:teamcash/core/services/notification_center_service.dart';
import 'package:teamcash/core/services/teamcash_functions_service.dart';
import 'package:teamcash/core/session/session_controller.dart';
import 'package:teamcash/core/utils/formatters.dart';
import 'package:teamcash/data/firestore/firestore_workspace_repository.dart';
import 'package:teamcash/features/client/application/client_transfer_controller.dart';
import 'package:teamcash/features/shared/presentation/customer_identity_widgets.dart';
import 'package:teamcash/features/shared/presentation/notification_center_widgets.dart';
import 'package:teamcash/features/shared/presentation/shell_widgets.dart';

part 'client_shell_chrome.dart';
part 'client_business_page.dart';
part 'client_shell_discover.dart';
part 'client_shell_stores.dart';
part 'client_shell_wallet.dart';
part 'client_shell_history.dart';
part 'client_shell_profile.dart';

class ClientShell extends ConsumerStatefulWidget {
  const ClientShell({super.key, this.initialTabIndex});

  final int? initialTabIndex;

  @override
  ConsumerState<ClientShell> createState() => _ClientShellState();
}

class _ClientShellState extends ConsumerState<ClientShell> {
  int _selectedIndex = 0;
  int _selectedHeaderTab = 0;
  String? _selectedDiscoverArea;
  final Set<String> _favoriteBusinessIds = {'silk-road-cafe'};
  final GlobalKey _shellOverlayKey = GlobalKey();
  final GlobalKey _favoriteBrandKey = GlobalKey();
  _HeartFlight? _activeHeartFlight;
  int _heartFlightSeed = 0;

  @override
  void initState() {
    super.initState();
    _selectedIndex = _normalizeClientTabIndex(widget.initialTabIndex, 0);
  }

  @override
  Widget build(BuildContext context) {
    final previewClient = ref.watch(appSnapshotProvider).client;
    final session = ref.watch(currentSessionProvider);
    final clientAsync = ref.watch(clientWorkspaceProvider);
    final notificationsAsync = ref.watch(currentNotificationsProvider);
    final canRunLiveTransfers =
        session?.role == AppRole.client &&
        session?.isPreview == false &&
        (session?.customerId?.isNotEmpty ?? false);
    final hasVerifiedPhoneClaimActions =
        session?.role == AppRole.client &&
        session?.isPreview == false &&
        (session?.phoneNumber?.isNotEmpty ?? false);
    final notifications =
        notificationsAsync.asData?.value ?? const <AppNotificationItem>[];
    final unreadNotificationsCount = notifications
        .where((notification) => !notification.isRead)
        .length;

    if (canRunLiveTransfers && clientAsync.isLoading && !clientAsync.hasValue) {
      return Scaffold(
        appBar: AppBar(title: const Text('Client wallet')),
        body: const SafeArea(child: Center(child: CircularProgressIndicator())),
      );
    }

    if (canRunLiveTransfers && clientAsync.hasError && !clientAsync.hasValue) {
      return Scaffold(
        appBar: AppBar(title: const Text('Client wallet')),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Client wallet could not be loaded from Firestore.',
                  ),
                  const SizedBox(height: 12),
                  Text(
                    clientAsync.error.toString(),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => ref.invalidate(clientWorkspaceProvider),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final client = canRunLiveTransfers
        ? clientAsync.requireValue
        : previewClient;
    final discoverAreaLabel = _resolveDiscoverAreaLabel(
      client.storeDirectory,
      _selectedDiscoverArea,
    );
    final discoverAreaStores = _storesNearClientArea(
      client.storeDirectory,
      discoverAreaLabel,
    );
    final customerIdentityToken = ref
        .watch(customerIdentityTokenServiceProvider)
        .buildForClient(client: client, session: session);
    final discoverTabs = _buildDiscoverFilterTabs(discoverAreaStores);
    final selectedDiscoverTabIndex = _normalizeDiscoverFilterIndex(
      _selectedHeaderTab,
      discoverTabs.length,
    );

    _touchLegacyClientSurfaces(
      client: client,
      customerIdentityToken: customerIdentityToken,
      customerId: session?.customerId,
      canEditProfile:
          session?.role == AppRole.client &&
          session?.isPreview == false &&
          (session?.customerId?.isNotEmpty ?? false),
      canRunLiveTransferActions: canRunLiveTransfers,
      hasVerifiedPhoneClaimActions: hasVerifiedPhoneClaimActions,
    );

    return Scaffold(
      key: const ValueKey('client-workspace-root'),
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Stack(
          key: _shellOverlayKey,
          fit: StackFit.expand,
          children: [
            Column(
              children: [
                _ClientMockHeader(
                  brandKey: _favoriteBrandKey,
                  tabs: discoverTabs,
                  selectedHeaderTab: selectedDiscoverTabIndex,
                  onHeaderTabSelected: (index) {
                    setState(() {
                      _selectedHeaderTab = index;
                    });
                  },
                ),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: _buildMockSurface(
                      client: client,
                      discoverTabs: discoverTabs,
                      selectedDiscoverTabIndex: selectedDiscoverTabIndex,
                      discoverAreaLabel: discoverAreaLabel,
                      hasManualDiscoverArea: _selectedDiscoverArea != null,
                      favoriteBusinessIds: _favoriteBusinessIds,
                      onOpenDiscoverAreaSelector: () =>
                          _openDiscoverAreaSelector(client.storeDirectory),
                      onToggleFavorite: _toggleFavoriteBusiness,
                      notifications: notifications,
                      customerIdentityToken: customerIdentityToken,
                      unreadNotificationsCount: unreadNotificationsCount,
                      canRunLiveTransfers: canRunLiveTransfers,
                      hasVerifiedPhoneClaimActions:
                          hasVerifiedPhoneClaimActions,
                      session: session,
                    ),
                  ),
                ),
              ],
            ),
            if (_activeHeartFlight != null)
              Positioned.fill(
                child: IgnorePointer(
                  child: _HeartFlightOverlay(flight: _activeHeartFlight!),
                ),
              ),
          ],
        ),
      ),
      bottomNavigationBar: _ClientMockBottomBar(
        selectedIndex: _selectedIndex,
        onSelected: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
      ),
    );
  }

  Widget _buildMockSurface({
    required ClientWorkspace client,
    required List<_DiscoverFilterTab> discoverTabs,
    required int selectedDiscoverTabIndex,
    required String discoverAreaLabel,
    required bool hasManualDiscoverArea,
    required Set<String> favoriteBusinessIds,
    required VoidCallback onOpenDiscoverAreaSelector,
    required void Function(String, BuildContext) onToggleFavorite,
    required List<AppNotificationItem> notifications,
    required CustomerIdentificationToken customerIdentityToken,
    required int unreadNotificationsCount,
    required bool canRunLiveTransfers,
    required bool hasVerifiedPhoneClaimActions,
    required AppSession? session,
  }) {
    return switch (_selectedIndex) {
      0 => _ClientDiscoverTab(
        key: const ValueKey('client-discover-feed'),
        client: client,
        discoverTabs: discoverTabs,
        selectedFilterIndex: selectedDiscoverTabIndex,
        selectedAreaLabel: discoverAreaLabel,
        hasManualAreaSelection: hasManualDiscoverArea,
        favoriteBusinessIds: favoriteBusinessIds,
        onOpenAreaSelector: onOpenDiscoverAreaSelector,
        onToggleFavorite: onToggleFavorite,
      ),
      1 => _QrCodeMockTab(
        key: const ValueKey('client-qr-mock'),
        customerIdentityToken: customerIdentityToken,
      ),
      2 => _ProfileMockTab(
        key: const ValueKey('client-profile-mock'),
        client: client,
        canRunLiveTransfers: canRunLiveTransfers,
        hasVerifiedPhoneClaimActions: hasVerifiedPhoneClaimActions,
        session: session,
      ),
      _ => _ChatMockTab(
        key: const ValueKey('client-chat-mock'),
        unreadNotificationsCount: unreadNotificationsCount,
        notifications: notifications,
        onOpenInbox: () => _openNotificationsCenter(notifications, client),
      ),
    };
  }

  Future<void> _openNotificationsCenter(
    List<AppNotificationItem> notifications,
    ClientWorkspace client,
  ) async {
    await showNotificationCenterBottomSheet(
      context: context,
      title: 'Client notifications',
      notifications: notifications,
      onMarkRead: (notificationId) async {
        final session = ref.read(currentSessionProvider);
        if (session == null || session.isPreview) {
          return;
        }
        await ref
            .read(notificationCenterServiceProvider)
            .markRead(notificationId);
      },
      onMarkAllRead: (notificationIds) async {
        final session = ref.read(currentSessionProvider);
        if (session == null || session.isPreview) {
          return;
        }
        await ref
            .read(notificationCenterServiceProvider)
            .markAllRead(notificationIds);
      },
      onOpenNotification: (notification) async {
        _openClientNotification(notification, client);
      },
    );
  }

  void _openClientNotification(
    AppNotificationItem notification,
    ClientWorkspace client,
  ) {
    final route = notification.actionRoute?.trim();
    if (route != null && route.isNotEmpty && route != '/client') {
      context.go(route);
      return;
    }

    setState(() {
      _selectedIndex = _clientTabForNotification(notification, client);
    });
  }

  int _clientTabForNotification(
    AppNotificationItem notification,
    ClientWorkspace client,
  ) {
    switch (notification.type) {
      case 'cashback_expiring':
      case 'gift_pending':
      case 'gift_claimed':
      case 'shared_checkout_created':
      case 'shared_checkout_contribution':
      case 'shared_checkout_finalized':
        return 1;
      case 'cashback_issued':
      case 'cashback_redeemed':
      case 'cashback_refunded':
      case 'cashback_expired':
      case 'admin_adjustment':
        return 2;
      case 'business_updated':
        return 0;
      default:
        return client.pendingTransfers.isNotEmpty ? 1 : 2;
    }
  }

  void _toggleFavoriteBusiness(String businessId, BuildContext sourceContext) {
    final shouldFavorite = !_favoriteBusinessIds.contains(businessId);
    final flight = shouldFavorite ? _createHeartFlight(sourceContext) : null;
    final flightId = flight?.id;
    setState(() {
      if (shouldFavorite) {
        _favoriteBusinessIds.add(businessId);
      } else {
        _favoriteBusinessIds.remove(businessId);
      }
      if (flight != null) {
        _activeHeartFlight = flight;
      }
    });
    if (flightId != null) {
      Future<void>.delayed(const Duration(milliseconds: 760), () {
        if (!mounted) {
          return;
        }
        setState(() {
          if (_activeHeartFlight?.id == flightId) {
            _activeHeartFlight = null;
          }
        });
      });
    }
  }

  _HeartFlight? _createHeartFlight(BuildContext sourceContext) {
    final sourceBox = sourceContext.findRenderObject() as RenderBox?;
    final targetBox =
        _favoriteBrandKey.currentContext?.findRenderObject() as RenderBox?;
    final overlayBox =
        _shellOverlayKey.currentContext?.findRenderObject() as RenderBox?;
    if (sourceBox == null || targetBox == null || overlayBox == null) {
      return null;
    }

    final sourceGlobal = sourceBox.localToGlobal(
      sourceBox.size.center(Offset.zero),
    );
    final targetGlobal = targetBox.localToGlobal(
      targetBox.size.center(Offset.zero),
    );

    return _HeartFlight(
      id: ++_heartFlightSeed,
      start: overlayBox.globalToLocal(sourceGlobal),
      end: overlayBox.globalToLocal(targetGlobal),
    );
  }

  Future<void> _openDiscoverAreaSelector(
    List<BusinessDirectoryEntry> stores,
  ) async {
    final currentArea = _resolveDiscoverAreaLabel(
      stores,
      _selectedDiscoverArea,
    );
    final areas = _discoverAvailableAreas(stores);
    final selection = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) {
        final theme = Theme.of(context);
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Choose location',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Use your current area or switch the discover feed manually.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: _clientInactive.withValues(alpha: 0.72),
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 18),
                _DiscoverAreaOptionTile(
                  icon: TeamCashIcons.locate,
                  label: 'Use my location',
                  selected: _selectedDiscoverArea == null,
                  subtitle: currentArea,
                  onTap: () => Navigator.of(context).pop(_autoDiscoverAreaKey),
                ),
                for (final area in areas) ...[
                  const SizedBox(height: 10),
                  _DiscoverAreaOptionTile(
                    icon: TeamCashIcons.location,
                    label: area,
                    selected: _selectedDiscoverArea == area,
                    onTap: () => Navigator.of(context).pop(area),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
    if (!mounted || selection == null) {
      return;
    }
    setState(() {
      _selectedDiscoverArea = selection == _autoDiscoverAreaKey
          ? null
          : selection;
      _selectedHeaderTab = 0;
    });
  }
}

int _normalizeClientTabIndex(int? value, int fallback) {
  if (value == null) {
    return fallback;
  }
  if (value < 0) {
    return 0;
  }
  if (value > 3) {
    return 3;
  }
  return value;
}

int _normalizeDiscoverFilterIndex(int value, int length) {
  if (length <= 0) {
    return 0;
  }
  if (value < 0) {
    return 0;
  }
  if (value >= length) {
    return 0;
  }
  return value;
}

const _clientActiveBlue = Color(0xFF0088FF);
const _clientInactive = Color(0xFF484C52);
const _liquidTabInactive = Color(0xFF171717);
const _autoDiscoverAreaKey = '__auto_discover_area__';

void _touchLegacyClientSurfaces({
  required ClientWorkspace client,
  required CustomerIdentificationToken customerIdentityToken,
  required String? customerId,
  required bool canEditProfile,
  required bool canRunLiveTransferActions,
  required bool hasVerifiedPhoneClaimActions,
}) {
  assert(() {
    <Widget>[
      _StoresTab(stores: client.storeDirectory),
      _WalletTab(
        client: client,
        canRunLiveTransferActions: canRunLiveTransferActions,
        hasVerifiedPhoneClaimActions: hasVerifiedPhoneClaimActions,
        customerId: customerId,
      ),
      _HistoryTab(events: client.history),
      _ProfileTab(
        client: client,
        customerIdentityToken: customerIdentityToken,
        customerId: customerId,
        canEditProfile: canEditProfile,
      ),
    ];
    return true;
  }());
}

class _ClientMockHeader extends StatelessWidget {
  const _ClientMockHeader({
    required this.brandKey,
    required this.tabs,
    required this.selectedHeaderTab,
    required this.onHeaderTabSelected,
  });

  final GlobalKey brandKey;
  final List<_DiscoverFilterTab> tabs;
  final int selectedHeaderTab;
  final ValueChanged<int> onHeaderTabSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
      child: SizedBox(
        height: 48,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 18),
                child: _StaticFavoriteBrand(brandKey: brandKey),
              ),
              for (var index = 0; index < tabs.length; index++) ...[
                _MockHeaderChip(
                  label: tabs[index].label,
                  selected: index == selectedHeaderTab,
                  onTap: () => onHeaderTabSelected(index),
                ),
                if (index != tabs.length - 1) const SizedBox(width: 12),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StaticFavoriteBrand extends StatelessWidget {
  const _StaticFavoriteBrand({required this.brandKey});

  final GlobalKey brandKey;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: brandKey,
      width: 36,
      height: 36,
      child: Transform.rotate(
        angle: 0.7853981633974483,
        child: const Icon(
          TeamCashIcons.brand,
          size: 30,
          color: _clientActiveBlue,
        ),
      ),
    );
  }
}

class _HeartFlight {
  const _HeartFlight({
    required this.id,
    required this.start,
    required this.end,
  });

  final int id;
  final Offset start;
  final Offset end;
}

class _HeartFlightOverlay extends StatelessWidget {
  const _HeartFlightOverlay({required this.flight});

  final _HeartFlight flight;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      key: ValueKey('heart-flight-${flight.id}'),
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 760),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        final x = lerpDouble(flight.start.dx, flight.end.dx, value) ?? 0;
        final yBase = lerpDouble(flight.start.dy, flight.end.dy, value) ?? 0;
        final arcLift = lerpDouble(0, -34, (1 - (value - 0.5).abs() * 2)) ?? 0;
        final scale = value <= 0.5
            ? (lerpDouble(1.0, 2.0, value / 0.5) ?? 1.0)
            : (lerpDouble(2.0, 1.0, (value - 0.5) / 0.5) ?? 1.0);
        final opacity = value < 0.82
            ? 1.0
            : (1.0 - ((value - 0.82) / 0.18)).clamp(0.0, 1.0).toDouble();
        return Stack(
          children: [
            Positioned(
              left: x - 9,
              top: yBase + arcLift - 9,
              child: Opacity(
                opacity: opacity,
                child: Transform.scale(
                  scale: scale,
                  child: Transform.rotate(angle: -0.55 * value, child: child),
                ),
              ),
            ),
          ],
        );
      },
      child: const Icon(
        TeamCashIcons.heart,
        size: 18,
        color: _clientActiveBlue,
      ),
    );
  }
}

class _DiscoverAreaOptionTile extends StatelessWidget {
  const _DiscoverAreaOptionTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.subtitle,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          decoration: BoxDecoration(
            color: selected
                ? _clientActiveBlue.withValues(alpha: 0.08)
                : const Color(0xFFF8FAFD),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected
                  ? _clientActiveBlue.withValues(alpha: 0.22)
                  : _clientInactive.withValues(alpha: 0.10),
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 20,
                color: selected ? _clientActiveBlue : _clientInactive,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: const Color(0xFF111111),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: _clientInactive.withValues(alpha: 0.72),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : TeamCashIcons.chevronRight,
                size: 20,
                color: selected
                    ? _clientActiveBlue
                    : _clientInactive.withValues(alpha: 0.56),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MockHeaderChip extends StatelessWidget {
  const _MockHeaderChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? _clientActiveBlue : _liquidTabInactive;
    final borderRadius = BorderRadius.circular(999);

    return Material(
      color: Colors.white,
      borderRadius: borderRadius,
      child: InkWell(
        onTap: onTap,
        borderRadius: borderRadius,
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: borderRadius,
            border: Border.all(color: _clientInactive.withValues(alpha: 0.16)),
          ),
          child: SizedBox(
            height: 48,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 21),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Transform.rotate(
                    angle: 0.7853981633974483,
                    child: Icon(TeamCashIcons.brand, size: 16, color: color),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w600,
                      fontSize: 17,
                      height: 20 / 17,
                      letterSpacing: -0.1,
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

// ignore: unused_element
class _DiscoverMockTab extends StatelessWidget {
  const _DiscoverMockTab({
    required this.client,
    required this.selectedHeaderLabel,
    required this.activePartnerCount,
    required this.incomingPendingAmount,
    required this.expiringLotsCount,
    required this.greeting,
  });

  final ClientWorkspace client;
  final String selectedHeaderLabel;
  final int activePartnerCount;
  final int incomingPendingAmount;
  final int expiringLotsCount;
  final String greeting;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      key: const ValueKey('legacy-client-discover-mock'),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      children: [
        Text(
          greeting,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: _clientInactive.withValues(alpha: 0.72),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '$selectedHeaderLabel picks',
          style: theme.textTheme.headlineMedium?.copyWith(
            color: const Color(0xFF111111),
            fontWeight: FontWeight.w800,
            letterSpacing: -1,
          ),
        ),
        const SizedBox(height: 18),
        _MockWhiteCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Together wallet',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: _clientInactive.withValues(alpha: 0.8),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                formatCurrency(client.totalWalletBalance),
                style: theme.textTheme.displaySmall?.copyWith(
                  color: const Color(0xFF111111),
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1.4,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: _MockMetric(
                      label: 'Partners',
                      value: '$activePartnerCount',
                    ),
                  ),
                  Expanded(
                    child: _MockMetric(
                      label: 'Pending',
                      value: formatCurrency(incomingPendingAmount),
                    ),
                  ),
                  Expanded(
                    child: _MockMetric(
                      label: 'Expiring',
                      value: '$expiringLotsCount lots',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _MockWhiteCard(
                child: _MiniMockPanel(
                  title: 'Nearby',
                  subtitle: '${client.storeDirectory.length} places ready',
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MockWhiteCard(
                child: _MiniMockPanel(
                  title: 'Trending',
                  subtitle: 'Mock content for $selectedHeaderLabel',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _MockWhiteCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Featured cards',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: const Color(0xFF111111),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 14),
              for (final title in [
                'Mock partner highlight',
                'Seasonal offer preview',
                'Pinned category collection',
              ]) ...[
                _MockListTile(
                  title: title,
                  subtitle: 'Dynamic data keyin ulanadi',
                ),
                if (title != 'Pinned category collection')
                  const SizedBox(height: 10),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _QrCodeMockTab extends StatelessWidget {
  const _QrCodeMockTab({super.key, required this.customerIdentityToken});

  final CustomerIdentificationToken customerIdentityToken;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      key: key,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      children: [
        Text(
          'QR Code',
          style: theme.textTheme.headlineMedium?.copyWith(
            color: const Color(0xFF111111),
            fontWeight: FontWeight.w800,
            letterSpacing: -1,
          ),
        ),
        const SizedBox(height: 18),
        _MockWhiteCard(
          child: Column(
            children: [
              Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  color: const Color(0xFFF7F8FA),
                  borderRadius: BorderRadius.circular(30),
                ),
                alignment: Alignment.center,
                child: Icon(
                  TeamCashIcons.qrCode,
                  size: 86,
                  color: _clientInactive.withValues(alpha: 0.78),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Client identity mock',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: const Color(0xFF111111),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                customerIdentityToken.customerId,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: _clientInactive.withValues(alpha: 0.72),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProfileMockTab extends StatelessWidget {
  const _ProfileMockTab({
    super.key,
    required this.client,
    required this.canRunLiveTransfers,
    required this.hasVerifiedPhoneClaimActions,
    required this.session,
  });

  final ClientWorkspace client;
  final bool canRunLiveTransfers;
  final bool hasVerifiedPhoneClaimActions;
  final AppSession? session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      key: key,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      children: [
        Text(
          'Profile',
          style: theme.textTheme.headlineMedium?.copyWith(
            color: const Color(0xFF111111),
            fontWeight: FontWeight.w800,
            letterSpacing: -1,
          ),
        ),
        const SizedBox(height: 18),
        _MockWhiteCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                client.clientName,
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: const Color(0xFF111111),
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                client.phoneNumber,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: _clientInactive.withValues(alpha: 0.72),
                ),
              ),
              const SizedBox(height: 16),
              _MockListTile(
                title: 'Account mode',
                subtitle: session?.isPreview == false ? 'Live' : 'Preview',
              ),
              const SizedBox(height: 10),
              _MockListTile(
                title: 'Wallet sync',
                subtitle: canRunLiveTransfers ? 'Connected' : 'Mock ready',
              ),
              const SizedBox(height: 10),
              _MockListTile(
                title: 'Phone claim',
                subtitle: hasVerifiedPhoneClaimActions
                    ? 'Verified'
                    : 'Pending setup',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ChatMockTab extends StatelessWidget {
  const _ChatMockTab({
    super.key,
    required this.unreadNotificationsCount,
    required this.notifications,
    required this.onOpenInbox,
  });

  final int unreadNotificationsCount;
  final List<AppNotificationItem> notifications;
  final VoidCallback onOpenInbox;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final previewItems = notifications.take(3).toList();

    return ListView(
      key: key,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      children: [
        Text(
          'Chat',
          style: theme.textTheme.headlineMedium?.copyWith(
            color: const Color(0xFF111111),
            fontWeight: FontWeight.w800,
            letterSpacing: -1,
          ),
        ),
        const SizedBox(height: 18),
        _MockWhiteCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _MockListTile(
                title: 'Inbox',
                subtitle: unreadNotificationsCount > 0
                    ? '$unreadNotificationsCount unread updates'
                    : 'No unread updates right now',
              ),
              const SizedBox(height: 14),
              FilledButton(
                onPressed: onOpenInbox,
                style: FilledButton.styleFrom(
                  backgroundColor: _clientActiveBlue,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Open inbox'),
              ),
            ],
          ),
        ),
        if (previewItems.isNotEmpty) ...[
          const SizedBox(height: 16),
          for (final notification in previewItems) ...[
            _MockWhiteCard(
              child: _MockListTile(
                title: notification.title,
                subtitle: notification.body,
              ),
            ),
            if (notification != previewItems.last) const SizedBox(height: 12),
          ],
        ],
      ],
    );
  }
}

class _MockWhiteCard extends StatelessWidget {
  const _MockWhiteCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _MiniMockPanel extends StatelessWidget {
  const _MiniMockPanel({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(TeamCashIcons.brand, size: 24, color: _clientActiveBlue),
        const SizedBox(height: 14),
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            color: const Color(0xFF111111),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: theme.textTheme.bodySmall?.copyWith(
            color: _clientInactive.withValues(alpha: 0.72),
          ),
        ),
      ],
    );
  }
}

class _MockMetric extends StatelessWidget {
  const _MockMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: _clientInactive.withValues(alpha: 0.72),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            color: const Color(0xFF111111),
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _MockListTile extends StatelessWidget {
  const _MockListTile({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: const Color(0xFFF5F7FA),
            borderRadius: BorderRadius.circular(14),
          ),
          alignment: Alignment.center,
          child: const Icon(
            TeamCashIcons.brand,
            size: 18,
            color: _clientActiveBlue,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: const Color(0xFF111111),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: _clientInactive.withValues(alpha: 0.72),
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ClientMockBottomBar extends StatelessWidget {
  const _ClientMockBottomBar({
    required this.selectedIndex,
    required this.onSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 14),
        child: Row(
          children: [
            _BottomNavItem(
              label: 'Discover',
              icon: TeamCashIcons.discover,
              selected: selectedIndex == 0,
              onTap: () => onSelected(0),
            ),
            _BottomNavItem(
              label: 'QR Code',
              icon: TeamCashIcons.qrCode,
              selected: selectedIndex == 1,
              onTap: () => onSelected(1),
            ),
            _BottomNavItem(
              label: 'Profile',
              icon: TeamCashIcons.profile,
              selected: selectedIndex == 2,
              onTap: () => onSelected(2),
            ),
            _BottomNavItem(
              label: 'Chat',
              icon: TeamCashIcons.chat,
              selected: selectedIndex == 3,
              onTap: () => onSelected(3),
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomNavItem extends StatelessWidget {
  const _BottomNavItem({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? _clientActiveBlue : _clientInactive;

    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(height: 6),
              Text(
                label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
