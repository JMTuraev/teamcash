enum TeamCashEnvironmentStage { dev, staging, prod }

class TeamCashEnvironment {
  TeamCashEnvironment._();

  static const String envName = String.fromEnvironment(
    'TEAMCASH_ENV',
    defaultValue: 'dev',
  );
  static const String functionsRegion = String.fromEnvironment(
    'TEAMCASH_FUNCTIONS_REGION',
    defaultValue: 'us-central1',
  );
  static const String appCheckMode = String.fromEnvironment(
    'TEAMCASH_APPCHECK_MODE',
    defaultValue: 'monitor',
  );
  static const String appCheckWebSiteKey = String.fromEnvironment(
    'TEAMCASH_APPCHECK_WEB_SITE_KEY',
    defaultValue: '',
  );
  static const String appCheckWebDebugToken = String.fromEnvironment(
    'TEAMCASH_APPCHECK_WEB_DEBUG_TOKEN',
    defaultValue: '',
  );
  static const bool useFirebaseEmulators = bool.fromEnvironment(
    'TEAMCASH_USE_FIREBASE_EMULATORS',
    defaultValue: false,
  );
  static const String authEmulatorHost = String.fromEnvironment(
    'TEAMCASH_AUTH_EMULATOR_HOST',
    defaultValue: '127.0.0.1',
  );
  static const int authEmulatorPort = int.fromEnvironment(
    'TEAMCASH_AUTH_EMULATOR_PORT',
    defaultValue: 9099,
  );
  static const String firestoreEmulatorHost = String.fromEnvironment(
    'TEAMCASH_FIRESTORE_EMULATOR_HOST',
    defaultValue: '127.0.0.1',
  );
  static const int firestoreEmulatorPort = int.fromEnvironment(
    'TEAMCASH_FIRESTORE_EMULATOR_PORT',
    defaultValue: 8080,
  );
  static const String functionsEmulatorHost = String.fromEnvironment(
    'TEAMCASH_FUNCTIONS_EMULATOR_HOST',
    defaultValue: '127.0.0.1',
  );
  static const int functionsEmulatorPort = int.fromEnvironment(
    'TEAMCASH_FUNCTIONS_EMULATOR_PORT',
    defaultValue: 5001,
  );
  static const String storageEmulatorHost = String.fromEnvironment(
    'TEAMCASH_STORAGE_EMULATOR_HOST',
    defaultValue: '127.0.0.1',
  );
  static const int storageEmulatorPort = int.fromEnvironment(
    'TEAMCASH_STORAGE_EMULATOR_PORT',
    defaultValue: 9199,
  );
  static const bool captureVerboseDiagnostics = bool.fromEnvironment(
    'TEAMCASH_VERBOSE_DIAGNOSTICS',
    defaultValue: false,
  );

  static TeamCashEnvironmentStage get stage {
    switch (envName.toLowerCase()) {
      case 'prod':
      case 'production':
        return TeamCashEnvironmentStage.prod;
      case 'staging':
        return TeamCashEnvironmentStage.staging;
      default:
        return TeamCashEnvironmentStage.dev;
    }
  }

  static bool get usesDebugAppCheckOnWeb =>
      stage != TeamCashEnvironmentStage.prod ||
      appCheckWebDebugToken.isNotEmpty;

  static bool get shouldAttemptAppCheck => appCheckMode.toLowerCase() != 'off';

  static bool get wantsEnforcedAppCheck =>
      appCheckMode.toLowerCase() == 'enforce';

  static String describe() {
    return [
      'env=$envName',
      'region=$functionsRegion',
      'appCheckMode=$appCheckMode',
      'emulators=$useFirebaseEmulators',
    ].join(' ');
  }
}
