import 'package:teamcash/core/models/business_content_models.dart';

enum GroupMembershipStatus { active, pendingApproval, rejected, notGrouped }

class BusinessSummary {
  const BusinessSummary({
    required this.id,
    required this.name,
    required this.category,
    required this.description,
    required this.logoUrl,
    required this.logoStoragePath,
    required this.coverImageUrl,
    required this.coverImageStoragePath,
    required this.address,
    required this.workingHours,
    required this.phoneNumbers,
    required this.cashbackBasisPoints,
    required this.groupId,
    required this.groupName,
    required this.groupStatus,
    required this.locationsCount,
    required this.productsCount,
    required this.manualPhoneIssuingEnabled,
    required this.redeemPolicy,
  });

  final String id;
  final String name;
  final String category;
  final String description;
  final String logoUrl;
  final String logoStoragePath;
  final String coverImageUrl;
  final String coverImageStoragePath;
  final String address;
  final String workingHours;
  final List<String> phoneNumbers;
  final int cashbackBasisPoints;
  final String groupId;
  final String groupName;
  final GroupMembershipStatus groupStatus;
  final int locationsCount;
  final int productsCount;
  final bool manualPhoneIssuingEnabled;
  final String redeemPolicy;
}

class StaffMemberSummary {
  const StaffMemberSummary({
    required this.id,
    required this.name,
    required this.username,
    required this.roleLabel,
    required this.businessName,
    required this.isActive,
    required this.lastActivityLabel,
  });

  final String id;
  final String name;
  final String username;
  final String roleLabel;
  final String businessName;
  final bool isActive;
  final String lastActivityLabel;
}

class GroupJoinRequestSummary {
  const GroupJoinRequestSummary({
    required this.id,
    required this.groupId,
    required this.businessId,
    required this.businessName,
    required this.groupName,
    required this.approvalsReceived,
    required this.approvalsRequired,
    required this.statusCode,
    required this.status,
    required this.requestedAt,
    required this.requestedAtLabel,
  });

  final String id;
  final String groupId;
  final String businessId;
  final String businessName;
  final String groupName;
  final int approvalsReceived;
  final int approvalsRequired;
  final String statusCode;
  final String status;
  final DateTime requestedAt;
  final String requestedAtLabel;
}

class GroupAuditEventSummary {
  const GroupAuditEventSummary({
    required this.id,
    required this.groupId,
    required this.groupName,
    required this.businessId,
    required this.businessName,
    required this.actorBusinessName,
    required this.eventType,
    required this.title,
    required this.detail,
    required this.occurredAt,
  });

  final String id;
  final String groupId;
  final String groupName;
  final String businessId;
  final String businessName;
  final String actorBusinessName;
  final String eventType;
  final String title;
  final String detail;
  final DateTime occurredAt;
}

class BusinessDirectoryEntry {
  const BusinessDirectoryEntry({
    required this.id,
    required this.name,
    required this.category,
    required this.description,
    required this.logoUrl,
    required this.coverImageUrl,
    required this.address,
    required this.workingHours,
    required this.cashbackBasisPoints,
    required this.redeemPolicy,
    required this.phoneNumbers,
    required this.locations,
    required this.products,
    required this.services,
    required this.locationsCount,
    required this.productsCount,
    required this.servicesCount,
    required this.mediaCount,
    required this.featuredMedia,
    required this.groupName,
    required this.groupStatus,
  });

  final String id;
  final String name;
  final String category;
  final String description;
  final String logoUrl;
  final String coverImageUrl;
  final String address;
  final String workingHours;
  final int cashbackBasisPoints;
  final String redeemPolicy;
  final List<String> phoneNumbers;
  final List<BusinessLocationSummary> locations;
  final List<BusinessCatalogItemSummary> products;
  final List<BusinessCatalogItemSummary> services;
  final int locationsCount;
  final int productsCount;
  final int servicesCount;
  final int mediaCount;
  final List<BusinessMediaSummary> featuredMedia;
  final String groupName;
  final GroupMembershipStatus groupStatus;
}
