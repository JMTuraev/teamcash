import 'package:teamcash/core/models/business_models.dart';
import 'package:teamcash/core/models/dashboard_models.dart';
import 'package:teamcash/core/models/wallet_models.dart';

class AppWorkspaceSnapshot {
  const AppWorkspaceSnapshot({
    required this.owner,
    required this.staff,
    required this.client,
    required this.directory,
  });

  final OwnerWorkspace owner;
  final StaffWorkspace staff;
  final ClientWorkspace client;
  final List<BusinessDirectoryEntry> directory;
}

class OwnerWorkspace {
  const OwnerWorkspace({
    required this.ownerName,
    required this.businesses,
    required this.dashboardMetrics,
    required this.trendPoints,
    required this.businessPerformance,
    required this.staffMembers,
    required this.joinRequests,
    required this.groupAuditEvents,
  });

  final String ownerName;
  final List<BusinessSummary> businesses;
  final List<DashboardMetric> dashboardMetrics;
  final List<DashboardTrendPoint> trendPoints;
  final List<BusinessPerformanceSnapshot> businessPerformance;
  final List<StaffMemberSummary> staffMembers;
  final List<GroupJoinRequestSummary> joinRequests;
  final List<GroupAuditEventSummary> groupAuditEvents;
}

class StaffWorkspace {
  const StaffWorkspace({
    required this.staffName,
    required this.businessId,
    required this.businessName,
    required this.groupId,
    required this.cashbackBasisPoints,
    required this.preferredStartTabIndex,
    required this.notificationDigestOptIn,
    required this.dashboardMetrics,
    required this.trendPoints,
    required this.recentTransactions,
    required this.activeSharedCheckouts,
  });

  final String staffName;
  final String businessId;
  final String businessName;
  final String groupId;
  final int cashbackBasisPoints;
  final int preferredStartTabIndex;
  final bool notificationDigestOptIn;
  final List<DashboardMetric> dashboardMetrics;
  final List<DashboardTrendPoint> trendPoints;
  final List<WalletEvent> recentTransactions;
  final List<StaffSharedCheckoutSummary> activeSharedCheckouts;
}

class StaffSharedCheckoutSummary {
  const StaffSharedCheckoutSummary({
    required this.id,
    required this.sourceTicketRef,
    required this.status,
    required this.totalMinorUnits,
    required this.contributedMinorUnits,
    required this.remainingMinorUnits,
    required this.contributionsCount,
    required this.createdAt,
  });

  final String id;
  final String sourceTicketRef;
  final String status;
  final int totalMinorUnits;
  final int contributedMinorUnits;
  final int remainingMinorUnits;
  final int contributionsCount;
  final DateTime createdAt;
}

class ClientWorkspace {
  const ClientWorkspace({
    required this.clientName,
    required this.phoneNumber,
    required this.totalWalletBalance,
    required this.preferredStartTabIndex,
    required this.marketingOptIn,
    required this.storeDirectory,
    required this.walletLots,
    required this.history,
    required this.pendingTransfers,
    required this.activeSharedCheckouts,
  });

  final String clientName;
  final String phoneNumber;
  final int totalWalletBalance;
  final int preferredStartTabIndex;
  final bool marketingOptIn;
  final List<BusinessDirectoryEntry> storeDirectory;
  final List<WalletLot> walletLots;
  final List<WalletEvent> history;
  final List<PendingTransferSummary> pendingTransfers;
  final List<SharedCheckoutSummary> activeSharedCheckouts;
}
