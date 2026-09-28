import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AdsService {
  AdsService._();

  static final AdsService instance = AdsService._();

  static const _bannerTestId =
      'ca-app-pub-3940256099942544/6300978111';
  static const _interstitialTestId =
      'ca-app-pub-3940256099942544/1033173712';
  static const _rewardedTestId =
      'ca-app-pub-3940256099942544/5224354917';
  static const _appOpenTestId =
      'ca-app-pub-3940256099942544/9257395921';

  static const bannerId = String.fromEnvironment(
    'ADMOB_BANNER_ID',
    defaultValue: _bannerTestId,
  );
  static const interstitialId = String.fromEnvironment(
    'ADMOB_INTERSTITIAL_ID',
    defaultValue: _interstitialTestId,
  );
  static const rewardedId = String.fromEnvironment(
    'ADMOB_REWARDED_ID',
    defaultValue: _rewardedTestId,
  );
  static const appOpenId = String.fromEnvironment(
    'ADMOB_APP_OPEN_ID',
    defaultValue: _appOpenTestId,
  );

  static const int _interstitialEvery =
      int.fromEnvironment('INTERSTITIAL_EVERY', defaultValue: 3);

  static const _sessionKey = 'pdfmate_ad_sessions';
  static const _lastAppOpenKey = 'pdfmate_last_app_open_ms';

  bool _initialized = false;
  bool _canRequestAds = false;
  bool _privacyOptionsRequired = false;

  InterstitialAd? _interstitial;
  RewardedAd? _rewarded;
  AppOpenAd? _appOpenAd;
  DateTime? _appOpenLoadTime;

  StreamSubscription<AppState>? _appStateSubscription;

  int _completedOperations = 0;
  int _sessionCount = 0;
  bool _isShowingFullScreenAd = false;

  bool get canRequestAds => _canRequestAds;
  bool get privacyOptionsRequired => _privacyOptionsRequired;
  bool get rewardedAvailable => _rewarded != null;

  bool get usingTestIds =>
      bannerId == _bannerTestId ||
      interstitialId == _interstitialTestId ||
      rewardedId == _rewardedTestId ||
      appOpenId == _appOpenTestId;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    final prefs = await SharedPreferences.getInstance();
    _sessionCount = (prefs.getInt(_sessionKey) ?? 0) + 1;
    await prefs.setInt(_sessionKey, _sessionCount);

    final completer = Completer<void>();
    final params = ConsentRequestParameters();

    ConsentInformation.instance.requestConsentInfoUpdate(
      params,
      () async {
        ConsentForm.loadAndShowConsentFormIfRequired((formError) async {
          if (formError != null) {
            debugPrint('UMP form error: ${formError.message}');
          }
          await _finishConsent();
          if (!completer.isCompleted) completer.complete();
        });
      },
      (error) async {
        debugPrint('UMP update error: ${error.message}');
        await _finishConsent();
        if (!completer.isCompleted) completer.complete();
      },
    );

    await completer.future;
  }

  Future<void> _finishConsent() async {
    _canRequestAds = await ConsentInformation.instance.canRequestAds();
    _privacyOptionsRequired = await ConsentInformation.instance
            .getPrivacyOptionsRequirementStatus() ==
        PrivacyOptionsRequirementStatus.required;

    if (!_canRequestAds) return;

    await MobileAds.instance.initialize();
    _loadInterstitial();
    _loadRewarded();
    _loadAppOpen();

    AppStateEventNotifier.startListening();
    _appStateSubscription ??=
        AppStateEventNotifier.appStateStream.listen((state) {
      if (state == AppState.foreground) {
        unawaited(showAppOpenIfEligible());
      }
    });
  }

  Future<void> showPrivacyOptions() async {
    final completer = Completer<void>();
    ConsentForm.showPrivacyOptionsForm((error) async {
      if (error != null) {
        debugPrint('Privacy options error: ${error.message}');
      }
      await _finishConsent();
      if (!completer.isCompleted) completer.complete();
    });
    await completer.future;
  }

  BannerAd? createBanner({required VoidCallback onChanged}) {
    if (!_canRequestAds) return null;

    final ad = BannerAd(
      adUnitId: bannerId,
      request: const AdRequest(),
      size: AdSize.banner,
      listener: BannerAdListener(
        onAdLoaded: (_) => onChanged(),
        onAdFailedToLoad: (ad, error) {
          debugPrint('Banner failed: $error');
          ad.dispose();
          onChanged();
        },
      ),
    );
    ad.load();
    return ad;
  }

  void _loadInterstitial() {
    if (!_canRequestAds || _interstitial != null) return;
    InterstitialAd.load(
      adUnitId: interstitialId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) => _interstitial = ad,
        onAdFailedToLoad: (error) {
          debugPrint('Interstitial failed: $error');
          _interstitial = null;
        },
      ),
    );
  }

  Future<void> recordCompletedOperation() async {
    _completedOperations++;
    if (_interstitialEvery <= 0 ||
        _completedOperations % _interstitialEvery != 0) {
      return;
    }

    final ad = _interstitial;
    if (ad == null || _isShowingFullScreenAd) {
      _loadInterstitial();
      return;
    }

    final completer = Completer<void>();
    _isShowingFullScreenAd = true;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (shownAd) {
        shownAd.dispose();
        _interstitial = null;
        _isShowingFullScreenAd = false;
        _loadInterstitial();
        if (!completer.isCompleted) completer.complete();
      },
      onAdFailedToShowFullScreenContent: (shownAd, error) {
        shownAd.dispose();
        _interstitial = null;
        _isShowingFullScreenAd = false;
        _loadInterstitial();
        if (!completer.isCompleted) completer.complete();
      },
    );
    ad.show();
    await completer.future;
  }

  void _loadRewarded() {
    if (!_canRequestAds || _rewarded != null) return;
    RewardedAd.load(
      adUnitId: rewardedId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) => _rewarded = ad,
        onAdFailedToLoad: (error) {
          debugPrint('Rewarded failed: $error');
          _rewarded = null;
        },
      ),
    );
  }

  Future<bool> showRewarded() async {
    final ad = _rewarded;
    if (ad == null || _isShowingFullScreenAd) {
      _loadRewarded();
      return false;
    }

    var earned = false;
    final completer = Completer<void>();
    _isShowingFullScreenAd = true;

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (shownAd) {
        shownAd.dispose();
        _rewarded = null;
        _isShowingFullScreenAd = false;
        _loadRewarded();
        if (!completer.isCompleted) completer.complete();
      },
      onAdFailedToShowFullScreenContent: (shownAd, error) {
        shownAd.dispose();
        _rewarded = null;
        _isShowingFullScreenAd = false;
        _loadRewarded();
        if (!completer.isCompleted) completer.complete();
      },
    );

    ad.show(
      onUserEarnedReward: (_, reward) => earned = true,
    );
    await completer.future;
    return earned;
  }

  void _loadAppOpen() {
    if (!_canRequestAds || _appOpenAd != null) return;

    AppOpenAd.load(
      adUnitId: appOpenId,
      request: const AdRequest(),
      adLoadCallback: AppOpenAdLoadCallback(
        onAdLoaded: (ad) {
          _appOpenAd = ad;
          _appOpenLoadTime = DateTime.now();
        },
        onAdFailedToLoad: (error) {
          debugPrint('App open failed: $error');
          _appOpenAd = null;
          _appOpenLoadTime = null;
        },
      ),
    );
  }

  Future<void> showAppOpenIfEligible() async {
    // Google recommends waiting until users have used the app a few times.
    if (!_canRequestAds || _sessionCount < 3 || _isShowingFullScreenAd) return;

    final prefs = await SharedPreferences.getInstance();
    final lastMs = prefs.getInt(_lastAppOpenKey);
    if (lastMs != null) {
      final lastShown = DateTime.fromMillisecondsSinceEpoch(lastMs);
      if (DateTime.now().difference(lastShown) < const Duration(hours: 6)) {
        return;
      }
    }

    final loadedAt = _appOpenLoadTime;
    final ad = _appOpenAd;

    if (ad == null ||
        loadedAt == null ||
        DateTime.now().difference(loadedAt) >= const Duration(hours: 4)) {
      ad?.dispose();
      _appOpenAd = null;
      _appOpenLoadTime = null;
      _loadAppOpen();
      return;
    }

    _isShowingFullScreenAd = true;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (_) async {
        await prefs.setInt(
          _lastAppOpenKey,
          DateTime.now().millisecondsSinceEpoch,
        );
      },
      onAdDismissedFullScreenContent: (shownAd) {
        shownAd.dispose();
        _appOpenAd = null;
        _appOpenLoadTime = null;
        _isShowingFullScreenAd = false;
        _loadAppOpen();
      },
      onAdFailedToShowFullScreenContent: (shownAd, error) {
        shownAd.dispose();
        _appOpenAd = null;
        _appOpenLoadTime = null;
        _isShowingFullScreenAd = false;
        _loadAppOpen();
      },
    );

    ad.show();
  }

  Future<void> dispose() async {
    await _appStateSubscription?.cancel();
    _interstitial?.dispose();
    _rewarded?.dispose();
    _appOpenAd?.dispose();
    _interstitial = null;
    _rewarded = null;
    _appOpenAd = null;
  }
}
