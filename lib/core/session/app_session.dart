import 'package:teamcash/core/models/app_role.dart';

class AppSession {
  const AppSession({
    required this.role,
    required this.displayName,
    required this.isPreview,
    this.uid,
    this.customerId,
    this.businessId,
    this.businessIds = const [],
    this.phoneNumber,
  });

  final AppRole role;
  final String displayName;
  final bool isPreview;
  final String? uid;
  final String? customerId;
  final String? businessId;
  final List<String> businessIds;
  final String? phoneNumber;

  String get routePath => role.routePath;
}
