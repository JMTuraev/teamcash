import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:teamcash/features/client/presentation/client_shell.dart';
import 'package:teamcash/features/owner/presentation/owner_shell.dart';
import 'package:teamcash/features/root/presentation/client_sign_in_page.dart';
import 'package:teamcash/features/root/presentation/operator_sign_in_page.dart';
import 'package:teamcash/features/root/presentation/role_hub_page.dart';
import 'package:teamcash/features/staff/presentation/staff_shell.dart';
import 'package:teamcash/core/models/app_role.dart';

final appRouterProvider = Provider<GoRouter>(
  (ref) => GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (context, state) => const RoleHubPage()),
      GoRoute(
        path: '/sign-in/:role',
        builder: (context, state) {
          final role = switch (state.pathParameters['role']) {
            'owner' => AppRole.owner,
            'staff' => AppRole.staff,
            'client' => AppRole.client,
            _ => AppRole.owner,
          };

          return role == AppRole.client
              ? const ClientSignInPage()
              : OperatorSignInPage(role: role);
        },
      ),
      GoRoute(path: '/owner', builder: (context, state) => const OwnerShell()),
      GoRoute(path: '/staff', builder: (context, state) => const StaffShell()),
      GoRoute(
        path: '/client',
        builder: (context, state) => const ClientShell(),
      ),
    ],
  ),
);
