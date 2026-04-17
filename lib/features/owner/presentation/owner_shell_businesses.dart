part of 'owner_shell.dart';

class _BusinessesTab extends ConsumerWidget {
  const _BusinessesTab({
    required this.businesses,
    required this.activeBusiness,
    required this.activeBusinessId,
    required this.canManageBusinesses,
    required this.actionInProgress,
    required this.onEditBusiness,
    required this.onCreateLocation,
    required this.onEditLocation,
    required this.onDeleteLocation,
    required this.onCreateProduct,
    required this.onEditProduct,
    required this.onDeleteProduct,
    required this.onCreateService,
    required this.onEditService,
    required this.onDeleteService,
    required this.onEditBranding,
    required this.onCreateMedia,
    required this.onEditMedia,
    required this.onDeleteMedia,
  });

  final List<BusinessSummary> businesses;
  final BusinessSummary activeBusiness;
  final String activeBusinessId;
  final bool canManageBusinesses;
  final bool actionInProgress;
  final Future<void> Function(BusinessSummary business)? onEditBusiness;
  final Future<void> Function()? onCreateLocation;
  final Future<void> Function(BusinessLocationSummary location)? onEditLocation;
  final Future<void> Function(BusinessLocationSummary location)?
  onDeleteLocation;
  final Future<void> Function()? onCreateProduct;
  final Future<void> Function(BusinessCatalogItemSummary item)? onEditProduct;
  final Future<void> Function(BusinessCatalogItemSummary item)? onDeleteProduct;
  final Future<void> Function()? onCreateService;
  final Future<void> Function(BusinessCatalogItemSummary item)? onEditService;
  final Future<void> Function(BusinessCatalogItemSummary item)? onDeleteService;
  final Future<void> Function()? onEditBranding;
  final Future<void> Function()? onCreateMedia;
  final Future<void> Function(BusinessMediaSummary media)? onEditMedia;
  final Future<void> Function(BusinessMediaSummary media)? onDeleteMedia;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locationsAsync = ref.watch(
      businessLocationsProvider(activeBusiness.id),
    );
    final productsAsync = ref.watch(
      businessProductsProvider(activeBusiness.id),
    );
    final servicesAsync = ref.watch(
      businessServicesProvider(activeBusiness.id),
    );
    final mediaAsync = ref.watch(businessMediaProvider(activeBusiness.id));

    return SectionCard(
      title: 'Business portfolio',
      subtitle:
          'Owners can run multiple businesses independently while keeping tandem membership at the business level.',
      child: Column(
        children: [
          ...businesses.map(
            (business) => Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: _BusinessTile(
                business: business,
                isActive: business.id == activeBusinessId,
                canManageBusinesses: canManageBusinesses,
                actionInProgress: actionInProgress,
                onEditBusiness: onEditBusiness,
              ),
            ),
          ),
          const SizedBox(height: 8),
          _BusinessCatalogSection(
            activeBusiness: activeBusiness,
            locationsAsync: locationsAsync,
            productsAsync: productsAsync,
            servicesAsync: servicesAsync,
            canManageBusinesses: canManageBusinesses,
            actionInProgress: actionInProgress,
            onCreateLocation: onCreateLocation,
            onEditLocation: onEditLocation,
            onDeleteLocation: onDeleteLocation,
            onCreateProduct: onCreateProduct,
            onEditProduct: onEditProduct,
            onDeleteProduct: onDeleteProduct,
            onCreateService: onCreateService,
            onEditService: onEditService,
            onDeleteService: onDeleteService,
          ),
          const SizedBox(height: 16),
          _BusinessBrandingSection(
            activeBusiness: activeBusiness,
            mediaAsync: mediaAsync,
            canManageBusinesses: canManageBusinesses,
            actionInProgress: actionInProgress,
            onEditBranding: onEditBranding,
            onCreateMedia: onCreateMedia,
            onEditMedia: onEditMedia,
            onDeleteMedia: onDeleteMedia,
          ),
        ],
      ),
    );
  }
}

class _BusinessCatalogSection extends StatelessWidget {
  const _BusinessCatalogSection({
    required this.activeBusiness,
    required this.locationsAsync,
    required this.productsAsync,
    required this.servicesAsync,
    required this.canManageBusinesses,
    required this.actionInProgress,
    required this.onCreateLocation,
    required this.onEditLocation,
    required this.onDeleteLocation,
    required this.onCreateProduct,
    required this.onEditProduct,
    required this.onDeleteProduct,
    required this.onCreateService,
    required this.onEditService,
    required this.onDeleteService,
  });

  final BusinessSummary activeBusiness;
  final AsyncValue<List<BusinessLocationSummary>> locationsAsync;
  final AsyncValue<List<BusinessCatalogItemSummary>> productsAsync;
  final AsyncValue<List<BusinessCatalogItemSummary>> servicesAsync;
  final bool canManageBusinesses;
  final bool actionInProgress;
  final Future<void> Function()? onCreateLocation;
  final Future<void> Function(BusinessLocationSummary location)? onEditLocation;
  final Future<void> Function(BusinessLocationSummary location)?
  onDeleteLocation;
  final Future<void> Function()? onCreateProduct;
  final Future<void> Function(BusinessCatalogItemSummary item)? onEditProduct;
  final Future<void> Function(BusinessCatalogItemSummary item)? onDeleteProduct;
  final Future<void> Function()? onCreateService;
  final Future<void> Function(BusinessCatalogItemSummary item)? onEditService;
  final Future<void> Function(BusinessCatalogItemSummary item)? onDeleteService;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      key: const ValueKey('owner-live-catalog-section'),
      title: 'Live catalog for ${activeBusiness.name}',
      subtitle:
          'Locations, products, and services are stored directly in Firestore so the owner surface reflects the real business profile.',
      child: Column(
        children: [
          _CatalogBlock<BusinessLocationSummary>(
            title: 'Locations',
            subtitle:
                'Physical branches, counters, or pickup points shown inside the private tandem directory.',
            emptyMessage:
                'No locations yet. Add the first branch for this business.',
            addLabel: 'Add location',
            itemsAsync: locationsAsync,
            canManageBusinesses: canManageBusinesses,
            actionInProgress: actionInProgress,
            onAdd: onCreateLocation,
            itemBuilder: (location) => _LocationRow(
              location: location,
              canManageBusinesses: canManageBusinesses,
              actionInProgress: actionInProgress,
              onEdit: onEditLocation,
              onDelete: onDeleteLocation,
            ),
          ),
          const SizedBox(height: 16),
          _CatalogBlock<BusinessCatalogItemSummary>(
            title: 'Products',
            subtitle:
                'Menu items and sellable goods that help clients browse the business before checkout.',
            emptyMessage: 'No products yet. Add items customers can browse.',
            addLabel: 'Add product',
            itemsAsync: productsAsync,
            canManageBusinesses: canManageBusinesses,
            actionInProgress: actionInProgress,
            onAdd: onCreateProduct,
            itemBuilder: (item) => _CatalogItemRow(
              item: item,
              itemTypeLabel: 'Product',
              canManageBusinesses: canManageBusinesses,
              actionInProgress: actionInProgress,
              onEdit: onEditProduct,
              onDelete: onDeleteProduct,
            ),
          ),
          const SizedBox(height: 16),
          _CatalogBlock<BusinessCatalogItemSummary>(
            title: 'Services',
            subtitle:
                'Service catalogue entries that appear alongside products in the business profile.',
            emptyMessage:
                'No services yet. Add the services this business provides.',
            addLabel: 'Add service',
            itemsAsync: servicesAsync,
            canManageBusinesses: canManageBusinesses,
            actionInProgress: actionInProgress,
            onAdd: onCreateService,
            itemBuilder: (item) => _CatalogItemRow(
              item: item,
              itemTypeLabel: 'Service',
              canManageBusinesses: canManageBusinesses,
              actionInProgress: actionInProgress,
              onEdit: onEditService,
              onDelete: onDeleteService,
            ),
          ),
        ],
      ),
    );
  }
}

class _BusinessBrandingSection extends StatelessWidget {
  const _BusinessBrandingSection({
    required this.activeBusiness,
    required this.mediaAsync,
    required this.canManageBusinesses,
    required this.actionInProgress,
    required this.onEditBranding,
    required this.onCreateMedia,
    required this.onEditMedia,
    required this.onDeleteMedia,
  });

  final BusinessSummary activeBusiness;
  final AsyncValue<List<BusinessMediaSummary>> mediaAsync;
  final bool canManageBusinesses;
  final bool actionInProgress;
  final Future<void> Function()? onEditBranding;
  final Future<void> Function()? onCreateMedia;
  final Future<void> Function(BusinessMediaSummary media)? onEditMedia;
  final Future<void> Function(BusinessMediaSummary media)? onDeleteMedia;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      key: const ValueKey('owner-branding-section'),
      title: 'Branding and media',
      subtitle:
          'Logo, cover, and gallery content live in Firebase-backed business documents so the directory can show rich business profiles.',
      trailing: canManageBusinesses
          ? FilledButton.icon(
              key: const ValueKey('owner-edit-branding-button'),
              onPressed: actionInProgress || onEditBranding == null
                  ? null
                  : onEditBranding,
              icon: const Icon(Icons.photo_camera_back_outlined),
              label: const Text('Edit branding'),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _BrandingPreview(activeBusiness: activeBusiness),
          const SizedBox(height: 16),
          _CatalogBlock<BusinessMediaSummary>(
            title: 'Gallery',
            subtitle:
                'Curated content, portfolio, and storefront imagery for the business profile.',
            emptyMessage:
                'No media items yet. Add gallery cards for clients to browse.',
            addLabel: 'Add media',
            itemsAsync: mediaAsync,
            canManageBusinesses: canManageBusinesses,
            actionInProgress: actionInProgress,
            addButtonKey: const ValueKey('owner-media-add-button'),
            onAdd: onCreateMedia,
            itemBuilder: (media) => _MediaRow(
              media: media,
              canManageBusinesses: canManageBusinesses,
              actionInProgress: actionInProgress,
              onEdit: onEditMedia,
              onDelete: onDeleteMedia,
            ),
          ),
        ],
      ),
    );
  }
}

class _CatalogBlock<T> extends StatelessWidget {
  const _CatalogBlock({
    required this.title,
    required this.subtitle,
    required this.emptyMessage,
    required this.addLabel,
    required this.itemsAsync,
    required this.canManageBusinesses,
    required this.actionInProgress,
    this.addButtonKey,
    required this.onAdd,
    required this.itemBuilder,
  });

  final String title;
  final String subtitle;
  final String emptyMessage;
  final String addLabel;
  final AsyncValue<List<T>> itemsAsync;
  final bool canManageBusinesses;
  final bool actionInProgress;
  final Key? addButtonKey;
  final Future<void> Function()? onAdd;
  final Widget Function(T item) itemBuilder;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBF9),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFDDE8E1)),
      ),
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
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF52606D),
                      ),
                    ),
                  ],
                ),
              ),
              if (canManageBusinesses)
                FilledButton.tonalIcon(
                  key: addButtonKey,
                  onPressed: actionInProgress || onAdd == null ? null : onAdd,
                  icon: const Icon(Icons.add),
                  label: Text(addLabel),
                ),
            ],
          ),
          const SizedBox(height: 14),
          itemsAsync.when(
            data: (items) {
              if (items.isEmpty) {
                return Text(
                  emptyMessage,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF6B7280),
                  ),
                );
              }

              return Column(
                children: [
                  for (final item in items) ...[
                    itemBuilder(item),
                    if (item != items.last) const SizedBox(height: 12),
                  ],
                ],
              );
            },
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, _) => Text(
              error.toString(),
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: const Color(0xFFB23A48)),
            ),
          ),
        ],
      ),
    );
  }
}

class _BrandingPreview extends StatelessWidget {
  const _BrandingPreview({required this.activeBusiness});

  final BusinessSummary activeBusiness;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('owner-branding-preview'),
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBF9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFDDE8E1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Directory presentation',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ImagePreviewCard(
                title: 'Logo',
                imageUrl: activeBusiness.logoUrl,
                fallbackIcon: Icons.storefront_outlined,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ImagePreviewCard(
                  title: 'Cover image',
                  imageUrl: activeBusiness.coverImageUrl,
                  fallbackIcon: Icons.landscape_outlined,
                  height: 132,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ImagePreviewCard extends StatelessWidget {
  const _ImagePreviewCard({
    required this.title,
    required this.imageUrl,
    required this.fallbackIcon,
    this.height = 96,
  });

  final String title;
  final String imageUrl;
  final IconData fallbackIcon;
  final double height;

  @override
  Widget build(BuildContext context) {
    final hasImage = imageUrl.trim().isNotEmpty;
    final width = title == 'Logo' ? 120.0 : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.labelLarge?.copyWith(color: const Color(0xFF52606D)),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Container(
            width: width,
            height: height,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF2EE),
              border: Border.all(color: const Color(0xFFD6E4DD)),
            ),
            child: hasImage
                ? Image.network(
                    imageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Center(
                      child: Icon(
                        fallbackIcon,
                        color: const Color(0xFF6B7280),
                        size: 32,
                      ),
                    ),
                  )
                : Center(
                    child: Icon(
                      fallbackIcon,
                      color: const Color(0xFF6B7280),
                      size: 32,
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

class _MediaRow extends StatelessWidget {
  const _MediaRow({
    required this.media,
    required this.canManageBusinesses,
    required this.actionInProgress,
    required this.onEdit,
    required this.onDelete,
  });

  final BusinessMediaSummary media;
  final bool canManageBusinesses;
  final bool actionInProgress;
  final Future<void> Function(BusinessMediaSummary media)? onEdit;
  final Future<void> Function(BusinessMediaSummary media)? onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: ValueKey('owner-media-row-${media.id}'),
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE4E7EB)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Container(
              width: 112,
              height: 84,
              color: const Color(0xFFEAF2EE),
              child: media.imageUrl.trim().isEmpty
                  ? const Icon(Icons.image_outlined, color: Color(0xFF6B7280))
                  : Image.network(
                      media.imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => const Icon(
                        Icons.image_outlined,
                        color: Color(0xFF6B7280),
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
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
                            media.title,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          if (media.isFeatured || media.isStorageBacked) ...[
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                if (media.isFeatured)
                                  const StatusPill(
                                    label: 'Featured',
                                    backgroundColor: Color(0xFFE7F5EF),
                                    foregroundColor: Color(0xFF1B7F5B),
                                  ),
                                if (media.isStorageBacked)
                                  const StatusPill(
                                    label: 'Storage-backed',
                                    backgroundColor: Color(0xFFE8F1FF),
                                    foregroundColor: Color(0xFF2457C5),
                                  ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  media.mediaType,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF1F2933),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (media.caption.trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    media.caption,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF52606D),
                    ),
                  ),
                ],
                if (canManageBusinesses) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    children: [
                      TextButton.icon(
                        key: ValueKey('owner-media-edit-${media.id}'),
                        onPressed: actionInProgress || onEdit == null
                            ? null
                            : () => onEdit!(media),
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('Edit'),
                      ),
                      TextButton.icon(
                        key: ValueKey('owner-media-delete-${media.id}'),
                        onPressed: actionInProgress || onDelete == null
                            ? null
                            : () => onDelete!(media),
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Delete'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LocationRow extends StatelessWidget {
  const _LocationRow({
    required this.location,
    required this.canManageBusinesses,
    required this.actionInProgress,
    required this.onEdit,
    required this.onDelete,
  });

  final BusinessLocationSummary location;
  final bool canManageBusinesses;
  final bool actionInProgress;
  final Future<void> Function(BusinessLocationSummary location)? onEdit;
  final Future<void> Function(BusinessLocationSummary location)? onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE4E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  location.name,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (location.isPrimary)
                const StatusPill(
                  label: 'Primary',
                  backgroundColor: Color(0xFFE7F5EF),
                  foregroundColor: Color(0xFF1B7F5B),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${location.address}\n${location.workingHours} • ${location.phoneNumbers.join(', ')}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (location.notes.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              location.notes,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF52606D)),
            ),
          ],
          if (canManageBusinesses) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: [
                TextButton.icon(
                  onPressed: actionInProgress || onEdit == null
                      ? null
                      : () => onEdit!(location),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit'),
                ),
                TextButton.icon(
                  onPressed: actionInProgress || onDelete == null
                      ? null
                      : () => onDelete!(location),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Delete'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _CatalogItemRow extends StatelessWidget {
  const _CatalogItemRow({
    required this.item,
    required this.itemTypeLabel,
    required this.canManageBusinesses,
    required this.actionInProgress,
    required this.onEdit,
    required this.onDelete,
  });

  final BusinessCatalogItemSummary item;
  final String itemTypeLabel;
  final bool canManageBusinesses;
  final bool actionInProgress;
  final Future<void> Function(BusinessCatalogItemSummary item)? onEdit;
  final Future<void> Function(BusinessCatalogItemSummary item)? onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE4E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.name,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              StatusPill(
                label: item.isActive ? 'Active' : 'Paused',
                backgroundColor: item.isActive
                    ? const Color(0xFFE7F5EF)
                    : const Color(0xFFFFF2D8),
                foregroundColor: item.isActive
                    ? const Color(0xFF1B7F5B)
                    : const Color(0xFF9C6100),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '$itemTypeLabel • ${item.priceLabel}',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: const Color(0xFF1F2933),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            item.description,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF52606D)),
          ),
          if (canManageBusinesses) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: [
                TextButton.icon(
                  onPressed: actionInProgress || onEdit == null
                      ? null
                      : () => onEdit!(item),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit'),
                ),
                TextButton.icon(
                  onPressed: actionInProgress || onDelete == null
                      ? null
                      : () => onDelete!(item),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Delete'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _BusinessTile extends StatelessWidget {
  const _BusinessTile({
    required this.business,
    required this.isActive,
    required this.canManageBusinesses,
    required this.actionInProgress,
    required this.onEditBusiness,
  });

  final BusinessSummary business;
  final bool isActive;
  final bool canManageBusinesses;
  final bool actionInProgress;
  final Future<void> Function(BusinessSummary business)? onEditBusiness;

  @override
  Widget build(BuildContext context) {
    final status = switch (business.groupStatus) {
      GroupMembershipStatus.active => (
        label: 'Active in tandem',
        background: const Color(0xFFE7F5EF),
        foreground: const Color(0xFF1B7F5B),
      ),
      GroupMembershipStatus.pendingApproval => (
        label: 'Pending approval',
        background: const Color(0xFFFFF2D8),
        foreground: const Color(0xFF9C6100),
      ),
      GroupMembershipStatus.rejected => (
        label: 'Rejected',
        background: const Color(0xFFFDECEC),
        foreground: const Color(0xFFB23A48),
      ),
      GroupMembershipStatus.notGrouped => (
        label: 'No tandem group',
        background: const Color(0xFFEFF4FF),
        foreground: const Color(0xFF2455A6),
      ),
    };

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isActive ? const Color(0xFFF1F7F4) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isActive ? const Color(0xFF1B5E52) : const Color(0xFFE6DED1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  business.name,
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
          if (canManageBusinesses) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: actionInProgress || onEditBusiness == null
                    ? null
                    : () => onEditBusiness!(business),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Edit profile'),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            business.description,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF52606D)),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              Chip(label: Text(business.category)),
              Chip(label: Text(business.workingHours)),
              Chip(label: Text('${business.locationsCount} locations')),
              Chip(label: Text('${business.productsCount} products/services')),
              Chip(label: Text(formatPercent(business.cashbackBasisPoints))),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '${business.address}\n${business.phoneNumbers.join(', ')}\n${business.groupName} • ${business.redeemPolicy}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}
