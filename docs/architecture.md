# TeamCash Architecture Audit

Audit date: 2026-04-05

## 1. Audit Summary

### What already exists
- Valid Flutter workspace with Android, iOS, web, desktop targets, and Git history.
- Android Firebase config file at `android/app/google-services.json` for Firebase project `teamcash-83a6e`.
- Standard Flutter tooling files and a clean working tree before this pass.

### What is reusable
- Existing Flutter project root and platform scaffolding.
- Existing Android Firebase project identity values inside `google-services.json`.
- Existing package name intent around `teamcash`, which is preserved.

### What is missing
- Any real application architecture in `lib/`.
- Any Firebase runtime bootstrap for Flutter.
- Any feature modules for owner, staff, or client.
- Any schema, Firestore security rules, indexes, storage rules, or Cloud Functions source.
- Any role-based auth implementation.
- Any ledger, wallet, transfer, shared checkout, or tandem-group logic.

### What should stay unchanged
- The repository itself as the main working project.
- Flutter as the app framework and Firebase as the backend platform.
- The private-group cashback tandem product rules from the brief.
- Client transfer and shared checkout as first-class flows.

### Critical findings
- `android/app/build.gradle.kts` still used `com.example.teamcash`, while `google-services.json` is bound to `uz.teamcash`. That made the Android Firebase wiring inconsistent.
- Web Firebase options were not configured, so Chrome development needed a graceful runtime fallback instead of a hard stop.
- The app code was still the Flutter counter scaffold, so there was no safe way to “extend existing features” without first laying down foundational structure.

## 2. Proposed Production Architecture

### Flutter module structure

```text
lib/
  app/
    bootstrap/
    router/
    theme/
  core/
    models/
    utils/
  data/
    preview/
  features/
    root/
    owner/
    staff/
    client/
    shared/
```

This keeps app-wide concerns separate from feature surfaces and leaves a clear place to add repositories, controllers, and Firebase-backed data sources in later phases.

### Role shell structure
- Owner shell:
  `Businesses`, `Dashboard`, `Staffs`
- Staff shell:
  `Dashboard`, `Scan`, `Profile`
- Client shell:
  `Stores`, `Wallet`, `History`, `Profile`

Each shell is isolated because the permissions, navigation, and decision surface are materially different.

### Auth design

#### Owner / staff
- Firebase Auth `email/password` behind a username-first UX.
- Store normalized usernames in `operatorUsernames/{username}`.
- Store account profile and authorization data in `operatorAccounts/{uid}`.
- Owners may reference multiple businesses.
- Staff references exactly one `businessId`.
- Staff disable is soft only: `disabledAt`, `disabledBy`, `disableReason`.
- Password reset and staff creation must run through Cloud Functions using Admin SDK.

#### Client
- Firebase Auth phone authentication for verified app users.
- Wallet identity is separate from app auth identity.
- `customers/{customerId}` stores the phone-first shadow customer record.
- `customerPhoneIndex/{e164}` maps phone number to `customerId`.
- `customerAuthLinks/{uid}` binds verified app auth to the existing customer wallet identity.
- Claim flow:
  1. staff issues cashback to a phone number
  2. backend creates or reuses `customers/{customerId}`
  3. later, verified phone auth links the app user to the same `customerId`
  4. wallet/history appear automatically because the wallet never lived on the auth user document

### Firestore schema

#### Identity / auth
- `operatorAccounts/{uid}`
  role, ownerId, businessIds or businessId, disabledAt, displayName
- `operatorUsernames/{normalizedUsername}`
  uid, loginAliasEmail, status
- `customers/{customerId}`
  phoneE164, displayName, isClaimed, claimedByUid, createdFrom, createdAt
- `customerPhoneIndex/{phoneE164}`
  customerId
- `customerAuthLinks/{uid}`
  customerId, phoneE164, verifiedAt

#### Businesses and tandem groups
- `businesses/{businessId}`
  profile, settings, tandem fields, owner linkage
- `businesses/{businessId}/locations/{locationId}`
- `businesses/{businessId}/products/{productId}`
- `businesses/{businessId}/services/{serviceId}`
- `businesses/{businessId}/media/{mediaId}`
- `businesses/{businessId}/statsDaily/{yyyyMMdd}`
- `groups/{groupId}`
  name, status, memberBusinessIds, createdByBusinessId
- `groups/{groupId}/members/{businessId}`
  joinedAt, joinedByRequestId, status
- `groups/{groupId}/joinRequests/{requestId}`
  targetBusinessId, requestedByOwnerUid, status
- `groups/{groupId}/joinRequests/{requestId}/votes/{businessId}`
  vote yes/no, votedByUid, votedAt
- `groups/{groupId}/history/{entryId}`
  membership audit trail

#### Ledger / wallet
- `walletLots/{lotId}`
  ownerCustomerId, groupId, issuerBusinessId, originalIssueEventId, expiresAt, availableMinorUnits, status
- `ledgerEvents/{eventId}`
  eventType, groupId, issuerBusinessId, sourceCustomerId, targetCustomerId, sharedCheckoutId, lotId, amountMinorUnits, createdAt, participantBusinessIds, participantCustomerIds
- `sharedCheckouts/{checkoutId}`
  businessId, groupId, totalMinorUnits, status, createdByOperatorUid, finalizedAt
- `sharedCheckouts/{checkoutId}/contributions/{contributionId}`
  customerId, amountMinorUnits, sourceLotIds, contributedAt

#### Stats / notifications
- `businessNotifications/{notificationId}`
- `ownerDashboards/{ownerUid}/summary/current`
- `clientViews/{customerId}/expiringLots/{lotId}`

### Cloud Functions responsibility map

#### Auth / identity
- `createOwnerAccount`
- `createStaffAccount`
- `disableStaffAccount`
- `resetStaffPassword`
- `claimCustomerWalletByPhone`

#### Tandem governance
- `createGroup`
- `requestGroupJoin`
- `voteOnGroupJoin`

#### Ledger
- `issueCashback`
- `redeemCashback`
- `createGiftTransfer`
- `claimGiftTransfer`
- `cancelGiftTransfer`
- `expireWalletLots`
- `refundCashback`
- `adminAdjustLedger`

#### Shared checkout
- `createSharedCheckout`
- `contributeSharedCheckout`
- `finalizeSharedCheckout`
- `cancelSharedCheckout`

#### Aggregations
- `onLedgerEventWritten`
- `onBusinessContentChanged`
- `onGroupMembershipChanged`

### Security model
- Direct client writes are allowed only for safe profile/content updates.
- All money-like writes are denied from clients:
  wallet lots, ledger events, shared checkout contributions, group approvals, staff auth actions.
- Firestore rules read `operatorAccounts` and `customerAuthLinks` to determine access scope.
- Storage access is limited to business owners for business media and to the linked customer for personal assets.
- Staff never receive multi-business scope.
- Group access is authenticated-only because the product is private, not a public marketplace.

### Navigation map
- `/`
  architecture hub / runtime entry
- `/owner`
  owner shell
- `/staff`
  staff shell
- `/client`
  client shell

Later phases should redirect into these shells from actual auth state rather than manual role entry.

## 3. Implementation Plan

### Phase 1: foundation
- replace scaffold app with modular shell architecture
- add theme, router, preview-safe bootstrap, and role surfaces
- add repo documentation, rules, and backend skeleton

### Phase 2: auth and identity
- owner/staff username + password flow using Firebase Auth alias emails
- client phone auth with shadow wallet claim
- operator/customer session bootstrapping

### Phase 3: business and tandem management
- business CRUD
- locations/products/services/media
- group creation / join / unanimous approval workflow

### Phase 4: authoritative ledger
- issue cashback
- redeem cashback
- expiry/refund/admin adjustment
- wallet lot projection and customer history queries

### Phase 5: transfer and shared checkout
- verified-user instant transfer
- pending gift by phone with claim/cancel rules
- multi-client shared checkout lifecycle

### Phase 6: dashboards and hardening
- stats aggregation
- notifications
- App Check, stricter indexes, analytics views, polish

## 4. What this pass implemented
- New Flutter app foundation with owner, staff, and client shells.
- Preview-safe Firebase bootstrap that keeps Chrome work moving without fake runtime config.
- Seeded domain snapshot that already reflects the required product rules.
- Initial Firestore rules, storage rules, indexes, Firebase config file, and Functions scaffold.
- Android package realignment toward the existing Firebase app identity.

## 5. Immediate next build phase
- Connect the new shells to real auth state.
- Implement `claimCustomerWalletByPhone`, `createStaffAccount`, and `issueCashback` first.
- Follow immediately with `redeemCashback`, then transfer/shared checkout transaction flows.
