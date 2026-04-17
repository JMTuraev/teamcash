import type { Timestamp } from 'firebase-admin/firestore';

import { db, serverTimestamp } from './core.js';

interface ExpiredLotNotificationRecord {
  customerId: string;
  groupId: string;
  amountMinorUnits: number;
  eventId: string;
}

export async function safelyRunNotificationTask(
  description: string,
  task: () => Promise<void>,
) {
  try {
    await task();
  } catch (error) {
    console.error(`[notifications] ${description} failed`, error);
  }
}

export async function notifyStaffAssignment({
  staffUid,
  businessId,
  businessName,
}: {
  staffUid: string;
  businessId: string;
  businessName: string;
}) {
  await persistNotification({
    notificationId: `staff-assigned-${staffUid}-${businessId}`,
    recipientUid: staffUid,
    roleSurface: 'staff',
    kind: 'staff_assignment',
    title: `Assigned to ${businessName}`,
    body: `Your staff access is now limited to ${businessName}. Use the dashboard and scan surface for this business only.`,
    businessId,
    entityId: businessId,
    actionRoute: '/staff',
    actionLabel: 'Open staff workspace',
  });
}

export async function notifyOwnersOfGroupJoinRequest({
  requestId,
  groupId,
  groupName,
  targetBusinessId,
  targetBusinessName,
  activeBusinessIds,
}: {
  requestId: string;
  groupId: string;
  groupName: string;
  targetBusinessId: string;
  targetBusinessName: string;
  activeBusinessIds: string[];
}) {
  const ownerUids = await loadOwnerUidsForBusinessIds(activeBusinessIds);
  await Promise.all(
    ownerUids.map((ownerUid) =>
      persistNotification({
        notificationId: `owner-join-request-${requestId}-${ownerUid}`,
        recipientUid: ownerUid,
        roleSurface: 'owner',
        kind: 'group_join_requested',
        title: `${targetBusinessName} requested to join ${groupName}`,
        body:
          'All active member businesses must approve before this business can join the tandem.',
        businessId: targetBusinessId,
        groupId,
        entityId: requestId,
        actionRoute: '/owner',
        actionLabel: 'Open approvals',
      }),
    ),
  );
}

export async function notifyTargetOwnersOfGroupJoinVote({
  requestId,
  groupId,
  groupName,
  targetBusinessId,
  targetBusinessName,
  status,
  approvalsReceived,
  approvalsRequired,
}: {
  requestId: string;
  groupId: string;
  groupName: string;
  targetBusinessId: string;
  targetBusinessName: string;
  status: string;
  approvalsReceived: number;
  approvalsRequired: number;
}) {
  const ownerUids = await loadOwnerUidsForBusinessIds([targetBusinessId]);
  let title = `${targetBusinessName} join request is still pending`;
  let body = `${approvalsReceived}/${approvalsRequired} approvals are now recorded in ${groupName}.`;

  if (status == 'approved') {
    title = `${targetBusinessName} was approved for ${groupName}`;
    body =
      'All required member approvals were received. The business is now active inside the tandem group.';
  } else if (status == 'rejected') {
    title = `${targetBusinessName} was rejected by ${groupName}`;
    body =
      'One of the current member businesses voted no, so the join request has been closed.';
  }

  await Promise.all(
    ownerUids.map((ownerUid) =>
      persistNotification({
        notificationId: `owner-join-status-${requestId}-${ownerUid}`,
        recipientUid: ownerUid,
        roleSurface: 'owner',
        kind: `group_join_${status}`,
        title,
        body,
        businessId: targetBusinessId,
        groupId,
        entityId: requestId,
        actionRoute: '/owner',
        actionLabel: 'Open group status',
      }),
    ),
  );
}

export async function notifyRecipientOfPendingGift({
  transferId,
  recipientPhoneE164,
  groupId,
  amountMinorUnits,
}: {
  transferId: string;
  recipientPhoneE164: string;
  groupId: string;
  amountMinorUnits: number;
}) {
  const phoneIndexSnap = await db
    .doc(`customerPhoneIndex/${recipientPhoneE164}`)
    .get();
  if (!phoneIndexSnap.exists) {
    return;
  }

  const recipientCustomerId = phoneIndexSnap.data()?.customerId;
  if (
    typeof recipientCustomerId != 'string' ||
    recipientCustomerId.trim().length == 0
  ) {
    return;
  }

  const recipientUid = await loadClaimedCustomerUid(recipientCustomerId);
  if (recipientUid == null) {
    return;
  }

  await persistNotification({
    notificationId: `client-gift-pending-${transferId}-${recipientUid}`,
    recipientUid,
    roleSurface: 'client',
    kind: 'gift_pending',
    title: 'Cashback gift is waiting for you',
    body: `A same-group gift worth ${formatNotificationAmount(amountMinorUnits)} is ready to claim in your wallet.`,
    customerId: recipientCustomerId,
    groupId,
    entityId: transferId,
    actionRoute: '/client',
    actionLabel: 'Open wallet',
  });
}

export async function notifySenderOfGiftClaim({
  transferId,
  claimedMinorUnits,
  expiredMinorUnits,
}: {
  transferId: string;
  claimedMinorUnits: number;
  expiredMinorUnits: number;
}) {
  const transferSnap = await db.doc(`giftTransfers/${transferId}`).get();
  if (!transferSnap.exists) {
    return;
  }

  const transfer = transferSnap.data() as {
    sourceCustomerId?: string | null;
    groupId?: string | null;
  };
  if (
    typeof transfer.sourceCustomerId != 'string' ||
    transfer.sourceCustomerId.trim().length == 0
  ) {
    return;
  }

  const senderUid = await loadClaimedCustomerUid(transfer.sourceCustomerId);
  if (senderUid == null) {
    return;
  }

  const title =
    claimedMinorUnits > 0
      ? 'Your cashback gift was claimed'
      : 'Your cashback gift expired';
  const body =
    claimedMinorUnits > 0
      ? `The recipient claimed ${formatNotificationAmount(claimedMinorUnits)}.${expiredMinorUnits > 0 ? ` ${formatNotificationAmount(expiredMinorUnits)} expired before claim.` : ''}`
      : 'The reserved gift expired before it could be claimed.';

  await persistNotification({
    notificationId: `client-gift-claimed-${transferId}-${senderUid}`,
    recipientUid: senderUid,
    roleSurface: 'client',
    kind: claimedMinorUnits > 0 ? 'gift_claimed' : 'gift_expired',
    title,
    body,
    customerId: transfer.sourceCustomerId,
    groupId:
      typeof transfer.groupId == 'string' && transfer.groupId.trim().length > 0
        ? transfer.groupId.trim()
        : null,
    entityId: transferId,
    actionRoute: '/client',
    actionLabel: 'Open history',
  });
}

export async function notifyClaimedCustomerCashbackIssued({
  customerId,
  businessId,
  businessName,
  groupId,
  amountMinorUnits,
  eventId,
}: {
  customerId: string;
  businessId: string;
  businessName: string;
  groupId: string;
  amountMinorUnits: number;
  eventId: string;
}) {
  await notifyClaimedCustomer({
    notificationId: `client-issue-${eventId}-${customerId}`,
    customerId,
    roleSurface: 'client',
    kind: 'cashback_issued',
    title: `Cashback added from ${businessName}`,
    body: `${formatNotificationAmount(amountMinorUnits)} was issued to your wallet and stays bound to this tandem group.`,
    businessId,
    groupId,
    entityId: eventId,
    actionRoute: '/client',
    actionLabel: 'Open wallet',
  });
}

export async function notifyClaimedCustomerCashbackRedeemed({
  customerId,
  businessId,
  businessName,
  groupId,
  amountMinorUnits,
  redemptionBatchId,
}: {
  customerId: string;
  businessId: string;
  businessName: string;
  groupId: string;
  amountMinorUnits: number;
  redemptionBatchId: string;
}) {
  await notifyClaimedCustomer({
    notificationId: `client-redeem-${redemptionBatchId}-${customerId}`,
    customerId,
    roleSurface: 'client',
    kind: 'cashback_redeemed',
    title: `Cashback redeemed at ${businessName}`,
    body: `${formatNotificationAmount(amountMinorUnits)} was used at checkout from your tandem wallet.`,
    businessId,
    groupId,
    entityId: redemptionBatchId,
    actionRoute: '/client',
    actionLabel: 'Open history',
  });
}

export async function notifyRefundBatchCustomers({
  refundBatchId,
  businessId,
  businessName,
}: {
  refundBatchId: string;
  businessId: string;
  businessName: string;
}) {
  const refundSnapshots = await db
    .collection('ledgerEvents')
    .where('refundBatchId', '==', refundBatchId)
    .get();

  const summaries = new Map<
    string,
    { amountMinorUnits: number; groupId: string | null }
  >();

  for (const doc of refundSnapshots.docs) {
    const event = doc.data() as {
      eventType?: string | null;
      sourceCustomerId?: string | null;
      amountMinorUnits?: number;
      groupId?: string | null;
    };
    if (
      event.eventType != 'refund' ||
      typeof event.sourceCustomerId != 'string' ||
      typeof event.amountMinorUnits != 'number'
    ) {
      continue;
    }

    const summary = summaries.get(event.sourceCustomerId) ?? {
      amountMinorUnits: 0,
      groupId:
        typeof event.groupId == 'string' && event.groupId.trim().length > 0
          ? event.groupId.trim()
          : null,
    };
    summary.amountMinorUnits += event.amountMinorUnits;
    summaries.set(event.sourceCustomerId, summary);
  }

  await Promise.all(
    [...summaries.entries()].map(([customerId, summary]) =>
      notifyClaimedCustomer({
        notificationId: `client-refund-${refundBatchId}-${customerId}`,
        customerId,
        roleSurface: 'client',
        kind: 'cashback_refunded',
        title: `Cashback refunded by ${businessName}`,
        body: `${formatNotificationAmount(summary.amountMinorUnits)} was returned to your wallet after a checkout refund.`,
        businessId,
        groupId: summary.groupId,
        entityId: refundBatchId,
        actionRoute: '/client',
        actionLabel: 'Open wallet',
      }),
    ),
  );
}

export async function notifyClaimedCustomerAdminAdjustment({
  customerId,
  businessId,
  businessName,
  groupId,
  amountMinorUnits,
  direction,
  adjustmentBatchId,
  note,
}: {
  customerId: string;
  businessId: string;
  businessName: string;
  groupId: string;
  amountMinorUnits: number;
  direction: string;
  adjustmentBatchId: string;
  note: string;
}) {
  const title =
    direction == 'credit'
      ? `Wallet credited by ${businessName}`
      : `Wallet adjusted by ${businessName}`;
  const body =
    direction == 'credit'
      ? `${formatNotificationAmount(amountMinorUnits)} was added to your wallet by the business owner.${note.length > 0 ? ` Note: ${note}` : ''}`
      : `${formatNotificationAmount(amountMinorUnits)} was removed from your wallet by the business owner.${note.length > 0 ? ` Note: ${note}` : ''}`;

  await notifyClaimedCustomer({
    notificationId: `client-admin-adjustment-${adjustmentBatchId}-${customerId}`,
    customerId,
    roleSurface: 'client',
    kind: `admin_adjustment_${direction}`,
    title,
    body,
    businessId,
    groupId,
    entityId: adjustmentBatchId,
    actionRoute: '/client',
    actionLabel: 'Open history',
  });
}

export async function notifyCustomersOfExpiredLots({
  expiredLots,
  trigger,
}: {
  expiredLots: ExpiredLotNotificationRecord[];
  trigger: 'manual_sweep' | 'scheduled_sweep';
}) {
  const summaries = new Map<
    string,
    {
      customerId: string;
      groupId: string;
      amountMinorUnits: number;
      eventIds: string[];
    }
  >();

  for (const lot of expiredLots) {
    const summaryKey = `${lot.customerId}::${lot.groupId}`;
    const summary = summaries.get(summaryKey) ?? {
      customerId: lot.customerId,
      groupId: lot.groupId,
      amountMinorUnits: 0,
      eventIds: [],
    };
    summary.amountMinorUnits += lot.amountMinorUnits;
    summary.eventIds.push(lot.eventId);
    summaries.set(summaryKey, summary);
  }

  await Promise.all(
    [...summaries.values()].map((summary) =>
      notifyClaimedCustomer({
        notificationId: `client-expire-${summary.eventIds[0]}-${summary.customerId}`,
        customerId: summary.customerId,
        roleSurface: 'client',
        kind: 'cashback_expired',
        title: 'Cashback expired from your wallet',
        body: `${formatNotificationAmount(summary.amountMinorUnits)} expired before it was used.${trigger == 'manual_sweep' ? ' The business ran an expiry sweep.' : ''}`,
        groupId: summary.groupId,
        entityId: summary.eventIds[0],
        actionRoute: '/client',
        actionLabel: 'Open history',
      }),
    ),
  );
}

export async function notifyClaimedCustomerSharedCheckoutContributionReserved({
  customerId,
  businessId,
  businessName,
  groupId,
  amountMinorUnits,
  checkoutId,
  contributionId,
}: {
  customerId: string;
  businessId: string;
  businessName: string;
  groupId: string | null;
  amountMinorUnits: number;
  checkoutId: string;
  contributionId: string;
}) {
  await notifyClaimedCustomer({
    notificationId: `client-shared-reserved-${contributionId}-${customerId}`,
    customerId,
    roleSurface: 'client',
    kind: 'shared_checkout_contribution',
    title: `Contribution reserved for ${businessName}`,
    body: `${formatNotificationAmount(amountMinorUnits)} is reserved for a shared checkout and will be finalized by the business.`,
    businessId,
    groupId,
    entityId: checkoutId,
    actionRoute: '/client',
    actionLabel: 'Open wallet',
  });
}

export async function notifyCustomersOfFinalizedSharedCheckout({
  checkoutId,
  businessId,
  businessName,
  groupId,
}: {
  checkoutId: string;
  businessId: string;
  businessName: string;
  groupId: string | null;
}) {
  const contributionsSnap = await db
    .collection(`sharedCheckouts/${checkoutId}/contributions`)
    .get();
  const summaries = new Map<
    string,
    { redeemedMinorUnits: number; expiredMinorUnits: number }
  >();

  for (const doc of contributionsSnap.docs) {
    const contribution = doc.data() as {
      customerId?: string | null;
      redeemedMinorUnits?: number;
      expiredMinorUnits?: number;
    };
    if (typeof contribution.customerId != 'string') {
      continue;
    }

    const summary = summaries.get(contribution.customerId) ?? {
      redeemedMinorUnits: 0,
      expiredMinorUnits: 0,
    };
    summary.redeemedMinorUnits += contribution.redeemedMinorUnits ?? 0;
    summary.expiredMinorUnits += contribution.expiredMinorUnits ?? 0;
    summaries.set(contribution.customerId, summary);
  }

  await Promise.all(
    [...summaries.entries()].map(([customerId, summary]) => {
      if (
        summary.redeemedMinorUnits <= 0 &&
        summary.expiredMinorUnits <= 0
      ) {
        return Promise.resolve();
      }

      const parts = [
        summary.redeemedMinorUnits > 0
          ? `${formatNotificationAmount(summary.redeemedMinorUnits)} was consumed`
          : null,
        summary.expiredMinorUnits > 0
          ? `${formatNotificationAmount(summary.expiredMinorUnits)} expired before finalization`
          : null,
      ].filter((value): value is string => value != null);

      return notifyClaimedCustomer({
        notificationId: `client-shared-finalized-${checkoutId}-${customerId}`,
        customerId,
        roleSurface: 'client',
        kind: 'shared_checkout_finalized',
        title: `Shared checkout finalized at ${businessName}`,
        body: `${parts.join('. ')}.`,
        businessId,
        groupId,
        entityId: checkoutId,
        actionRoute: '/client',
        actionLabel: 'Open history',
      });
    }),
  );
}

async function notifyClaimedCustomer({
  notificationId,
  customerId,
  roleSurface,
  kind,
  title,
  body,
  businessId,
  groupId,
  entityId,
  actionRoute,
  actionLabel,
}: {
  notificationId: string;
  customerId: string;
  roleSurface: 'client';
  kind: string;
  title: string;
  body: string;
  businessId?: string | null;
  groupId?: string | null;
  entityId?: string | null;
  actionRoute?: string | null;
  actionLabel?: string | null;
}) {
  const recipientUid = await loadClaimedCustomerUid(customerId);
  if (recipientUid == null) {
    return;
  }

  await persistNotification({
    notificationId,
    recipientUid,
    roleSurface,
    kind,
    title,
    body,
    businessId,
    customerId,
    groupId,
    entityId,
    actionRoute,
    actionLabel,
  });
}

async function loadOwnerUidsForBusinessIds(
  businessIds: string[],
): Promise<string[]> {
  const ownerUids = new Set<string>();

  await Promise.all(
    uniqueStrings(businessIds)
      .filter((businessId) => businessId.trim().length > 0)
      .map(async (businessId) => {
        const snapshot = await db
          .collection('operatorAccounts')
          .where('businessIds', 'array-contains', businessId)
          .get();

        for (const doc of snapshot.docs) {
          const data = doc.data() as {
            role?: string | null;
            disabledAt?: Timestamp | null;
          };
          if (data.role == 'owner' && data.disabledAt == null) {
            ownerUids.add(doc.id);
          }
        }
      }),
  );

  return [...ownerUids];
}

async function loadClaimedCustomerUid(
  customerId: string,
): Promise<string | null> {
  const customerSnap = await db.doc(`customers/${customerId}`).get();
  if (!customerSnap.exists) {
    return null;
  }

  const claimedByUid = customerSnap.data()?.claimedByUid;
  return typeof claimedByUid == 'string' && claimedByUid.trim().length > 0
    ? claimedByUid.trim()
    : null;
}

async function persistNotification({
  notificationId,
  recipientUid,
  roleSurface,
  kind,
  title,
  body,
  businessId,
  customerId,
  groupId,
  entityId,
  actionRoute,
  actionLabel,
}: {
  notificationId: string;
  recipientUid: string;
  roleSurface: 'owner' | 'staff' | 'client';
  kind: string;
  title: string;
  body: string;
  businessId?: string | null;
  customerId?: string | null;
  groupId?: string | null;
  entityId?: string | null;
  actionRoute?: string | null;
  actionLabel?: string | null;
}) {
  if (recipientUid.trim().length == 0) {
    return;
  }

  await db.doc(`notifications/${notificationId}`).set(
    {
      recipientUid,
      roleSurface,
      kind,
      title,
      body,
      businessId: businessId ?? null,
      customerId: customerId ?? null,
      groupId: groupId ?? null,
      entityId: entityId ?? null,
      actionRoute: actionRoute ?? null,
      actionLabel: actionLabel ?? null,
      isRead: false,
      readAt: null,
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    },
    { merge: true },
  );
}

function formatNotificationAmount(amountMinorUnits: number): string {
  return `UZS ${amountMinorUnits.toLocaleString('en-US')}`;
}

function uniqueStrings(values: string[]): string[] {
  return [...new Set(values)];
}
