import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:teamcash/core/services/teamcash_functions_service.dart';
import 'package:teamcash/data/firestore/firestore_workspace_repository.dart';

final clientTransferControllerProvider =
    NotifierProvider<ClientTransferController, ClientTransferState>(
      ClientTransferController.new,
    );

class ClientTransferState {
  const ClientTransferState({
    this.isSubmitting = false,
    this.statusMessage,
    this.lastCreatedTransfer,
    this.lastClaimedTransfer,
  });

  final bool isSubmitting;
  final String? statusMessage;
  final GiftTransferResult? lastCreatedTransfer;
  final ClaimGiftTransferResult? lastClaimedTransfer;

  ClientTransferState copyWith({
    bool? isSubmitting,
    String? statusMessage,
    bool clearStatusMessage = false,
    GiftTransferResult? lastCreatedTransfer,
    bool clearLastCreatedTransfer = false,
    ClaimGiftTransferResult? lastClaimedTransfer,
    bool clearLastClaimedTransfer = false,
  }) {
    return ClientTransferState(
      isSubmitting: isSubmitting ?? this.isSubmitting,
      statusMessage: clearStatusMessage
          ? null
          : statusMessage ?? this.statusMessage,
      lastCreatedTransfer: clearLastCreatedTransfer
          ? null
          : lastCreatedTransfer ?? this.lastCreatedTransfer,
      lastClaimedTransfer: clearLastClaimedTransfer
          ? null
          : lastClaimedTransfer ?? this.lastClaimedTransfer,
    );
  }
}

class ClientTransferController extends Notifier<ClientTransferState> {
  @override
  ClientTransferState build() => const ClientTransferState();

  Future<GiftTransferResult> createGiftTransfer({
    required String sourceCustomerId,
    required String recipientPhoneE164,
    required String groupId,
    required int amountMinorUnits,
  }) async {
    state = state.copyWith(
      isSubmitting: true,
      clearStatusMessage: true,
      clearLastClaimedTransfer: true,
    );

    try {
      final result = await ref
          .read(teamCashFunctionsServiceProvider)
          .createGiftTransfer(
            sourceCustomerId: sourceCustomerId,
            recipientPhoneE164: recipientPhoneE164,
            groupId: groupId,
            amountMinorUnits: amountMinorUnits,
            requestId: _buildRequestId(),
          );

      state = state.copyWith(
        isSubmitting: false,
        lastCreatedTransfer: result,
        statusMessage:
            'Gift created for ${result.recipientPhoneE164}. Transfer id: ${result.transferId}.',
      );
      ref.invalidate(clientWorkspaceProvider);
      return result;
    } catch (error) {
      state = state.copyWith(
        isSubmitting: false,
        statusMessage: error.toString(),
      );
      rethrow;
    }
  }

  Future<ClaimGiftTransferResult> claimGiftTransfer({
    required String transferId,
  }) async {
    state = state.copyWith(
      isSubmitting: true,
      clearStatusMessage: true,
      clearLastCreatedTransfer: true,
    );

    try {
      final result = await ref
          .read(teamCashFunctionsServiceProvider)
          .claimGiftTransfer(transferId: transferId);

      state = state.copyWith(
        isSubmitting: false,
        lastClaimedTransfer: result,
        statusMessage:
            'Gift $transferId processed with status ${result.status}. Claimed ${result.claimedMinorUnits}.',
      );
      ref.invalidate(clientWorkspaceProvider);
      return result;
    } catch (error) {
      state = state.copyWith(
        isSubmitting: false,
        statusMessage: error.toString(),
      );
      rethrow;
    }
  }

  void clearStatus() {
    state = state.copyWith(
      clearStatusMessage: true,
      clearLastCreatedTransfer: true,
      clearLastClaimedTransfer: true,
    );
  }

  String _buildRequestId() {
    final now = DateTime.now().toUtc();
    return 'gift-${now.microsecondsSinceEpoch}';
  }
}
