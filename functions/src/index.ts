import {
  HttpsError,
  onCall,
  type CallableRequest,
} from 'firebase-functions/v2/https';
import * as logger from 'firebase-functions/logger';
import { onSchedule } from 'firebase-functions/v2/scheduler';

import {
  assertIntegerRange,
  assertNonEmptyString,
  assertObject,
  assertOptionalStringMaxLength,
  assertPositiveInteger,
  assertStringArray,
  assertStringMaxLength,
  normalizeHttpsError,
  requireAuthUid,
} from './core.js';
import {
  adminAdjustCashbackFlow,
  claimGiftTransferFlow,
  claimCustomerWalletByPhoneFlow,
  contributeSharedCheckoutFlow,
  createGroupFlow,
  createGiftTransferFlow,
  createSharedCheckoutFlow,
  finalizeSharedCheckoutFlow,
  expireWalletLotsFlow,
  issueCashbackFlow,
  redeemCashbackFlow,
  refundCashbackFlow,
  requestGroupJoinFlow,
  sweepExpiredActiveWalletLotsBatchFlow,
  voteOnGroupJoinFlow,
} from './operations.js';
import {
  createBusinessFlow,
  createStaffAccountFlow,
  disableStaffAccountFlow,
  resetStaffPasswordFlow,
  updateStaffProfileFlow,
} from './operator_flows.js';
import type {
  AdminAdjustCashbackInput,
  CreateBusinessInput,
  CreateGroupInput,
  ExpireWalletLotsInput,
  GiftTransferInput,
  GroupJoinRequestInput,
  GroupJoinVoteInput,
  IssueCashbackInput,
  RedeemCashbackInput,
  RefundCashbackInput,
  ResetStaffPasswordInput,
  SharedCheckoutContributionInput,
  SharedCheckoutInput,
  StaffAccountInput,
  UpdateStaffProfileInput,
} from './types.js';

const functionsRegion = process.env.TEAMCASH_FUNCTIONS_REGION?.trim() || 'us-central1';
const appCheckMode = (process.env.TEAMCASH_APPCHECK_MODE ?? 'monitor')
  .trim()
  .toLowerCase();
const enforceAppCheck = appCheckMode == 'enforce';

type CallableHandler<T = unknown> = (request: CallableRequest<T>) => Promise<unknown>;

export const createBusiness = secureOnCall<CreateBusinessInput>(
  'createBusiness',
  async (request) => {
    const ownerUid = requireAuthUid(request.auth?.uid);
    const input = assertObject<CreateBusinessInput>(request.data);

    assertStringMaxLength(input.name, 'name', 80);
    assertStringMaxLength(input.category, 'category', 40);
    assertStringMaxLength(input.description, 'description', 400);
    assertStringMaxLength(input.address, 'address', 180);
    assertStringMaxLength(input.workingHours, 'workingHours', 80);
    assertStringArray(input.phoneNumbers, 'phoneNumbers', {
      minItems: 1,
      maxItems: 4,
      maxItemLength: 24,
    });
    assertIntegerRange(input.cashbackBasisPoints, 'cashbackBasisPoints', 0, 10000);
    assertStringMaxLength(input.redeemPolicy, 'redeemPolicy', 200);

    return createBusinessFlow(ownerUid, input);
  },
);

export const createStaffAccount = secureOnCall<StaffAccountInput>(
  'createStaffAccount',
  async (request) => {
    const ownerUid = requireAuthUid(request.auth?.uid);
    const input = assertObject<StaffAccountInput>(request.data);

    assertStringMaxLength(input.businessId, 'businessId', 80);
    assertStringMaxLength(input.username, 'username', 40);
    assertStringMaxLength(input.displayName, 'displayName', 80);
    const password = assertStringMaxLength(input.password, 'password', 128);
    if (password.length < 8) {
      throw new HttpsError(
        'invalid-argument',
        'password must contain at least 8 characters.',
      );
    }

    return createStaffAccountFlow(ownerUid, input);
  },
);

export const disableStaffAccount = secureOnCall<{ staffUid: string; reason?: string }>(
  'disableStaffAccount',
  async (request) => {
    const ownerUid = requireAuthUid(request.auth?.uid);
    const input = assertObject<{ staffUid: string; reason?: string }>(request.data);
    const staffUid = assertStringMaxLength(input.staffUid, 'staffUid', 128);
    const reason = assertOptionalStringMaxLength(input.reason, 'reason', 240);

    return disableStaffAccountFlow(ownerUid, staffUid, reason);
  },
);

export const resetStaffPassword = secureOnCall<ResetStaffPasswordInput>(
  'resetStaffPassword',
  async (request) => {
    const ownerUid = requireAuthUid(request.auth?.uid);
    const input = assertObject<ResetStaffPasswordInput>(request.data);
    assertStringMaxLength(input.staffUid, 'staffUid', 128);
    const password = assertStringMaxLength(input.password, 'password', 128);
    if (password.length < 8) {
      throw new HttpsError(
        'invalid-argument',
        'password must contain at least 8 characters.',
      );
    }

    return resetStaffPasswordFlow(ownerUid, input);
  },
);

export const updateStaffProfile = secureOnCall<UpdateStaffProfileInput>(
  'updateStaffProfile',
  async (request) => {
    const ownerUid = requireAuthUid(request.auth?.uid);
    const input = assertObject<UpdateStaffProfileInput>(request.data);
    assertStringMaxLength(input.staffUid, 'staffUid', 128);
    assertStringMaxLength(input.displayName, 'displayName', 80);

    return updateStaffProfileFlow(ownerUid, input);
  },
);

export const claimCustomerWalletByPhone = secureOnCall(
  'claimCustomerWalletByPhone',
  async (request) => {
    const uid = requireAuthUid(request.auth?.uid);
    const phoneNumber = request.auth?.token.phone_number;
    return claimCustomerWalletByPhoneFlow(uid, phoneNumber);
  },
);

export const createGroup = secureOnCall<CreateGroupInput>(
  'createGroup',
  async (request) => {
    const ownerUid = requireAuthUid(request.auth?.uid);
    const input = assertObject<CreateGroupInput>(request.data);
    assertStringMaxLength(input.businessId, 'businessId', 80);
    assertStringMaxLength(input.name, 'name', 80);

    return createGroupFlow(ownerUid, input);
  },
);

export const requestGroupJoin = secureOnCall<GroupJoinRequestInput>(
  'requestGroupJoin',
  async (request) => {
    const ownerUid = requireAuthUid(request.auth?.uid);
    const input = assertObject<GroupJoinRequestInput>(request.data);
    assertStringMaxLength(input.groupId, 'groupId', 80);
    assertStringMaxLength(input.businessId, 'businessId', 80);

    return requestGroupJoinFlow(ownerUid, input);
  },
);

export const voteOnGroupJoin = secureOnCall<GroupJoinVoteInput>(
  'voteOnGroupJoin',
  async (request) => {
    const ownerUid = requireAuthUid(request.auth?.uid);
    const input = assertObject<GroupJoinVoteInput>(request.data);
    assertStringMaxLength(input.requestId, 'requestId', 120);
    if (input.vote != 'yes' && input.vote != 'no') {
      throw new HttpsError(
        'invalid-argument',
        'vote must be either yes or no.',
      );
    }
    assertOptionalStringMaxLength(input.voterBusinessId, 'voterBusinessId', 80);

    return voteOnGroupJoinFlow(ownerUid, input);
  },
);

export const issueCashback = secureOnCall<IssueCashbackInput>(
  'issueCashback',
  async (request) => {
    const operatorUid = requireAuthUid(request.auth?.uid);
    const input = assertObject<IssueCashbackInput>(request.data);

    assertStringMaxLength(input.businessId, 'businessId', 80);
    assertStringMaxLength(input.customerPhoneE164, 'customerPhoneE164', 24);
    assertStringMaxLength(input.groupId, 'groupId', 80);
    assertPositiveInteger(input.paidMinorUnits, 'paidMinorUnits');
    assertIntegerRange(input.cashbackBasisPoints, 'cashbackBasisPoints', 1, 10000);
    assertStringMaxLength(input.sourceTicketRef, 'sourceTicketRef', 120);

    return issueCashbackFlow(operatorUid, input);
  },
);

export const redeemCashback = secureOnCall<RedeemCashbackInput>(
  'redeemCashback',
  async (request) => {
    const operatorUid = requireAuthUid(request.auth?.uid);
    const input = assertObject<RedeemCashbackInput>(request.data);

    assertStringMaxLength(input.businessId, 'businessId', 80);
    assertStringMaxLength(input.groupId, 'groupId', 80);
    assertPositiveInteger(input.redeemMinorUnits, 'redeemMinorUnits');
    assertStringMaxLength(input.sourceTicketRef, 'sourceTicketRef', 120);
    assertOptionalStringMaxLength(input.customerId, 'customerId', 120);
    assertOptionalStringMaxLength(input.customerPhoneE164, 'customerPhoneE164', 24);
    if (
      (input.customerId == null || input.customerId.trim().length === 0) &&
      (input.customerPhoneE164 == null ||
        input.customerPhoneE164.trim().length === 0)
    ) {
      throw new HttpsError(
        'invalid-argument',
        'Either customerId or customerPhoneE164 must be provided.',
      );
    }

    return redeemCashbackFlow(operatorUid, input);
  },
);

export const refundCashback = secureOnCall<RefundCashbackInput>(
  'refundCashback',
  async (request) => {
    const operatorUid = requireAuthUid(request.auth?.uid);
    const input = assertObject<RefundCashbackInput>(request.data);

    assertStringMaxLength(input.businessId, 'businessId', 80);
    assertStringMaxLength(input.redemptionBatchId, 'redemptionBatchId', 140);
    assertOptionalStringMaxLength(input.note, 'note', 240);

    return refundCashbackFlow(operatorUid, input);
  },
);

export const adminAdjustCashback = secureOnCall<AdminAdjustCashbackInput>(
  'adminAdjustCashback',
  async (request) => {
    const ownerUid = requireAuthUid(request.auth?.uid);
    const input = assertObject<AdminAdjustCashbackInput>(request.data);

    assertStringMaxLength(input.businessId, 'businessId', 80);
    assertStringMaxLength(input.groupId, 'groupId', 80);
    assertStringMaxLength(input.note, 'note', 240);
    assertStringMaxLength(input.requestId, 'requestId', 120);
    assertOptionalStringMaxLength(input.customerId, 'customerId', 120);
    assertOptionalStringMaxLength(input.customerPhoneE164, 'customerPhoneE164', 24);
    if (
      typeof input.amountMinorUnits !== 'number' ||
      !Number.isInteger(input.amountMinorUnits) ||
      input.amountMinorUnits == 0
    ) {
      throw new HttpsError(
        'invalid-argument',
        'amountMinorUnits must be a non-zero whole number.',
      );
    }
    if (
      (input.customerId == null || input.customerId.trim().length === 0) &&
      (input.customerPhoneE164 == null ||
        input.customerPhoneE164.trim().length === 0)
    ) {
      throw new HttpsError(
        'invalid-argument',
        'Either customerId or customerPhoneE164 must be provided.',
      );
    }

    return adminAdjustCashbackFlow(ownerUid, input);
  },
);

export const expireWalletLots = secureOnCall<ExpireWalletLotsInput>(
  'expireWalletLots',
  async (request) => {
    const ownerUid = requireAuthUid(request.auth?.uid);
    const input = assertObject<ExpireWalletLotsInput>(request.data);

    assertStringMaxLength(input.businessId, 'businessId', 80);
    assertStringMaxLength(input.groupId, 'groupId', 80);
    if (input.maxLots != null) {
      assertIntegerRange(input.maxLots, 'maxLots', 1, 200);
    }

    return expireWalletLotsFlow(ownerUid, input);
  },
);

export const createGiftTransfer = secureOnCall<GiftTransferInput>(
  'createGiftTransfer',
  async (request) => {
    const uid = requireAuthUid(request.auth?.uid);
    const input = assertObject<GiftTransferInput>(request.data);

    assertStringMaxLength(input.sourceCustomerId, 'sourceCustomerId', 120);
    assertStringMaxLength(input.recipientPhoneE164, 'recipientPhoneE164', 24);
    assertStringMaxLength(input.groupId, 'groupId', 80);
    assertPositiveInteger(input.amountMinorUnits, 'amountMinorUnits');
    assertStringMaxLength(input.requestId, 'requestId', 120);

    return createGiftTransferFlow(uid, input);
  },
);

export const claimGiftTransfer = secureOnCall<{ transferId: string }>(
  'claimGiftTransfer',
  async (request) => {
    const uid = requireAuthUid(request.auth?.uid);
    const input = assertObject<{ transferId: string }>(request.data);
    assertStringMaxLength(input.transferId, 'transferId', 120);
    const phoneNumber = request.auth?.token.phone_number;

    return claimGiftTransferFlow(uid, input.transferId, phoneNumber);
  },
);

export const createSharedCheckout = secureOnCall<SharedCheckoutInput>(
  'createSharedCheckout',
  async (request) => {
    const operatorUid = requireAuthUid(request.auth?.uid);
    const input = assertObject<SharedCheckoutInput>(request.data);
    assertStringMaxLength(input.businessId, 'businessId', 80);
    assertStringMaxLength(input.groupId, 'groupId', 80);
    assertPositiveInteger(input.totalMinorUnits, 'totalMinorUnits');
    assertStringMaxLength(input.sourceTicketRef, 'sourceTicketRef', 120);

    return createSharedCheckoutFlow(operatorUid, input);
  },
);

export const contributeSharedCheckout = secureOnCall<SharedCheckoutContributionInput>(
  'contributeSharedCheckout',
  async (request) => {
    const uid = requireAuthUid(request.auth?.uid);
    const input = assertObject<SharedCheckoutContributionInput>(request.data);
    assertStringMaxLength(input.checkoutId, 'checkoutId', 120);
    assertStringMaxLength(input.customerId, 'customerId', 120);
    assertPositiveInteger(input.contributionMinorUnits, 'contributionMinorUnits');
    assertStringMaxLength(input.requestId, 'requestId', 120);

    return contributeSharedCheckoutFlow(uid, input);
  },
);

export const finalizeSharedCheckout = secureOnCall<{ checkoutId: string }>(
  'finalizeSharedCheckout',
  async (request) => {
    const operatorUid = requireAuthUid(request.auth?.uid);
    const input = assertObject<{ checkoutId: string }>(request.data);
    assertStringMaxLength(input.checkoutId, 'checkoutId', 120);

    return finalizeSharedCheckoutFlow(operatorUid, input.checkoutId);
  },
);

export const sweepExpiredWalletLots = onSchedule(
  {
    region: functionsRegion,
    schedule: 'every 4 hours',
  },
  async () => {
    const startedAt = Date.now();
    try {
      const result = await sweepExpiredActiveWalletLotsBatchFlow({
        limit: 200,
        trigger: 'scheduled_sweep',
      });
      logger.info('scheduled_callable_completed', {
        callable: 'sweepExpiredWalletLots',
        durationMs: Date.now() - startedAt,
        result,
      });
    } catch (error) {
      const normalized = normalizeHttpsError(error);
      logger.error('scheduled_callable_failed', {
        callable: 'sweepExpiredWalletLots',
        durationMs: Date.now() - startedAt,
        errorCode: normalized.code,
        errorMessage: normalized.message,
      });
      throw normalized;
    }
  },
);

function secureOnCall<T = unknown>(
  name: string,
  handler: CallableHandler<T>,
  options: {
    timeoutSeconds?: number;
    enforceAppCheck?: boolean;
  } = {},
) {
  return onCall(
    {
      region: functionsRegion,
      cors: true,
      timeoutSeconds: options.timeoutSeconds ?? 60,
      enforceAppCheck: enforceAppCheck && (options.enforceAppCheck ?? true),
    },
    async (request) => {
      const startedAt = Date.now();
      const requestData = readRequestData(request.data);
      const metadata = {
        callable: name,
        uid: request.auth?.uid ?? null,
        appId: request.app?.appId ?? null,
        appCheckEnforced: enforceAppCheck && (options.enforceAppCheck ?? true),
        appCheckAlreadyConsumed: request.app?.alreadyConsumed ?? null,
        idempotencyKey:
          readStringField(requestData, 'requestId') ??
          readStringField(requestData, 'sourceTicketRef') ??
          readStringField(requestData, 'redemptionBatchId') ??
          readStringField(requestData, 'checkoutId') ??
          null,
      };

      logger.info('callable_started', metadata);

      try {
        const result = await handler(request);
        logger.info('callable_completed', {
          ...metadata,
          durationMs: Date.now() - startedAt,
          resultKeys:
            result != null && typeof result == 'object'
              ? Object.keys(result as Record<string, unknown>).slice(0, 12)
              : [],
        });
        return result;
      } catch (error) {
        const normalized = normalizeHttpsError(error);
        logger.error('callable_failed', {
          ...metadata,
          durationMs: Date.now() - startedAt,
          errorCode: normalized.code,
          errorMessage: normalized.message,
        });
        throw normalized;
      }
    },
  );
}

function readRequestData(data: unknown): Record<string, unknown> | undefined {
  if (data == null || typeof data !== 'object' || Array.isArray(data)) {
    return undefined;
  }

  return data as Record<string, unknown>;
}

function readStringField(
  data: Record<string, unknown> | undefined,
  key: string,
): string | undefined {
  const value = data?.[key];
  return typeof value == 'string' && value.trim().length > 0
    ? value.trim()
    : undefined;
}
