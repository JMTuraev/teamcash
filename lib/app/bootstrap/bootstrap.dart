import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'package:teamcash/app/app.dart';
import 'package:teamcash/app/bootstrap/firebase_bootstrap.dart';
import 'package:teamcash/core/config/teamcash_environment.dart';
import 'package:teamcash/core/diagnostics/app_diagnostics.dart';
import 'package:teamcash/data/preview/preview_repository.dart';

Future<void> bootstrap({List overrides = const []}) async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  if (!_isTestBinding(binding)) {
    installAppDiagnostics();
  }

  final firebaseResult = await initializeFirebase();
  if (firebaseResult.mode == FirebaseBootstrapMode.connected) {
    _configureFirestore();
  }
  logAppDiagnostic(
    'app_bootstrap_completed',
    payload: {
      'firebaseMode': firebaseResult.mode.name,
      'message': firebaseResult.message,
      'environment': TeamCashEnvironment.describe(),
    },
  );
  final snapshot = PreviewRepository.seeded();

  runApp(
    TeamCashApp(
      bootstrapState: AppBootstrapState(
        firebaseResult: firebaseResult,
        snapshot: snapshot,
      ),
      overrides: overrides,
    ),
  );
}

void _configureFirestore() {
  if (kIsWeb) {
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: false,
      webExperimentalAutoDetectLongPolling: true,
      webExperimentalForceLongPolling: true,
    );
    return;
  }

  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
  );
}

bool _isTestBinding(WidgetsBinding binding) {
  final bindingName = binding.runtimeType.toString();
  return bindingName.contains('TestWidgetsFlutterBinding') ||
      bindingName.contains('IntegrationTestWidgetsFlutterBinding') ||
      bindingName.contains('LiveTestWidgetsFlutterBinding');
}
