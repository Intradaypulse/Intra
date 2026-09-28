import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum RewardedAdOutcome { earned, unavailable, dismissed, failed }

class AdsService {
  AdsService._();

  static final AdsService instance = AdsService._();

  static const _bannerTestId = 'ca-app-pub-3940256099942544/6300978111';
  static const _interstitialTestId = 'ca-app-pub-3940256099942544/1033173712';
  static const _rewardedTestId = 'ca-app-pub-3940256099942544/5224354917';
  static const _appOpenTestId = 'ca-app-pub-3940256099942544/9257395921';

  static const _productionBannerId = String.fromEnvironment('ADMOB_BANNER_ID');
  static const _productionInterstitialId = String.fromEnvironment(
    'ADMOB_INTERSTITIAL_ID',
  );
  static const _productionRewardedId = String.fromEnvironment(
    'ADMOB_REWARDED_ID',
  );
  static const _productionAppOpenId = String.fromEnvironment(
    'ADMOB_APP_OPEN_ID',
  );

  static bool get _productionIdsPresent =>
      _productionBannerId.isNotEmpty &&
      _productionInterstitialId.isNotEmpty &&
      _productionRewardedId.isNotEmpty &&
      _productionAppOpenId.isNotEmpty &&
      _productionBannerId != _bannerTestId &&
      _productionInterstitialId != _interstitialTestId &&
      _productionRewardedId != _rewardedTestId &&
      _productionAppOpenId != _appOpenTestId;

  static String get bannerId => kReleaseMode && _productionIdsPresent
      ? _productionBannerId
      : _bannerTestId;
  static String get interstitialId => kReleaseMode && _productionIdsPresent
      ? _productionInterstitialId
      : _interstitialTestId;
  static String get rewardedId => kReleaseMode && _productionIdsPresent
      ? _productionRewardedId
      : _rewardedTestId;
  static String get appOpenId => kReleaseMode && _productionIdsPresent
      ? _productionAppOpenId
      : _appOpenTestId;

  static const int _defaultInterstitialEvery = int.fromEnvironment(
    'INTERSTITIAL_EVERY',
    defaultValue: 3,
  );

  int _interstitialEvery = _defaultInterstitialEvery;

  static const _sessionKey = 'pdfmate_ad_sessions';
  static const _lastAppOpenKey = 'pdfmate_last_app_open_ms';

  final ValueNotifier<bool> adsAllowed = ValueNotifier<bool>(false);
  final Set<BannerAd> _banners = {};
  int _consentGeneration = 0;
  bool _loadingInterstitial = false;
  bool _loadingRewarded = false;
  bool _loadingAppOpen = false;
  bool _initialized = false;
  bool _canRequestAds = false;
  bool _privacyOptionsRequired = false;

  InterstitialAd? _interstitial;
  RewardedAd? _rewarded;
  Completer<bool>? _rewardedLoadCompleter;
  AppOpenAd? _appOpenAd;
  DateTime? _appOpenLoadTime;

  StreamSubscription<AppState>? _appStateSubscription;

  int _completedOperations = 0;
  bool _appOpenEnabled = true;
  int _sessionCount = 0;
  bool _isShowingFullScreenAd = false;
  DateTime? _lastFullScreenAdAt;

  bool get canRequestAds => _canRequestAds;
  bool get privacyOptionsRequired => _privacyOptionsRequired;
  bool get rewardedAvailable => _rewarded != null;
  bool get recentlyShowedFullScreenAd {
    final last = _lastFullScreenAdAt;
    return last != null &&
        DateTime.now().difference(last) < const Duration(minutes: 2);
  }

  void configureInterstitialFrequency(int every) {
    _interstitialEvery = every.clamp(2, 10);
  }

  void configureAppOpenEnabled(bool enabled) {
    _appOpenEnabled = enabled;
  }

  bool get productionConfigured => _productionIdsPresent;

  bool get productionRevenueMode => kReleaseMode && _productionIdsPresent;

  bool get usingTestIds => !productionRevenueMode;

  Future<void> initialize() async {
    try {
      await _initialize();
    } catch (_) {
      _initialized = false;
      _clearAds();
      rethrow;
    }
  }

  Future<void> _initialize() async {
    if (_initialized) return;
    _initialized = true;

    if (kReleaseMode && !productionConfigured) {
      debugPrint(
        'AdMob disabled in release: production ad unit IDs are missing.',
      );
      return;
    }

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
          await _completeConsent(completer);
        });
      },
      (error) async {
        debugPrint('UMP update error: ${error.message}');
        await _completeConsent(completer);
      },
    );

    await completer.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        _initialized = false;
      },
    );
  }

  Future<void> _completeConsent(Completer<void> completer) async {
    try {
      await _finishConsent();
    } catch (e) {
      debugPrint('Consent initialization failed: $e');
      _initialized = false;
      _clearAds();
    } finally {
      if (!completer.isCompleted) completer.complete();
    }
  }

  void _clearAds() {
    _canRequestAds = false;
    _consentGeneration++;
    _loadingInterstitial = _loadingRewarded = _loadingAppOpen = false;
    _interstitial?.dispose();
    _rewarded?.dispose();
    _appOpenAd?.dispose();
    _interstitial = null;
    _rewarded = null;
    _appOpenAd = null;
    _appOpenLoadTime = null;
    for (final banner in _banners.toList()) {
      banner.dispose();
    }
    _banners.clear();
    final pending = _rewardedLoadCompleter;
    if (pending != null && !pending.isCompleted) pending.complete(false);
    _rewardedLoadCompleter = null;
    adsAllowed.value = false;
  }

  Future<void> _finishConsent() async {
    _canRequestAds = await ConsentInformation.instance.canRequestAds();
    _privacyOptionsRequired =
        await ConsentInformation.instance
            .getPrivacyOptionsRequirementStatus() ==
        PrivacyOptionsRequirementStatus.required;

    if (!_canRequestAds) {
      _clearAds();
      return;
    }

    await MobileAds.instance.initialize();
    if (!_canRequestAds) return;
    adsAllowed.value = true;
    _loadInterstitial();
    _loadRewarded();
    _loadAppOpen();

    AppStateEventNotifier.startListening();
    _appStateSubscription ??= AppStateEventNotifier.appStateStream.listen((
      state,
    ) {
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
      await _completeConsent(completer);
    });
    await completer.future;
  }

  BannerAd? createBanner({required VoidCallback onChanged}) {
    if (!_canRequestAds) return null;

    final generation = _consentGeneration;
    final ad = BannerAd(
      adUnitId: bannerId,
      request: const AdRequest(),
      size: AdSize.banner,
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (!_canRequestAds || generation != _consentGeneration) {
            ad.dispose();
            return;
          }
          onChanged();
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint('Banner failed: $error');
          _banners.remove(ad);
          ad.dispose();
          onChanged();
        },
      ),
    );
    _banners.add(ad);
    ad.load();
    return ad;
  }

  bool isBannerActive(BannerAd ad) => _canRequestAds && _banners.contains(ad);

  void releaseBanner(BannerAd? ad) {
    if (ad == null) return;
    _banners.remove(ad);
    ad.dispose();
  }

  void _loadInterstitial() {
    if (!_canRequestAds || _interstitial != null || _loadingInterstitial)
      return;
    _loadingInterstitial = true;
    final generation = _consentGeneration;
    InterstitialAd.load(
      adUnitId: interstitialId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          if (generation != _consentGeneration || !_canRequestAds) {
            ad.dispose();
            return;
          }
          _loadingInterstitial = false;
          _interstitial = ad;
        },
        onAdFailedToLoad: (error) {
          if (generation != _consentGeneration) return;
          _loadingInterstitial = false;
          debugPrint('Interstitial failed: $error');
          _interstitial = null;
        },
      ),
    );
  }

  Future<void> recordCompletedOperation() async {
    if (!_canRequestAds) return;
    _completedOperations++;
    if (recentlyShowedFullScreenAd) return;
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
    _lastFullScreenAdAt = DateTime.now();
    await completer.future;
  }

  void _loadRewarded() {
    if (!_canRequestAds || _rewarded != null || _loadingRewarded) return;
    _loadingRewarded = true;
    final generation = _consentGeneration;
    RewardedAd.load(
      adUnitId: rewardedId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          if (generation != _consentGeneration || !_canRequestAds) {
            ad.dispose();
            return;
          }
          _loadingRewarded = false;
          _rewarded = ad;
          final completer = _rewardedLoadCompleter;
          if (completer != null && !completer.isCompleted) {
            completer.complete(true);
          }
          _rewardedLoadCompleter = null;
        },
        onAdFailedToLoad: (error) {
          if (generation != _consentGeneration) return;
          _loadingRewarded = false;
          debugPrint('Rewarded failed: $error');
          _rewarded = null;
          final completer = _rewardedLoadCompleter;
          if (completer != null && !completer.isCompleted) {
            completer.complete(false);
          }
          _rewardedLoadCompleter = null;
        },
      ),
    );
  }

  Future<bool> ensureRewardedReady({
    Duration timeout = const Duration(seconds: 6),
  }) async {
    if (!_canRequestAds || _isShowingFullScreenAd) return false;
    if (_rewarded != null) return true;

    final pending = _rewardedLoadCompleter;
    if (pending != null) {
      try {
        return await pending.future.timeout(timeout);
      } on TimeoutException {
        return false;
      }
    }

    final completer = Completer<bool>();
    _rewardedLoadCompleter = completer;
    _loadRewarded();
    try {
      return await completer.future.timeout(timeout);
    } on TimeoutException {
      if (identical(_rewardedLoadCompleter, completer)) {
        _rewardedLoadCompleter = null;
      }
      return _rewarded != null;
    }
  }

  Future<RewardedAdOutcome> showRewardedGate() async {
    if (_isShowingFullScreenAd) return RewardedAdOutcome.unavailable;
    final ready = await ensureRewardedReady();
    if (!ready || !_canRequestAds || _isShowingFullScreenAd)
      return RewardedAdOutcome.unavailable;

    final ad = _rewarded;
    if (ad == null) return RewardedAdOutcome.unavailable;

    var earned = false;
    var failed = false;
    final completer = Completer<void>();
    _isShowingFullScreenAd = true;

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (_) {
        _lastFullScreenAdAt = DateTime.now();
      },
      onAdDismissedFullScreenContent: (shownAd) {
        shownAd.dispose();
        _rewarded = null;
        _isShowingFullScreenAd = false;
        _loadRewarded();
        if (!completer.isCompleted) completer.complete();
      },
      onAdFailedToShowFullScreenContent: (shownAd, error) {
        failed = true;
        shownAd.dispose();
        _rewarded = null;
        _isShowingFullScreenAd = false;
        _loadRewarded();
        if (!completer.isCompleted) completer.complete();
      },
    );

    ad.show(
      onUserEarnedReward: (_, reward) {
        earned = true;
        _lastFullScreenAdAt = DateTime.now();
      },
    );
    await completer.future;

    if (failed) return RewardedAdOutcome.failed;
    return earned ? RewardedAdOutcome.earned : RewardedAdOutcome.dismissed;
  }

  Future<bool> showRewarded() async =>
      (await showRewardedGate()) == RewardedAdOutcome.earned;

  void _loadAppOpen() {
    if (!_canRequestAds || _appOpenAd != null || _loadingAppOpen) return;
    _loadingAppOpen = true;
    final generation = _consentGeneration;

    AppOpenAd.load(
      adUnitId: appOpenId,
      request: const AdRequest(),
      adLoadCallback: AppOpenAdLoadCallback(
        onAdLoaded: (ad) {
          if (generation != _consentGeneration || !_canRequestAds) {
            ad.dispose();
            return;
          }
          _loadingAppOpen = false;
          _appOpenAd = ad;
          _appOpenLoadTime = DateTime.now();
        },
        onAdFailedToLoad: (error) {
          if (generation != _consentGeneration) return;
          _loadingAppOpen = false;
          debugPrint('App open failed: $error');
          _appOpenAd = null;
          _appOpenLoadTime = null;
        },
      ),
    );
  }

  Future<void> showAppOpenIfEligible() async {
    // Google recommends waiting until users have used the app a few times.
    if (!_appOpenEnabled ||
        !_canRequestAds ||
        _sessionCount < 3 ||
        _isShowingFullScreenAd ||
        recentlyShowedFullScreenAd)
      return;

    final prefs = await SharedPreferences.getInstance();
    if (!_appOpenEnabled ||
        !_canRequestAds ||
        _isShowingFullScreenAd ||
        recentlyShowedFullScreenAd)
      return;
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
    _lastFullScreenAdAt = DateTime.now();
  }

  Future<void> dispose() async {
    _clearAds();
    await _appStateSubscription?.cancel();
    _appStateSubscription = null;
    _initialized = false;
  }
}
