part of 'client_shell.dart';

enum _ClientStoreFilter { all, active, pending }

class _StoresTab extends StatefulWidget {
  const _StoresTab({required this.stores});

  final List<BusinessDirectoryEntry> stores;

  @override
  State<_StoresTab> createState() => _StoresTabState();
}

class _StoresTabState extends State<_StoresTab> {
  _ClientStoreFilter _selectedFilter = _ClientStoreFilter.all;
  int _activePage = 0;

  @override
  Widget build(BuildContext context) {
    final filteredStores = widget.stores
        .where((store) => _matchesStoreFilter(store, _selectedFilter))
        .toList();
    if (_activePage >= filteredStores.length && filteredStores.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        setState(() {
          _activePage = 0;
        });
      });
    }

    return SizedBox.expand(
      child: SectionCard(
        key: const ValueKey('client-stores-section'),
        title: 'Partner businesses',
        subtitle:
            'Critical UX fix: one business at a time is easier to compare on mobile than a long marketplace feed.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SegmentedChoice<_ClientStoreFilter>(
              value: _selectedFilter,
              items: _ClientStoreFilter.values
                  .map(
                    (filter) => SegmentedChoiceItem<_ClientStoreFilter>(
                      value: filter,
                      label: _labelForStoreFilter(filter),
                    ),
                  )
                  .toList(),
              onChanged: (filter) {
                setState(() {
                  _selectedFilter = filter;
                  _activePage = 0;
                });
              },
            ),
            const SizedBox(height: 12),
            Text(
              '${filteredStores.length} businesses in this view',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 300,
              child: filteredStores.isEmpty
                  ? const Center(
                      child: ListTile(
                        key: ValueKey('client-store-empty-state'),
                        contentPadding: EdgeInsets.zero,
                        title: Text('No stores in this filter'),
                        subtitle: Text(
                          'Switch the partner group filter to see more businesses.',
                        ),
                      ),
                    )
                  : _CompactStoreCard(
                      key: ValueKey(
                        'client-store-card-${filteredStores[_activePage].id}',
                      ),
                      store: filteredStores[_activePage],
                    ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                IconButton(
                  onPressed: filteredStores.isNotEmpty && _activePage > 0
                      ? () {
                          setState(() {
                            _activePage -= 1;
                          });
                        }
                      : null,
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
                ),
                Expanded(
                  child: PagerDots(
                    count: filteredStores.length,
                    activeIndex: _activePage,
                  ),
                ),
                IconButton(
                  onPressed:
                      filteredStores.isNotEmpty &&
                          _activePage < filteredStores.length - 1
                      ? () {
                          setState(() {
                            _activePage += 1;
                          });
                        }
                      : null,
                  icon: const Icon(Icons.arrow_forward_ios_rounded, size: 18),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  bool _matchesStoreFilter(
    BusinessDirectoryEntry store,
    _ClientStoreFilter filter,
  ) {
    switch (filter) {
      case _ClientStoreFilter.all:
        return true;
      case _ClientStoreFilter.active:
        return store.groupStatus == GroupMembershipStatus.active;
      case _ClientStoreFilter.pending:
        return store.groupStatus == GroupMembershipStatus.pendingApproval;
    }
  }

  String _labelForStoreFilter(_ClientStoreFilter filter) {
    return switch (filter) {
      _ClientStoreFilter.all => 'All',
      _ClientStoreFilter.active => 'Active',
      _ClientStoreFilter.pending => 'Pending',
    };
  }
}

// ignore: unused_element
class _StoreTile extends StatelessWidget {
  const _StoreTile({required this.store});

  final BusinessDirectoryEntry store;

  @override
  Widget build(BuildContext context) {
    final status = switch (store.groupStatus) {
      GroupMembershipStatus.active => (
        label: 'Active',
        background: const Color(0xFFE8FBF4),
        foreground: const Color(0xFF2CB991),
      ),
      GroupMembershipStatus.pendingApproval => (
        label: 'Pending',
        background: const Color(0xFFFFF3DF),
        foreground: const Color(0xFFF29C38),
      ),
      GroupMembershipStatus.rejected => (
        label: 'Rejected',
        background: const Color(0xFFFFE8EA),
        foreground: const Color(0xFFE56874),
      ),
      GroupMembershipStatus.notGrouped => (
        label: 'Not grouped',
        background: const Color(0xFFEFF2FF),
        foreground: const Color(0xFF6374FF),
      ),
    };
    final primaryLocation = store.locations.isEmpty
        ? null
        : store.locations.first;
    final mediaUrl = store.coverImageUrl.trim().isNotEmpty
        ? store.coverImageUrl
        : store.featuredMedia
              .map((media) => media.imageUrl.trim())
              .firstWhere((url) => url.isNotEmpty, orElse: () => '');

    return Container(
      key: ValueKey('client-store-${store.id}'),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFE4E8F7)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x15444EA4),
            blurRadius: 28,
            offset: Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
                child: AspectRatio(
                  aspectRatio: 1.55,
                  child: mediaUrl.isNotEmpty
                      ? Image.network(
                          mediaUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              _StoreCoverFallback(category: store.category),
                        )
                      : _StoreCoverFallback(category: store.category),
                ),
              ),
              Positioned(
                top: 14,
                right: 14,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF45C1B2),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${formatPercent(store.cashbackBasisPoints)} back',
                    style: Theme.of(
                      context,
                    ).textTheme.labelLarge?.copyWith(color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        store.name,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    StatusPill(
                      label: status.label,
                      backgroundColor: status.background,
                      foregroundColor: status.foreground,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  store.category,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: const Color(0xFF8A91B1),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  store.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    Chip(label: Text(store.workingHours)),
                    Chip(
                      label: Text(
                        '${store.productsCount + store.servicesCount} offers',
                      ),
                    ),
                    if (primaryLocation != null)
                      Chip(label: Text(primaryLocation.name)),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    const Icon(
                      Icons.location_on_outlined,
                      size: 18,
                      color: Color(0xFF8A91B1),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        store.address,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                FilledButton.tonalIcon(
                  key: ValueKey('client-store-open-details-${store.id}'),
                  onPressed: () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    useSafeArea: true,
                    builder: (context) => _StoreDetailSheet(store: store),
                  ),
                  icon: const Icon(Icons.menu_book_outlined),
                  label: const Text('View Full Details'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactStoreCard extends StatelessWidget {
  const _CompactStoreCard({super.key, required this.store});

  final BusinessDirectoryEntry store;

  @override
  Widget build(BuildContext context) {
    final mediaUrl = store.coverImageUrl.trim().isNotEmpty
        ? store.coverImageUrl
        : store.featuredMedia
              .map((media) => media.imageUrl.trim())
              .firstWhere((url) => url.isNotEmpty, orElse: () => '');
    final totalOffers = store.productsCount + store.servicesCount;
    void openDetails() {
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (context) => _StoreDetailSheet(store: store),
      );
    }

    return GestureDetector(
      onTap: openDetails,
      behavior: HitTestBehavior.opaque,
      child: Container(
        key: ValueKey('client-store-${store.id}'),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: const Color(0xFFE4E8F7)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              key: ValueKey('client-store-open-details-${store.id}'),
              onTap: openDetails,
              behavior: HitTestBehavior.opaque,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: SizedBox(
                  height: 124,
                  child: mediaUrl.isNotEmpty
                      ? Image.network(
                          mediaUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              _StoreCoverFallback(category: store.category),
                        )
                      : _StoreCoverFallback(category: store.category),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    store.name,
                    style: Theme.of(context).textTheme.titleLarge,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                StatusPill(
                  label: formatPercent(store.cashbackBasisPoints),
                  backgroundColor: const Color(0xFFE8FBF4),
                  foregroundColor: const Color(0xFF2CB991),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${store.category} • ${store.groupName}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Text(
              store.description,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: CompactStatTile(
                    label: 'Offers',
                    value: '$totalOffers',
                    tint: const Color(0xFF6474FF),
                    icon: Icons.shopping_bag_outlined,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: CompactStatTile(
                    label: 'Hours',
                    value: store.workingHours,
                    tint: const Color(0xFFFF8C6B),
                    icon: Icons.schedule_outlined,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: openDetails,
              icon: const Icon(Icons.menu_book_outlined),
              label: const Text('View Full Details'),
            ),
          ],
        ),
      ),
    );
  }
}

class _StoreCoverFallback extends StatelessWidget {
  const _StoreCoverFallback({required this.category});

  final String category;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFE7EBFF), Color(0xFFF7FAFF), Color(0xFFEAFBF6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -18,
            top: -10,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: const Color(0xFF6678FF).withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.storefront_outlined,
                  size: 42,
                  color: Color(0xFF6374FF),
                ),
                const SizedBox(height: 10),
                Text(
                  category,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: const Color(0xFF4B59A8),
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

class _StoreDetailSheet extends StatelessWidget {
  const _StoreDetailSheet({required this.store});

  final BusinessDirectoryEntry store;

  @override
  Widget build(BuildContext context) {
    final hasCoverImage = store.coverImageUrl.trim().isNotEmpty;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.88,
      maxChildSize: 0.96,
      minChildSize: 0.6,
      builder: (context, scrollController) => Material(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: ListView(
          key: ValueKey('client-store-detail-sheet-${store.id}'),
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
          children: [
            Center(
              child: Container(
                width: 56,
                height: 5,
                decoration: BoxDecoration(
                  color: const Color(0xFFD6E4DD),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(store.name, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              '${store.category} • ${formatPercent(store.cashbackBasisPoints)} cashback',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(color: const Color(0xFF2455A6)),
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: Container(
                height: 220,
                color: const Color(0xFFEAF2EE),
                child: hasCoverImage
                    ? Image.network(
                        store.coverImageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            const _StoreMediaFallback(mediaType: 'cover'),
                      )
                    : const _StoreMediaFallback(mediaType: 'cover'),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              store.description,
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(color: const Color(0xFF52606D)),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                Chip(label: Text(store.workingHours)),
                Chip(label: Text(store.groupName)),
                Chip(label: Text(store.redeemPolicy)),
              ],
            ),
            if (store.phoneNumbers.isNotEmpty) ...[
              const SizedBox(height: 18),
              _StoreDetailBlock(
                key: ValueKey('client-store-detail-contact-${store.id}'),
                title: 'Contact',
                lines: [store.address, ...store.phoneNumbers],
              ),
            ],
            if (store.locations.isNotEmpty) ...[
              const SizedBox(height: 18),
              _StoreDetailBlock(
                key: ValueKey('client-store-detail-locations-${store.id}'),
                title: 'All locations',
                lines: store.locations
                    .map(
                      (location) =>
                          '${location.name} • ${location.address} • ${location.workingHours}',
                    )
                    .toList(),
              ),
            ],
            if (store.products.isNotEmpty) ...[
              const SizedBox(height: 18),
              _StoreDetailBlock(
                key: ValueKey('client-store-detail-products-${store.id}'),
                title: 'Full product list',
                lines: store.products
                    .map(
                      (product) =>
                          '${product.name}${product.priceLabel.trim().isEmpty ? '' : ' • ${product.priceLabel}'}',
                    )
                    .toList(),
              ),
            ],
            if (store.services.isNotEmpty) ...[
              const SizedBox(height: 18),
              _StoreDetailBlock(
                key: ValueKey('client-store-detail-services-${store.id}'),
                title: 'Full service list',
                lines: store.services
                    .map(
                      (service) =>
                          '${service.name}${service.priceLabel.trim().isEmpty ? '' : ' • ${service.priceLabel}'}',
                    )
                    .toList(),
              ),
            ],
            if (store.featuredMedia.isNotEmpty) ...[
              const SizedBox(height: 18),
              _StoreMediaStrip(
                storeId: '${store.id}-detail',
                media: store.featuredMedia,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StoreMediaStrip extends StatelessWidget {
  const _StoreMediaStrip({required this.storeId, required this.media});

  final String storeId;
  final List<BusinessMediaSummary> media;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: ValueKey('client-store-media-$storeId'),
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F4EE),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Portfolio', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Text(
            'Media from the live business gallery so clients can preview the storefront before visiting.',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF52606D)),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: media
                .map(
                  (entry) => SizedBox(
                    width: 170,
                    child: _StoreMediaCard(storeId: storeId, media: entry),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _StoreMediaCard extends StatelessWidget {
  const _StoreMediaCard({required this.storeId, required this.media});

  final String storeId;
  final BusinessMediaSummary media;

  @override
  Widget build(BuildContext context) {
    final hasImage = media.imageUrl.trim().isNotEmpty;

    return Container(
      key: ValueKey('client-store-media-item-$storeId-${media.id}'),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE6DED1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: AspectRatio(
              aspectRatio: 4 / 3,
              child: hasImage
                  ? Image.network(
                      media.imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          _StoreMediaFallback(mediaType: media.mediaType),
                    )
                  : _StoreMediaFallback(mediaType: media.mediaType),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  media.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              if (media.isFeatured)
                const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Icon(
                    Icons.star_rounded,
                    size: 18,
                    color: Color(0xFF1B7F5B),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            media.mediaType,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: const Color(0xFF2455A6),
              fontWeight: FontWeight.w700,
            ),
          ),
          if (media.caption.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              media.caption,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: const Color(0xFF52606D)),
            ),
          ],
        ],
      ),
    );
  }
}

class _StoreMediaFallback extends StatelessWidget {
  const _StoreMediaFallback({required this.mediaType});

  final String mediaType;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFEAF2EE),
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.photo_library_outlined, color: Color(0xFF6B7280)),
          const SizedBox(height: 8),
          Text(
            mediaType,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: const Color(0xFF52606D)),
          ),
        ],
      ),
    );
  }
}

class _StoreDetailBlock extends StatelessWidget {
  const _StoreDetailBlock({
    super.key,
    required this.title,
    required this.lines,
  });

  final String title;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F4EE),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          ...lines.map(
            (line) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(line),
            ),
          ),
        ],
      ),
    );
  }
}
