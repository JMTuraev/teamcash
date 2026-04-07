enum WalletEventType {
  issue,
  redeem,
  transferOut,
  transferIn,
  giftPending,
  giftClaimed,
  sharedCheckoutCreated,
  sharedCheckoutContribution,
  sharedCheckoutFinalized,
  expire,
  refund,
  adminAdjustment,
}

enum PendingTransferDirection { outgoing, incoming }

class WalletLot {
  const WalletLot({
    required this.id,
    required this.groupId,
    required this.issuerBusinessName,
    required this.groupName,
    required this.availableAmount,
    required this.expiresAt,
    required this.currentOwnerLabel,
  });

  final String id;
  final String groupId;
  final String issuerBusinessName;
  final String groupName;
  final int availableAmount;
  final DateTime expiresAt;
  final String currentOwnerLabel;
}

class WalletEvent {
  const WalletEvent({
    required this.id,
    required this.type,
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.occurredAt,
    required this.groupName,
    required this.issuerBusinessName,
    required this.isIncoming,
  });

  final String id;
  final WalletEventType type;
  final String title;
  final String subtitle;
  final int amount;
  final DateTime occurredAt;
  final String groupName;
  final String issuerBusinessName;
  final bool isIncoming;
}

class PendingTransferSummary {
  const PendingTransferSummary({
    required this.id,
    required this.phoneNumber,
    required this.amount,
    required this.statusLabel,
    required this.expiresAt,
    required this.direction,
    required this.groupId,
    required this.groupName,
    this.canClaim = false,
  });

  final String id;
  final String phoneNumber;
  final int amount;
  final String statusLabel;
  final DateTime expiresAt;
  final PendingTransferDirection direction;
  final String groupId;
  final String groupName;
  final bool canClaim;
}

class SharedContributionSummary {
  const SharedContributionSummary({
    required this.participantName,
    required this.amount,
  });

  final String participantName;
  final int amount;
}

class SharedCheckoutSummary {
  const SharedCheckoutSummary({
    required this.id,
    required this.businessId,
    required this.businessName,
    required this.groupId,
    required this.status,
    required this.sourceTicketRef,
    required this.totalAmount,
    required this.contributedAmount,
    required this.remainingAmount,
    required this.contributions,
    required this.createdAt,
  });

  final String id;
  final String businessId;
  final String businessName;
  final String groupId;
  final String status;
  final String sourceTicketRef;
  final int totalAmount;
  final int contributedAmount;
  final int remainingAmount;
  final List<SharedContributionSummary> contributions;
  final DateTime createdAt;
}
