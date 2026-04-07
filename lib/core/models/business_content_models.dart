class BusinessLocationSummary {
  const BusinessLocationSummary({
    required this.id,
    required this.name,
    required this.address,
    required this.workingHours,
    required this.phoneNumbers,
    required this.notes,
    required this.isPrimary,
  });

  final String id;
  final String name;
  final String address;
  final String workingHours;
  final List<String> phoneNumbers;
  final String notes;
  final bool isPrimary;
}

class BusinessCatalogItemSummary {
  const BusinessCatalogItemSummary({
    required this.id,
    required this.name,
    required this.description,
    required this.priceLabel,
    required this.isActive,
  });

  final String id;
  final String name;
  final String description;
  final String priceLabel;
  final bool isActive;
}

class BusinessMediaSummary {
  const BusinessMediaSummary({
    required this.id,
    required this.title,
    required this.caption,
    required this.mediaType,
    required this.imageUrl,
    required this.storagePath,
    required this.isFeatured,
  });

  final String id;
  final String title;
  final String caption;
  final String mediaType;
  final String imageUrl;
  final String storagePath;
  final bool isFeatured;

  bool get isStorageBacked => storagePath.trim().isNotEmpty;
}
