enum MetricTrendDirection { up, neutral, down }

class DashboardMetric {
  const DashboardMetric({
    required this.label,
    required this.value,
    required this.detail,
    this.trendDirection = MetricTrendDirection.neutral,
  });

  final String label;
  final String value;
  final String detail;
  final MetricTrendDirection trendDirection;
}

class DashboardTrendPoint {
  const DashboardTrendPoint({
    required this.label,
    required this.salesMinorUnits,
    required this.issuedMinorUnits,
    required this.redeemedMinorUnits,
    required this.clientsCount,
    required this.lookupsCount,
  });

  final String label;
  final int salesMinorUnits;
  final int issuedMinorUnits;
  final int redeemedMinorUnits;
  final int clientsCount;
  final int lookupsCount;
}

class BusinessPerformanceSnapshot {
  const BusinessPerformanceSnapshot({
    required this.businessId,
    required this.businessName,
    required this.groupName,
    required this.todaySalesMinorUnits,
    required this.todaySalesCount,
    required this.rolling7DaySalesMinorUnits,
    required this.rolling7DayIssuedMinorUnits,
    required this.rolling7DayRedeemedMinorUnits,
    required this.rolling7DayLookupsCount,
    required this.todayClientsCount,
    required this.totalClientsCount,
  });

  final String businessId;
  final String businessName;
  final String groupName;
  final int todaySalesMinorUnits;
  final int todaySalesCount;
  final int rolling7DaySalesMinorUnits;
  final int rolling7DayIssuedMinorUnits;
  final int rolling7DayRedeemedMinorUnits;
  final int rolling7DayLookupsCount;
  final int todayClientsCount;
  final int totalClientsCount;
}
