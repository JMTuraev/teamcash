part of 'owner_shell.dart';

class _EditBusinessPayload {
  const _EditBusinessPayload({
    required this.name,
    required this.category,
    required this.description,
    required this.address,
    required this.workingHours,
    required this.phoneNumbers,
    required this.cashbackBasisPoints,
    required this.redeemPolicy,
  });

  final String name;
  final String category;
  final String description;
  final String address;
  final String workingHours;
  final List<String> phoneNumbers;
  final int cashbackBasisPoints;
  final String redeemPolicy;
}

IconData _auditIcon(String eventType) {
  switch (eventType) {
    case 'group_created':
      return Icons.groups_2_outlined;
    case 'join_request_created':
    case 'join_request_pending':
      return Icons.hourglass_top_outlined;
    case 'join_request_vote_yes':
      return Icons.how_to_vote_outlined;
    case 'join_request_approved':
      return Icons.verified_outlined;
    case 'join_request_rejected':
      return Icons.cancel_outlined;
    default:
      return Icons.timeline_outlined;
  }
}

Color _auditBackgroundColor(String eventType) {
  switch (eventType) {
    case 'join_request_rejected':
      return const Color(0xFFFDECEC);
    case 'join_request_approved':
    case 'group_created':
      return const Color(0xFFE7F5EF);
    case 'join_request_created':
    case 'join_request_pending':
    case 'join_request_vote_yes':
      return const Color(0xFFFFF2D8);
    default:
      return const Color(0xFFEFF4FF);
  }
}

Color _auditForegroundColor(String eventType) {
  switch (eventType) {
    case 'join_request_rejected':
      return const Color(0xFFB23A48);
    case 'join_request_approved':
    case 'group_created':
      return const Color(0xFF1B7F5B);
    case 'join_request_created':
    case 'join_request_pending':
    case 'join_request_vote_yes':
      return const Color(0xFF9C6100);
    default:
      return const Color(0xFF2455A6);
  }
}

class _CreateBusinessPayload extends _EditBusinessPayload {
  const _CreateBusinessPayload({
    required super.name,
    required super.category,
    required super.description,
    required super.address,
    required super.workingHours,
    required super.phoneNumbers,
    required super.cashbackBasisPoints,
    required super.redeemPolicy,
  });
}

class _RequestJoinGroupPayload {
  const _RequestJoinGroupPayload({
    required this.groupId,
    required this.groupName,
  });

  final String groupId;
  final String groupName;
}

class _LocationPayload {
  const _LocationPayload({
    required this.name,
    required this.address,
    required this.workingHours,
    required this.phoneNumbers,
    required this.notes,
    required this.isPrimary,
  });

  final String name;
  final String address;
  final String workingHours;
  final List<String> phoneNumbers;
  final String notes;
  final bool isPrimary;
}

class _CatalogItemPayload {
  const _CatalogItemPayload({
    required this.name,
    required this.description,
    required this.priceLabel,
    required this.isActive,
  });

  final String name;
  final String description;
  final String priceLabel;
  final bool isActive;
}

class _BrandingPayload {
  const _BrandingPayload({
    required this.logoUrl,
    required this.coverImageUrl,
    this.logoFile,
    this.coverFile,
  });

  final String logoUrl;
  final String coverImageUrl;
  final PickedBusinessAsset? logoFile;
  final PickedBusinessAsset? coverFile;
}

class _MediaPayload {
  const _MediaPayload({
    required this.title,
    required this.caption,
    required this.mediaType,
    required this.imageUrl,
    required this.isFeatured,
    this.imageFile,
  });

  final String title;
  final String caption;
  final String mediaType;
  final String imageUrl;
  final bool isFeatured;
  final PickedBusinessAsset? imageFile;
}
