import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class AdsService {
  AdsService._();

  static final AdsService instance = AdsService._();

  static const bannerTestId = 'ca-app-pub-3940256099942544/6300978111';
  static const interstitialTestId =
      'ca-app-pub-3940256099942544/1033173712';
  static const rewardedTestId =
      'ca-app-pub-3940256099942544/5224354917';

  bool _initialized = false;
  bool _canRequestAds = false;
  bool _privacyOptionsRequired = false;
  InterstitialAd? _interstitial;
  RewardedAd? _rewarded;
  int _completedOperations = 0;

  bool get canRequestAds => _canRequestAds;
  bool get privacyOptionsRequired => _privacyOptionsRequired;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

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

    if (_canRequestAds) {
      await MobileAds.instance.initialize();
      _loadInterstitial();
      _loadRewarded();
    }
  }

  Future<void> showPrivacyOptions() async {
    final completer = Completer<void>();
    ConsentForm.showPrivacyOptionsForm((error) {
      if (error != null) {
        debugPrint('Privacy options error: ${error.message}');
      }
      if (!completer.isCompleted) completer.complete();
    });
    await completer.future;
  }

  BannerAd? createBanner({required VoidCallback onChanged}) {
    if (!_canRequestAds) return null;
    final ad = BannerAd(
      adUnitId: bannerTestId,
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
      adUnitId: interstitialTestId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitial = ad;
        },
        onAdFailedToLoad: (error) {
          debugPrint('Interstitial failed: $error');
          _interstitial = null;
        },
      ),
    );
  }

  Future<void> recordCompletedOperation() async {
    _completedOperations++;
    if (_completedOperations % 3 != 0) return;
    final ad = _interstitial;
    if (ad == null) {
      _loadInterstitial();
      return;
    }

    final completer = Completer<void>();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (shownAd) {
        shownAd.dispose();
        _interstitial = null;
        _loadInterstitial();
        if (!completer.isCompleted) completer.complete();
      },
      onAdFailedToShowFullScreenContent: (shownAd, error) {
        shownAd.dispose();
        _interstitial = null;
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
      adUnitId: rewardedTestId,
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
    if (ad == null) {
      _loadRewarded();
      return false;
    }

    var earned = false;
    final completer = Completer<void>();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (shownAd) {
        shownAd.dispose();
        _rewarded = null;
        _loadRewarded();
        if (!completer.isCompleted) completer.complete();
      },
      onAdFailedToShowFullScreenContent: (shownAd, error) {
        shownAd.dispose();
        _rewarded = null;
        _loadRewarded();
        if (!completer.isCompleted) completer.complete();
      },
    );
    ad.show(onUserEarnedReward: (_, __) => earned = true);
    await completer.future;
    return earned;
  }

  void dispose() {
    _interstitial?.dispose();
    _rewarded?.dispose();
    _interstitial = null;
    _rewarded = null;
  }
}
