import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';

class TelemetryService {
  TelemetryService._();

  static final TelemetryService instance = TelemetryService._();

  static const _apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const _appId = String.fromEnvironment('FIREBASE_APP_ID');
  static const _projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const _senderId =
      String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
  static const _storageBucket =
      String.fromEnvironment('FIREBASE_STORAGE_BUCKET');

  bool _enabled = false;
  FirebaseAnalytics? _analytics;
  FirebaseRemoteConfig? _remoteConfig;

  bool get enabled => _enabled;

  bool get configurationPresent =>
      _apiKey.isNotEmpty &&
      _appId.isNotEmpty &&
      _projectId.isNotEmpty &&
      _senderId.isNotEmpty;

  int get interstitialEvery {
    if (!_enabled) return 3;
    final value = _remoteConfig?.getInt('interstitial_every') ?? 3;
    return value.clamp(2, 10);
  }

  bool get appOpenEnabled =>
      !_enabled || (_remoteConfig?.getBool('app_open_enabled') ?? true);

  int get rewardedOcrThresholdPages {
    if (!_enabled) return 10;
    final value =
        _remoteConfig?.getInt('rewarded_ocr_threshold_pages') ?? 10;
    return value.clamp(1, 500);
  }

  Future<bool> initialize() async {
    if (_enabled) return true;

    if (!configurationPresent) {
      debugPrint(
        'Firebase disabled: FIREBASE_* dart-defines are not configured.',
      );
      return false;
    }

    try {
      await Firebase.initializeApp(
        options: FirebaseOptions(
          apiKey: _apiKey,
          appId: _appId,
          messagingSenderId: _senderId,
          projectId: _projectId,
          storageBucket:
              _storageBucket.isEmpty ? null : _storageBucket,
        ),
      );

      final analytics = FirebaseAnalytics.instance;
      await analytics.setAnalyticsCollectionEnabled(true);
      _analytics = analytics;

      final crashlytics = FirebaseCrashlytics.instance;
      await crashlytics.setCrashlyticsCollectionEnabled(!kDebugMode);

      final previousFlutterError = FlutterError.onError;
      FlutterError.onError = (details) {
        previousFlutterError?.call(details);
        if (!kDebugMode) {
          crashlytics.recordFlutterFatalError(details);
        }
      };

      final previousPlatformError = PlatformDispatcher.instance.onError;
      PlatformDispatcher.instance.onError = (error, stack) {
        if (!kDebugMode) {
          crashlytics.recordError(error, stack, fatal: true);
        }
        return previousPlatformError?.call(error, stack) ?? true;
      };

      final remote = FirebaseRemoteConfig.instance;
      await remote.setDefaults(const {
        'interstitial_every': 3,
        'app_open_enabled': true,
        'rewarded_ocr_threshold_pages': 10,
      });
      await remote.setConfigSettings(
        RemoteConfigSettings(
          fetchTimeout: const Duration(seconds: 10),
          minimumFetchInterval: const Duration(hours: 1),
        ),
      );
      try {
        await remote.fetchAndActivate();
      } catch (e) {
        debugPrint('Remote Config fetch skipped: $e');
      }

      _remoteConfig = remote;
      _enabled = true;
      await logEvent('app_bootstrap_ready');
      return true;
    } catch (e, stack) {
      debugPrint('Firebase initialization failed: $e\n$stack');
      return false;
    }
  }

  Future<void> logEvent(
    String name, {
    Map<String, Object>? parameters,
  }) async {
    final analytics = _analytics;
    if (!_enabled || analytics == null) return;
    try {
      await analytics.logEvent(
        name: name,
        parameters: parameters,
      );
    } catch (e) {
      debugPrint('Analytics event failed: $e');
    }
  }

  Future<void> recordNonFatal(
    Object error,
    StackTrace stack, {
    String? reason,
  }) async {
    if (!_enabled || kDebugMode) return;
    try {
      await FirebaseCrashlytics.instance.recordError(
        error,
        stack,
        fatal: false,
        reason: reason,
      );
    } catch (_) {}
  }
}
