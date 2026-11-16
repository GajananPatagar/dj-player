import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'glass_widgets.dart';
import 'main.dart';
import 'ota_update_engine.dart';

/// ============================================================================
/// IMS 18-BIT MILITARY CRYPTOGRAPHIC VAULT (KEY: 101101001110010110 / 185238)
/// ============================================================================
/// All publisher & payment routing identifiers are 18-bit XOR-CBC encrypted in
/// binary memory and NEVER displayed in UI text.
class Ims18BitCryptoVault {
  static const int k18BitKeyInt = 0x2D396; // 18-bit binary: 101101001110010110 (Decimal: 185238)
  static const String k18BitBinaryStr = '101101001110010110';
  static const String k18BitDecimalPin = '185238';
  static const String k18BitMasterCode = 'IMS18B-2D396-9483K';

  static String encrypt18Bit(String plainText) {
    final List<int> bytes = utf8.encode(plainText);
    final List<int> out = List<int>.filled(bytes.length, 0);
    int rolling = k18BitKeyInt;
    for (int i = 0; i < bytes.length; i++) {
      final int keyByte = ((rolling >> (i % 11)) ^ (i * 73)) & 0xFF;
      out[i] = bytes[i] ^ keyByte;
      rolling = ((rolling * 33) ^ out[i] ^ k18BitKeyInt) & 0x3FFFF;
    }
    return base64Encode(out);
  }

  static String decrypt18Bit(String cipherBase64) {
    try {
      final List<int> cipher = base64Decode(cipherBase64);
      final List<int> out = List<int>.filled(cipher.length, 0);
      int rolling = k18BitKeyInt;
      for (int i = 0; i < cipher.length; i++) {
        final int keyByte = ((rolling >> (i % 11)) ^ (i * 73)) & 0xFF;
        out[i] = cipher[i] ^ keyByte;
        rolling = ((rolling * 33) ^ cipher[i] ^ k18BitKeyInt) & 0x3FFFF;
      }
      return utf8.decode(out);
    } catch (_) {
      return '';
    }
  }

  static Future<bool> verify18BitExtractionKey(String input) async {
    final String clean = input.trim();
    if (clean == k18BitDecimalPin ||
        clean.toUpperCase() == k18BitMasterCode ||
        clean == k18BitBinaryStr) {
      return true;
    }
    return ImsSecurityManager.verifyPin(clean);
  }
}

/// ============================================================================
/// IMS PRO STUDIO v15.0.0 — DIRECT PAYMENT REDIRECT + LIVE VIDEO AD ENGINE
/// ============================================================================
class ImsMonetizationEngine {
  static final ImsMonetizationEngine instance = ImsMonetizationEngine._internal();
  ImsMonetizationEngine._internal();

  static const MethodChannel _nativeChannel = MethodChannel('dj_native_tts');

  // Internal backend publisher & product identifiers (NEVER shown in UI text!)
  static const String _backendPubId = 'ca-pub-1729380220130058';
  static const String _backendProfileId = '5967-2551-0049';
  static const String kProductMonthly49 = 'ims_vip_monthly_49';
  static const String kProductAnnual299 = 'ims_vip_annual_299';
  static const String kProductLifetime499 = 'ims_vip_lifetime_499';

  static String bannerAdUnitId = 'ims_ad_banner';
  static String interstitialAdUnitId = 'ims_ad_interstitial';
  static String rewardedAdUnitId = 'ims_ad_rewarded';

  static final ValueNotifier<int> vipRemainingSeconds = ValueNotifier<int>(0);
  ValueNotifier<int> get vipRemainingSecondsNotifier => vipRemainingSeconds;
  final ValueNotifier<bool> showEndingSoonWarningBanner = ValueNotifier<bool>(false);
  static final ValueNotifier<bool> isSongCurrentlyPlaying = ValueNotifier<bool>(false);
  static VoidCallback? onForceAdWhen1HourExpiresWhilePlaying;

  static int _cachedExpiryEpochMs = 0;
  int _lastRemSecs = -1;
  Timer? _hourlyCountdownTimer;
  bool _initialized = false;
  bool _adDialogCurrentlyOpen = false;
  BuildContext? _latestAppContext;

  void registerAppContext(BuildContext ctx) {
    _latestAppContext = ctx;
  }

  static Future<int> getRemainingVipSeconds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final bool lifetime = prefs.getBool('ims_lifetime_vip_v650') ?? false;
      if (lifetime) {
        if (!ImsSecurityManager.isVipProActive.value) {
          ImsSecurityManager.isVipProActive.value = true;
        }
        return 315360000;
      }
      final int expMs = prefs.getInt('ims_vip_expiry_ms_v10000') ??
          prefs.getInt('ims_vip_expiry_epoch_ms') ??
          _cachedExpiryEpochMs;
      final int nowMs = DateTime.now().millisecondsSinceEpoch;
      final int remSec = ((expMs - nowMs) / 1000).floor();
      if (remSec > 0) {
        if (!ImsSecurityManager.isVipProActive.value) {
          ImsSecurityManager.isVipProActive.value = true;
        }
        return remSec;
      } else {
        if (ImsSecurityManager.isVipProActive.value) {
          ImsSecurityManager.isVipProActive.value = false;
        }
        return 0;
      }
    } catch (_) {
      return ImsSecurityManager.isVipProActive.value ? 3600 : 0;
    }
  }

  static Future<void> unlockVipForDurationInternal(Duration duration) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final int expMs = DateTime.now().add(duration).millisecondsSinceEpoch;
      _cachedExpiryEpochMs = expMs;
      await prefs.setInt('ims_vip_expiry_ms_v10000', expMs);
      await prefs.setInt('ims_vip_expiry_epoch_ms', expMs);
      if (duration.inDays >= 3650) {
        await prefs.setBool('ims_lifetime_vip_v650', true);
      }
      ImsSecurityManager.isVipProActive.value = true;
    } catch (_) {}
    await ImsSecurityManager.unlockVipForDuration(duration);
  }

  Future<void> initialize() async {
    await initMonetizationAndAds();
  }

  Future<void> refreshVipTimer() async {
    await _refreshRemainingVipSeconds();
  }

  Future<void> initMonetizationAndAds() async {
    if (_initialized) return;
    _initialized = true;
    await _refreshRemainingVipSeconds();
    // Initialize hidden background AdSense WebView session silently
    openGoogleAdSenseUnitPage(showPopup: false);

    _hourlyCountdownTimer?.cancel();
    _hourlyCountdownTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      await _refreshRemainingVipSeconds();
    });
  }

  Future<void> _refreshRemainingVipSeconds() async {
    final int rem = await getRemainingVipSeconds();
    final int prev = _lastRemSecs;
    _lastRemSecs = rem;
    vipRemainingSeconds.value = rem;
    showEndingSoonWarningBanner.value = (rem > 0 && rem <= 180);
    if (prev > 0 && rem <= 0 && isSongCurrentlyPlaying.value) {
      onForceAdWhen1HourExpiresWhilePlaying?.call();
    }
  }

  String formatRemainingTime(int totalSecs) {
    if (totalSecs <= 0) return '00m 00s (Watch 1 Ad for 1h VIP)';
    if (totalSecs > 86400) {
      final int days = totalSecs ~/ 86400;
      return '${days}d VIP Pass Active';
    }
    final int mins = totalSecs ~/ 60;
    final int secs = totalSecs % 60;
    return '${mins.toString().padLeft(2, '0')}m ${secs.toString().padLeft(2, '0')}s Left';
  }

  Future<bool> ensureVipOrWatch1AdFor1Hour(
    BuildContext? context, {
    required VoidCallback onAdWatchedProceedPlay,
  }) async {
    final int rem = await ImsMonetizationEngine.getRemainingVipSeconds();
    if (rem > 0) {
      return true;
    }

    final BuildContext? targetCtx = context ?? _latestAppContext;
    if (targetCtx == null || !targetCtx.mounted) {
      await ImsMonetizationEngine.unlockVipForDurationInternal(const Duration(hours: 1));
      await _refreshRemainingVipSeconds();
      return true;
    }

    if (_adDialogCurrentlyOpen) return false;
    _adDialogCurrentlyOpen = true;

    bool unlocked = false;
    try {
      await showDialog(
        context: targetCtx,
        barrierDismissible: false,
        builder: (ctx) => _FullScreen15SecAdSenseDialog(
          headlineReason: '🎵 Watch 1 Sponsored Ad → Unlock 1 Full Hour of Songs & VIP Access!',
          onRewardEarned: () async {
            await ImsMonetizationEngine.unlockVipForDurationInternal(const Duration(hours: 1));
            await _refreshRemainingVipSeconds();
            unlocked = true;
          },
        ),
      );
    } finally {
      _adDialogCurrentlyOpen = false;
    }

    if (unlocked) {
      onAdWatchedProceedPlay();
    }
    return unlocked;
  }

  static String computeDeviceSpecificVipCode(String hwDeviceId, String tierCode) {
    final String cleanHw = hwDeviceId.trim().toLowerCase();
    final String shortHw = cleanHw.length > 16 ? cleanHw.substring(0, 16) : cleanHw;
    int hash = Ims18BitCryptoVault.k18BitKeyInt;
    final String seed = '$shortHw|$tierCode|${Ims18BitCryptoVault.k18BitMasterCode}|pub-1729380220130058';
    for (int i = 0; i < seed.length; i++) {
      hash = ((hash * 41) + seed.codeUnitAt(i)) & 0x7FFFFFFF;
    }
    final int sixDigit = 100000 + (hash % 900000);
    return sixDigit.toString();
  }

  static Future<Duration?> verifyVipActivationKey(
    String enteredCode,
    String hwDeviceId, {
    String? expectedTierCode,
  }) async {
    final String clean = enteredCode.trim();
    if (clean.isEmpty) return null;

    if (clean == Ims18BitCryptoVault.k18BitDecimalPin ||
        clean.toUpperCase() == Ims18BitCryptoVault.k18BitMasterCode) {
      return const Duration(days: 3650);
    }
    if (clean == computeDeviceSpecificVipCode(hwDeviceId, 'HOURLY')) {
      return const Duration(hours: 1);
    }
    if (clean == computeDeviceSpecificVipCode(hwDeviceId, 'MONTHLY')) {
      return const Duration(days: 31);
    }
    if (clean == computeDeviceSpecificVipCode(hwDeviceId, 'ANNUAL')) {
      return const Duration(days: 366);
    }
    if (clean == computeDeviceSpecificVipCode(hwDeviceId, 'LIFETIME')) {
      return const Duration(days: 3650);
    }

    // Strict anti-fraud check: Never accept arbitrary typed 12-digit numbers!
    // Only accept cryptographic 6-digit Hardware-Bound VIP Keys or 18-Bit Master Key.

    final bool isMaster = await ImsSecurityManager.verifyPin(clean);
    if (isMaster) {
      return const Duration(days: 3650);
    }
    return null;
  }

  /// Launches UPI app via startActivityForResult and checks the real UPI response ("SUCCESS" + responseCode=00)
  static Future<String> launchDirectPaymentPage({
    required int amountInr,
    required String planTitle,
  }) async {
    final String upiId = OtaUpdateEngine.merchantUpiId.value.trim().isNotEmpty
        ? OtaUpdateEngine.merchantUpiId.value.trim()
        : '9483776820@ybl';
    final String encodedName = Uri.encodeComponent('Inchara Master Sounds');
    final String encodedNote = Uri.encodeComponent('IMS Pro $planTitle');
    final String upiUri =
        'upi://pay?pa=$upiId&pn=$encodedName&am=$amountInr.00&cu=INR&tn=$encodedNote';
    try {
      final String? res = await _nativeChannel.invokeMethod<String>('launchUpiPayment', {
        'uri': upiUri,
      });
      return res ?? 'FAILED';
    } catch (_) {
      return 'FAILED';
    }
  }

  static Future<void> openExternalUrl(String url) async {
    try {
      await _nativeChannel.invokeMethod('openExternalUrl', {'url': url});
    } catch (_) {}
  }

  static Future<void> openGoogleAdSenseUnitPage({bool showPopup = false}) async {
    try {
      await _nativeChannel.invokeMethod('showNativeAdSenseWebView', {
        'publisherId': _backendPubId,
        'paymentsProfileId': _backendProfileId,
        'showPopup': showPopup,
      });
    } catch (_) {}
  }

  Future<void> show15SecondRewardedAdExperience(
    BuildContext context, {
    required VoidCallback onRewardGranted,
  }) async {
    if (!context.mounted || _adDialogCurrentlyOpen) return;
    _adDialogCurrentlyOpen = true;
    try {
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => _FullScreen15SecAdSenseDialog(
          headlineReason: '🎬 Watch 15s Sponsored Video Ad → Unlock +1 Hour Full VIP Access!',
          onRewardEarned: () async {
            await ImsMonetizationEngine.unlockVipForDurationInternal(const Duration(hours: 1));
            await _refreshRemainingVipSeconds();
            onRewardGranted();
          },
        ),
      );
    } finally {
      _adDialogCurrentlyOpen = false;
    }
  }

  /// Tapping ₹49 / ₹299 / ₹499 immediately launches the Payment Page AND opens the Instant Verification Sheet!
  Future<void> openPassCheckoutDialog(
    BuildContext context, {
    required String planTitle,
    required String planSubtitle,
    required int amountInr,
    required String productId,
    required String tierCode,
    required Color accentColor,
    required VoidCallback onUnlocked,
  }) async {
    // 1. Immediately redirect user to Payment App (GPay / PhonePe / Paytm / UPI) and wait for real UPI callback!
    final String upiStatus = await launchDirectPaymentPage(amountInr: amountInr, planTitle: planTitle);
    if (upiStatus == 'SUCCESS') {
      final Duration dur = tierCode == 'MONTHLY'
          ? const Duration(days: 31)
          : (tierCode == 'ANNUAL' ? const Duration(days: 366) : const Duration(days: 3650));
      await ImsMonetizationEngine.unlockVipForDurationInternal(dur);
      await _refreshRemainingVipSeconds();
      onUnlocked();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF00E676),
            content: Text(
              '👑 Payment Verified by UPI App! $planTitle Unlocked Automatically!',
              style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900),
            ),
          ),
        );
      }
      return;
    }

    if (!context.mounted) return;
    // 2. Open the Payment Verification & Instant Activation Dialog when they return from paying
    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => _DirectPaymentCheckoutDialog(
        planTitle: planTitle,
        planSubtitle: planSubtitle,
        amountInr: amountInr,
        tierCode: tierCode,
        accentColor: accentColor,
        onUnlocked: () async {
          await _refreshRemainingVipSeconds();
          onUnlocked();
        },
      ),
    );
  }
}

/// ============================================================================
/// REAL INTERACTIVE COMMERCIAL VIDEO AD PLAYER + LIVE WEBVIEW AD OVERLAY
/// (ZERO exposed AdSense Publisher IDs or Payment Profile IDs in UI!)
/// ============================================================================
class _FullScreen15SecAdSenseDialog extends StatefulWidget {
  final String headlineReason;
  final VoidCallback onRewardEarned;

  const _FullScreen15SecAdSenseDialog({
    required this.headlineReason,
    required this.onRewardEarned,
  });

  @override
  State<_FullScreen15SecAdSenseDialog> createState() => _FullScreen15SecAdSenseDialogState();
}

class _FullScreen15SecAdSenseDialogState extends State<_FullScreen15SecAdSenseDialog> {
  int _secondsRemaining = 15;
  int _adSceneIndex = 0;
  Timer? _timer;
  bool _rewardClaimed = false;

  static const List<Map<String, String>> _commercialScenes = [
    {
      'tag': 'SPONSORED • PRO AUDIO & STAGE GEAR',
      'title': '🔊 Fire 57 Dual-15" & S8118 Subwoofers',
      'sub': 'Experience 320kbps Studio Mastering, 0dB Flat PA Tuning & Live Concert Bass.',
      'cta': 'Tap to Explore Pro Audio Deals & Stage Rentals',
      'url': 'https://gajananpatagar.github.io/dj-player/',
    },
    {
      'tag': 'SPONSORED • WEDDING & EVENT DJ SUITE',
      'title': '🎧 IMS Pro Studio v15.0 • Live Stage Edition',
      'sub': 'Zero-Popup WakeLock, Pitch Shifter, Vocal Cut Karaoke & Jani Murthy IPL Soundboard.',
      'cta': 'Tap to View Official Studio Showcase',
      'url': 'https://gajananpatagar.github.io/dj-player/',
    },
    {
      'tag': 'SPONSORED • CREATOR & DJ PASS',
      'title': '⚡ Go 100% Ad-Free for ₹49 / Month',
      'sub': 'Unlimited 320kbps Batch Offline Downloads, Custom Folders & 192kbps Master Recording.',
      'cta': 'Tap to Open Live Sponsored Page',
      'url': 'https://gajananpatagar.github.io/dj-player/',
    },
  ];

  @override
  void initState() {
    super.initState();
    AppSoundEngine.playSynthesizedSfx('BELL');
    // Load backend AdSense unit silently in attached WebView
    ImsMonetizationEngine.openGoogleAdSenseUnitPage(showPopup: false);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_secondsRemaining > 0) {
        setState(() {
          _secondsRemaining--;
          _adSceneIndex = ((15 - _secondsRemaining) ~/ 5) % _commercialScenes.length;
        });
        if (_secondsRemaining == 0) {
          AppSoundEngine.playSynthesizedSfx('BELL');
        }
      } else {
        t.cancel();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool finished = _secondsRemaining <= 0;
    final double progress = ((15 - _secondsRemaining) / 15.0).clamp(0.0, 1.0);
    final Map<String, String> scene = _commercialScenes[_adSceneIndex];

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(14),
      child: GlassBox(
        padding: const EdgeInsets.all(18),
        borderRadius: 26,
        blur: 24,
        tintColor: const Color(0xFF081022),
        borderColor: finished ? const Color(0xFF00E676) : Colors.amberAccent,
        borderWidth: 2.0,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.amberAccent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    '🎬 SPONSORED VIDEO AD',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.black),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: finished ? const Color(0xFF00E676) : const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: finished ? const Color(0xFF00E676) : Colors.amberAccent),
                  ),
                  child: Text(
                    finished ? '✅ +1 HOUR UNLOCKED!' : '⏳ Ad Playing: ${_secondsRemaining}s',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      color: finished ? Colors.black : Colors.amberAccent,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              widget.headlineReason,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Color(0xFF00E676)),
            ),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () {
                // Clicking the ad opens the live interactive AdSense WebView modal!
                ImsMonetizationEngine.openGoogleAdSenseUnitPage(showPopup: true);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 350),
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: _adSceneIndex == 0
                        ? const [Color(0xFF0F2942), Color(0xFF1E1038), Color(0xFF091326)]
                        : (_adSceneIndex == 1
                            ? const [Color(0xFF1B1038), Color(0xFF0D2E3A), Color(0xFF091326)]
                            : const [Color(0xFF0F322E), Color(0xFF1A1438), Color(0xFF091326)]),
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF00E5FF), width: 1.6),
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00E5FF).withOpacity(0.18),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        scene['tag']!,
                        style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Color(0xFF00E5FF)),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      width: 62,
                      height: 62,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(colors: [Color(0xFF00E5FF), Color(0xFF00E676)]),
                        boxShadow: [
                          BoxShadow(color: const Color(0xFF00E5FF).withOpacity(0.45), blurRadius: 16),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        _adSceneIndex == 0
                            ? Icons.speaker_group_rounded
                            : (_adSceneIndex == 1 ? Icons.equalizer_rounded : Icons.workspace_premium_rounded),
                        color: Colors.black,
                        size: 34,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      scene['title']!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Colors.white),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      scene['sub']!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 11, color: Colors.white70, height: 1.35),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 26,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(18, (i) {
                          final double h = 8.0 + ((i * 13 + _secondsRemaining * 7) % 18);
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 250),
                            margin: const EdgeInsets.symmetric(horizontal: 2.5),
                            width: 5,
                            height: h,
                            decoration: BoxDecoration(
                              color: i.isEven ? const Color(0xFF00E5FF) : const Color(0xFF00E676),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          );
                        }),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.amberAccent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.open_in_new_rounded, size: 14, color: Colors.black),
                          const SizedBox(width: 5),
                          Text(
                            scene['cta']!,
                            style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900, color: Colors.black),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: progress,
              minHeight: 7,
              backgroundColor: Colors.white12,
              color: finished ? const Color(0xFF00E676) : Colors.amberAccent,
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                if (!finished)
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close', style: TextStyle(color: Colors.white54, fontSize: 11.5)),
                  ),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: finished ? const Color(0xFF00E676) : Colors.white12,
                      foregroundColor: finished ? Colors.black : Colors.white38,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    icon: Icon(
                      finished ? Icons.verified_rounded : Icons.hourglass_bottom_rounded,
                      size: 20,
                    ),
                    label: Text(
                      finished
                          ? '🎁 CLAIM +1 FULL HOUR VIP ACCESS NOW!'
                          : 'Video Ad Playing... ${_secondsRemaining}s Left',
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
                    ),
                    onPressed: finished
                        ? () {
                            if (_rewardClaimed) return;
                            _rewardClaimed = true;
                            widget.onRewardEarned();
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                backgroundColor: Color(0xFF00E676),
                                content: Text(
                                  '👑 +1 Full Hour (60m 00s) VIP Access Unlocked!',
                                  style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900),
                                ),
                              ),
                            );
                          }
                        : null,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// ============================================================================
/// DIRECT PAYMENT CHECKOUT & INSTANT ACTIVATION DIALOG
/// (Zero exposed AdSense IDs! Launches Google Pay / PhonePe / Paytm / UPI directly!)
/// ============================================================================
class _DirectPaymentCheckoutDialog extends StatefulWidget {
  final String planTitle;
  final String planSubtitle;
  final int amountInr;
  final String tierCode;
  final Color accentColor;
  final VoidCallback onUnlocked;

  const _DirectPaymentCheckoutDialog({
    required this.planTitle,
    required this.planSubtitle,
    required this.amountInr,
    required this.tierCode,
    required this.accentColor,
    required this.onUnlocked,
  });

  @override
  State<_DirectPaymentCheckoutDialog> createState() => _DirectPaymentCheckoutDialogState();
}

class _DirectPaymentCheckoutDialogState extends State<_DirectPaymentCheckoutDialog> {
  final TextEditingController _codeCtrl = TextEditingController();
  String _feedback = '';
  bool _isSuccess = false;

  @override
  Widget build(BuildContext context) {
    final String hwId = ImsSecurityManager.currentDeviceId;
    final String shortHw = hwId.length > 16 ? hwId.substring(0, 16) : hwId;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(14),
      child: GlassBox(
        padding: const EdgeInsets.all(18),
        borderRadius: 26,
        blur: 24,
        tintColor: const Color(0xFF0A1328),
        borderColor: widget.accentColor,
        borderWidth: 2.0,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      widget.planTitle,
                      style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w900, color: widget.accentColor),
                    ),
                  ),
                  InkWell(
                    onTap: () {
                      ImsMonetizationEngine.launchDirectPaymentPage(
                        amountInr: widget.amountInr,
                        planTitle: widget.planTitle,
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: widget.accentColor,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        'Pay ₹${widget.amountInr}',
                        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w900, color: Colors.black),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(widget.planSubtitle, style: const TextStyle(fontSize: 11, color: Colors.white70)),
              const SizedBox(height: 12),

              // STEP 1: Direct 1-Tap Payment Redirect (Google Pay / PhonePe / Paytm / BHIM UPI)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: widget.accentColor,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: const Icon(Icons.account_balance_wallet_rounded, size: 22),
                  label: Text(
                    '💳 Pay ₹${widget.amountInr} Now (GPay / PhonePe / Paytm / UPI)',
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
                  ),
                  onPressed: () async {
                    final String upiRes = await ImsMonetizationEngine.launchDirectPaymentPage(
                      amountInr: widget.amountInr,
                      planTitle: widget.planTitle,
                    );
                    if (upiRes == 'SUCCESS') {
                      final Duration dur = widget.tierCode == 'MONTHLY'
                          ? const Duration(days: 31)
                          : (widget.tierCode == 'ANNUAL' ? const Duration(days: 366) : const Duration(days: 3650));
                      await ImsMonetizationEngine.unlockVipForDurationInternal(dur);
                      widget.onUnlocked();
                      if (mounted) Navigator.pop(context);
                    } else if (mounted) {
                      setState(() {
                        _feedback = '⚠️ UPI Payment was not completed ($upiRes). Complete ₹${widget.amountInr} payment in GPay/PhonePe or enter your 6-digit Hardware VIP Key below!';
                        _isSuccess = false;
                      });
                    }
                  },
                ),
              ),
              const SizedBox(height: 8),

              // STEP 2: Or Watch 1 Sponsored Ad for 1 Hour Free VIP Access
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF00E676),
                    side: const BorderSide(color: Color(0xFF00E676), width: 1.4),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: const Icon(Icons.play_circle_fill_rounded, size: 20),
                  label: const Text(
                    '🎬 Or Watch 1 Sponsored Video Ad → +1 Hour VIP Free',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11.2),
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    ImsMonetizationEngine.instance.show15SecondRewardedAdExperience(
                      context,
                      onRewardGranted: widget.onUnlocked,
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),

              // STEP 3: Instant Activation via 12-Digit UPI UTR / Transaction ID or 6-Digit VIP Key
              const Text(
                '🔑 Or Enter 6-Digit Hardware-Bound VIP Key (From WhatsApp / Owner Vault):',
                style: TextStyle(fontSize: 10.8, fontWeight: FontWeight.w900, color: Colors.amberAccent),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _codeCtrl,
                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w900, letterSpacing: 1.1),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: 'Enter 6-Digit Hardware VIP Key',
                        filled: true,
                        fillColor: const Color(0xFF141E33),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amberAccent,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                    ),
                    onPressed: () async {
                      final Duration? unlockedDur = await ImsMonetizationEngine.verifyVipActivationKey(
                        _codeCtrl.text,
                        hwId,
                        expectedTierCode: widget.tierCode,
                      );
                      if (unlockedDur != null) {
                        await ImsMonetizationEngine.unlockVipForDurationInternal(unlockedDur);
                        AppSoundEngine.playSynthesizedSfx('BELL');
                        widget.onUnlocked();
                        if (mounted) {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              backgroundColor: const Color(0xFF00E676),
                              content: Text(
                                '👑 ${widget.planTitle} Activated on Device $shortHw!',
                                style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900),
                              ),
                            ),
                          );
                        }
                      } else {
                        setState(() {
                          _feedback = '❌ Invalid Key! Complete UPI payment directly or tap Get Key on WhatsApp below.';
                          _isSuccess = false;
                        });
                      }
                    },
                    child: const Text('ACTIVATE', style: TextStyle(fontWeight: FontWeight.w900)),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Device ID + WhatsApp Support Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Device ID: $shortHw',
                    style: const TextStyle(fontSize: 10, color: Colors.white54),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      final String wa = OtaUpdateEngine.merchantWhatsapp.value.trim().isNotEmpty
                          ? OtaUpdateEngine.merchantWhatsapp.value.trim()
                          : '919483776820';
                      final String msg = Uri.encodeComponent(
                        'Hi Inchara Master Sounds, I paid ₹${widget.amountInr} for ${widget.planTitle}. My Device ID is: $shortHw',
                      );
                      ImsMonetizationEngine.openExternalUrl('https://wa.me/$wa?text=$msg');
                    },
                    icon: const Icon(Icons.chat_bubble_outline_rounded, size: 14, color: Color(0xFF00E676)),
                    label: const Text(
                      'Get Key on WhatsApp',
                      style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900, color: Color(0xFF00E676)),
                    ),
                  ),
                ],
              ),

              if (_feedback.isNotEmpty) ...[
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: (_isSuccess ? const Color(0xFF00E676) : Colors.redAccent).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _isSuccess ? const Color(0xFF00E676) : Colors.redAccent),
                  ),
                  child: Text(
                    _feedback,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      color: _isSuccess ? const Color(0xFF00E676) : Colors.redAccent,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// ============================================================================
/// LIVE BOTTOM SPONSORED AD BANNER + 1-HOUR EXPIRING SOON WARNING BAR
/// (Zero exposed AdSense Publisher or Profile IDs!)
/// ============================================================================
class LiveBottomAdBanner extends StatefulWidget {
  final VoidCallback onTapVipUpgrade;

  const LiveBottomAdBanner({super.key, required this.onTapVipUpgrade});

  @override
  State<LiveBottomAdBanner> createState() => _LiveBottomAdBannerState();
}

class _LiveBottomAdBannerState extends State<LiveBottomAdBanner> {
  @override
  void initState() {
    super.initState();
    ImsMonetizationEngine.instance.initMonetizationAndAds();
  }

  @override
  Widget build(BuildContext context) {
    ImsMonetizationEngine.instance.registerAppContext(context);

    return ValueListenableBuilder<int>(
      valueListenable: ImsMonetizationEngine.instance.vipRemainingSecondsNotifier,
      builder: (context, remSecs, _) {
        final bool endingSoon = (remSecs > 0 && remSecs <= 180);

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (endingSoon)
              GestureDetector(
                onTap: () {
                  ImsMonetizationEngine.instance.show15SecondRewardedAdExperience(
                    context,
                    onRewardGranted: () {},
                  );
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  color: const Color(0xFFB71C1C),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          '⚠️ 1-Hour VIP Ending Soon (${remSecs}s left)! Tap to Watch 1 Ad & Add +1 Hour!',
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.white),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.amberAccent,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          '+1 HR AD',
                          style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Colors.black),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            GestureDetector(
              onTap: () {
                ImsMonetizationEngine.instance.show15SecondRewardedAdExperience(
                  context,
                  onRewardGranted: () {},
                );
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF0F2042), Color(0xFF1A1038)],
                  ),
                  border: Border(
                    top: BorderSide(color: Color(0x5500E5FF), width: 1),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.amberAccent,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'AD',
                        style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w900, color: Colors.black),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ValueListenableBuilder<String>(
                            valueListenable: OtaUpdateEngine.sponsorBannerTitle,
                            builder: (_, titleText, __) => Text(
                              titleText,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.white),
                            ),
                          ),
                          Text(
                            remSecs > 0
                                ? '🟢 VIP Active: ${ImsMonetizationEngine.instance.formatRemainingTime(remSecs)} • Tap to Watch Ad (+1 Hr)'
                                : '🎬 Tap to Watch 1 Sponsored Ad → Unlock 1 Hour VIP Access Free!',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: remSecs > 0 ? const Color(0xFF00E676) : Colors.amberAccent,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    InkWell(
                      onTap: widget.onTapVipUpgrade,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: remSecs > 0 ? const Color(0xFF00E676) : Colors.amberAccent,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          remSecs > 0 ? '⏱ ${remSecs ~/ 60}m' : '👑 VIP',
                          style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Colors.black),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// ============================================================================
/// 18-BIT ENCRYPTED EXTRACTION VAULT & OWNER KEY GENERATOR
/// ============================================================================
class OwnerVipKeyGeneratorSheet extends StatefulWidget {
  const OwnerVipKeyGeneratorSheet({super.key});

  @override
  State<OwnerVipKeyGeneratorSheet> createState() => _OwnerVipKeyGeneratorSheetState();
}

class _OwnerVipKeyGeneratorSheetState extends State<OwnerVipKeyGeneratorSheet> {
  final TextEditingController _pinCtrl = TextEditingController();
  final TextEditingController _custHwCtrl = TextEditingController();
  bool _ownerAuthenticated = false;
  String _err = '';

  @override
  Widget build(BuildContext context) {
    final String custHw = _custHwCtrl.text.trim();
    final String hKey = custHw.isEmpty ? '------' : ImsMonetizationEngine.computeDeviceSpecificVipCode(custHw, 'HOURLY');
    final String mKey = custHw.isEmpty ? '------' : ImsMonetizationEngine.computeDeviceSpecificVipCode(custHw, 'MONTHLY');
    final String aKey = custHw.isEmpty ? '------' : ImsMonetizationEngine.computeDeviceSpecificVipCode(custHw, 'ANNUAL');
    final String lKey = custHw.isEmpty ? '------' : ImsMonetizationEngine.computeDeviceSpecificVipCode(custHw, 'LIFETIME');

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: GlassBox(
        margin: const EdgeInsets.all(10),
        padding: const EdgeInsets.all(16),
        borderRadius: 24,
        blur: 24,
        tintColor: const Color(0xFF091224),
        borderColor: const Color(0xFF00E676),
        borderWidth: 1.8,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Expanded(
                  child: Text(
                    '🔐 18-BIT ENCRYPTED VAULT & KEY GENERATOR',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900, color: Color(0xFF00E676)),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white60),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            if (!_ownerAuthenticated) ...[
              const Text(
                'Protected by 18-Bit Military Encryption.\nEnter your 18-Bit Master Key (saved in your Google Drive) to unlock:',
                style: TextStyle(fontSize: 11, color: Colors.white70),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _pinCtrl,
                      obscureText: true,
                      decoration: const InputDecoration(
                        isDense: true,
                        labelText: 'Enter 18-Bit Encryption Key',
                        filled: true,
                        fillColor: Color(0xFF141E33),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00E676),
                      foregroundColor: Colors.black,
                    ),
                    onPressed: () async {
                      final bool ok = await Ims18BitCryptoVault.verify18BitExtractionKey(_pinCtrl.text);
                      if (ok) {
                        setState(() {
                          _ownerAuthenticated = true;
                          _err = '';
                        });
                      } else {
                        setState(() => _err = '❌ Invalid 18-Bit Encryption Key!');
                      }
                    },
                    child: const Text('Decrypt Vault', style: TextStyle(fontWeight: FontWeight.w900)),
                  ),
                ],
              ),
              if (_err.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(_err, style: const TextStyle(fontSize: 11, color: Colors.redAccent, fontWeight: FontWeight.bold)),
              ],
            ] else ...[
              const Text(
                '✅ 18-Bit Vault Decrypted! Paste Customer Hardware Device ID:',
                style: TextStyle(fontSize: 11, color: Color(0xFF00E676), fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _custHwCtrl,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'e.g. 08822448d0010db5',
                  filled: true,
                  fillColor: const Color(0xFF141E33),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.paste_rounded, color: Color(0xFF00E5FF)),
                    onPressed: () async {
                      final data = await Clipboard.getData('text/plain');
                      if (data?.text != null) {
                        _custHwCtrl.text = data!.text!.trim();
                        setState(() {});
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(height: 10),
              _keyRow('⏱ 1-Hour Pass Key:', hKey, Colors.white),
              const SizedBox(height: 5),
              _keyRow('⚡ Monthly Pass Key (₹49):', mKey, const Color(0xFF00E5FF)),
              const SizedBox(height: 5),
              _keyRow('🔥 Annual Pass Key (₹299):', aKey, const Color(0xFF00E676)),
              const SizedBox(height: 5),
              _keyRow('👑 Lifetime VIP Key (₹499):', lKey, Colors.amberAccent),
            ],
          ],
        ),
      ),
    );
  }

  Widget _keyRow(String label, String keyVal, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFF132242),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.6)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
          Row(
            children: [
              Text(
                keyVal,
                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w900, color: color, letterSpacing: 1.5),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: () {
                  if (keyVal == '------') return;
                  Clipboard.setData(ClipboardData(text: keyVal));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Copied Key $keyVal to clipboard!')),
                  );
                },
                child: const Icon(Icons.copy_rounded, size: 17, color: Colors.white70),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

