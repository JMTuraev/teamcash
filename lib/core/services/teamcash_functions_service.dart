import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:teamcash/app/app.dart';
import 'package:teamcash/app/bootstrap/firebase_bootstrap.dart';
import 'package:teamcash/core/config/teamcash_environment.dart';
import 'package:teamcash/core/diagnostics/app_diagnostics.dart';

final teamCashFunctionsServiceProvider = Provider<TeamCashFunctionsService>(
  (ref) => TeamCashFunctionsService(ref.watch(firebaseStatusProvider)),
);

class TeamCashFunctionsService {
  TeamCashFunctionsService(this._bootstrapResult);

  final FirebaseBootstrapResult _bootstrapResult;

  bool get isConnected =>
      _bootstrapResult.mode == FirebaseBootstrapMode.connected;

  FirebaseFunctions get _functions => FirebaseFunctions.instanceFor(
    region: TeamCashEnvironment.functionsRegion,
  );

  Future<CreateStaffAccountResult> createStaffAccount({
    required String businessId,
    required String username,
    required String displayName,
    required String password,
  }) async {
    final response = await _call('createStaffAccount', {
      'businessId': businessId,
      'username': username,
      'displayName': displayName,
      'password': password,
    });

    return CreateStaffAccountResult.fromMap(response);
  }

  Future<CreateBusinessResult> createBusiness({
    required String name,
    required String category,
    required String description,
    required String address,
    required String workingHours,
    required List<String> phoneNumbers,
    required int cashbackBasisPoints,
    required String redeemPolicy,
  }) async {
    final response = await _call('createBusiness', {
      'name': name,
      'category': category,
      'description': description,
      'address': address,
      'workingHours': workingHours,
      'phoneNumbers': phoneNumbers,
      'cashbackBasisPoints': cashbackBasisPoints,
      'redeemPolicy': redeemPolicy,
    });

    return CreateBusinessResult.fromMap(response);
  }

  Future<void> disableStaffAccount({
    required String staffUid,
    String? reason,
  }) async {
    await _call('disableStaffAccount', {
      'staffUid': staffUid,
      if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
    });
  }

  Future<ResetStaffPasswordResult> resetStaffPassword({
    required String staffUid,
    required String password,
  }) async {
    final response = await _call('resetStaffPassword', {
      'staffUid': staffUid,
      'password': password,
    });

    return ResetStaffPasswordResult.fromMap(response);
  }

  Future<UpdateStaffProfileResult> updateStaffProfile({
    required String staffUid,
    required String displayName,
  }) async {
    final response = await _call('updateStaffProfile', {
      'staffUid': staffUid,
      'displayName': displayName,
    });

    return UpdateStaffProfileResult.fromMap(response);
  }

  Future<CreateGroupResult> createGroup({
    required String businessId,
    required String name,
  }) async {
    final response = await _call('createGroup', {
      'businessId': businessId,
      'name': name,
    });

    return CreateGroupResult.fromMap(response);
  }

  Future<GroupJoinRequestResult> requestGroupJoin({
    required String groupId,
    required String businessId,
  }) async {
    final response = await _call('requestGroupJoin', {
      'groupId': groupId,
      'businessId': businessId,
    });

    return GroupJoinRequestResult.fromMap(response);
  }

  Future<GroupJoinVoteResult> voteOnGroupJoin({
    required String requestId,
    required String vote,
    String? voterBusinessId,
  }) async {
    final payload = <String, dynamic>{'requestId': requestId, 'vote': vote};
    if (voterBusinessId != null && voterBusinessId.trim().isNotEmpty) {
      payload['voterBusinessId'] = voterBusinessId.trim();
    }

    final response = await _call('voteOnGroupJoin', payload);
    return GroupJoinVoteResult.fromMap(response);
  }

  Future<IssueCashbackResult> issueCashback({
    required String businessId,
    required String groupId,
    required String customerPhoneE164,
    required int paidMinorUnits,
    required int cashbackBasisPoints,
    required String sourceTicketRef,
  }) async {
    final response = await _call('issueCashback', {
      'businessId': businessId,
      'groupId': groupId,
      'customerPhoneE164': customerPhoneE164,
      'paidMinorUnits': paidMinorUnits,
      'cashbackBasisPoints': cashbackBasisPoints,
      'sourceTicketRef': sourceTicketRef,
    });

    return IssueCashbackResult.fromMap(response);
  }

  Future<ClaimCustomerWalletResult> claimCustomerWalletByPhone() async {
    final response = await _call('claimCustomerWalletByPhone', const {});
    return ClaimCustomerWalletResult.fromMap(response);
  }

  Future<GiftTransferResult> createGiftTransfer({
    required String sourceCustomerId,
    required String recipientPhoneE164,
    required String groupId,
    required int amountMinorUnits,
    required String requestId,
  }) async {
    final response = await _call('createGiftTransfer', {
      'sourceCustomerId': sourceCustomerId,
      'recipientPhoneE164': recipientPhoneE164,
      'groupId': groupId,
      'amountMinorUnits': amountMinorUnits,
      'requestId': requestId,
    });

    return GiftTransferResult.fromMap(response);
  }

  Future<ClaimGiftTransferResult> claimGiftTransfer({
    required String transferId,
  }) async {
    final response = await _call('claimGiftTransfer', {
      'transferId': transferId,
    });

    return ClaimGiftTransferResult.fromMap(response);
  }

  Future<CreateSharedCheckoutResult> createSharedCheckout({
    required String businessId,
    required String groupId,
    required int totalMinorUnits,
    required String sourceTicketRef,
  }) async {
    final response = await _call('createSharedCheckout', {
      'businessId': businessId,
      'groupId': groupId,
      'totalMinorUnits': totalMinorUnits,
      'sourceTicketRef': sourceTicketRef,
    });

    return CreateSharedCheckoutResult.fromMap(response);
  }

  Future<SharedCheckoutContributionResult> contributeSharedCheckout({
    required String checkoutId,
    required String customerId,
    required int contributionMinorUnits,
    required String requestId,
  }) async {
    final response = await _call('contributeSharedCheckout', {
      'checkoutId': checkoutId,
      'customerId': customerId,
      'contributionMinorUnits': contributionMinorUnits,
      'requestId': requestId,
    });

    return SharedCheckoutContributionResult.fromMap(response);
  }

  Future<FinalizeSharedCheckoutResult> finalizeSharedCheckout({
    required String checkoutId,
  }) async {
    final response = await _call('finalizeSharedCheckout', {
      'checkoutId': checkoutId,
    });

    return FinalizeSharedCheckoutResult.fromMap(response);
  }

  Future<RedeemCashbackResult> redeemCashback({
    required String businessId,
    required String groupId,
    required int redeemMinorUnits,
    required String sourceTicketRef,
    String? customerId,
    String? customerPhoneE164,
  }) async {
    final trimmedCustomerId = customerId?.trim();
    final trimmedCustomerPhone = customerPhoneE164?.trim();
    final payload = <String, dynamic>{
      'businessId': businessId,
      'groupId': groupId,
      'redeemMinorUnits': redeemMinorUnits,
      'sourceTicketRef': sourceTicketRef,
    };
    if (trimmedCustomerId?.isNotEmpty ?? false) {
      payload['customerId'] = trimmedCustomerId;
    }
    if (trimmedCustomerPhone?.isNotEmpty ?? false) {
      payload['customerPhoneE164'] = trimmedCustomerPhone;
    }

    final response = await _call('redeemCashback', payload);

    return RedeemCashbackResult.fromMap(response);
  }

  Future<RefundCashbackResult> refundCashback({
    required String businessId,
    required String redemptionBatchId,
    String? note,
  }) async {
    final payload = <String, dynamic>{
      'businessId': businessId,
      'redemptionBatchId': redemptionBatchId,
    };
    if (note != null && note.trim().isNotEmpty) {
      payload['note'] = note.trim();
    }

    final response = await _call('refundCashback', payload);
    return RefundCashbackResult.fromMap(response);
  }

  Future<AdminAdjustCashbackResult> adminAdjustCashback({
    required String businessId,
    required String groupId,
    String? customerId,
    String? customerPhoneE164,
    required int amountMinorUnits,
    required String note,
    required String requestId,
  }) async {
    final payload = <String, dynamic>{
      'businessId': businessId,
      'groupId': groupId,
      'amountMinorUnits': amountMinorUnits,
      'note': note,
      'requestId': requestId,
    };
    if (customerId != null && customerId.trim().isNotEmpty) {
      payload['customerId'] = customerId.trim();
    }
    if (customerPhoneE164 != null && customerPhoneE164.trim().isNotEmpty) {
      payload['customerPhoneE164'] = customerPhoneE164.trim();
    }

    final response = await _call('adminAdjustCashback', payload);
    return AdminAdjustCashbackResult.fromMap(response);
  }

  Future<ExpireWalletLotsResult> expireWalletLots({
    required String businessId,
    required String groupId,
    int? maxLots,
  }) async {
    final payload = <String, dynamic>{
      'businessId': businessId,
      'groupId': groupId,
    };
    if (maxLots case final value?) {
      payload['maxLots'] = value;
    }

    final response = await _call('expireWalletLots', payload);
    return ExpireWalletLotsResult.fromMap(response);
  }

  Future<Map<String, dynamic>> _call(
    String name,
    Map<String, dynamic> payload,
  ) async {
    if (!isConnected) {
      throw TeamCashActionUnavailable(_bootstrapResult.message);
    }

    try {
      final callable = _functions.httpsCallable(name);
      final result = await callable.call<Map<String, dynamic>>(payload);
      return _asMap(result.data);
    } on FirebaseFunctionsException catch (error) {
      logAppDiagnostic(
        'callable_failed',
        payload: {
          'callable': name,
          'code': error.code,
          'message': error.message,
        },
        isError: true,
      );
      throw TeamCashActionUnavailable(
        _friendlyCallableMessage(
          name: name,
          code: error.code,
          message: error.message,
        ),
      );
    }
  }

  String _friendlyCallableMessage({
    required String name,
    required String code,
    required String? message,
  }) {
    if (code == 'failed-precondition' &&
        message != null &&
        message.toLowerCase().contains('phone auth')) {
      return message;
    }
    if (code == 'failed-precondition' &&
        message != null &&
        message.toLowerCase().contains('app check')) {
      return 'App Check validation failed for $name. Verify the current environment App Check setup and try again.';
    }
    if (code == 'unauthenticated') {
      return 'Your session expired before $name could complete. Sign in again and retry.';
    }
    if (code == 'permission-denied') {
      return message ?? 'You do not have permission to run $name.';
    }
    return message ?? 'Cloud Function call failed for $name.';
  }

  Map<String, dynamic> _asMap(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.map((key, dynamic value) => MapEntry(key.toString(), value));
    }

    throw TeamCashActionUnavailable(
      'Unexpected Cloud Function response shape.',
    );
  }
}

class TeamCashActionUnavailable implements Exception {
  const TeamCashActionUnavailable(this.message);

  final String message;

  @override
  String toString() => message;
}

class CreateStaffAccountResult {
  const CreateStaffAccountResult({
    required this.staffUid,
    required this.username,
    required this.businessId,
    required this.businessName,
    required this.loginAliasEmail,
  });

  final String staffUid;
  final String username;
  final String businessId;
  final String businessName;
  final String loginAliasEmail;

  factory CreateStaffAccountResult.fromMap(Map<String, dynamic> map) {
    return CreateStaffAccountResult(
      staffUid: map['staffUid'] as String? ?? '',
      username: map['username'] as String? ?? '',
      businessId: map['businessId'] as String? ?? '',
      businessName: map['businessName'] as String? ?? '',
      loginAliasEmail: map['loginAliasEmail'] as String? ?? '',
    );
  }
}

class ResetStaffPasswordResult {
  const ResetStaffPasswordResult({
    required this.staffUid,
    required this.businessId,
    required this.username,
    required this.displayName,
  });

  final String staffUid;
  final String businessId;
  final String username;
  final String displayName;

  factory ResetStaffPasswordResult.fromMap(Map<String, dynamic> map) {
    return ResetStaffPasswordResult(
      staffUid: map['staffUid'] as String? ?? '',
      businessId: map['businessId'] as String? ?? '',
      username: map['username'] as String? ?? '',
      displayName: map['displayName'] as String? ?? '',
    );
  }
}

class UpdateStaffProfileResult {
  const UpdateStaffProfileResult({
    required this.staffUid,
    required this.businessId,
    required this.username,
    required this.displayName,
  });

  final String staffUid;
  final String businessId;
  final String username;
  final String displayName;

  factory UpdateStaffProfileResult.fromMap(Map<String, dynamic> map) {
    return UpdateStaffProfileResult(
      staffUid: map['staffUid'] as String? ?? '',
      businessId: map['businessId'] as String? ?? '',
      username: map['username'] as String? ?? '',
      displayName: map['displayName'] as String? ?? '',
    );
  }
}

class CreateBusinessResult {
  const CreateBusinessResult({
    required this.businessId,
    required this.name,
    required this.status,
    required this.groupMembershipStatus,
  });

  final String businessId;
  final String name;
  final String status;
  final String groupMembershipStatus;

  factory CreateBusinessResult.fromMap(Map<String, dynamic> map) {
    return CreateBusinessResult(
      businessId: map['businessId'] as String? ?? '',
      name: map['name'] as String? ?? '',
      status: map['status'] as String? ?? '',
      groupMembershipStatus: map['groupMembershipStatus'] as String? ?? '',
    );
  }
}

class CreateGroupResult {
  const CreateGroupResult({
    required this.groupId,
    required this.businessId,
    required this.groupName,
    required this.status,
  });

  final String groupId;
  final String businessId;
  final String groupName;
  final String status;

  factory CreateGroupResult.fromMap(Map<String, dynamic> map) {
    return CreateGroupResult(
      groupId: map['groupId'] as String? ?? '',
      businessId: map['businessId'] as String? ?? '',
      groupName: map['groupName'] as String? ?? '',
      status: map['status'] as String? ?? '',
    );
  }
}

class GroupJoinRequestResult {
  const GroupJoinRequestResult({
    required this.requestId,
    required this.groupId,
    required this.businessId,
    required this.approvalsReceived,
    required this.approvalsRequired,
    required this.status,
    required this.reusedExisting,
  });

  final String requestId;
  final String groupId;
  final String businessId;
  final int approvalsReceived;
  final int approvalsRequired;
  final String status;
  final bool reusedExisting;

  factory GroupJoinRequestResult.fromMap(Map<String, dynamic> map) {
    return GroupJoinRequestResult(
      requestId: map['requestId'] as String? ?? '',
      groupId: map['groupId'] as String? ?? '',
      businessId: map['businessId'] as String? ?? '',
      approvalsReceived: (map['approvalsReceived'] as num?)?.toInt() ?? 0,
      approvalsRequired: (map['approvalsRequired'] as num?)?.toInt() ?? 0,
      status: map['status'] as String? ?? '',
      reusedExisting: map['reusedExisting'] as bool? ?? false,
    );
  }
}

class GroupJoinVoteResult {
  const GroupJoinVoteResult({
    required this.requestId,
    required this.groupId,
    required this.voterBusinessId,
    required this.approvalsReceived,
    required this.approvalsRequired,
    required this.status,
    required this.resolved,
  });

  final String requestId;
  final String groupId;
  final String voterBusinessId;
  final int approvalsReceived;
  final int approvalsRequired;
  final String status;
  final bool resolved;

  factory GroupJoinVoteResult.fromMap(Map<String, dynamic> map) {
    return GroupJoinVoteResult(
      requestId: map['requestId'] as String? ?? '',
      groupId: map['groupId'] as String? ?? '',
      voterBusinessId: map['voterBusinessId'] as String? ?? '',
      approvalsReceived: (map['approvalsReceived'] as num?)?.toInt() ?? 0,
      approvalsRequired: (map['approvalsRequired'] as num?)?.toInt() ?? 0,
      status: map['status'] as String? ?? '',
      resolved: map['resolved'] as bool? ?? false,
    );
  }
}

class IssueCashbackResult {
  const IssueCashbackResult({
    required this.eventId,
    required this.lotId,
    required this.customerId,
    required this.issuedMinorUnits,
    required this.expiresAtIso,
  });

  final String eventId;
  final String lotId;
  final String customerId;
  final int issuedMinorUnits;
  final String expiresAtIso;

  factory IssueCashbackResult.fromMap(Map<String, dynamic> map) {
    return IssueCashbackResult(
      eventId: map['eventId'] as String? ?? '',
      lotId: map['lotId'] as String? ?? '',
      customerId: map['customerId'] as String? ?? '',
      issuedMinorUnits: (map['issuedMinorUnits'] as num?)?.toInt() ?? 0,
      expiresAtIso: map['expiresAtIso'] as String? ?? '',
    );
  }
}

class ClaimCustomerWalletResult {
  const ClaimCustomerWalletResult({
    required this.customerId,
    required this.phoneE164,
    required this.createdCustomer,
    required this.claimed,
  });

  final String customerId;
  final String phoneE164;
  final bool createdCustomer;
  final bool claimed;

  factory ClaimCustomerWalletResult.fromMap(Map<String, dynamic> map) {
    return ClaimCustomerWalletResult(
      customerId: map['customerId'] as String? ?? '',
      phoneE164: map['phoneE164'] as String? ?? '',
      createdCustomer: map['createdCustomer'] as bool? ?? false,
      claimed: map['claimed'] as bool? ?? false,
    );
  }
}

class GiftTransferResult {
  const GiftTransferResult({
    required this.transferId,
    required this.amountMinorUnits,
    required this.recipientPhoneE164,
    required this.pendingLotCount,
    required this.transferOutEventId,
    required this.giftPendingEventId,
    this.earliestExpiresAtIso,
    this.latestExpiresAtIso,
  });

  final String transferId;
  final int amountMinorUnits;
  final String recipientPhoneE164;
  final int pendingLotCount;
  final String transferOutEventId;
  final String giftPendingEventId;
  final String? earliestExpiresAtIso;
  final String? latestExpiresAtIso;

  factory GiftTransferResult.fromMap(Map<String, dynamic> map) {
    return GiftTransferResult(
      transferId: map['transferId'] as String? ?? '',
      amountMinorUnits: (map['amountMinorUnits'] as num?)?.toInt() ?? 0,
      recipientPhoneE164: map['recipientPhoneE164'] as String? ?? '',
      pendingLotCount: (map['pendingLotCount'] as num?)?.toInt() ?? 0,
      transferOutEventId: map['transferOutEventId'] as String? ?? '',
      giftPendingEventId: map['giftPendingEventId'] as String? ?? '',
      earliestExpiresAtIso: map['earliestExpiresAtIso'] as String?,
      latestExpiresAtIso: map['latestExpiresAtIso'] as String?,
    );
  }
}

class ClaimGiftTransferResult {
  const ClaimGiftTransferResult({
    required this.transferId,
    required this.customerId,
    required this.claimedMinorUnits,
    required this.expiredMinorUnits,
    required this.claimedLotCount,
    required this.expiredLotCount,
    required this.status,
  });

  final String transferId;
  final String customerId;
  final int claimedMinorUnits;
  final int expiredMinorUnits;
  final int claimedLotCount;
  final int expiredLotCount;
  final String status;

  factory ClaimGiftTransferResult.fromMap(Map<String, dynamic> map) {
    return ClaimGiftTransferResult(
      transferId: map['transferId'] as String? ?? '',
      customerId: map['customerId'] as String? ?? '',
      claimedMinorUnits: (map['claimedMinorUnits'] as num?)?.toInt() ?? 0,
      expiredMinorUnits: (map['expiredMinorUnits'] as num?)?.toInt() ?? 0,
      claimedLotCount: (map['claimedLotCount'] as num?)?.toInt() ?? 0,
      expiredLotCount: (map['expiredLotCount'] as num?)?.toInt() ?? 0,
      status: map['status'] as String? ?? '',
    );
  }
}

class CreateSharedCheckoutResult {
  const CreateSharedCheckoutResult({
    required this.checkoutId,
    required this.status,
    required this.totalMinorUnits,
    required this.contributedMinorUnits,
    required this.remainingMinorUnits,
    required this.createdEventId,
  });

  final String checkoutId;
  final String status;
  final int totalMinorUnits;
  final int contributedMinorUnits;
  final int remainingMinorUnits;
  final String createdEventId;

  factory CreateSharedCheckoutResult.fromMap(Map<String, dynamic> map) {
    return CreateSharedCheckoutResult(
      checkoutId: map['checkoutId'] as String? ?? '',
      status: map['status'] as String? ?? '',
      totalMinorUnits: (map['totalMinorUnits'] as num?)?.toInt() ?? 0,
      contributedMinorUnits:
          (map['contributedMinorUnits'] as num?)?.toInt() ?? 0,
      remainingMinorUnits: (map['remainingMinorUnits'] as num?)?.toInt() ?? 0,
      createdEventId: map['createdEventId'] as String? ?? '',
    );
  }
}

class SharedCheckoutContributionResult {
  const SharedCheckoutContributionResult({
    required this.checkoutId,
    required this.contributionId,
    required this.contributedMinorUnits,
    required this.reservedLotCount,
    required this.remainingMinorUnits,
    required this.contributionEventId,
  });

  final String checkoutId;
  final String contributionId;
  final int contributedMinorUnits;
  final int reservedLotCount;
  final int remainingMinorUnits;
  final String contributionEventId;

  factory SharedCheckoutContributionResult.fromMap(Map<String, dynamic> map) {
    return SharedCheckoutContributionResult(
      checkoutId: map['checkoutId'] as String? ?? '',
      contributionId: map['contributionId'] as String? ?? '',
      contributedMinorUnits:
          (map['contributedMinorUnits'] as num?)?.toInt() ?? 0,
      reservedLotCount: (map['reservedLotCount'] as num?)?.toInt() ?? 0,
      remainingMinorUnits: (map['remainingMinorUnits'] as num?)?.toInt() ?? 0,
      contributionEventId: map['contributionEventId'] as String? ?? '',
    );
  }
}

class FinalizeSharedCheckoutResult {
  const FinalizeSharedCheckoutResult({
    required this.checkoutId,
    required this.status,
    required this.contributedMinorUnits,
    required this.remainingMinorUnits,
    required this.expiredMinorUnits,
    this.redemptionBatchId,
    this.finalizationEventId,
  });

  final String checkoutId;
  final String status;
  final int contributedMinorUnits;
  final int remainingMinorUnits;
  final int expiredMinorUnits;
  final String? redemptionBatchId;
  final String? finalizationEventId;

  factory FinalizeSharedCheckoutResult.fromMap(Map<String, dynamic> map) {
    return FinalizeSharedCheckoutResult(
      checkoutId: map['checkoutId'] as String? ?? '',
      status: map['status'] as String? ?? '',
      contributedMinorUnits:
          (map['contributedMinorUnits'] as num?)?.toInt() ?? 0,
      remainingMinorUnits: (map['remainingMinorUnits'] as num?)?.toInt() ?? 0,
      expiredMinorUnits: (map['expiredMinorUnits'] as num?)?.toInt() ?? 0,
      redemptionBatchId: map['redemptionBatchId'] as String?,
      finalizationEventId: map['finalizationEventId'] as String?,
    );
  }
}

class RedeemCashbackResult {
  const RedeemCashbackResult({
    required this.customerId,
    required this.redemptionBatchId,
    required this.redeemedMinorUnits,
    required this.consumedLotsCount,
  });

  final String customerId;
  final String redemptionBatchId;
  final int redeemedMinorUnits;
  final int consumedLotsCount;

  factory RedeemCashbackResult.fromMap(Map<String, dynamic> map) {
    final consumedLots = (map['consumedLots'] as List<dynamic>?) ?? const [];

    return RedeemCashbackResult(
      customerId: map['customerId'] as String? ?? '',
      redemptionBatchId: map['redemptionBatchId'] as String? ?? '',
      redeemedMinorUnits: (map['redeemedMinorUnits'] as num?)?.toInt() ?? 0,
      consumedLotsCount: consumedLots.length,
    );
  }
}

class RefundCashbackResult {
  const RefundCashbackResult({
    required this.businessId,
    required this.redemptionBatchId,
    required this.refundBatchId,
    required this.refundedMinorUnits,
    required this.refundedLotCount,
    required this.refundEventIds,
    required this.refundLotIds,
  });

  final String businessId;
  final String redemptionBatchId;
  final String refundBatchId;
  final int refundedMinorUnits;
  final int refundedLotCount;
  final List<String> refundEventIds;
  final List<String> refundLotIds;

  factory RefundCashbackResult.fromMap(Map<String, dynamic> map) {
    return RefundCashbackResult(
      businessId: map['businessId'] as String? ?? '',
      redemptionBatchId: map['redemptionBatchId'] as String? ?? '',
      refundBatchId: map['refundBatchId'] as String? ?? '',
      refundedMinorUnits: (map['refundedMinorUnits'] as num?)?.toInt() ?? 0,
      refundedLotCount: (map['refundedLotCount'] as num?)?.toInt() ?? 0,
      refundEventIds: (map['refundEventIds'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(),
      refundLotIds: (map['refundLotIds'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(),
    );
  }
}

class AdminAdjustCashbackResult {
  const AdminAdjustCashbackResult({
    required this.businessId,
    required this.customerId,
    required this.groupId,
    required this.adjustmentBatchId,
    required this.direction,
    required this.adjustedMinorUnits,
    required this.note,
    required this.adjustmentEventIds,
    required this.createdLotIds,
  });

  final String businessId;
  final String customerId;
  final String groupId;
  final String adjustmentBatchId;
  final String direction;
  final int adjustedMinorUnits;
  final String note;
  final List<String> adjustmentEventIds;
  final List<String> createdLotIds;

  factory AdminAdjustCashbackResult.fromMap(Map<String, dynamic> map) {
    return AdminAdjustCashbackResult(
      businessId: map['businessId'] as String? ?? '',
      customerId: map['customerId'] as String? ?? '',
      groupId: map['groupId'] as String? ?? '',
      adjustmentBatchId: map['adjustmentBatchId'] as String? ?? '',
      direction: map['direction'] as String? ?? '',
      adjustedMinorUnits: (map['adjustedMinorUnits'] as num?)?.toInt() ?? 0,
      note: map['note'] as String? ?? '',
      adjustmentEventIds:
          (map['adjustmentEventIds'] as List<dynamic>? ?? const [])
              .whereType<String>()
              .toList(),
      createdLotIds: (map['createdLotIds'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(),
    );
  }
}

class ExpireWalletLotsResult {
  const ExpireWalletLotsResult({
    required this.businessId,
    required this.groupId,
    required this.scannedLotCount,
    required this.expiredLotCount,
    required this.expiredMinorUnits,
    required this.expiredLotIds,
    required this.expireEventIds,
    required this.trigger,
  });

  final String? businessId;
  final String? groupId;
  final int scannedLotCount;
  final int expiredLotCount;
  final int expiredMinorUnits;
  final List<String> expiredLotIds;
  final List<String> expireEventIds;
  final String trigger;

  factory ExpireWalletLotsResult.fromMap(Map<String, dynamic> map) {
    return ExpireWalletLotsResult(
      businessId: map['businessId'] as String?,
      groupId: map['groupId'] as String?,
      scannedLotCount: (map['scannedLotCount'] as num?)?.toInt() ?? 0,
      expiredLotCount: (map['expiredLotCount'] as num?)?.toInt() ?? 0,
      expiredMinorUnits: (map['expiredMinorUnits'] as num?)?.toInt() ?? 0,
      expiredLotIds: (map['expiredLotIds'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(),
      expireEventIds: (map['expireEventIds'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(),
      trigger: map['trigger'] as String? ?? '',
    );
  }
}
