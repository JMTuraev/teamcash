part of 'client_shell.dart';

class _DiscoverFilterTab {
  const _DiscoverFilterTab({required this.id, required this.label});

  final String id;
  final String label;

  bool matches(BusinessDirectoryEntry store) {
    if (id == 'all') {
      return true;
    }
    return _discoverCategoryKey(store.category) == id;
  }
}

class _DiscoverBusinessCardData {
  const _DiscoverBusinessCardData({
    required this.store,
    required this.earnedClientsCount,
    required this.totalCashbackEarned,
    required this.teamBusinesses,
  });

  final BusinessDirectoryEntry store;
  final int earnedClientsCount;
  final int totalCashbackEarned;
  final List<BusinessDirectoryEntry> teamBusinesses;

  factory _DiscoverBusinessCardData.fromStore({
    required BusinessDirectoryEntry store,
    required List<BusinessDirectoryEntry> allStores,
  }) {
    return _DiscoverBusinessCardData(
      store: store,
      earnedClientsCount: _mockEarnedClientsCount(store),
      totalCashbackEarned: _mockTotalCashbackEarned(store),
      teamBusinesses: _teamBusinessesForStore(store, allStores),
    );
  }
}

List<_DiscoverFilterTab> _buildDiscoverFilterTabs(
  List<BusinessDirectoryEntry> stores,
) {
  final nearStores = _storesNearClientArea(stores, _discoverAreaLabel(stores));
  final seen = <String>{};
  final dynamicKeys = <String>[];

  for (final store in nearStores) {
    final key = _discoverCategoryKey(store.category);
    if (seen.add(key)) {
      dynamicKeys.add(key);
    }
  }

  const preferredOrder = [
    'coffee',
    'bakery',
    'beauty',
    'clinic',
    'market',
    'other',
  ];
  dynamicKeys.sort((left, right) {
    final leftIndex = preferredOrder.indexOf(left);
    final rightIndex = preferredOrder.indexOf(right);
    final normalizedLeftIndex = leftIndex == -1
        ? preferredOrder.length
        : leftIndex;
    final normalizedRightIndex = rightIndex == -1
        ? preferredOrder.length
        : rightIndex;
    if (normalizedLeftIndex != normalizedRightIndex) {
      return normalizedLeftIndex.compareTo(normalizedRightIndex);
    }
    return _discoverCategoryLabel(
      left,
    ).compareTo(_discoverCategoryLabel(right));
  });

  return [
    const _DiscoverFilterTab(id: 'all', label: 'All'),
    for (final key in dynamicKeys)
      _DiscoverFilterTab(id: key, label: _discoverCategoryLabel(key)),
  ];
}

String _discoverAreaLabel(List<BusinessDirectoryEntry> stores) {
  final counters = <String, int>{};
  for (final store in stores) {
    final area = _extractAreaLabel(store.address);
    if (area.isEmpty) {
      continue;
    }
    counters.update(area, (value) => value + 1, ifAbsent: () => 1);
  }
  if (counters.isEmpty) {
    return 'Nearby';
  }
  final ordered = counters.entries.toList()
    ..sort((left, right) => right.value.compareTo(left.value));
  return ordered.first.key;
}

String _resolveDiscoverAreaLabel(
  List<BusinessDirectoryEntry> stores,
  String? preferredArea,
) {
  if (preferredArea == null) {
    return _discoverAreaLabel(stores);
  }
  final availableAreas = _discoverAvailableAreas(stores);
  if (availableAreas.contains(preferredArea)) {
    return preferredArea;
  }
  return _discoverAreaLabel(stores);
}

List<String> _discoverAvailableAreas(List<BusinessDirectoryEntry> stores) {
  final areas =
      stores
          .map((store) => _extractAreaLabel(store.address))
          .where((area) => area.isNotEmpty)
          .toSet()
          .toList()
        ..sort();
  return areas;
}

List<BusinessDirectoryEntry> _storesNearClientArea(
  List<BusinessDirectoryEntry> stores,
  String areaLabel,
) {
  final matchingStores = stores
      .where((store) => _extractAreaLabel(store.address) == areaLabel)
      .toList();
  return matchingStores.isEmpty ? stores : matchingStores;
}

String _extractAreaLabel(String address) {
  final parts = address
      .split(',')
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .toList();
  if (parts.isEmpty) {
    return '';
  }
  return parts.last;
}

String _discoverCategoryKey(String rawCategory) {
  final normalized = rawCategory.trim().toLowerCase();
  if (normalized.contains('cafe') ||
      normalized.contains('coffee') ||
      normalized.contains('bar')) {
    return 'coffee';
  }
  if (normalized.contains('salon') || normalized.contains('beauty')) {
    return 'beauty';
  }
  if (normalized.contains('clinic') || normalized.contains('dental')) {
    return 'clinic';
  }
  if (normalized.contains('bakery') ||
      normalized.contains('pastry') ||
      normalized.contains('bread')) {
    return 'bakery';
  }
  if (normalized.contains('market') || normalized.contains('shop')) {
    return 'market';
  }
  return normalized.isEmpty ? 'other' : normalized;
}

String _discoverCategoryLabel(String categoryKey) {
  return switch (categoryKey) {
    'all' => 'All',
    'coffee' => 'Coffee',
    'beauty' => 'Beauty',
    'clinic' => 'Clinic',
    'bakery' => 'Bakery',
    'market' => 'Market',
    'other' => 'Other',
    _ => _capitalize(categoryKey),
  };
}

String _capitalize(String value) {
  if (value.isEmpty) {
    return value;
  }
  return '${value[0].toUpperCase()}${value.substring(1)}';
}

int _mockEarnedClientsCount(BusinessDirectoryEntry store) {
  final signal =
      store.name.runes.fold<int>(0, (sum, rune) => sum + rune) +
      store.locationsCount * 19 +
      store.productsCount * 11 +
      store.servicesCount * 13 +
      store.cashbackBasisPoints;
  return 24 + signal % 170;
}

int _mockTotalCashbackEarned(BusinessDirectoryEntry store) {
  final clients = _mockEarnedClientsCount(store);
  final averageTicket =
      90000 +
      store.productsCount * 14000 +
      store.servicesCount * 19000 +
      store.locationsCount * 12000;
  return clients * averageTicket * store.cashbackBasisPoints ~/ 10000;
}

List<BusinessDirectoryEntry> _teamBusinessesForStore(
  BusinessDirectoryEntry store,
  List<BusinessDirectoryEntry> stores,
) {
  final siblings =
      stores
          .where(
            (candidate) =>
                candidate.id != store.id &&
                candidate.groupName.trim().isNotEmpty &&
                candidate.groupName == store.groupName,
          )
          .toList()
        ..sort((left, right) {
          if (left.groupStatus != right.groupStatus) {
            return left.groupStatus.index.compareTo(right.groupStatus.index);
          }
          return left.name.compareTo(right.name);
        });
  return siblings;
}

class _ClientDiscoverTab extends StatelessWidget {
  const _ClientDiscoverTab({
    super.key,
    required this.client,
    required this.discoverTabs,
    required this.selectedFilterIndex,
    required this.selectedAreaLabel,
    required this.hasManualAreaSelection,
    required this.favoriteBusinessIds,
    required this.onOpenAreaSelector,
    required this.onToggleFavorite,
  });

  final ClientWorkspace client;
  final List<_DiscoverFilterTab> discoverTabs;
  final int selectedFilterIndex;
  final String selectedAreaLabel;
  final bool hasManualAreaSelection;
  final Set<String> favoriteBusinessIds;
  final VoidCallback onOpenAreaSelector;
  final void Function(String, BuildContext) onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final areaLabel = selectedAreaLabel;
    final nearbyStores = _storesNearClientArea(
      client.storeDirectory,
      areaLabel,
    );
    final activeTab = discoverTabs[selectedFilterIndex];
    final filteredStores = nearbyStores.where(activeTab.matches).toList()
      ..sort(
        (left, right) => _mockEarnedClientsCount(
          right,
        ).compareTo(_mockEarnedClientsCount(left)),
      );
    final cards = filteredStores
        .map(
          (store) => _DiscoverBusinessCardData.fromStore(
            store: store,
            allStores: nearbyStores,
          ),
        )
        .toList();

    return ListView(
      key: key,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        Row(
          children: [
            Text(
              areaLabel,
              style: theme.textTheme.headlineMedium?.copyWith(
                color: const Color(0xFF111111),
                fontWeight: FontWeight.w800,
                letterSpacing: -1,
              ),
            ),
            const SizedBox(width: 10),
            _DiscoverLocationButton(
              label: hasManualAreaSelection ? 'Change' : 'Use location',
              onTap: onOpenAreaSelector,
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (cards.isEmpty)
          _MockWhiteCard(
            child: Text(
              'No businesses in this area yet.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: _clientInactive.withValues(alpha: 0.72),
                height: 1.45,
              ),
            ),
          )
        else ...[
          for (var index = 0; index < cards.length; index++) ...[
            _DiscoverBusinessCard(
              data: cards[index],
              isFavorite: favoriteBusinessIds.contains(cards[index].store.id),
              onToggleFavorite: (buttonContext) =>
                  onToggleFavorite(cards[index].store.id, buttonContext),
            ),
            if (index != cards.length - 1) const SizedBox(height: 16),
          ],
        ],
      ],
    );
  }
}

class _DiscoverBusinessCard extends StatelessWidget {
  const _DiscoverBusinessCard({
    required this.data,
    required this.isFavorite,
    required this.onToggleFavorite,
  });

  final _DiscoverBusinessCardData data;
  final bool isFavorite;
  final ValueChanged<BuildContext> onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    const imageHeight = 210.0;
    final mediaUrl = _businessMediaUrl(data.store);
    final mockAssetPath = _mockBusinessPhotoAsset(data.store);
    final totalTeamCount = data.teamBusinesses.length + 1;
    final totalCashbackLabel =
        '+ ${_formatCompactCurrency(data.totalCashbackEarned)}';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => context.push('/client/business/${data.store.id}'),
        borderRadius: BorderRadius.circular(30),
        child: Container(
          height: 266,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            boxShadow: const [
              BoxShadow(
                color: Color(0x16000000),
                blurRadius: 28,
                offset: Offset(0, 14),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(30),
            child: Stack(
              children: [
                Column(
                  children: [
                    SizedBox(
                      height: imageHeight,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          _BusinessVisualSurface(
                            mediaUrl: mediaUrl,
                            mockAssetPath: mockAssetPath,
                          ),
                          DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.black.withValues(alpha: 0.18),
                                  Colors.black.withValues(alpha: 0.26),
                                  Colors.black.withValues(alpha: 0.46),
                                ],
                                stops: const [0, 0.42, 1],
                              ),
                            ),
                          ),
                          Positioned.fill(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(
                                16,
                                16,
                                16,
                                14,
                              ),
                              child: Column(
                                children: [
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          data.store.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: _discoverOverlayTextStyle(
                                            Theme.of(
                                              context,
                                            ).textTheme.headlineSmall?.copyWith(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: -0.7,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Text(
                                        formatPercent(
                                          data.store.cashbackBasisPoints,
                                        ),
                                        style: _discoverOverlayTextStyle(
                                          Theme.of(
                                            context,
                                          ).textTheme.titleMedium?.copyWith(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: -0.2,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const Spacer(),
                                  Align(
                                    alignment: Alignment.bottomRight,
                                    child: Text(
                                      totalCashbackLabel,
                                      style: _discoverOverlayTextStyle(
                                        Theme.of(
                                          context,
                                        ).textTheme.labelLarge?.copyWith(
                                          color: const Color(0xFF49A1FF),
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: -0.2,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Container(
                        color: Colors.white,
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                        child: Row(
                          children: [
                            _DiscoverFooterMetric(
                              icon: TeamCashIcons.person,
                              value: '${data.earnedClientsCount}',
                            ),
                            const SizedBox(width: 18),
                            _DiscoverFooterMetric(
                              icon: TeamCashIcons.hub,
                              value: '$totalTeamCount',
                            ),
                            const Spacer(),
                            _DiscoverFavoriteButton(
                              selected: isFavorite,
                              onTap: onToggleFavorite,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _businessMediaUrl(BusinessDirectoryEntry store) {
  if (store.coverImageUrl.trim().isNotEmpty) {
    return store.coverImageUrl.trim();
  }
  final featuredUrl = store.featuredMedia
      .map((media) => media.imageUrl.trim())
      .firstWhere((url) => url.isNotEmpty, orElse: () => '');
  if (featuredUrl.isNotEmpty) {
    return featuredUrl;
  }
  return '';
}

String _mockBusinessPhotoAsset(BusinessDirectoryEntry store) {
  const byId = <String, String>{
    'silk-road-cafe': 'assets/images/discover/coffee.jpg',
    'cedar-studio': 'assets/images/discover/salon.jpg',
    'atlas-dental': 'assets/images/discover/clinic.jpg',
    'bread-and-ember': 'assets/images/discover/bakery.jpg',
  };
  final direct = byId[store.id];
  if (direct != null) {
    return direct;
  }
  return switch (_discoverCategoryKey(store.category)) {
    'coffee' => 'assets/images/discover/coffee.jpg',
    'beauty' => 'assets/images/discover/salon.jpg',
    'clinic' => 'assets/images/discover/clinic.jpg',
    'bakery' => 'assets/images/discover/bakery.jpg',
    'market' => 'assets/images/discover/market.jpg',
    _ => 'assets/images/discover/coffee.jpg',
  };
}

String _formatCompactCurrency(int amount) {
  if (amount >= 1000000) {
    final compact = amount / 1000000;
    final value = compact.truncateToDouble() == compact
        ? compact.toStringAsFixed(0)
        : compact.toStringAsFixed(1);
    return 'UZS ${value}M';
  }
  if (amount >= 1000) {
    return 'UZS ${(amount / 1000).round()}K';
  }
  return formatCurrency(amount);
}

TextStyle? _discoverOverlayTextStyle(TextStyle? baseStyle) {
  return baseStyle?.copyWith(
    shadows: const [
      Shadow(color: Color(0x40000000), blurRadius: 10, offset: Offset(0, 2)),
    ],
  );
}

class _DiscoverLocationButton extends StatelessWidget {
  const _DiscoverLocationButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFF6F8FB),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: _clientInactive.withValues(alpha: 0.12)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                TeamCashIcons.location,
                size: 16,
                color: _clientActiveBlue,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: _clientInactive,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                TeamCashIcons.chevronDown,
                size: 18,
                color: _clientInactive.withValues(alpha: 0.76),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DiscoverFooterMetric extends StatelessWidget {
  const _DiscoverFooterMetric({required this.icon, required this.value});

  final IconData icon;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 17, color: _clientActiveBlue),
        const SizedBox(width: 7),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: const Color(0xFF111111),
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _DiscoverFavoriteButton extends StatelessWidget {
  const _DiscoverFavoriteButton({required this.selected, required this.onTap});

  final bool selected;
  final ValueChanged<BuildContext> onTap;

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (buttonContext) {
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => onTap(buttonContext),
            borderRadius: BorderRadius.circular(999),
            child: Ink(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: const Color(0xFFF6F8FB),
                shape: BoxShape.circle,
                border: Border.all(
                  color: _clientInactive.withValues(alpha: 0.12),
                ),
              ),
              child: Center(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  transitionBuilder: (child, animation) {
                    return ScaleTransition(scale: animation, child: child);
                  },
                  child: Icon(
                    selected ? TeamCashIcons.heart : TeamCashIcons.heartOutline,
                    key: ValueKey(selected),
                    size: 18,
                    color: selected
                        ? _clientActiveBlue
                        : _clientInactive.withValues(alpha: 0.72),
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

class _BusinessVisualSurface extends StatelessWidget {
  const _BusinessVisualSurface({
    required this.mediaUrl,
    required this.mockAssetPath,
  });

  final String mediaUrl;
  final String mockAssetPath;

  @override
  Widget build(BuildContext context) {
    final fallback = Image.asset(mockAssetPath, fit: BoxFit.cover);
    if (mediaUrl.isNotEmpty) {
      return Image.network(
        mediaUrl,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => fallback,
      );
    }
    return fallback;
  }
}
