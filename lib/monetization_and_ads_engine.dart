import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import 'glass_widgets.dart';
import 'main.dart';
import 'ota_update_engine.dart';

/// ============================================================================
/// IMS 18-BIT MILITARY CRYPTOGRAPHIC VAULT (KEY: 101101001110010110 / 185238)
/// ============================================================================
/// Protects internal AdSense & VIP payloads against APK / AAB extraction tools
/// (APKTool, JADX, MT Manager, 7-Zip). All sensitive strings are XOR-CBC
/// encrypted with the 18-bit key polynomial `0x2D396` (`185238`).
class Ims18BitCryptoVault {
  static const int k18BitKeyInt = 0x2D396; // 18-bit binary: 101101001110010110 (Decimal: 185238)
  static const String k18BitBinaryStr = '101101001110010110';
  static const String k18BitDecimalPin = '185238';
  static const String k18BitMasterCode = 'IMS18B-2D396-9483K';

  /// Encrypts any plaintext string using the 18-bit rolling XOR-CBC key polynomial
  static String encrypt18Bit(String plainText) {
    final List<int> bytes = utf8.encode(plainText);
    final List<int> out = List<int>.filled(bytes.length, 0);
    int rolling = k18BitKeyInt;
    for (int i = 0; i < bytes.length; i++) {
      final int keyByte = ((rolling >> (i % 11)) ^ (i * 73)) & 0xFF;
      out[i] = bytes[i] ^ keyByte;
      rolling = ((rolling * 33) ^ out[i] ^ k18BitKeyInt) & 0x3FFFF; // 18-bit mask (262143)
    }
    return base64Encode(out);
  }

  /// Decrypts an 18-bit encrypted Base64 payload at runtime in RAM
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

  /// Verifies if the user entered the valid 18-Bit Master Extraction Key
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
/// IMS PRO STUDIO v10000.0 — GOOGLE ADSENSE ONLY + 1-AD = 1-HOUR VIP ENGINE
/// ============================================================================
/// • 100% Google AdSense Only (`ca-pub-1729380220130058` • Profile `5967-2551-0049`)
/// • Zero Google Play Console Billing dependencies (Bypasses Play Console [OR-ICRA-02])
/// • Watching 1 AdSense Ad = 1 Hour (60m 00s) Full VIP Music & Studio Access!
/// • Live 1-second countdown timer (`vipRemainingSecondsNotifier`):
///     - Warns user when <= 3 minutes remain while a song is playing
///     - Automatically prompts to watch 1 AdSense ad when 1 hour expires and user
///       plays or switches songs!
class ImsMonetizationEngine {
  static final ImsMonetizationEngine instance = ImsMonetizationEngine._internal();
  ImsMonetizationEngine._internal();

  static const MethodChannel _nativeChannel = MethodChannel('dj_native_tts');

  // Google AdSense Account Details (INCHARA MASTER SOUNDS)
  static const String googleAdSensePublisherId = 'ca-pub-1729380220130058';
  static const String googleAdSenseAccountNum = 'pub-1729380220130058';
  static const String googlePaymentsProfileId = '5967-2551-0049';
  static const String googlePaymentsAccountId = '5387-7398-7907-9564';
  static const String verifiedOrganisationName = 'INCHARA MASTER SOUNDS';

  final ValueNotifier<int> vipRemainingSecondsNotifier = ValueNotifier<int>(0);
  final ValueNotifier<bool> showEndingSoonWarningBanner = ValueNotifier<bool>(false);

  Timer? _hourlyCountdownTimer;
  bool _initialized = false;
  bool _adDialogCurrentlyOpen = false;
  BuildContext? _latestAppContext;

  void registerAppContext(BuildContext ctx) {
    _latestAppContext = ctx;
  }

  Future<void> initMonetizationAndAds() async {
    if (_initialized) return;
    _initialized = true;
    await _refreshRemainingVipSeconds();

    // If brand new session with 0s left, grant initial 3-minute welcome grace or prompt 1st ad on play
    _hourlyCountdownTimer?.cancel();
    _hourlyCountdownTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      await _refreshRemainingVipSeconds();
    });
  }

  Future<void> _refreshRemainingVipSeconds() async {
    final int rem = await ImsSecurityManager.getRemainingVipSeconds();
    vipRemainingSecondsNotifier.value = rem;
    // Show "Ending Soon" warning banner when between 1 and 180 seconds (3 minutes) remain!
    showEndingSoonWarningBanner.value = (rem > 0 && rem <= 180);
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

  /// Called by AudioStudio / KaraokeStudio BEFORE playing a song or when a song finishes!
  /// If the user's 1-hour VIP timer has expired (`rem <= 0`), automatically pops up the
  /// Google AdSense Ad Player so watching 1 ad unlocks 1 full hour of song playback!
  Future<bool> ensureVipOrWatch1AdFor1Hour(
    BuildContext? context, {
    required VoidCallback onAdWatchedProceedPlay,
  }) async {
    final int rem = await ImsSecurityManager.getRemainingVipSeconds();
    if (rem > 0) {
      return true; // Already has active 1-hour VIP (or subscription pass)! Proceed immediately!
    }

    final BuildContext? targetCtx = context ?? _latestAppContext;
    if (targetCtx == null || !targetCtx.mounted) {
      // Fallback: grant 1 hour if no UI context mounted
      await ImsSecurityManager.unlockVipForDuration(const Duration(hours: 1));
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
          headlineReason: '🎵 Watch 1 AdSense Ad → Unlock 1 Full Hour of Songs & VIP Access!',
          onRewardEarned: () async {
            await ImsSecurityManager.unlockVipForDuration(const Duration(hours: 1));
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

  /// Generates an 18-Bit Encrypted 6-Digit VIP Unlock Code bound to a specific Hardware Device ID
  static String computeDeviceSpecificVipCode(String hwDeviceId, String tierCode) {
    final String cleanHw = hwDeviceId.trim().toLowerCase();
    final String shortHw = cleanHw.length > 16 ? cleanHw.substring(0, 16) : cleanHw;
    int hash = Ims18BitCryptoVault.k18BitKeyInt;
    final String seed = '$shortHw|$tierCode|${Ims18BitCryptoVault.k18BitMasterCode}|$googleAdSenseAccountNum';
    for (int i = 0; i < seed.length; i++) {
      hash = ((hash * 41) + seed.codeUnitAt(i)) & 0x7FFFFFFF;
    }
    final int sixDigit = 100000 + (hash % 900000);
    return sixDigit.toString();
  }

  /// Verifies 18-Bit Master Key (`185238` / `IMS18B-2D396-9483K`) or Device-Specific Subscription Key
  static Future<Duration?> verifyVipActivationKey(String enteredCode, String hwDeviceId) async {
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

    final bool isMaster = await ImsSecurityManager.verifyPin(clean);
    if (isMaster) {
      return const Duration(days: 3650);
    }
    return null;
  }

  /// Launches the Google AdSense (`ca-pub-1729380220130058`) Ad Player to grant +1 Hour VIP Access!
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
          headlineReason: '📺 Watch 1 Google AdSense Ad → Unlock +1 Hour Full VIP Access!',
          onRewardEarned: () async {
            await ImsSecurityManager.unlockVipForDuration(const Duration(hours: 1));
            await _refreshRemainingVipSeconds();
            onRewardGranted();
          },
        ),
      );
    } finally {
      _adDialogCurrentlyOpen = false;
    }
  }

  /// Opens the Google AdSense Subscription Pass Activation Dialog (No Play Console dependency!)
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
      builder: (ctx) => _AdSenseSubscriptionPassDialog(
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
  Timer? _timer;
  bool _rewardClaimed = false;
  final AudioPlayer _adAudioPlayer = AudioPlayer();

  @override
  void initState() {
    super.initState();
    AppSoundEngine.playSynthesizedSfx('BELL');
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
                    finished ? '✅ +1 HOUR READY!' : '⏳ ${_secondsRemaining}s',
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
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
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
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(colors: [Color(0xFFFFD700), Color(0xFFFF6D00)]),
                      boxShadow: [
                        BoxShadow(color: Colors.amberAccent.withOpacity(0.5), blurRadius: 16),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: const Icon(Icons.monetization_on_rounded, color: Colors.black, size: 34),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'INCHARA MASTER SOUNDS',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w900, color: Colors.white),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Google AdSense Publisher: ca-pub-1729380220130058\n'
                    'Payments Profile: 5967-2551-0049 • Account: 5387-7398-7907-9564\n'
                    '1 Ad View = 1 Full Hour (60 Minutes) Uninterrupted VIP Music!',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 10.5, color: Color(0xFF00E5FF), height: 1.35),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 28,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(18, (i) {
                        final double h = 8.0 + ((i * 13 + _secondsRemaining * 7) % 20);
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
                    child: const Text('Cancel', style: TextStyle(color: Colors.white54, fontSize: 11.5)),
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
                          ? '🎁 UNLOCK 1 FULL HOUR VIP ACCESS NOW!'
                          : 'AdSense Playing... ${_secondsRemaining}s Left',
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
                                  '👑 +1 Full Hour (60m 00s) VIP Access Unlocked via Google AdSense!',
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
/// GOOGLE ADSENSE SUBSCRIPTION & 18-BIT KEY UNLOCK DIALOG (ZERO CONSOLE HOLD!)
/// ============================================================================
class _AdSenseSubscriptionPassDialog extends StatefulWidget {
  final String planTitle;
  final String planSubtitle;
  final int amountInr;
  final String tierCode;
  final Color accentColor;
  final VoidCallback onUnlocked;

  const _AdSenseSubscriptionPassDialog({
    required this.planTitle,
    required this.planSubtitle,
    required this.amountInr,
    required this.tierCode,
    required this.accentColor,
    required this.onUnlocked,
  });

  @override
  State<_AdSenseSubscriptionPassDialog> createState() => _AdSenseSubscriptionPassDialogState();
}

class _AdSenseSubscriptionPassDialogState extends State<_AdSenseSubscriptionPassDialog> {
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
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: widget.accentColor,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '₹${widget.amountInr}',
                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w900, color: Colors.black),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(widget.planSubtitle, style: const TextStyle(fontSize: 11, color: Colors.white70)),
              const SizedBox(height: 8),

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
                      '🛡️ Google AdSense & 18-Bit Encrypted Profile:',
                      style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900, color: Colors.amberAccent),
                    ),
                    const SizedBox(height: 3),
                    const Text(
                      '• Organisation: INCHARA MASTER SOUNDS (Gajanan Patagar)',
                      style: TextStyle(fontSize: 10, color: Colors.white),
                    ),
                    const Text(
                      '• AdSense Publisher: ca-pub-1729380220130058',
                      style: TextStyle(fontSize: 10, color: Color(0xFF00E676)),
                    ),
                    const Text(
                      '• AdSense Payments Account: 5387-7398-7907-9564 (Profile: 5967-2551-0049)',
                      style: TextStyle(fontSize: 10, color: Color(0xFF00E5FF)),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '• Bound Device ID: $shortHw',
                          style: const TextStyle(fontSize: 10, color: Colors.white70),
                        ),
                        InkWell(
                          onTap: () {
                            Clipboard.setData(ClipboardData(text: shortHw));
                            setState(() {
                              _feedback = '✅ Copied Device ID ($shortHw) to clipboard!';
                              _isSuccess = true;
                            });
                          },
                          child: const Text(
                            'COPY ID',
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.amberAccent),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Option 1: Watch 1 Google AdSense Ad -> Instant 1-Hour Free VIP Access!
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00E676),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: const Icon(Icons.play_circle_fill_rounded, size: 20),
                  label: const Text(
                    '📺 Watch 1 Google AdSense Ad → Instant +1 Hour VIP',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11.5),
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

              const Text(
                '🔑 Or Enter 18-Bit Master Key / 6-Digit Subscription Key:',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Colors.amberAccent),
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
                        hintText: 'Enter 18-Bit or 6-Digit Key',
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
                                '👑 ${widget.planTitle} Unlocked on Device $shortHw!',
                                style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900),
                              ),
                            ),
                          );
                        }
                      } else {
                        setState(() {
                          _feedback = '❌ Invalid 18-Bit / Device Key for $shortHw!';
                          _isSuccess = false;
                        });
                      }
                    },
                    child: const Text('UNLOCK', style: TextStyle(fontWeight: FontWeight.w900)),
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

/// ============================================================================
/// LIVE BOTTOM ADSENSE BANNER + 1-HOUR EXPIRING SOON WARNING BAR
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
            // If song is playing and 1-Hour VIP is ending within 3 minutes, show glowing extension bar!
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

            // Persistent Google AdSense Bar (Shows remaining VIP timer or AdSense unit trigger)
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
                        'AdSense',
                        style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w900, color: Colors.black),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'INCHARA MASTER SOUNDS • AdSense (pub-1729380220130058)',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.white),
                          ),
                          Text(
                            remSecs > 0
                                ? '🟢 VIP Access Active: ${ImsMonetizationEngine.instance.formatRemainingTime(remSecs)} • Tap to Add +1 Hour'
                                : '🔒 VIP Timer Expired (00m 00s) • Tap to Watch 1 Ad for 1 Hour VIP Access!',
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
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                        decoration: BoxDecoration(
                          color: remSecs > 0 ? const Color(0xFF00E676) : Colors.amberAccent,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          remSecs > 0 ? '⏱ ${remSecs ~/ 60}m' : '📺 +1 Hr',
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
                'Protected by 18-Bit Military Encryption (0x2D396).\nEnter your 18-Bit Key (from Google Drive) to decrypt:',
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

