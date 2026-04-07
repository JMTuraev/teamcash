import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

import 'package:teamcash/core/config/teamcash_environment.dart';

void installAppDiagnostics() {
  FlutterError.onError = (details) {
    _logStructured(
      event: 'flutter_error',
      payload: {
        'exception': details.exceptionAsString(),
        'library': details.library,
        'context': details.context?.toDescription(),
      },
      stackTrace: details.stack,
      isError: true,
    );
    FlutterError.presentError(details);
  };

  PlatformDispatcher.instance.onError = (error, stackTrace) {
    _logStructured(
      event: 'platform_error',
      payload: {'exception': error.toString()},
      stackTrace: stackTrace,
      isError: true,
    );
    return false;
  };
}

void logAppDiagnostic(
  String event, {
  Map<String, Object?> payload = const {},
  StackTrace? stackTrace,
  bool isError = false,
}) {
  _logStructured(
    event: event,
    payload: payload,
    stackTrace: stackTrace,
    isError: isError,
  );
}

void _logStructured({
  required String event,
  required Map<String, Object?> payload,
  StackTrace? stackTrace,
  required bool isError,
}) {
  final record = <String, Object?>{
    'event': event,
    'env': TeamCashEnvironment.envName,
    'region': TeamCashEnvironment.functionsRegion,
    'mode': kReleaseMode ? 'release' : 'debug',
    'platform': defaultTargetPlatform.name,
    'payload': payload,
  };

  developer.log(
    jsonEncode(record),
    name: 'teamcash',
    error: isError ? payload : null,
    stackTrace: stackTrace,
    level: isError ? 1000 : 800,
  );

  if (!kReleaseMode || TeamCashEnvironment.captureVerboseDiagnostics) {
    debugPrint('teamcash:${isError ? 'error' : 'info'}:${jsonEncode(record)}');
  }
}
