export type OperatorRole = 'owner' | 'staff';

export interface StaffAccountInput {
  businessId: string;
  username: string;
  displayName: string;
  password: string;
}

export interface ResetStaffPasswordInput {
  staffUid: string;
  password: string;
}

export interface UpdateStaffProfileInput {
  staffUid: string;
  displayName: string;
}

export interface CreateBusinessInput {
  name: string;
  category: string;
  description: string;
  address: string;
  workingHours: string;
  phoneNumbers: string[];
  cashbackBasisPoints: number;
  redeemPolicy: string;
}

export interface CreateGroupInput {
  businessId: string;
  name: string;
}

export interface GroupJoinRequestInput {
  groupId: string;
  businessId: string;
}

export interface GroupJoinVoteInput {
  requestId: string;
  vote: 'yes' | 'no';
  voterBusinessId?: string;
}

export interface IssueCashbackInput {
  businessId: string;
  customerPhoneE164: string;
  groupId: string;
  paidMinorUnits: number;
  cashbackBasisPoints: number;
  sourceTicketRef: string;
}

export interface RedeemCashbackInput {
  businessId: string;
  customerId?: string;
  customerPhoneE164?: string;
  groupId: string;
  redeemMinorUnits: number;
  sourceTicketRef: string;
}

export interface RefundCashbackInput {
  businessId: string;
  redemptionBatchId: string;
  note?: string;
}

export interface ExpireWalletLotsInput {
  businessId: string;
  groupId: string;
  maxLots?: number;
}

export interface AdminAdjustCashbackInput {
  businessId: string;
  customerId?: string;
  customerPhoneE164?: string;
  groupId: string;
  amountMinorUnits: number;
  note: string;
  requestId: string;
}

export interface GiftTransferInput {
  sourceCustomerId: string;
  recipientPhoneE164: string;
  groupId: string;
  amountMinorUnits: number;
  requestId: string;
}

export interface SharedCheckoutInput {
  businessId: string;
  groupId: string;
  totalMinorUnits: number;
  sourceTicketRef: string;
}

export interface SharedCheckoutContributionInput {
  checkoutId: string;
  customerId: string;
  contributionMinorUnits: number;
  requestId: string;
}
