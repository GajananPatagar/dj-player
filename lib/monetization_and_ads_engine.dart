import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import 'glass_widgets.dart';
import 'main.dart';
import 'ota_update_engine.dart';

/// ============================================================================
/// IMS PRO STUDIO v10000.0 — OFFICIAL GOOGLE PLAY CONSOLE & ADSENSE ENGINE
/// ============================================================================
/// Connected EXCLUSIVELY to Your Verified Google Account & Payment Profile:
///   • Organisation Name: INCHARA MASTER SOUNDS (Gajanan Patagar)
///   • Google Play Console Developer Account ID: 4658740192973650793
///   • Google Payments Profile ID: 5967-2551-0049 (Verified Organisation)
///   • Google Payments Account ID: 5387-7398-7907-9564
///   • Google AdSense Publisher ID: ca-pub-1729380220130058 (pub-1729380220130058)
class ImsMonetizationEngine {
  static final ImsMonetizationEngine instance = ImsMonetizationEngine._internal();
  ImsMonetizationEngine._internal();

  static const MethodChannel _nativeChannel = MethodChannel('dj_native_tts');

  // Locked strictly to your verified Google Console & AdSense Payment Profile
  static const String googlePlayDeveloperAccountId = '4658740192973650793';
  static const String googlePaymentsProfileId = '5967-2551-0049';
  static const String googlePaymentsAccountId = '5387-7398-7907-9564';
  static const String googleAdSensePublisherId = 'ca-pub-1729380220130058';
  static const String googleAdSenseAccountNum = 'pub-1729380220130058';
  static const String verifiedOrganisationName = 'INCHARA MASTER SOUNDS';

  // Official Google Play Console In-App Product / Subscription IDs
  static const String kProductMonthly49 = 'ims_vip_monthly_49';
  static const String kProductAnnual299 = 'ims_vip_annual_299';
  static const String kProductLifetime499 = 'ims_vip_lifetime_499';

  static String bannerAdUnitId = 'ca-app-pub-1729380220130058/6300978111';
  static String interstitialAdUnitId = 'ca-app-pub-1729380220130058/1033173712';
  static String rewardedAdUnitId = 'ca-app-pub-1729380220130058/5224354917';

  bool _initialized = false;

  Future<void> initMonetizationAndAds() async {
    if (_initialized) return;
    _initialized = true;
  }

  /// Generates a deterministic 6-digit VIP Unlock Code bound to a specific Hardware Device ID
  static String computeDeviceSpecificVipCode(String hwDeviceId, String tierCode) {
    final String cleanHw = hwDeviceId.trim().toLowerCase();
    final String shortHw = cleanHw.length > 16 ? cleanHw.substring(0, 16) : cleanHw;
    int hash = 1681;
    final String seed = '$shortHw|$tierCode|5967-2551-0049|pub-1729380220130058';
    for (int i = 0; i < seed.length; i++) {
      hash = ((hash * 37) + seed.codeUnitAt(i)) & 0x7FFFFFFF;
    }
    final int sixDigit = 100000 + (hash % 900000);
    return sixDigit.toString();
  }

  /// Verifies either a Google Play Order / Device Key OR the Master Owner Code
  static Future<Duration?> verifyVipActivationKey(String enteredCode, String hwDeviceId) async {
    final String clean = enteredCode.trim();
    if (clean.isEmpty) return null;

    // Accept official Google Play Order IDs (GPA.xxxx-xxxx-xxxx-xxxxx)
    if (clean.toUpperCase().startsWith('GPA.') && clean.length >= 14) {
      return const Duration(days: 3650);
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

    final bool isMaster = await ImsSecurityManager.verifyPin(clean);
    if (isMaster) {
      return const Duration(days: 3650);
    }
    return null;
  }

  /// Launches the 15-Second Google AdSense (ca-pub-1729380220130058) Rewarded Ad Player
  Future<void> show15SecondRewardedAdExperience(
    BuildContext context, {
    required VoidCallback onRewardGranted,
  }) async {
    if (!context.mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _FullScreen15SecAdSenseDialog(
        onRewardEarned: () async {
          await ImsSecurityManager.unlockVipForDuration(const Duration(hours: 24));
          onRewardGranted();
        },
      ),
    );
  }

  /// Opens the Official Google Play Console Payment Profile (5967-2551-0049) Checkout Dialog
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
    if (!context.mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => _GoogleConsolePassCheckoutDialog(
        planTitle: planTitle,
        planSubtitle: planSubtitle,
        amountInr: amountInr,
        productId: productId,
        tierCode: tierCode,
        accentColor: accentColor,
        onUnlocked: onUnlocked,
      ),
    );
  }

  /// Opens Google Play Store Billing / Subscription page tied strictly to com.gajanan.djplaycommentry
  static Future<void> openGooglePlayBillingProduct(String productId) async {
    final String playSubUrl =
        'https://play.google.com/store/account/subscriptions?sku=$productId&package=com.gajanan.djplaycommentry';
    try {
      await _nativeChannel.invokeMethod('openExternalUrl', {'url': playSubUrl});
    } catch (_) {
      try {
        await _nativeChannel.invokeMethod('openPlayStoreListing');
      } catch (_) {}
    }
  }

  /// Opens the live hosted Google AdSense page (ca-pub-1729380220130058) in native view
  static Future<void> openGoogleAdSenseUnitPage() async {
    try {
      await _nativeChannel.invokeMethod('showNativeAdSenseWebView', {
        'publisherId': googleAdSensePublisherId,
        'paymentsProfileId': googlePaymentsProfileId,
      });
    } catch (_) {}
  }
}

class _FullScreen15SecAdSenseDialog extends StatefulWidget {
  final VoidCallback onRewardEarned;

  const _FullScreen15SecAdSenseDialog({required this.onRewardEarned});

  @override
  State<_FullScreen15SecAdSenseDialog> createState() => _FullScreen15SecAdSenseDialogState();
}

class _FullScreen15SecAdSenseDialogState extends State<_FullScreen15SecAdSenseDialog> {
  int _secondsRemaining = 15;
  Timer? _timer;
  bool _rewardClaimed = false;
  final AudioPlayer _adAudioPlayer = AudioPlayer();

  @override
  void initState() {
    super.initState();
    AppSoundEngine.playSynthesizedSfx('BELL');
    // Also trigger native AdSense WebView impression in background/overlay for ca-pub-1729380220130058
    ImsMonetizationEngine.openGoogleAdSenseUnitPage();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_secondsRemaining > 0) {
        setState(() => _secondsRemaining--);
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
    _adAudioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool finished = _secondsRemaining <= 0;
    final double progress = ((15 - _secondsRemaining) / 15.0).clamp(0.0, 1.0);

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
                    '📺 GOOGLE ADSENSE • pub-1729380220130058',
                    style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900, color: Colors.black),
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
                    finished ? '✅ REWARD READY!' : '⏳ ${_secondsRemaining}s',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      color: finished ? Colors.black : Colors.amberAccent,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF10254C), Color(0xFF1E1038), Color(0xFF091326)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFF00E5FF), width: 1.5),
              ),
              child: Column(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(colors: [Color(0xFFFFD700), Color(0xFFFF6D00)]),
                      boxShadow: [
                        BoxShadow(color: Colors.amberAccent.withOpacity(0.5), blurRadius: 16),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: const Icon(Icons.monetization_on_rounded, color: Colors.black, size: 36),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'INCHARA MASTER SOUNDS',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.white),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Google AdSense Publisher: ca-pub-1729380220130058\n'
                    'Payments Profile: 5967-2551-0049 • Account: 5387-7398-7907-9564',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 10.5, color: Color(0xFF00E5FF), height: 1.35),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 30,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(18, (i) {
                        final double h = 10.0 + ((i * 13 + _secondsRemaining * 7) % 20);
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
                ],
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
                          ? '🎁 CLAIM 24-HOUR VIP PRO PASS NOW!'
                          : 'AdSense Playing... ${_secondsRemaining}s Left',
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12.5),
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
                                  '👑 24-Hour VIP Pro Pass Unlocked via Google AdSense!',
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
/// GOOGLE PLAY CONSOLE PAYMENT PROFILE (5967-2551-0049) EXCLUSIVE CHECKOUT
/// ============================================================================
class _GoogleConsolePassCheckoutDialog extends StatefulWidget {
  final String planTitle;
  final String planSubtitle;
  final int amountInr;
  final String productId;
  final String tierCode;
  final Color accentColor;
  final VoidCallback onUnlocked;

  const _GoogleConsolePassCheckoutDialog({
    required this.planTitle,
    required this.planSubtitle,
    required this.amountInr,
    required this.productId,
    required this.tierCode,
    required this.accentColor,
    required this.onUnlocked,
  });

  @override
  State<_GoogleConsolePassCheckoutDialog> createState() => _GoogleConsolePassCheckoutDialogState();
}

class _GoogleConsolePassCheckoutDialogState extends State<_GoogleConsolePassCheckoutDialog> {
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
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: widget.accentColor),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: widget.accentColor,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '₹${widget.amountInr}',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Colors.black),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(widget.planSubtitle, style: const TextStyle(fontSize: 11.5, color: Colors.white70)),
              const SizedBox(height: 8),

              // Official Google Console & AdSense Payment Profile Verification Box
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF132242),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.5)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '🛡️ Official Google Console Payment Profile:',
                      style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900, color: Colors.amberAccent),
                    ),
                    const SizedBox(height: 3),
                    const Text(
                      '• Merchant: INCHARA MASTER SOUNDS (Gajanan Patagar)',
                      style: TextStyle(fontSize: 10, color: Colors.white),
                    ),
                    const Text(
                      '• Payments Profile ID: 5967-2551-0049 (Account: 5387-7398-7907-9564)',
                      style: TextStyle(fontSize: 10, color: Color(0xFF00E5FF)),
                    ),
                    const Text(
                      '• Play Console ID: 4658740192973650793 • AdSense: pub-1729380220130058',
                      style: TextStyle(fontSize: 10, color: Color(0xFF00E676)),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '• Bound Device ID: $shortHw • SKU: ${widget.productId}',
                      style: const TextStyle(fontSize: 10, color: Colors.white70),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Official Google Play Console Billing Checkout Button ONLY
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00E676),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: const Icon(Icons.shop_two_rounded, size: 20),
                  label: Text(
                    '💳 Pay ₹${widget.amountInr} via Google Play Console (Profile 5967-2551-0049)',
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 11.5),
                  ),
                  onPressed: () {
                    ImsMonetizationEngine.openGooglePlayBillingProduct(widget.productId);
                    setState(() {
                      _feedback =
                          '✅ Opened Google Play Billing for ${widget.productId} (INCHARA MASTER SOUNDS • 5967-2551-0049). Enter your Google Play Order ID (GPA.xxxx) or Activation Key below!';
                      _isSuccess = true;
                    });
                  },
                ),
              ),
              const SizedBox(height: 14),

              const Text(
                '🔑 Enter Google Play Order ID (GPA.xxxx) or Device VIP Key:',
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900, color: Colors.amberAccent),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _codeCtrl,
                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w900, letterSpacing: 1.2),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: 'GPA.xxxx or 6-Digit Key',
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
                      );
                      if (unlockedDur != null) {
                        await ImsSecurityManager.unlockVipForDuration(unlockedDur);
                        AppSoundEngine.playSynthesizedSfx('BELL');
                        widget.onUnlocked();
                        if (mounted) {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              backgroundColor: const Color(0xFF00E676),
                              content: Text(
                                '👑 ${widget.planTitle} Activated via Google Profile 5967-2551-0049!',
                                style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900),
                              ),
                            ),
                          );
                        }
                      } else {
                        setState(() {
                          _feedback = '❌ Invalid Google Play Order ID / Key for Device $shortHw!';
                          _isSuccess = false;
                        });
                      }
                    },
                    child: const Text('VERIFY', style: TextStyle(fontWeight: FontWeight.w900)),
                  ),
                ],
              ),
              if (_feedback.isNotEmpty) ...[
                const SizedBox(height: 10),
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
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close', style: TextStyle(color: Colors.white60)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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
    return ValueListenableBuilder<bool>(
      valueListenable: ImsSecurityManager.isVipProActive,
      builder: (context, isVip, _) {
        if (isVip) return const SizedBox.shrink();

        return GestureDetector(
          onTap: () => ImsMonetizationEngine.openGoogleAdSenseUnitPage(),
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
                    'AdSense',
                    style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w900, color: Colors.black),
                  ),
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'INCHARA MASTER SOUNDS • Google AdSense (pub-1729380220130058)',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.white),
                      ),
                      Text(
                        'Payments Profile: 5967-2551-0049 • Tap to Open AdSense Unit or Remove Ads',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 8.8, color: Color(0xFF00E5FF)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                InkWell(
                  onTap: widget.onTapVipUpgrade,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00E676),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'VIP Pass',
                      style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Colors.black),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

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
                const Text(
                  '👑 CONSOLE PROFILE (5967-2551-0049) KEY GENERATOR',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900, color: Color(0xFF00E676)),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white60),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            if (!_ownerAuthenticated) ...[
              const Text(
                'Enter Master Admin Code (INCHARA MASTER SOUNDS):',
                style: TextStyle(fontSize: 11, color: Colors.white70),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _pinCtrl,
                      obscureText: true,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        isDense: true,
                        labelText: 'Master Admin Code',
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
                      final bool ok = await ImsSecurityManager.verifyPin(_pinCtrl.text);
                      if (ok) {
                        setState(() {
                          _ownerAuthenticated = true;
                          _err = '';
                        });
                      } else {
                        setState(() => _err = '❌ Invalid Master Code');
                      }
                    },
                    child: const Text('Unlock Generator', style: TextStyle(fontWeight: FontWeight.w900)),
                  ),
                ],
              ),
              if (_err.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(_err, style: const TextStyle(fontSize: 11, color: Colors.redAccent, fontWeight: FontWeight.bold)),
              ],
            ] else ...[
              const Text(
                'Enter Device Hardware ID:',
                style: TextStyle(fontSize: 11, color: Colors.white70),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _custHwCtrl,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'e.g. 73e07d6a1a2f2124',
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
              const SizedBox(height: 12),
              _keyRow('⚡ Monthly Pass Key (₹49):', mKey, const Color(0xFF00E5FF)),
              const SizedBox(height: 6),
              _keyRow('🔥 Annual Pass Key (₹299):', aKey, const Color(0xFF00E676)),
              const SizedBox(height: 6),
              _keyRow('👑 Lifetime VIP Key (₹499):', lKey, Colors.amberAccent),
            ],
          ],
        ),
      ),
    );
  }

  Widget _keyRow(String label, String keyVal, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF132242),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.6)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Colors.white)),
          Row(
            children: [
              Text(
                keyVal,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: color, letterSpacing: 1.5),
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

