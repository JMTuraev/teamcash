import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:teamcash/app/app.dart';
import 'package:teamcash/app/bootstrap/firebase_bootstrap.dart';
import 'package:teamcash/core/models/app_role.dart';
import 'package:teamcash/core/models/business_models.dart';
import 'package:teamcash/core/models/business_content_models.dart';
import 'package:teamcash/core/models/dashboard_models.dart';
import 'package:teamcash/core/models/wallet_models.dart';
import 'package:teamcash/core/models/workspace_models.dart';
import 'package:teamcash/core/session/app_session.dart';
import 'package:teamcash/core/session/session_controller.dart';
import 'package:teamcash/core/utils/formatters.dart';

final firestoreWorkspaceRepositoryProvider =
    Provider<FirestoreWorkspaceRepository>(
      (ref) => FirestoreWorkspaceRepository(FirebaseFirestore.instance),
    );

final ownerWorkspaceProvider = FutureProvider<OwnerWorkspace>((ref) async {
  final preview = ref.watch(appSnapshotProvider).owner;
  final bootstrap = ref.watch(firebaseStatusProvider);
  final session = ref.watch(currentSessionProvider);

  if (!_shouldLoadLiveWorkspace(
    session: session,
    bootstrap: bootstrap,
    role: AppRole.owner,
  )) {
    return preview;
  }

  return ref
      .watch(firestoreWorkspaceRepositoryProvider)
      .loadOwnerWorkspace(session!, preview);
});

final staffWorkspaceProvider = FutureProvider<StaffWorkspace>((ref) async {
  final preview = ref.watch(appSnapshotProvider).staff;
  final bootstrap = ref.watch(firebaseStatusProvider);
  final session = ref.watch(currentSessionProvider);

  if (!_shouldLoadLiveWorkspace(
    session: session,
    bootstrap: bootstrap,
    role: AppRole.staff,
  )) {
    return preview;
  }

  return ref
      .watch(firestoreWorkspaceRepositoryProvider)
      .loadStaffWorkspace(session!, preview);
});

final clientWorkspaceProvider = FutureProvider<ClientWorkspace>((ref) async {
  final preview = ref.watch(appSnapshotProvider).client;
  final bootstrap = ref.watch(firebaseStatusProvider);
  final session = ref.watch(currentSessionProvider);

  if (!_shouldLoadLiveWorkspace(
    session: session,
    bootstrap: bootstrap,
    role: AppRole.client,
  )) {
    return preview;
  }

  return ref
      .watch(firestoreWorkspaceRepositoryProvider)
      .loadClientWorkspace(session!, preview);
});

bool _shouldLoadLiveWorkspace({
  required AppSession? session,
  required FirebaseBootstrapResult bootstrap,
  required AppRole role,
}) {
  return bootstrap.mode == FirebaseBootstrapMode.connected &&
      session != null &&
      session.isPreview == false &&
      session.role == role;
}

class FirestoreWorkspaceRepository {
  FirestoreWorkspaceRepository(this._firestore);

  final FirebaseFirestore _firestore;
  static const Duration _firestoreRequestTimeout = Duration(seconds: 20);

  Future<OwnerWorkspace> loadOwnerWorkspace(
    AppSession session,
    OwnerWorkspace preview,
  ) async {
    final ownerUid = session.uid;
    if (ownerUid == null || ownerUid.isEmpty) {
      return preview;
    }

    final operatorSnap = await _awaitFirestoreStep(
      _firestore.doc('operatorAccounts/$ownerUid').get(),
      'owner operator account',
    );
    final operatorData = operatorSnap.data() ?? <String, dynamic>{};
    final businessIds = {
      ...session.businessIds,
      ...((operatorData['businessIds'] as List<dynamic>?) ?? const [])
          .whereType<String>(),
    }.toList();
    if (businessIds.isEmpty) {
      return preview;
    }

    final businessesFuture = _loadBusinessesByIds(businessIds);
    final statsHistoryFuture = _loadStatsHistoryByBusinessId(businessIds);
    final businesses = await businessesFuture;
    final statsHistory = await statsHistoryFuture;
    final groups = await _loadGroupsById(
      businesses.values
          .map((business) => business['groupId'])
          .whereType<String>()
          .toSet(),
    );
    final groupHistory = await _loadGroupHistoryByGroupId(groups.keys);

    final businessSummaries = businessIds
        .map((businessId) => businesses[businessId])
        .whereType<Map<String, dynamic>>()
        .map(_mapBusinessSummary)
        .toList();

    final todayDayId = _dayIdForDate(DateTime.now());
    final yesterdayDayId = _dayIdForDate(
      DateTime.now().subtract(const Duration(days: 1)),
    );
    final recentDayIds = _recentDayIds(count: 7);
    final previousDayIds = _recentDayIds(count: 7, endOffsetDays: 7);

    final allStats = statsHistory.values.expand((records) => records);
    final totalSalesMinorUnits = _sumStats(allStats, 'totalSalesMinorUnits');
    final salesCount = _sumStats(allStats, 'salesCount');
    final cashbackIssuedMinorUnits = _sumStats(
      allStats,
      'cashbackIssuedMinorUnits',
    );
    final cashbackRedeemedMinorUnits = _sumStats(
      allStats,
      'cashbackRedeemedMinorUnits',
    );
    final clientLookupCount = _sumStats(
      allStats,
      'scanCount',
      fallbackKey: 'qrScanCount',
    );
    final totalClientsCount = _sumStats(allStats, 'newClientCount');
    final todayUniqueClientsCount = statsHistory.values.fold<int>(
      0,
      (total, records) =>
          total +
          _readInt(
            _statsDataForDay(records, todayDayId),
            'todayClientCount',
            fallbackKey: 'uniqueClientsCount',
          ),
    );
    final yesterdayUniqueClientsCount = statsHistory.values.fold<int>(
      0,
      (total, records) =>
          total +
          _readInt(
            _statsDataForDay(records, yesterdayDayId),
            'todayClientCount',
            fallbackKey: 'uniqueClientsCount',
          ),
    );
    final recentSalesMinorUnits = _sumStatsForDayIds(
      statsHistory.values,
      recentDayIds,
      'totalSalesMinorUnits',
    );
    final previousSalesMinorUnits = _sumStatsForDayIds(
      statsHistory.values,
      previousDayIds,
      'totalSalesMinorUnits',
    );
    final recentSalesCount = _sumStatsForDayIds(
      statsHistory.values,
      recentDayIds,
      'salesCount',
    );
    final previousSalesCount = _sumStatsForDayIds(
      statsHistory.values,
      previousDayIds,
      'salesCount',
    );
    final recentIssuedMinorUnits = _sumStatsForDayIds(
      statsHistory.values,
      recentDayIds,
      'cashbackIssuedMinorUnits',
    );
    final previousIssuedMinorUnits = _sumStatsForDayIds(
      statsHistory.values,
      previousDayIds,
      'cashbackIssuedMinorUnits',
    );
    final recentRedeemedMinorUnits = _sumStatsForDayIds(
      statsHistory.values,
      recentDayIds,
      'cashbackRedeemedMinorUnits',
    );
    final previousRedeemedMinorUnits = _sumStatsForDayIds(
      statsHistory.values,
      previousDayIds,
      'cashbackRedeemedMinorUnits',
    );
    final recentLookupCount = _sumStatsForDayIds(
      statsHistory.values,
      recentDayIds,
      'scanCount',
      fallbackKey: 'qrScanCount',
    );
    final previousLookupCount = _sumStatsForDayIds(
      statsHistory.values,
      previousDayIds,
      'scanCount',
      fallbackKey: 'qrScanCount',
    );

    final trendPoints = recentDayIds
        .map(
          (dayId) => DashboardTrendPoint(
            label: _formatTrendDayLabel(dayId),
            salesMinorUnits: _sumStatsForDayIds(statsHistory.values, [
              dayId,
            ], 'totalSalesMinorUnits'),
            issuedMinorUnits: _sumStatsForDayIds(statsHistory.values, [
              dayId,
            ], 'cashbackIssuedMinorUnits'),
            redeemedMinorUnits: _sumStatsForDayIds(statsHistory.values, [
              dayId,
            ], 'cashbackRedeemedMinorUnits'),
            clientsCount: _sumStatsForDayIds(
              statsHistory.values,
              [dayId],
              'todayClientCount',
              fallbackKey: 'uniqueClientsCount',
            ),
            lookupsCount: _sumStatsForDayIds(
              statsHistory.values,
              [dayId],
              'scanCount',
              fallbackKey: 'qrScanCount',
            ),
          ),
        )
        .toList();

    final businessPerformance =
        businessSummaries.map((business) {
          final records =
              statsHistory[business.id] ?? const <_DailyStatRecord>[];
          final todayStats = _statsDataForDay(records, todayDayId);
          return BusinessPerformanceSnapshot(
            businessId: business.id,
            businessName: business.name,
            groupName: business.groupName,
            todaySalesMinorUnits: _readInt(todayStats, 'totalSalesMinorUnits'),
            todaySalesCount: _readInt(todayStats, 'salesCount'),
            rolling7DaySalesMinorUnits: _sumStatsForDayIds(
              [records],
              recentDayIds,
              'totalSalesMinorUnits',
            ),
            rolling7DayIssuedMinorUnits: _sumStatsForDayIds(
              [records],
              recentDayIds,
              'cashbackIssuedMinorUnits',
            ),
            rolling7DayRedeemedMinorUnits: _sumStatsForDayIds(
              [records],
              recentDayIds,
              'cashbackRedeemedMinorUnits',
            ),
            rolling7DayLookupsCount: _sumStatsForDayIds(
              [records],
              recentDayIds,
              'scanCount',
              fallbackKey: 'qrScanCount',
            ),
            todayClientsCount: _readInt(
              todayStats,
              'todayClientCount',
              fallbackKey: 'uniqueClientsCount',
            ),
            totalClientsCount: _sumStats(records, 'newClientCount'),
          );
        }).toList()..sort(
          (left, right) => right.rolling7DaySalesMinorUnits.compareTo(
            left.rolling7DaySalesMinorUnits,
          ),
        );

    final staffQuery = await _awaitFirestoreStep(
      _firestore
          .collection('operatorAccounts')
          .where('ownerId', isEqualTo: ownerUid)
          .where('role', isEqualTo: 'staff')
          .limit(50)
          .get(),
      'owner staff members',
    );

    final staffMembers =
        staffQuery.docs
            .where((doc) => doc.data()['role'] == 'staff')
            .map(
              (doc) => _mapStaffMemberSummary(
                staffId: doc.id,
                data: doc.data(),
                businessesById: businesses,
              ),
            )
            .toList()
          ..sort((left, right) => left.name.compareTo(right.name));

    final joinRequestsById = <String, GroupJoinRequestSummary>{};
    for (final business in businesses.values) {
      final groupId = business['groupId'] as String?;
      if (groupId == null || groupId.isEmpty) {
        continue;
      }

      final requests = await _awaitFirestoreStep(
        _firestore
            .collection('groups')
            .doc(groupId)
            .collection('joinRequests')
            .get(),
        'group join requests for $groupId',
      );

      final groupName =
          groups[groupId]?['name'] as String? ??
          business['groupName'] as String? ??
          groupId;

      for (final requestDoc in requests.docs) {
        final requestData = requestDoc.data();
        joinRequestsById[requestDoc.id] = GroupJoinRequestSummary(
          id: requestDoc.id,
          groupId: groupId,
          businessId:
              requestData['targetBusinessId'] as String? ??
              requestData['businessId'] as String? ??
              '',
          businessName:
              businesses[requestData['businessId']]?['name'] as String? ??
              requestData['targetBusinessId'] as String? ??
              requestData['businessId'] as String? ??
              'Pending business',
          groupName: groupName,
          approvalsReceived: _readInt(requestData, 'approvalsReceived'),
          approvalsRequired: _readInt(requestData, 'approvalsRequired'),
          statusCode: requestData['status'] as String? ?? 'pending',
          status: _mapJoinRequestStatus(requestData['status'] as String?),
          requestedAt:
              _readDateTime(requestData, 'requestedAt') ??
              DateTime.fromMillisecondsSinceEpoch(0),
          requestedAtLabel: _buildRequestedAtLabel(
            _readDateTime(requestData, 'requestedAt'),
          ),
        );
      }
    }

    final joinRequests = joinRequestsById.values.toList();
    joinRequests.sort(
      (left, right) => right.requestedAt.compareTo(left.requestedAt),
    );
    final groupAuditEvents = _buildGroupAuditEvents(
      groupsById: groups,
      businessesById: businesses,
      joinRequests: joinRequests,
      historyByGroupId: groupHistory,
    );

    return OwnerWorkspace(
      ownerName:
          (operatorData['displayName'] as String?) ?? session.displayName,
      businesses: businessSummaries,
      dashboardMetrics: [
        DashboardMetric(
          label: 'Total sales',
          value: formatCurrency(totalSalesMinorUnits),
          detail: '${formatCurrency(recentSalesMinorUnits)} in the last 7 days',
          trendDirection: _trendDirection(
            recentSalesMinorUnits,
            previousSalesMinorUnits,
          ),
        ),
        DashboardMetric(
          label: 'Sales count',
          value: salesCount.toString(),
          detail: '$recentSalesCount paid tickets in the last 7 days',
          trendDirection: _trendDirection(recentSalesCount, previousSalesCount),
        ),
        DashboardMetric(
          label: 'Cashback issued',
          value: formatCurrency(cashbackIssuedMinorUnits),
          detail:
              '${formatCurrency(recentIssuedMinorUnits)} issued in the last 7 days',
          trendDirection: _trendDirection(
            recentIssuedMinorUnits,
            previousIssuedMinorUnits,
          ),
        ),
        DashboardMetric(
          label: 'Cashback redeemed',
          value: formatCurrency(cashbackRedeemedMinorUnits),
          detail:
              '${formatCurrency(recentRedeemedMinorUnits)} redeemed in the last 7 days',
          trendDirection: _trendDirection(
            recentRedeemedMinorUnits,
            previousRedeemedMinorUnits,
          ),
        ),
        DashboardMetric(
          label: 'Client lookups',
          value: clientLookupCount.toString(),
          detail: '$recentLookupCount scan/manual lookups in the last 7 days',
          trendDirection: _trendDirection(
            recentLookupCount,
            previousLookupCount,
          ),
        ),
        DashboardMetric(
          label: 'Total clients',
          value: totalClientsCount.toString(),
          detail: '$todayUniqueClientsCount active unique clients today',
          trendDirection: _trendDirection(
            todayUniqueClientsCount,
            yesterdayUniqueClientsCount,
          ),
        ),
        DashboardMetric(
          label: 'Today unique clients',
          value: todayUniqueClientsCount.toString(),
          detail:
              '${trendPoints.fold<int>(0, (total, point) => total + point.clientsCount)} unique touches in the last 7 days',
          trendDirection: _trendDirection(
            todayUniqueClientsCount,
            yesterdayUniqueClientsCount,
          ),
        ),
      ],
      trendPoints: trendPoints,
      businessPerformance: businessPerformance,
      staffMembers: staffMembers,
      joinRequests: joinRequests,
      groupAuditEvents: groupAuditEvents,
    );
  }

  Future<StaffWorkspace> loadStaffWorkspace(
    AppSession session,
    StaffWorkspace preview,
  ) async {
    final businessId = session.businessId;
    final staffUid = session.uid;
    if (businessId == null || businessId.isEmpty || staffUid == null) {
      return preview;
    }

    final operatorSnap = await _awaitFirestoreStep(
      _firestore.doc('operatorAccounts/$staffUid').get(),
      'staff operator account',
    );
    final operatorData = operatorSnap.data() ?? <String, dynamic>{};
    final businessSnap = await _awaitFirestoreStep(
      _firestore.doc('businesses/$businessId').get(),
      'staff business',
    );
    final businessData = businessSnap.data() ?? <String, dynamic>{};
    final statsHistory = await _loadStatsHistoryByBusinessId([businessId]);
    final records = statsHistory[businessId] ?? const <_DailyStatRecord>[];
    final todayDayId = _dayIdForDate(DateTime.now());
    final yesterdayDayId = _dayIdForDate(
      DateTime.now().subtract(const Duration(days: 1)),
    );
    final recentDayIds = _recentDayIds(count: 7);
    final todayStats = _statsDataForDay(records, todayDayId);
    final yesterdayStats = _statsDataForDay(records, yesterdayDayId);
    final businessMap = {businessId: businessData};

    final historyQuery = await _awaitFirestoreStep(
      _firestore
          .collection('ledgerEvents')
          .where('participantBusinessIds', arrayContains: businessId)
          .limit(12)
          .get(),
      'staff history',
    );

    final historyDocs = historyQuery.docs.toList()
      ..sort(
        (left, right) => _createdAtForSort(
          right.data(),
        ).compareTo(_createdAtForSort(left.data())),
      );
    final sharedCheckoutQuery = await _awaitFirestoreStep(
      _firestore
          .collection('sharedCheckouts')
          .where('businessId', isEqualTo: businessId)
          .limit(12)
          .get(),
      'staff shared checkouts',
    );
    final activeSharedCheckouts = sharedCheckoutQuery.docs.toList()
      ..sort(
        (left, right) => _createdAtForSort(
          right.data(),
        ).compareTo(_createdAtForSort(left.data())),
      );

    return StaffWorkspace(
      staffName:
          (operatorData['displayName'] as String?) ?? session.displayName,
      businessId: businessId,
      businessName: (businessData['name'] as String?) ?? preview.businessName,
      groupId: (businessData['groupId'] as String?) ?? preview.groupId,
      cashbackBasisPoints: _readInt(
        businessData,
        'cashbackBasisPoints',
        fallback: preview.cashbackBasisPoints,
      ),
      preferredStartTabIndex: _staffTabIndexFromPreference(
        operatorData['preferredStartTab'] as String?,
        fallback: preview.preferredStartTabIndex,
      ),
      notificationDigestOptIn:
          operatorData['notificationDigestOptIn'] as bool? ??
          preview.notificationDigestOptIn,
      dashboardMetrics: [
        DashboardMetric(
          label: 'Today sales',
          value: formatCurrency(_readInt(todayStats, 'totalSalesMinorUnits')),
          detail: '${_readInt(todayStats, 'salesCount')} completed tickets',
          trendDirection: _trendDirection(
            _readInt(todayStats, 'totalSalesMinorUnits'),
            _readInt(yesterdayStats, 'totalSalesMinorUnits'),
          ),
        ),
        DashboardMetric(
          label: 'Today scans',
          value: _readInt(
            todayStats,
            'qrScanCount',
            fallbackKey: 'scanCount',
          ).toString(),
          detail: 'Scan and manual phone identification combined',
          trendDirection: _trendDirection(
            _readInt(todayStats, 'scanCount', fallbackKey: 'qrScanCount'),
            _readInt(yesterdayStats, 'scanCount', fallbackKey: 'qrScanCount'),
          ),
        ),
        DashboardMetric(
          label: 'Today clients',
          value: _readInt(
            todayStats,
            'todayClientCount',
            fallbackKey: 'uniqueClientsCount',
          ).toString(),
          detail: 'Live daily projection from Firestore stats',
          trendDirection: _trendDirection(
            _readInt(
              todayStats,
              'todayClientCount',
              fallbackKey: 'uniqueClientsCount',
            ),
            _readInt(
              yesterdayStats,
              'todayClientCount',
              fallbackKey: 'uniqueClientsCount',
            ),
          ),
        ),
      ],
      trendPoints: recentDayIds
          .map(
            (dayId) => DashboardTrendPoint(
              label: _formatTrendDayLabel(dayId),
              salesMinorUnits: _sumStatsForDayIds(
                [records],
                [dayId],
                'totalSalesMinorUnits',
              ),
              issuedMinorUnits: _sumStatsForDayIds(
                [records],
                [dayId],
                'cashbackIssuedMinorUnits',
              ),
              redeemedMinorUnits: _sumStatsForDayIds(
                [records],
                [dayId],
                'cashbackRedeemedMinorUnits',
              ),
              clientsCount: _sumStatsForDayIds(
                [records],
                [dayId],
                'todayClientCount',
                fallbackKey: 'uniqueClientsCount',
              ),
              lookupsCount: _sumStatsForDayIds(
                [records],
                [dayId],
                'scanCount',
                fallbackKey: 'qrScanCount',
              ),
            ),
          )
          .toList(),
      recentTransactions: historyDocs
          .map(
            (doc) => _mapWalletEvent(
              eventId: doc.id,
              data: doc.data(),
              businessesById: businessMap,
              groupNamesById: _buildGroupNamesById(businessMap.values),
              viewerBusinessId: businessId,
            ),
          )
          .toList(),
      activeSharedCheckouts: activeSharedCheckouts
          .where((doc) => (doc.data()['status'] as String?) != 'finalized')
          .map(
            (doc) => StaffSharedCheckoutSummary(
              id: doc.id,
              sourceTicketRef:
                  (doc.data()['sourceTicketRef'] as String?) ?? doc.id,
              status: (doc.data()['status'] as String?) ?? 'open',
              totalMinorUnits: _readInt(doc.data(), 'totalMinorUnits'),
              contributedMinorUnits: _readInt(
                doc.data(),
                'contributedMinorUnits',
              ),
              remainingMinorUnits: _readInt(doc.data(), 'remainingMinorUnits'),
              contributionsCount: _readInt(doc.data(), 'contributionsCount'),
              createdAt:
                  _readDateTime(doc.data(), 'createdAt') ?? DateTime.now(),
            ),
          )
          .toList(),
    );
  }

  Future<ClientWorkspace> loadClientWorkspace(
    AppSession session,
    ClientWorkspace preview,
  ) async {
    final customerId = session.customerId;
    if (customerId == null || customerId.isEmpty) {
      return preview;
    }

    final customerSnap = await _awaitFirestoreStep(
      _firestore.doc('customers/$customerId').get(),
      'client customer',
    );
    final customerData = customerSnap.data() ?? <String, dynamic>{};
    final customerPhoneNumber =
        (customerData['phoneE164'] as String?) ??
        session.phoneNumber ??
        preview.phoneNumber;
    final businesses = await _loadAllBusinesses();
    final groupNamesById = _buildGroupNamesById(businesses.values);
    final directoryDetails = await _loadBusinessDirectoryDetailsByBusinessId(
      businesses.keys,
    );

    final lotsQuery = await _awaitFirestoreStep(
      _firestore
          .collection('walletLots')
          .where('ownerCustomerId', isEqualTo: customerId)
          .get(),
      'client wallet lots',
    );
    final walletLotDocs = lotsQuery.docs.toList()
      ..sort(
        (left, right) => _expiresAtForSort(
          left.data(),
        ).compareTo(_expiresAtForSort(right.data())),
      );

    final availableLots = walletLotDocs
        .where((doc) => _isAvailableWalletLot(doc.data()))
        .map(
          (doc) => _mapWalletLot(
            lotId: doc.id,
            data: doc.data(),
            businessesById: businesses,
            currentCustomerName:
                (customerData['displayName'] as String?) ?? session.displayName,
          ),
        )
        .toList();

    final totalWalletBalance = availableLots.fold<int>(
      0,
      (total, lot) => total + lot.availableAmount,
    );

    final historyQuery = await _awaitFirestoreStep(
      _firestore
          .collection('ledgerEvents')
          .where('participantCustomerIds', arrayContains: customerId)
          .limit(40)
          .get(),
      'client history',
    );
    final historyDocs = historyQuery.docs.toList()
      ..sort(
        (left, right) => _createdAtForSort(
          right.data(),
        ).compareTo(_createdAtForSort(left.data())),
      );

    final outgoingPendingTransfersQuery = await _awaitFirestoreStep(
      _firestore
          .collection('giftTransfers')
          .where('sourceCustomerId', isEqualTo: customerId)
          .where('status', isEqualTo: 'pending')
          .get(),
      'client outgoing pending gifts',
    );
    final outgoingPendingTransferDocs =
        outgoingPendingTransfersQuery.docs.toList()..sort(
          (left, right) => _createdAtForSort(
            right.data(),
          ).compareTo(_createdAtForSort(left.data())),
        );

    final incomingPendingTransferDocs =
        customerPhoneNumber.trim().isEmpty
              ? <QueryDocumentSnapshot<Map<String, dynamic>>>[]
              : (await _awaitFirestoreStep(
                  _firestore
                      .collection('giftTransfers')
                      .where(
                        'recipientPhoneE164',
                        isEqualTo: customerPhoneNumber,
                      )
                      .where('status', isEqualTo: 'pending')
                      .get(),
                  'client incoming pending gifts',
                )).docs.toList()
          ..sort(
            (left, right) => _createdAtForSort(
              right.data(),
            ).compareTo(_createdAtForSort(left.data())),
          );

    final pendingTransferEntries =
        <
            ({
              QueryDocumentSnapshot<Map<String, dynamic>> doc,
              PendingTransferDirection direction,
            })
          >[
            ...outgoingPendingTransferDocs.map(
              (doc) => (doc: doc, direction: PendingTransferDirection.outgoing),
            ),
            ...incomingPendingTransferDocs
                .where(
                  (doc) => !outgoingPendingTransferDocs.any(
                    (outgoingDoc) => outgoingDoc.id == doc.id,
                  ),
                )
                .map(
                  (doc) =>
                      (doc: doc, direction: PendingTransferDirection.incoming),
                ),
          ]
          ..sort(
            (left, right) => _createdAtForSort(
              right.doc.data(),
            ).compareTo(_createdAtForSort(left.doc.data())),
          );

    final sharedCheckoutQuery = await _awaitFirestoreStep(
      _firestore
          .collection('sharedCheckouts')
          .where('participantCustomerIds', arrayContains: customerId)
          .limit(10)
          .get(),
      'client shared checkouts',
    );
    final sharedCheckoutDocs = sharedCheckoutQuery.docs.toList()
      ..sort(
        (left, right) => _createdAtForSort(
          right.data(),
        ).compareTo(_createdAtForSort(left.data())),
      );

    final activeSharedCheckouts = <SharedCheckoutSummary>[];
    for (final checkoutDoc in sharedCheckoutDocs) {
      final checkoutData = checkoutDoc.data();
      if ((checkoutData['status'] as String?) == 'finalized') {
        continue;
      }

      final contributionsQuery = await _awaitFirestoreStep(
        checkoutDoc.reference.collection('contributions').get(),
        'client checkout contributions for ${checkoutDoc.id}',
      );
      final contributions =
          contributionsQuery.docs
              .map(
                (doc) => SharedContributionSummary(
                  participantName:
                      (doc.data()['customerId'] as String?) == customerId
                      ? 'You'
                      : 'Participant',
                  amount: _readInt(doc.data(), 'amountMinorUnits'),
                ),
              )
              .toList()
            ..sort((left, right) => right.amount.compareTo(left.amount));

      activeSharedCheckouts.add(
        SharedCheckoutSummary(
          id: checkoutDoc.id,
          businessId: checkoutData['businessId'] as String? ?? '',
          businessName:
              businesses[checkoutData['businessId']]?['name'] as String? ??
              (checkoutData['businessId'] as String?) ??
              'Shared checkout',
          groupId: checkoutData['groupId'] as String? ?? 'ungrouped',
          status: checkoutData['status'] as String? ?? 'open',
          sourceTicketRef:
              checkoutData['sourceTicketRef'] as String? ?? checkoutDoc.id,
          totalAmount: _readInt(checkoutData, 'totalMinorUnits'),
          contributedAmount: _readInt(checkoutData, 'contributedMinorUnits'),
          remainingAmount: _readInt(checkoutData, 'remainingMinorUnits'),
          contributions: contributions,
          createdAt: _readDateTime(checkoutData, 'createdAt') ?? DateTime.now(),
        ),
      );
    }

    return ClientWorkspace(
      clientName:
          (customerData['displayName'] as String?) ?? session.displayName,
      phoneNumber: customerPhoneNumber,
      totalWalletBalance: totalWalletBalance,
      preferredStartTabIndex: _clientTabIndexFromPreference(
        customerData['preferredClientTab'] as String?,
        fallback: preview.preferredStartTabIndex,
      ),
      marketingOptIn:
          customerData['marketingOptIn'] as bool? ?? preview.marketingOptIn,
      storeDirectory:
          businesses.entries
              .map(
                (entry) => _mapBusinessDirectoryEntry(
                  entry.key,
                  entry.value,
                  directoryDetails[entry.key] ??
                      const _BusinessDirectoryDetails.empty(),
                ),
              )
              .toList()
            ..sort((left, right) => left.name.compareTo(right.name)),
      walletLots: availableLots,
      history: historyDocs
          .map(
            (doc) => _mapWalletEvent(
              eventId: doc.id,
              data: doc.data(),
              businessesById: businesses,
              groupNamesById: groupNamesById,
              viewerCustomerId: customerId,
            ),
          )
          .toList(),
      pendingTransfers: pendingTransferEntries
          .map(
            (entry) => PendingTransferSummary(
              id: entry.doc.id,
              phoneNumber: entry.direction == PendingTransferDirection.outgoing
                  ? entry.doc.data()['recipientPhoneE164'] as String? ??
                        'Unknown'
                  : customerPhoneNumber,
              amount: _readInt(entry.doc.data(), 'amountMinorUnits'),
              statusLabel: _mapPendingTransferStatus(
                entry.doc.data()['status'] as String?,
              ),
              direction: entry.direction,
              groupId: entry.doc.data()['groupId'] as String? ?? 'ungrouped',
              groupName:
                  groupNamesById[entry.doc.data()['groupId'] as String? ??
                      'ungrouped'] ??
                  (entry.doc.data()['groupId'] as String? ?? 'Tandem group'),
              canClaim: entry.direction == PendingTransferDirection.incoming,
              expiresAt:
                  _readDateTime(entry.doc.data(), 'earliestExpiresAt') ??
                  _readDateTime(entry.doc.data(), 'latestExpiresAt') ??
                  DateTime.now(),
            ),
          )
          .toList(),
      activeSharedCheckouts: activeSharedCheckouts,
    );
  }

  Future<Map<String, Map<String, dynamic>>> _loadAllBusinesses() async {
    final snapshot = await _awaitFirestoreStep(
      _firestore.collection('businesses').get(),
      'all businesses',
    );
    return {for (final doc in snapshot.docs) doc.id: doc.data()};
  }

  Future<Map<String, Map<String, dynamic>>> _loadBusinessesByIds(
    List<String> businessIds,
  ) async {
    final entries = await Future.wait(
      businessIds.toSet().map((businessId) async {
        final snapshot = await _awaitFirestoreStep(
          _firestore.doc('businesses/$businessId').get(),
          'business document $businessId',
        );
        return MapEntry<String, Map<String, dynamic>?>(
          businessId,
          snapshot.exists ? snapshot.data() ?? <String, dynamic>{} : null,
        );
      }),
    );

    return {
      for (final entry in entries)
        if (entry.value != null) entry.key: entry.value!,
    };
  }

  Future<Map<String, List<_DailyStatRecord>>> _loadStatsHistoryByBusinessId(
    List<String> businessIds,
  ) async {
    final entries = await Future.wait(
      businessIds.toSet().map((businessId) async {
        final snapshot = await _awaitFirestoreStep(
          _firestore
              .collection('businesses')
              .doc(businessId)
              .collection('statsDaily')
              .get(),
          'daily stats for $businessId',
        );
        final docs = snapshot.docs.toList()
          ..sort((left, right) => left.id.compareTo(right.id));
        return MapEntry(
          businessId,
          docs
              .map((doc) => _DailyStatRecord(dayId: doc.id, data: doc.data()))
              .toList(),
        );
      }),
    );

    return {for (final entry in entries) entry.key: entry.value};
  }

  Future<Map<String, Map<String, dynamic>>> _loadGroupsById(
    Set<String> groupIds,
  ) async {
    final entries = await Future.wait(
      groupIds.map((groupId) async {
        final snapshot = await _awaitFirestoreStep(
          _firestore.doc('groups/$groupId').get(),
          'group document $groupId',
        );
        return MapEntry<String, Map<String, dynamic>?>(
          groupId,
          snapshot.exists ? snapshot.data() ?? <String, dynamic>{} : null,
        );
      }),
    );

    return {
      for (final entry in entries)
        if (entry.value != null) entry.key: entry.value!,
    };
  }

  Future<Map<String, _BusinessDirectoryDetails>>
  _loadBusinessDirectoryDetailsByBusinessId(
    Iterable<String> businessIds,
  ) async {
    final entries = await Future.wait(
      businessIds.toSet().map((businessId) async {
        final locationsFuture = _awaitFirestoreStep(
          _firestore
              .collection('businesses')
              .doc(businessId)
              .collection('locations')
              .get(),
          'client business locations for $businessId',
        );
        final productsFuture = _awaitFirestoreStep(
          _firestore
              .collection('businesses')
              .doc(businessId)
              .collection('products')
              .get(),
          'client business products for $businessId',
        );
        final servicesFuture = _awaitFirestoreStep(
          _firestore
              .collection('businesses')
              .doc(businessId)
              .collection('services')
              .get(),
          'client business services for $businessId',
        );
        final mediaFuture = _awaitFirestoreStep(
          _firestore
              .collection('businesses')
              .doc(businessId)
              .collection('media')
              .get(),
          'client business media for $businessId',
        );

        final locationsSnapshot = await locationsFuture;
        final productsSnapshot = await productsFuture;
        final servicesSnapshot = await servicesFuture;
        final mediaSnapshot = await mediaFuture;

        final locations =
            locationsSnapshot.docs
                .map((doc) => _mapBusinessLocation(doc.id, doc.data()))
                .toList()
              ..sort((left, right) {
                if (left.isPrimary != right.isPrimary) {
                  return left.isPrimary ? -1 : 1;
                }
                return left.name.compareTo(right.name);
              });
        final products =
            productsSnapshot.docs
                .map((doc) => _mapBusinessCatalogItem(doc.id, doc.data()))
                .where((item) => item.isActive)
                .toList()
              ..sort((left, right) => left.name.compareTo(right.name));
        final services =
            servicesSnapshot.docs
                .map((doc) => _mapBusinessCatalogItem(doc.id, doc.data()))
                .where((item) => item.isActive)
                .toList()
              ..sort((left, right) => left.name.compareTo(right.name));
        final media =
            mediaSnapshot.docs
                .map((doc) => _mapBusinessMediaSummary(doc.id, doc.data()))
                .where(
                  (item) =>
                      item.title.trim().isNotEmpty ||
                      item.caption.trim().isNotEmpty ||
                      item.imageUrl.trim().isNotEmpty,
                )
                .toList()
              ..sort((left, right) {
                if (left.isFeatured != right.isFeatured) {
                  return left.isFeatured ? -1 : 1;
                }
                return left.title.compareTo(right.title);
              });

        return MapEntry(
          businessId,
          _BusinessDirectoryDetails(
            locations: locations,
            products: products,
            services: services,
            locationsCount: locations.length,
            productsCount: products.length,
            servicesCount: services.length,
            mediaCount: media.length,
            featuredMedia: media,
          ),
        );
      }),
    );

    return {for (final entry in entries) entry.key: entry.value};
  }

  Future<Map<String, List<_GroupHistoryRecord>>> _loadGroupHistoryByGroupId(
    Iterable<String> groupIds,
  ) async {
    final entries = await Future.wait(
      groupIds.where((groupId) => groupId.trim().isNotEmpty).toSet().map((
        groupId,
      ) async {
        final snapshot = await _awaitFirestoreStep(
          _firestore
              .collection('groups')
              .doc(groupId)
              .collection('history')
              .get(),
          'group history for $groupId',
        );
        final records =
            snapshot.docs
                .map((doc) => _GroupHistoryRecord(id: doc.id, data: doc.data()))
                .toList()
              ..sort(
                (left, right) => _createdAtForSort(
                  right.data,
                ).compareTo(_createdAtForSort(left.data)),
              );
        return MapEntry(groupId, records);
      }),
    );

    return {for (final entry in entries) entry.key: entry.value};
  }

  BusinessSummary _mapBusinessSummary(Map<String, dynamic> data) {
    final id = data['id'] as String? ?? data['businessId'] as String? ?? '';
    return BusinessSummary(
      id: id,
      name: data['name'] as String? ?? id,
      category: data['category'] as String? ?? 'Business',
      description: data['description'] as String? ?? 'No description yet.',
      logoUrl: data['logoUrl'] as String? ?? '',
      logoStoragePath: data['logoStoragePath'] as String? ?? '',
      coverImageUrl: data['coverImageUrl'] as String? ?? '',
      coverImageStoragePath: data['coverImageStoragePath'] as String? ?? '',
      address: data['address'] as String? ?? 'Address not set',
      workingHours: data['workingHours'] as String? ?? 'Hours not set',
      phoneNumbers: (data['phoneNumbers'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(),
      cashbackBasisPoints: _readInt(data, 'cashbackBasisPoints'),
      groupId: data['groupId'] as String? ?? 'ungrouped',
      groupName:
          data['groupName'] as String? ??
          data['groupId'] as String? ??
          'No tandem group yet',
      groupStatus: _mapGroupMembershipStatus(
        data['groupMembershipStatus'] as String? ??
            data['tandemStatus'] as String?,
      ),
      locationsCount: _readInt(data, 'locationsCount'),
      productsCount: _readInt(data, 'productsCount'),
      manualPhoneIssuingEnabled:
          data['manualPhoneIssuingEnabled'] as bool? ?? true,
      redeemPolicy:
          data['redeemPolicy'] as String? ?? 'Redeem policy not set yet.',
    );
  }

  BusinessDirectoryEntry _mapBusinessDirectoryEntry(
    String businessId,
    Map<String, dynamic> data,
    _BusinessDirectoryDetails details,
  ) {
    final businessPhoneNumbers =
        (data['phoneNumbers'] as List<dynamic>? ?? const [])
            .whereType<String>()
            .map((phone) => phone.trim())
            .where((phone) => phone.isNotEmpty);
    final locationPhoneNumbers = details.locations
        .expand((location) => location.phoneNumbers)
        .map((phone) => phone.trim())
        .where((phone) => phone.isNotEmpty);

    return BusinessDirectoryEntry(
      id: businessId,
      name: data['name'] as String? ?? businessId,
      category: data['category'] as String? ?? 'Business',
      description: data['description'] as String? ?? 'No description yet.',
      logoUrl: data['logoUrl'] as String? ?? '',
      coverImageUrl: data['coverImageUrl'] as String? ?? '',
      address: data['address'] as String? ?? 'Address not set',
      workingHours: data['workingHours'] as String? ?? 'Hours not set',
      cashbackBasisPoints: _readInt(data, 'cashbackBasisPoints'),
      redeemPolicy:
          data['redeemPolicy'] as String? ?? 'Redeem policy not set yet.',
      phoneNumbers: {...businessPhoneNumbers, ...locationPhoneNumbers}.toList(),
      locations: details.locations,
      products: details.products,
      services: details.services,
      locationsCount: details.locationsCount,
      productsCount: details.productsCount,
      servicesCount: details.servicesCount,
      mediaCount: details.mediaCount,
      featuredMedia: details.featuredMedia,
      groupName:
          data['groupName'] as String? ??
          data['groupId'] as String? ??
          'No tandem group yet',
      groupStatus: _mapGroupMembershipStatus(
        data['groupMembershipStatus'] as String? ??
            data['tandemStatus'] as String?,
      ),
    );
  }

  BusinessLocationSummary _mapBusinessLocation(
    String locationId,
    Map<String, dynamic> data,
  ) {
    return BusinessLocationSummary(
      id: locationId,
      name: data['name'] as String? ?? locationId,
      address: data['address'] as String? ?? 'Address not set',
      workingHours: data['workingHours'] as String? ?? 'Hours not set',
      phoneNumbers: (data['phoneNumbers'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(),
      notes: data['notes'] as String? ?? '',
      isPrimary: data['isPrimary'] as bool? ?? false,
    );
  }

  BusinessCatalogItemSummary _mapBusinessCatalogItem(
    String itemId,
    Map<String, dynamic> data,
  ) {
    return BusinessCatalogItemSummary(
      id: itemId,
      name: data['name'] as String? ?? itemId,
      description: data['description'] as String? ?? '',
      priceLabel: data['priceLabel'] as String? ?? '',
      isActive: data['isActive'] as bool? ?? true,
    );
  }

  List<GroupAuditEventSummary> _buildGroupAuditEvents({
    required Map<String, Map<String, dynamic>> groupsById,
    required Map<String, Map<String, dynamic>> businessesById,
    required List<GroupJoinRequestSummary> joinRequests,
    required Map<String, List<_GroupHistoryRecord>> historyByGroupId,
  }) {
    final events = <GroupAuditEventSummary>[];

    for (final entry in historyByGroupId.entries) {
      final groupId = entry.key;
      for (final record in entry.value) {
        events.add(
          _mapGroupAuditEventSummary(
            groupId: groupId,
            historyId: record.id,
            data: record.data,
            groupsById: groupsById,
            businessesById: businessesById,
          ),
        );
      }
    }

    for (final request in joinRequests.where(
      (request) => request.statusCode == 'pending',
    )) {
      events.add(
        GroupAuditEventSummary(
          id: 'pending-${request.id}',
          groupId: request.groupId,
          groupName: request.groupName,
          businessId: request.businessId,
          businessName: request.businessName,
          actorBusinessName: request.groupName,
          eventType: 'join_request_pending',
          title: 'Join request awaiting unanimous approval',
          detail:
              '${request.businessName} has ${request.approvalsReceived}/${request.approvalsRequired} approvals in ${request.groupName}.',
          occurredAt: request.requestedAt,
        ),
      );
    }

    events.sort((left, right) => right.occurredAt.compareTo(left.occurredAt));
    return events.take(12).toList();
  }

  GroupAuditEventSummary _mapGroupAuditEventSummary({
    required String groupId,
    required String historyId,
    required Map<String, dynamic> data,
    required Map<String, Map<String, dynamic>> groupsById,
    required Map<String, Map<String, dynamic>> businessesById,
  }) {
    final eventType = data['eventType'] as String? ?? 'group_event';
    final historyGroupId = data['groupId'] as String? ?? groupId;
    final historyBusinessId = data['businessId'] as String? ?? '';
    final actorBusinessId = data['actorBusinessId'] as String? ?? '';
    final groupName =
        groupsById[historyGroupId]?['name'] as String? ??
        businessesById[historyBusinessId]?['groupName'] as String? ??
        historyGroupId;
    final businessName =
        businessesById[historyBusinessId]?['name'] as String? ??
        (historyBusinessId.isEmpty ? 'Tandem group' : historyBusinessId);
    final actorBusinessName =
        businessesById[actorBusinessId]?['name'] as String? ??
        (actorBusinessId.isEmpty ? groupName : actorBusinessId);

    final presentation = _describeGroupAuditEvent(
      eventType: eventType,
      groupName: groupName,
      businessName: businessName,
      actorBusinessName: actorBusinessName,
    );

    return GroupAuditEventSummary(
      id: historyId,
      groupId: historyGroupId,
      groupName: groupName,
      businessId: historyBusinessId,
      businessName: businessName,
      actorBusinessName: actorBusinessName,
      eventType: eventType,
      title: presentation.title,
      detail: presentation.detail,
      occurredAt:
          _readDateTime(data, 'createdAt') ??
          _readDateTime(data, 'updatedAt') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  BusinessMediaSummary _mapBusinessMediaSummary(
    String mediaId,
    Map<String, dynamic> data,
  ) {
    return BusinessMediaSummary(
      id: mediaId,
      title: data['title'] as String? ?? mediaId,
      caption: data['caption'] as String? ?? '',
      mediaType: data['mediaType'] as String? ?? 'gallery',
      imageUrl: data['imageUrl'] as String? ?? '',
      storagePath: data['storagePath'] as String? ?? '',
      isFeatured: data['isFeatured'] as bool? ?? false,
    );
  }

  StaffMemberSummary _mapStaffMemberSummary({
    required String staffId,
    required Map<String, dynamic> data,
    required Map<String, Map<String, dynamic>> businessesById,
  }) {
    final disabledAt = _readDateTime(data, 'disabledAt');
    final updatedAt = _readDateTime(data, 'updatedAt');
    final isActive = disabledAt == null;

    return StaffMemberSummary(
      id: staffId,
      name: data['displayName'] as String? ?? staffId,
      username: data['usernameNormalized'] as String? ?? 'staff',
      roleLabel: data['roleLabel'] as String? ?? 'Staff',
      businessName:
          businessesById[data['businessId']]?['name'] as String? ??
          (data['businessId'] as String?) ??
          'Unassigned business',
      isActive: isActive,
      lastActivityLabel: isActive
          ? _buildLastActivityLabel(updatedAt)
          : _buildDisabledLabel(disabledAt),
    );
  }

  Future<T> _awaitFirestoreStep<T>(Future<T> future, String step) async {
    try {
      return await future.timeout(_firestoreRequestTimeout);
    } on TimeoutException {
      throw StateError('Firestore request timed out while loading $step.');
    }
  }

  WalletLot _mapWalletLot({
    required String lotId,
    required Map<String, dynamic> data,
    required Map<String, Map<String, dynamic>> businessesById,
    required String currentCustomerName,
  }) {
    final issuerBusinessId = data['issuerBusinessId'] as String?;
    final groupId = data['groupId'] as String? ?? 'ungrouped';

    return WalletLot(
      id: lotId,
      groupId: groupId,
      issuerBusinessName:
          businessesById[issuerBusinessId]?['name'] as String? ??
          issuerBusinessId ??
          'Unknown issuer',
      groupName:
          businessesById[issuerBusinessId]?['groupName'] as String? ?? groupId,
      availableAmount: _readInt(data, 'availableMinorUnits'),
      expiresAt: _readDateTime(data, 'expiresAt') ?? DateTime.now(),
      currentOwnerLabel: 'Owned by $currentCustomerName',
    );
  }

  WalletEvent _mapWalletEvent({
    required String eventId,
    required Map<String, dynamic> data,
    required Map<String, Map<String, dynamic>> businessesById,
    required Map<String, String> groupNamesById,
    String? viewerCustomerId,
    String? viewerBusinessId,
  }) {
    final eventTypeValue = data['eventType'] as String? ?? 'admin_adjustment';
    final eventType = _mapWalletEventType(eventTypeValue);
    final issuerBusinessId =
        data['issuerBusinessId'] as String? ??
        data['actorBusinessId'] as String? ??
        data['targetBusinessId'] as String?;
    final groupId = data['groupId'] as String? ?? 'ungrouped';

    return WalletEvent(
      id: eventId,
      type: eventType,
      title: _buildWalletEventTitle(eventType),
      subtitle: _buildWalletEventSubtitle(
        eventType: eventType,
        data: data,
        businessesById: businessesById,
        viewerCustomerId: viewerCustomerId,
      ),
      amount: _readInt(data, 'amountMinorUnits'),
      occurredAt: _readDateTime(data, 'createdAt') ?? DateTime.now(),
      groupName: groupNamesById[groupId] ?? groupId,
      issuerBusinessName:
          businessesById[issuerBusinessId]?['name'] as String? ??
          issuerBusinessId ??
          'Unknown issuer',
      isIncoming: _isIncomingEvent(
        eventType: eventType,
        data: data,
        viewerCustomerId: viewerCustomerId,
        viewerBusinessId: viewerBusinessId,
      ),
    );
  }
}

class _DailyStatRecord {
  const _DailyStatRecord({required this.dayId, required this.data});

  final String dayId;
  final Map<String, dynamic> data;
}

class _GroupHistoryRecord {
  const _GroupHistoryRecord({required this.id, required this.data});

  final String id;
  final Map<String, dynamic> data;
}

class _BusinessDirectoryDetails {
  const _BusinessDirectoryDetails({
    required this.locations,
    required this.products,
    required this.services,
    required this.locationsCount,
    required this.productsCount,
    required this.servicesCount,
    required this.mediaCount,
    required this.featuredMedia,
  });

  const _BusinessDirectoryDetails.empty()
    : locations = const [],
      products = const [],
      services = const [],
      locationsCount = 0,
      productsCount = 0,
      servicesCount = 0,
      mediaCount = 0,
      featuredMedia = const [];

  final List<BusinessLocationSummary> locations;
  final List<BusinessCatalogItemSummary> products;
  final List<BusinessCatalogItemSummary> services;
  final int locationsCount;
  final int productsCount;
  final int servicesCount;
  final int mediaCount;
  final List<BusinessMediaSummary> featuredMedia;
}

({String title, String detail}) _describeGroupAuditEvent({
  required String eventType,
  required String groupName,
  required String businessName,
  required String actorBusinessName,
}) {
  switch (eventType) {
    case 'group_created':
      return (
        title: 'Tandem group created',
        detail: '$businessName started $groupName.',
      );
    case 'group_seeded':
      return (
        title: 'Seed group initialized',
        detail: 'Live Firestore seed established for $groupName.',
      );
    case 'join_request_created':
      return (
        title: 'Join request submitted',
        detail: '$businessName requested entry into $groupName.',
      );
    case 'join_request_vote_yes':
      return (
        title: 'Approval recorded',
        detail: '$actorBusinessName approved $businessName.',
      );
    case 'join_request_approved':
      return (
        title: 'Business admitted',
        detail: '$businessName joined $groupName after unanimous approval.',
      );
    case 'join_request_rejected':
      return (
        title: 'Join request rejected',
        detail: '$actorBusinessName rejected $businessName.',
      );
    default:
      return (title: 'Group event', detail: '$groupName recorded $eventType.');
  }
}

Map<String, String> _buildGroupNamesById(
  Iterable<Map<String, dynamic>> businesses,
) {
  final result = <String, String>{};
  for (final business in businesses) {
    final groupId = business['groupId'] as String?;
    final groupName = business['groupName'] as String?;
    if (groupId == null || groupId.isEmpty || groupName == null) {
      continue;
    }
    result[groupId] = groupName;
  }
  return result;
}

GroupMembershipStatus _mapGroupMembershipStatus(String? value) {
  switch (value) {
    case 'none':
    case 'not_grouped':
    case 'ungrouped':
    case null:
      return GroupMembershipStatus.notGrouped;
    case 'active':
      return GroupMembershipStatus.active;
    case 'rejected':
      return GroupMembershipStatus.rejected;
    case 'pending':
    case 'pendingApproval':
    case 'pending_approval':
    default:
      return GroupMembershipStatus.pendingApproval;
  }
}

WalletEventType _mapWalletEventType(String value) {
  switch (value) {
    case 'issue':
      return WalletEventType.issue;
    case 'redeem':
      return WalletEventType.redeem;
    case 'transfer_out':
      return WalletEventType.transferOut;
    case 'transfer_in':
      return WalletEventType.transferIn;
    case 'gift_pending':
      return WalletEventType.giftPending;
    case 'gift_claimed':
      return WalletEventType.giftClaimed;
    case 'shared_checkout_created':
      return WalletEventType.sharedCheckoutCreated;
    case 'shared_checkout_contribution':
      return WalletEventType.sharedCheckoutContribution;
    case 'shared_checkout_finalized':
      return WalletEventType.sharedCheckoutFinalized;
    case 'expire':
      return WalletEventType.expire;
    case 'refund':
      return WalletEventType.refund;
    case 'admin_adjustment':
    default:
      return WalletEventType.adminAdjustment;
  }
}

bool _isIncomingEvent({
  required WalletEventType eventType,
  required Map<String, dynamic> data,
  String? viewerCustomerId,
  String? viewerBusinessId,
}) {
  if (viewerCustomerId != null && viewerCustomerId.isNotEmpty) {
    switch (eventType) {
      case WalletEventType.issue:
      case WalletEventType.transferIn:
      case WalletEventType.giftClaimed:
      case WalletEventType.refund:
        return true;
      case WalletEventType.adminAdjustment:
        return (data['adjustmentDirection'] as String?) != 'debit';
      case WalletEventType.redeem:
      case WalletEventType.transferOut:
      case WalletEventType.giftPending:
      case WalletEventType.sharedCheckoutCreated:
      case WalletEventType.sharedCheckoutContribution:
      case WalletEventType.sharedCheckoutFinalized:
      case WalletEventType.expire:
        return false;
    }
  }

  if (viewerBusinessId != null && viewerBusinessId.isNotEmpty) {
    final actorBusinessId = data['actorBusinessId'] as String?;
    return actorBusinessId == viewerBusinessId;
  }

  return false;
}

String _buildWalletEventTitle(WalletEventType eventType) {
  switch (eventType) {
    case WalletEventType.issue:
      return 'Cashback issued';
    case WalletEventType.redeem:
      return 'Cashback redeemed';
    case WalletEventType.transferOut:
      return 'Gift sent';
    case WalletEventType.transferIn:
      return 'Transfer received';
    case WalletEventType.giftPending:
      return 'Gift pending';
    case WalletEventType.giftClaimed:
      return 'Gift claimed';
    case WalletEventType.sharedCheckoutCreated:
      return 'Shared checkout opened';
    case WalletEventType.sharedCheckoutContribution:
      return 'Shared checkout contribution';
    case WalletEventType.sharedCheckoutFinalized:
      return 'Shared checkout finalized';
    case WalletEventType.expire:
      return 'Cashback expired';
    case WalletEventType.refund:
      return 'Cashback refunded';
    case WalletEventType.adminAdjustment:
      return 'Admin adjustment';
  }
}

String _buildWalletEventSubtitle({
  required WalletEventType eventType,
  required Map<String, dynamic> data,
  required Map<String, Map<String, dynamic>> businessesById,
  String? viewerCustomerId,
}) {
  final ticketRef = data['sourceTicketRef'] as String?;
  final phoneNumber = data['recipientPhoneE164'] as String?;
  final checkoutId = data['checkoutId'] as String?;
  final sourceBusinessId = data['actorBusinessId'] as String?;
  final sourceBusinessName =
      businessesById[sourceBusinessId]?['name'] as String? ?? sourceBusinessId;

  switch (eventType) {
    case WalletEventType.issue:
      return ticketRef != null && ticketRef.isNotEmpty
          ? 'Ticket $ticketRef at $sourceBusinessName'
          : 'Issued by $sourceBusinessName';
    case WalletEventType.redeem:
      return ticketRef != null && ticketRef.isNotEmpty
          ? 'Ticket $ticketRef'
          : 'Redeemed in tandem group';
    case WalletEventType.transferOut:
    case WalletEventType.giftPending:
      return phoneNumber != null && phoneNumber.isNotEmpty
          ? 'Pending claim for $phoneNumber'
          : 'Pending recipient phone verification';
    case WalletEventType.transferIn:
    case WalletEventType.giftClaimed:
      return (data['sourceCustomerId'] as String?) == viewerCustomerId
          ? 'Moved within your wallet history'
          : 'Claimed by verified phone';
    case WalletEventType.sharedCheckoutCreated:
      return ticketRef != null && ticketRef.isNotEmpty
          ? 'Checkout $ticketRef'
          : 'Group payment session';
    case WalletEventType.sharedCheckoutContribution:
      return checkoutId != null && checkoutId.isNotEmpty
          ? 'Checkout $checkoutId'
          : 'Contribution reserved';
    case WalletEventType.sharedCheckoutFinalized:
      return checkoutId != null && checkoutId.isNotEmpty
          ? 'Checkout $checkoutId finalized'
          : 'Shared checkout finalized';
    case WalletEventType.expire:
      return 'Expired before redemption';
    case WalletEventType.refund:
      return 'Refund restored wallet balance';
    case WalletEventType.adminAdjustment:
      final direction = data['adjustmentDirection'] as String? ?? 'credit';
      final note = data['adjustmentNote'] as String?;
      final prefix = direction == 'debit'
          ? 'Manual debit adjustment'
          : 'Manual credit adjustment';
      if (note != null && note.trim().isNotEmpty) {
        return '$prefix • ${note.trim()}';
      }
      return '$prefix by owner control';
  }
}

bool _isAvailableWalletLot(Map<String, dynamic> data) {
  final status = data['status'] as String?;
  return _readInt(data, 'availableMinorUnits') > 0 &&
      status != 'redeemed' &&
      status != 'expired' &&
      status != 'gift_pending' &&
      status != 'shared_checkout_reserved' &&
      status != 'transferred';
}

String _mapJoinRequestStatus(String? status) {
  switch (status) {
    case 'pending':
      return 'Waiting for unanimous approval';
    case 'rejected':
      return 'Rejected by a group member';
    case 'approved':
      return 'Approved';
    default:
      return status ?? 'Pending';
  }
}

String _mapPendingTransferStatus(String? status) {
  switch (status) {
    case 'pending':
      return 'Awaiting claim';
    case 'claimed':
    case 'claimed_partial':
      return 'Claimed';
    case 'expired':
      return 'Expired';
    default:
      return status ?? 'Pending';
  }
}

String _buildRequestedAtLabel(DateTime? requestedAt) {
  if (requestedAt == null) {
    return 'Requested recently';
  }
  return 'Requested ${formatShortDate(requestedAt)}';
}

String _buildLastActivityLabel(DateTime? updatedAt) {
  if (updatedAt == null) {
    return 'Active recently';
  }

  final difference = DateTime.now().difference(updatedAt.toLocal());
  if (difference.inMinutes < 60) {
    final minutes = difference.inMinutes <= 0 ? 1 : difference.inMinutes;
    return 'Active $minutes min ago';
  }
  if (difference.inHours < 24) {
    return 'Active ${difference.inHours} hr ago';
  }
  return 'Active ${formatShortDate(updatedAt)}';
}

String _buildDisabledLabel(DateTime? disabledAt) {
  if (disabledAt == null) {
    return 'Disabled';
  }
  return 'Disabled ${formatShortDate(disabledAt)}';
}

List<String> _recentDayIds({required int count, int endOffsetDays = 0}) {
  final today = DateTime.now();
  final anchor = DateTime(today.year, today.month, today.day);
  return List<String>.generate(count, (index) {
    final daysAgo = endOffsetDays + (count - index - 1);
    return _dayIdForDate(anchor.subtract(Duration(days: daysAgo)));
  });
}

String _dayIdForDate(DateTime date) {
  final normalized = DateTime(date.year, date.month, date.day);
  final month = normalized.month.toString().padLeft(2, '0');
  final day = normalized.day.toString().padLeft(2, '0');
  return '${normalized.year}$month$day';
}

String _formatTrendDayLabel(String dayId) {
  if (dayId.length != 8) {
    return dayId;
  }

  final year = int.tryParse(dayId.substring(0, 4));
  final month = int.tryParse(dayId.substring(4, 6));
  final day = int.tryParse(dayId.substring(6, 8));
  if (year == null || month == null || day == null) {
    return dayId;
  }
  return formatShortDate(DateTime(year, month, day));
}

Map<String, dynamic> _statsDataForDay(
  List<_DailyStatRecord> records,
  String dayId,
) {
  for (final record in records.reversed) {
    if (record.dayId == dayId) {
      return record.data;
    }
  }
  return const <String, dynamic>{};
}

int _sumStats(
  Iterable<_DailyStatRecord> records,
  String key, {
  String? fallbackKey,
}) {
  return records.fold<int>(
    0,
    (total, record) =>
        total + _readInt(record.data, key, fallbackKey: fallbackKey),
  );
}

int _sumStatsForDayIds(
  Iterable<List<_DailyStatRecord>> series,
  List<String> dayIds,
  String key, {
  String? fallbackKey,
}) {
  final dayIdSet = dayIds.toSet();
  var total = 0;
  for (final records in series) {
    for (final record in records) {
      if (!dayIdSet.contains(record.dayId)) {
        continue;
      }
      total += _readInt(record.data, key, fallbackKey: fallbackKey);
    }
  }
  return total;
}

MetricTrendDirection _trendDirection(int current, int previous) {
  if (current > previous) {
    return MetricTrendDirection.up;
  }
  if (current < previous) {
    return MetricTrendDirection.down;
  }
  return MetricTrendDirection.neutral;
}

DateTime? _readDateTime(Map<String, dynamic> data, String key) {
  final value = data[key];
  if (value is Timestamp) {
    return value.toDate();
  }
  if (value is DateTime) {
    return value;
  }
  return null;
}

int _readInt(
  Map<String, dynamic> data,
  String key, {
  String? fallbackKey,
  int fallback = 0,
}) {
  final value = data[key] ?? (fallbackKey != null ? data[fallbackKey] : null);
  if (value is num) {
    return value.toInt();
  }
  return fallback;
}

DateTime _createdAtForSort(Map<String, dynamic> data) {
  return _readDateTime(data, 'createdAt') ??
      DateTime.fromMillisecondsSinceEpoch(0);
}

DateTime _expiresAtForSort(Map<String, dynamic> data) {
  return _readDateTime(data, 'expiresAt') ??
      DateTime.fromMillisecondsSinceEpoch(0);
}

int _staffTabIndexFromPreference(String? value, {int fallback = 0}) {
  switch (value?.trim()) {
    case 'dashboard':
      return 0;
    case 'scan':
      return 1;
    case 'profile':
      return 2;
    default:
      return fallback;
  }
}

int _clientTabIndexFromPreference(String? value, {int fallback = 1}) {
  switch (value?.trim()) {
    case 'stores':
      return 0;
    case 'wallet':
      return 1;
    case 'history':
      return 2;
    case 'profile':
      return 3;
    default:
      return fallback;
  }
}
