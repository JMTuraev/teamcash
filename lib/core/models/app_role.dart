enum AppRole { owner, staff, client }

extension AppRoleX on AppRole {
  String get label => switch (this) {
    AppRole.owner => 'Owner',
    AppRole.staff => 'Staff',
    AppRole.client => 'Client',
  };

  String get routePath => switch (this) {
    AppRole.owner => '/owner',
    AppRole.staff => '/staff',
    AppRole.client => '/client',
  };

  String get summary => switch (this) {
    AppRole.owner =>
      'Multi-business management, staff administration, tandem governance, and business analytics.',
    AppRole.staff =>
      'Single-business operations, phone lookup fallback, QR scan entry points, and daily sales actions.',
    AppRole.client =>
      'Store discovery, group-bound wallet lots, transfers, shared checkout participation, and profile claims.',
  };

  String get navigationLabel => switch (this) {
    AppRole.owner => 'Businesses • Dashboard • Staffs',
    AppRole.staff => 'Dashboard • Scan • Profile',
    AppRole.client => 'Stores • Wallet • History • Profile',
  };
}
