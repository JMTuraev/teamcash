import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:teamcash/app/bootstrap/firebase_bootstrap.dart';
import 'package:teamcash/app/router/app_router.dart';
import 'package:teamcash/app/theme/app_theme.dart';
import 'package:teamcash/core/models/workspace_models.dart';
import 'package:teamcash/data/preview/preview_repository.dart';

final bootstrapStateProvider = Provider<AppBootstrapState>(
  (ref) => throw UnimplementedError('App bootstrap state was not provided.'),
);

final appSnapshotProvider = Provider<AppWorkspaceSnapshot>(
  (ref) => ref.watch(bootstrapStateProvider).snapshot,
);

final firebaseStatusProvider = Provider<FirebaseBootstrapResult>(
  (ref) => ref.watch(bootstrapStateProvider).firebaseResult,
);

class AppBootstrapState {
  const AppBootstrapState({
    required this.firebaseResult,
    required this.snapshot,
  });

  final FirebaseBootstrapResult firebaseResult;
  final AppWorkspaceSnapshot snapshot;

  factory AppBootstrapState.preview() {
    return AppBootstrapState(
      firebaseResult: const FirebaseBootstrapResult.preview(
        'Running in preview mode because final Firebase runtime settings are not available for this platform yet.',
      ),
      snapshot: PreviewRepository.seeded(),
    );
  }
}

class TeamCashApp extends StatelessWidget {
  const TeamCashApp({
    super.key,
    required this.bootstrapState,
    this.overrides = const [],
  });

  final AppBootstrapState bootstrapState;
  final List overrides;

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [
        bootstrapStateProvider.overrideWithValue(bootstrapState),
        ...overrides,
      ],
      child: Consumer(
        builder: (context, ref, _) {
          final router = ref.watch(appRouterProvider);

          return MaterialApp.router(
            title: 'TeamCash',
            debugShowCheckedModeBanner: false,
            theme: buildTeamCashTheme(),
            routerConfig: router,
          );
        },
      ),
    );
  }
}
