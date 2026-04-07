import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';
import 'package:teamcash/firebase_options.dart';
import 'package:teamcash/core/config/teamcash_environment.dart';
import 'package:teamcash/core/diagnostics/app_diagnostics.dart';

enum FirebaseBootstrapMode { connected, preview }

class FirebaseBootstrapResult {
  const FirebaseBootstrapResult._({required this.mode, required this.message});

  const FirebaseBootstrapResult.connected(String message)
    : this._(mode: FirebaseBootstrapMode.connected, message: message);

  const FirebaseBootstrapResult.preview(String message)
    : this._(mode: FirebaseBootstrapMode.preview, message: message);

  final FirebaseBootstrapMode mode;
  final String message;
}

Future<FirebaseBootstrapResult> initializeFirebase() async {
  if (Firebase.apps.isNotEmpty) {
    return const FirebaseBootstrapResult.connected(
      'Firebase was already initialized for this session.',
    );
  }

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    final appCheckMessage = await _activateAppCheck();
    return const FirebaseBootstrapResult.connected(
      'Firebase is active using the generated FlutterFire platform options.',
    )._withMessageSuffix(appCheckMessage);
  } on FirebaseException catch (error, stackTrace) {
    logAppDiagnostic(
      'firebase_bootstrap_failed',
      payload: {
        'code': error.code,
        'message': error.message,
        'environment': TeamCashEnvironment.describe(),
      },
      stackTrace: stackTrace,
      isError: true,
    );
    return FirebaseBootstrapResult.preview(
      'Firebase initialization failed on this platform, so the app fell back to preview mode. Details: ${error.message ?? error.code}',
    );
  } on UnsupportedError catch (error) {
    return FirebaseBootstrapResult.preview(
      'Firebase is not configured for this platform yet, so the app fell back to preview mode. Details: $error',
    );
  } on Object catch (error) {
    return FirebaseBootstrapResult.preview(
      'Firebase initialization failed on this platform, so the app fell back to preview mode. Details: $error',
    );
  }
}

extension on FirebaseBootstrapResult {
  FirebaseBootstrapResult _withMessageSuffix(String suffix) {
    if (suffix.trim().isEmpty) {
      return this;
    }

    return mode == FirebaseBootstrapMode.connected
        ? FirebaseBootstrapResult.connected('$message $suffix')
        : FirebaseBootstrapResult.preview('$message $suffix');
  }
}

Future<String> _activateAppCheck() async {
  if (!TeamCashEnvironment.shouldAttemptAppCheck) {
    return 'App Check is disabled for this runtime.';
  }

  try {
    if (kIsWeb) {
      final appCheckActivated = await _activateWebAppCheck();
      if (!appCheckActivated) {
        return 'App Check is in monitor mode until a web provider is configured.';
      }

      await FirebaseAppCheck.instance.setTokenAutoRefreshEnabled(true);
      return TeamCashEnvironment.usesDebugAppCheckOnWeb
          ? 'App Check is active in debug mode on web.'
          : 'App Check is active with reCAPTCHA v3 on web.';
    }

    await FirebaseAppCheck.instance.activate();
    await FirebaseAppCheck.instance.setTokenAutoRefreshEnabled(true);
    return 'App Check is active for native platforms.';
  } on Object catch (error, stackTrace) {
    logAppDiagnostic(
      'app_check_activation_failed',
      payload: {
        'error': error.toString(),
        'environment': TeamCashEnvironment.describe(),
      },
      stackTrace: stackTrace,
      isError: TeamCashEnvironment.wantsEnforcedAppCheck,
    );

    if (TeamCashEnvironment.wantsEnforcedAppCheck) {
      rethrow;
    }

    return 'App Check setup is pending: $error';
  }
}

Future<bool> _activateWebAppCheck() async {
  if (TeamCashEnvironment.usesDebugAppCheckOnWeb) {
    final debugToken = TeamCashEnvironment.appCheckWebDebugToken.trim();
    await FirebaseAppCheck.instance.activate(
      providerWeb: debugToken.isEmpty
          ? WebDebugProvider()
          : WebDebugProvider(debugToken: debugToken),
    );
    return true;
  }

  final siteKey = TeamCashEnvironment.appCheckWebSiteKey.trim();
  if (siteKey.isEmpty) {
    return false;
  }

  await FirebaseAppCheck.instance.activate(
    providerWeb: ReCaptchaV3Provider(siteKey),
  );
  return true;
}
