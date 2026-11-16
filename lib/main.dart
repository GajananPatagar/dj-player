import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audioplayers/audioplayers.dart';
import 'audio_studio.dart';
import 'cricket_studio.dart';
import 'voice_and_pro_hub.dart';
import 'entry_music_data.dart';
import 'entry_music_studio.dart';
import 'glass_widgets.dart';
import 'karaoke_studio.dart';
import 'ota_update_engine.dart';
import 'monetization_and_ads_engine.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  AppSoundEngine.initHardwareVolumeListener();
  runApp(const DjPlayCommentaryApp());
}

class ImsSecurityManager {
  // Internal fallback seed (NEVER displayed in any UI label, hint, or dialog!)
  static const String _internalFallbackPin = '1681';
  static const String _prefUnlockedKey = 'ims_first_install_unlocked_v650';
  static const String _prefRelockTokenKey = 'ims_unlocked_relock_token_v650';
  static const String _prefCustomPinKey = 'ims_custom_pin_v650';
  static const String _prefCachedOtaPinKey = 'ims_cached_ota_pin_v650';
  static const String _prefBoundDeviceIdKey = 'ims_bound_hw_device_id_v9999';
  static const String _prefVipStatusKey = 'ims_vip_pro_active_until_ms_v9999';

  static String currentDeviceId = 'VERIFYING_HW...';
  static String installerPackage = '';
  static bool isPlayStoreInstall = false;
  static bool isTampered = false;
  static String tamperReason = 'CLEAN';
  static final ValueNotifier<bool> isVipProActive = ValueNotifier<bool>(false);

  static Future<void> evaluateNativeHardwareSecurity() async {
    try {
      final Map? res = await AppSoundEngine._nativeChannel.invokeMethod<Map>('getHardwareSecurityStatus');
      if (res != null) {
        currentDeviceId = (res['deviceId'] ?? 'HW_LOCKED').toString();
        installerPackage = (res['installerPackage'] ?? '').toString();
        isPlayStoreInstall = (res['isPlayStoreInstall'] == true);
        isTampered = (res['isTampered'] == true);
        tamperReason = (res['tamperReason'] ?? 'CLEAN').toString();
      }
    } catch (_) {}
    await checkVipStatus();
  }

  static Future<bool> checkVipStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final int untilMs = prefs.getInt(_prefVipStatusKey) ?? 0;
      final bool active = untilMs > DateTime.now().millisecondsSinceEpoch;
      isVipProActive.value = active;
      return active;
    } catch (_) {
      return false;
    }
  }

  static Future<void> unlockVipForDuration(Duration dur) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final int target = DateTime.now().add(dur).millisecondsSinceEpoch;
      await prefs.setInt(_prefVipStatusKey, target);
      isVipProActive.value = true;
    } catch (_) {}
  }

  /// Checks if this specific hardware device is authorized and NOT a shared/cloned install on another phone!
  static Future<bool> isFirstTimeInstallUnlocked() async {
    await evaluateNativeHardwareSecurity();
    if (isTampered) return false;

    // Official Google Play Store installations automatically bind to the buyer's hardware Device ID!
    if (isPlayStoreInstall) {
      await markFirstTimeInstallUnlocked();
      return true;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final bool unlocked = prefs.getBool(_prefUnlockedKey) ?? false;
      final int savedToken = prefs.getInt(_prefRelockTokenKey) ?? 1;
      final String savedHwId = prefs.getString(_prefBoundDeviceIdKey) ?? '';
      final int remoteToken = OtaUpdateEngine.remoteRelockToken.value;
      if (unlocked && savedToken >= remoteToken) {
        if (savedHwId.isEmpty || savedHwId == currentDeviceId) {
          if (savedHwId.isEmpty) {
            await prefs.setString(_prefBoundDeviceIdKey, currentDeviceId);
          }
          return true;
        } else {
          // Shared/Cloned data detected on a DIFFERENT hardware device! Block immediately!
          return false;
        }
      }
    } catch (_) {}
    try {
      final dir = await getApplicationDocumentsDirectory();
      final f = File('${dir.path}/ims_unlocked_v650.flag');
      if (await f.exists()) {
        final String content = (await f.readAsString()).trim();
        final List<String> parts = content.split('|');
        final int fileTok = int.tryParse(parts.first) ?? 1;
        final String fileHw = parts.length > 1 ? parts[1] : currentDeviceId;
        if (fileTok >= OtaUpdateEngine.remoteRelockToken.value && fileHw == currentDeviceId) {
          return true;
        }
      }
    } catch (_) {}
    return false;
  }

  static Future<void> markFirstTimeInstallUnlocked() async {
    final int tok = OtaUpdateEngine.remoteRelockToken.value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefUnlockedKey, true);
      await prefs.setInt(_prefRelockTokenKey, tok);
      await prefs.setString(_prefBoundDeviceIdKey, currentDeviceId);
    } catch (_) {}
    try {
      final dir = await getApplicationDocumentsDirectory();
      final f = File('${dir.path}/ims_unlocked_v650.flag');
      await f.writeAsString('$tok|$currentDeviceId');
    } catch (_) {}
  }

  static Future<void> relockForTesting() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefUnlockedKey, false);
    } catch (_) {}
    try {
      final dir = await getApplicationDocumentsDirectory();
      final f = File('${dir.path}/ims_unlocked_v650.flag');
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  /// Resolves the active PIN:
  /// Priority 1: Live OTA PIN from `ims_live_ota.json` on GitHub (`OtaUpdateEngine.remoteOtaPin`)
  /// Priority 2: Custom PIN set by user inside the app
  /// Priority 3: Internal fallback seed
  static Future<String> getActivePin() async {
    final String liveOtaPin = OtaUpdateEngine.remoteOtaPin.value.trim();
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? cachedOta = prefs.getString(_prefCachedOtaPinKey);
      final String? custom = prefs.getString(_prefCustomPinKey);
      if (custom != null && custom.trim().isNotEmpty) {
        return custom.trim();
      }
      if (cachedOta != null && cachedOta.trim().isNotEmpty) {
        return cachedOta.trim();
      }
    } catch (_) {}
    return liveOtaPin.isNotEmpty ? liveOtaPin : _internalFallbackPin;
  }

  static Future<void> setCustomPin(String newPin) async {
    final String clean = newPin.trim();
    if (clean.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefCustomPinKey, clean);
    } catch (_) {}
  }

  static Future<bool> verifyPin(String entered) async {
    final String clean = entered.trim();
    if (clean.isEmpty) return false;
    final String activePin = await getActivePin();
    final String remotePin = OtaUpdateEngine.remoteOtaPin.value.trim();
    return clean == activePin ||
        (remotePin.isNotEmpty && clean == remotePin) ||
        clean == _internalFallbackPin;
  }
}

class AppSoundEngine {
  static const MethodChannel _nativeChannel = MethodChannel('dj_native_tts');
  static final AudioPlayer _voicePlayer = AudioPlayer();
  static final AudioPlayer _sfxPlayer = AudioPlayer();

  static Future<void> boostAllPlayersMax(AudioPlayer p) async {
    try {
      await p.setVolume(1.0);
    } catch (_) {}
  }

  /// Ensures Hardware EQ & Virtualizer are 100% bypassed / flat (0dB Normal Original Sound)
  static Future<void> resetHardwareAudioToNormalFlat() async {
    try {
      await _nativeChannel.invokeMethod('resetAudioToNormalFlat');
    } catch (_) {}
  }

  static bool _isSpeakingLock = false;
  static bool hardwareVolumeEntryMode = false;
  static final ValueNotifier<int> activeTabIndexNotifier = ValueNotifier<int>(0);
  static final ValueNotifier<String?> incomingSharedMediaNotifier = ValueNotifier<String?>(null);
  static final ValueNotifier<String?> mediaNotificationActionNotifier = ValueNotifier<String?>(null);

  static const Map<String, String> _knPhonetics = {
    'gajanan': 'ಗಜಾನನ',
    'patagar': 'ಪಟಗಾರ',
    'darshan': 'ದರ್ಶನ್',
    'sudeep': 'ಸುದೀಪ್',
    'yash': 'ಯಶ್',
    'manjunath': 'ಮಂಜುನಾಥ್',
    'prashanth': 'ಪ್ರಶಾಂತ್',
    'virat': 'ವಿರಾಟ್',
    'kohli': 'ಕೊಹ್ಲಿ',
    'rahul': 'ರಾಹುಲ್',
    'rohit': 'ರೋಹಿತ್',
    'sharma': 'ಶರ್ಮಾ',
    'bumrah': 'ಬುಮ್ರಾ',
    'dhoni': 'ಧೋನಿ',
    'jadeja': 'ಜಡೇಜಾ',
    'hardik': 'ಹಾರ್ದಿಕ್',
    'karthik': 'ಕಾರ್ತಿಕ್',
    'padikkal': 'ಪಡಿಕ್ಕಲ್',
    'siraj': 'ಸಿರಾಜ್',
  };

  static const Map<String, String> _hiPhonetics = {
    'gajanan': 'गजानन',
    'patagar': 'पटगार',
    'darshan': 'दर्शन',
    'virat': 'विराट',
    'kohli': 'कोहली',
    'rohit': 'रोहित',
    'bumrah': 'बुमराह',
    'dhoni': 'धोनी',
    'jadeja': 'जडेजा',
    'hardik': 'हार्दिक',
  };

  static String applyPhonetics(String text, String langMode) {
    String out = text;
    if (langMode == 'KANNADA') {
      _knPhonetics.forEach((en, kn) {
        out = out.replaceAll(RegExp(en, caseSensitive: false), kn);
      });
    } else if (langMode == 'HINDI') {
      _hiPhonetics.forEach((en, hi) {
        out = out.replaceAll(RegExp(en, caseSensitive: false), hi);
      });
    }
    return out;
  }

  static void initHardwareVolumeListener() {
    _nativeChannel.setMethodCallHandler((call) async {
      if (call.method == 'onSharedMedia' && call.arguments != null) {
        final String shared = call.arguments.toString().trim();
        if (shared.isNotEmpty) {
          activeTabIndexNotifier.value = 1;
          incomingSharedMediaNotifier.value =
              '$shared##${DateTime.now().millisecondsSinceEpoch}';
        }
        return;
      }
      if (call.method == 'onMediaNotificationAction' && call.arguments != null) {
        final String act = call.arguments.toString().trim();
        if (act.isNotEmpty) {
          mediaNotificationActionNotifier.value =
              '$act##${DateTime.now().microsecondsSinceEpoch}';
        }
        return;
      }
      if (!hardwareVolumeEntryMode) return;
      if (call.method == 'onVolumeKey') {
        final String dir = (call.arguments ?? '').toString();
        if (dir == 'DOWN') {
          MasterVolumeController.page4EntryVolume.value = 0.0;
        } else if (dir == 'UP') {
          final cur = MasterVolumeController.page4EntryVolume.value;
          MasterVolumeController.page4EntryVolume.value =
              (cur <= 0.02) ? 0.85 : (cur + 0.15).clamp(0.0, 1.0);
        }
      }
    });
  }

  static Future<void> panicMuteAll() async {
    try {
      await _nativeChannel.invokeMethod('stopSpeak');
      await _voicePlayer.stop();
      await _sfxPlayer.stop();
      MasterVolumeController.page4EntryVolume.value = 0.0;
    } catch (_) {}
  }

  static Future<void> speakRealVoice(
    String rawText,
    String langMode, {
    String? eventKey,
    String? coCommentatorText,
  }) async {
    if (rawText.trim().isEmpty) return;
    final double voiceVol = MasterVolumeController.page2VoiceVolume.value;
    if (voiceVol <= 0.01) return;

    final String fullText = (coCommentatorText != null && coCommentatorText.isNotEmpty)
        ? ('$rawText ... $coCommentatorText')
        : rawText;
    final String phoneticText = applyPhonetics(fullText, langMode);

    if (_isSpeakingLock) {
      try {
        await _nativeChannel.invokeMethod('stopSpeak');
        await _voicePlayer.stop();
      } catch (_) {}
    }
    _isSpeakingLock = true;

    try {
      final profile = VoiceCloneProfileStore.activeProfile;

      if (eventKey != null) {
        final String? recordedPath = VoiceCloneProfileStore.recordedEventClips[eventKey];
        if (recordedPath != null && File(recordedPath).existsSync()) {
          await _voicePlayer.stop();
          await _voicePlayer.setVolume(voiceVol);
          await _voicePlayer.play(DeviceFileSource(recordedPath));
          _isSpeakingLock = false;
          return;
        }
      }

      String locale = 'kn-IN';
      String tl = 'kn';
      if (langMode == 'HINDI') {
        locale = 'hi-IN';
        tl = 'hi';
      } else if (langMode == 'ENGLISH') {
        locale = 'en-IN';
        tl = 'en';
      }

      if (!profile.preferCloudVoiceOnly) {
        final bool? nativeSpoke = await _nativeChannel.invokeMethod<bool>('speak', {
          'text': phoneticText,
          'lang': locale,
          'pitch': profile.pitch,
          'rate': profile.speed,
        });
        if (nativeSpoke == true) {
          _isSpeakingLock = false;
          return;
        }
      }

      final String cleanText =
          phoneticText.length > 185 ? phoneticText.substring(0, 185) : phoneticText;
      final String url =
          'https://translate.google.com/translate_tts?ie=UTF-8&client=tw-ob&tl=$tl&q=${Uri.encodeComponent(cleanText)}';
      await _voicePlayer.stop();
      await _voicePlayer.setVolume(voiceVol);
      await _voicePlayer.play(UrlSource(url));
      await _voicePlayer.setPlaybackRate(profile.speed.clamp(0.75, 1.35));
    } catch (_) {
    } finally {
      _isSpeakingLock = false;
    }
  }

  static Future<String?> startMicRecording(String fileName) async {
    try {
      return await _nativeChannel.invokeMethod<String>('startRecord', {'name': fileName});
    } catch (_) {
      return null;
    }
  }

  static Future<String?> stopMicRecording() async {
    try {
      return await _nativeChannel.invokeMethod<String>('stopRecord');
    } catch (_) {
      return null;
    }
  }

  static Future<void> playRecordedFile(String path) async {
    try {
      if (File(path).existsSync()) {
        await _voicePlayer.stop();
        await _voicePlayer.setVolume(MasterVolumeController.page2VoiceVolume.value);
        await _voicePlayer.play(DeviceFileSource(path));
      }
    } catch (_) {}
  }

  static Future<void> playSynthesizedSfx(String type) async {
    if (type == 'MUTE_ALL') {
      await panicMuteAll();
      return;
    }
    try {
      final double sfxVol = MasterVolumeController.page3SfxVolume.value;
      if (sfxVol <= 0.01) return;
      final bytes = _buildWavBytes(type);
      await _sfxPlayer.stop();
      await _sfxPlayer.setVolume(sfxVol);
      await _sfxPlayer.play(BytesSource(bytes));
    } catch (_) {}
  }

  static Uint8List _buildWavBytes(String type) {
    const int sampleRate = 22050;
    final double durationSec =
        (type == 'CROWD' || type == 'SIX' || type == 'DHOL' || type == 'HEARTBEAT' || type == 'RISER')
            ? 1.15
            : 0.48;
    final int numSamples = (sampleRate * durationSec).toInt();
    final int dataSize = numSamples * 2;
    final ByteData bd = ByteData(44 + dataSize);

    final header = [
      0x52, 0x49, 0x46, 0x46,
      ..._int32Le(36 + dataSize),
      0x57, 0x41, 0x56, 0x45,
      0x66, 0x6D, 0x74, 0x20,
      16, 0, 0, 0, 1, 0, 1, 0,
      ..._int32Le(sampleRate),
      ..._int32Le(sampleRate * 2),
      2, 0, 16, 0,
      0x64, 0x61, 0x74, 0x61,
      ..._int32Le(dataSize),
    ];
    for (int i = 0; i < header.length; i++) {
      bd.setUint8(i, header[i]);
    }

    final Random rng = Random();
    for (int i = 0; i < numSamples; i++) {
      final double t = i / sampleRate;
      final double env = (1.0 - (i / numSamples)).clamp(0.0, 1.0);
      double sample = 0.0;

      if (type == 'BOWLED') {
        sample = (sin(2 * pi * (175 - t * 220) * t) * 0.6 + (rng.nextDouble() * 2 - 1) * 0.35) * env;
      } else if (type == 'NO_BALL') {
        final freq = 460 + 280 * sin(2 * pi * 6 * t);
        sample = sin(2 * pi * freq * t) * 0.65 * env;
      } else if (type == 'AIRHORN') {
        sample = (sin(2 * pi * 390 * t) + 0.6 * sin(2 * pi * 780 * t)) * 0.48 * env;
      } else if (type == 'LASER') {
        final freq = 1400 - (t * 2400);
        sample = sin(2 * pi * freq.clamp(100, 1500) * t) * 0.65 * env;
      } else if (type == 'SUB_DROP') {
        final freq = (130 - t * 95).clamp(38.0, 130.0);
        sample = sin(2 * pi * freq * t) * 0.88 * env;
      } else if (type == 'DHOL') {
        final pulse = (sin(2 * pi * 6.5 * t) > 0) ? 1.0 : 0.25;
        sample = sin(2 * pi * 115 * t) * pulse * 0.78 * env;
      } else if (type == 'TRUMPET') {
        final f = (t < 0.2) ? 523.25 : ((t < 0.4) ? 659.25 : 783.99);
        sample = (sin(2 * pi * f * t) + 0.4 * sin(4 * pi * f * t)) * 0.55 * env;
      } else if (type == 'HEARTBEAT') {
        final thump = ((t % 0.45) < 0.12) ? 1.0 : 0.05;
        sample = sin(2 * pi * 62 * t) * thump * 0.9;
      } else if (type == 'BELL') {
        sample = (sin(2 * pi * 880 * t) + 0.5 * sin(2 * pi * 1760 * t)) * 0.5 * env;
      } else if (type == 'RISER') {
        final freq = 120 + (t * 950);
        sample = sin(2 * pi * freq * t) * (t / durationSec).clamp(0.1, 0.85);
      } else if (type == 'SUB_TEST_50HZ') {
        sample = sin(2 * pi * 50 * t) * 0.85;
      } else if (type == 'TOP_TEST_1KHZ') {
        sample = sin(2 * pi * 1000 * t) * 0.55;
      } else {
        final crack = (t < 0.045) ? sin(2 * pi * 520 * t) * 0.85 : 0.0;
        final roar = (rng.nextDouble() * 2 - 1) * 0.28 * env;
        sample = (crack + roar).clamp(-1.0, 1.0);
      }

      final int pcm = (sample.clamp(-1.0, 1.0) * 32760).toInt();
      bd.setInt16(44 + i * 2, pcm, Endian.little);
    }
    return bd.buffer.asUint8List();
  }

  static List<int> _int32Le(int v) => [v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff, (v >> 24) & 0xff];
}

class DjPlayCommentaryApp extends StatelessWidget {
  const DjPlayCommentaryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IMS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF050914),
        primaryColor: const Color(0xFF00E5FF),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00E5FF),
          secondary: Color(0xFFFFAB00),
          surface: Color(0xFF0E1729),
        ),
      ),
      home: const ImsFirstTimeLockGate(),
    );
  }
}

/// First-Time Installation Auto-OTA Scanner + Secret PIN Security Gate:
/// 1) On 1st-time installation open, automatically scans GitHub OTA for the latest version & remote PIN,
///    and if a newer APK build exists, auto-updates before the user starts using the app!
/// 2) Never displays or hints the PIN anywhere in the UI.
/// 3) Once unlocked on 1st install, everyday launches open straight into the app!
class ImsFirstTimeLockGate extends StatefulWidget {
  const ImsFirstTimeLockGate({super.key});

  @override
  State<ImsFirstTimeLockGate> createState() => _ImsFirstTimeLockGateState();
}

class _ImsFirstTimeLockGateState extends State<ImsFirstTimeLockGate> {
  bool _isBootstrapping = true;
  bool _isAutoUpdatingOnFirstInstall = false;
  String _bootstrapStatus = '🔍 Scanning IMS Cloud OTA for Latest Updates...';
  double? _bootstrapProgress;
  bool _isUnlocked = false;
  String _enteredPin = '';
  String _errorMsg = '';

  @override
  void initState() {
    super.initState();
    _runStartupOtaScanAndLockCheck();
  }

  Future<void> _runStartupOtaScanAndLockCheck() async {
    // Ensure Hardware EQ & Virtualizer start 100% flat / normal (0dB Original Audio)
    await AppSoundEngine.resetHardwareAudioToNormalFlat();

    // First sync live OTA manifest (fetches latest remote PIN & forceRelockToken in <1.5s)
    await OtaUpdateEngine.syncInAppLiveCloudOta();
    final bool alreadyUnlocked = await ImsSecurityManager.isFirstTimeInstallUnlocked();

    if (alreadyUnlocked) {
      if (mounted) {
        setState(() {
          _isUnlocked = true;
          _isBootstrapping = false;
        });
      }
      return;
    }

    // User is opening the app for the 1st time after installation!
    // Automatically scan for any newer OTA update and auto-install it before use!
    if (mounted) {
      setState(() {
        _bootstrapStatus = '🔄 1st-Time Setup: Scanning OTA Server for Latest IMS Build...';
      });
    }

    final bool startedApkUpdate = await OtaUpdateEngine.checkAndAutoInstallOtaUpdate(
      forceManualCheck: true,
      onProgressCallback: (status, pct) {
        if (mounted) {
          setState(() {
            _bootstrapStatus = status;
            _bootstrapProgress = pct;
            if (pct != null && pct < 1.0) {
              _isAutoUpdatingOnFirstInstall = true;
            }
          });
        }
      },
    );

    if (mounted) {
      setState(() {
        _isAutoUpdatingOnFirstInstall = startedApkUpdate;
        _isBootstrapping = false;
      });
    }
  }

  Future<void> _onDigitTap(String digit) async {
    if (_enteredPin.length >= 8) return;
    setState(() {
      _enteredPin += digit;
      _errorMsg = '';
    });

    final String activePin = await ImsSecurityManager.getActivePin();
    final int targetLen = activePin.length >= 4 ? activePin.length : 4;
    if (_enteredPin.length >= targetLen) {
      final bool valid = await ImsSecurityManager.verifyPin(_enteredPin);
      if (valid) {
        AppSoundEngine.playSynthesizedSfx('BELL');
        await ImsSecurityManager.markFirstTimeInstallUnlocked();
        if (mounted) {
          setState(() => _isUnlocked = true);
        }
      } else {
        setState(() {
          _errorMsg = '❌ Invalid Security Code';
          _enteredPin = '';
        });
      }
    }
  }

  void _onBackspace() {
    if (_enteredPin.isEmpty) return;
    setState(() {
      _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1);
      _errorMsg = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isUnlocked) {
      return MasterHomeShell(
        onRelockRequested: () async {
          await ImsSecurityManager.relockForTesting();
          if (mounted) {
            setState(() {
              _enteredPin = '';
              _errorMsg = '';
              _isUnlocked = false;
            });
          }
        },
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF050914),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: GlassBox(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 26),
              borderRadius: 28,
              blur: 22,
              tintColor: const Color(0xFF0B152B),
              borderColor: const Color(0xFF00E5FF),
              borderWidth: 1.6,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 82,
                    height: 82,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [Color(0xFF0F2042), Color(0xFF071024)],
                      ),
                      border: Border.all(color: Colors.amberAccent, width: 2.2),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF00E5FF).withOpacity(0.38),
                          blurRadius: 18,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: const Text(
                      'IMS',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        color: Colors.amberAccent,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'IMS PRO STUDIO',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: 1.1,
                    ),
                  ),
                  const SizedBox(height: 6),

                  // 1st-Time Install Auto-OTA Scanner Status Box
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00E676).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF00E676).withOpacity(0.45)),
                    ),
                    child: Column(
                      children: [
                        Text(
                          _bootstrapStatus,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF00E676),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (_isBootstrapping || _isAutoUpdatingOnFirstInstall) ...[
                          const SizedBox(height: 6),
                          LinearProgressIndicator(
                            value: _bootstrapProgress,
                            backgroundColor: Colors.white12,
                            color: Colors.amberAccent,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  Text(
                    ImsSecurityManager.isTampered
                        ? '🛡️ SECURITY ALERT: MODDING / PATCHING DETECTED (${ImsSecurityManager.tamperReason})\nThis modified APK is permanently blocked.'
                        : '🔒 Hardware Device-Locked Protection Active\nShared APKs Outside Google Play Store Require One-Time Device Authorization',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: ImsSecurityManager.isTampered ? Colors.redAccent : const Color(0xFF00E5FF),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF00E676)),
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(Icons.shop_two_rounded, size: 16, color: Color(0xFF00E676)),
                    label: const Text(
                      'Install Official App on Google Play Store',
                      style: TextStyle(fontSize: 10.5, color: Color(0xFF00E676), fontWeight: FontWeight.w900),
                    ),
                    onPressed: () {
                      AppSoundEngine._nativeChannel.invokeMethod('openPlayStoreListing');
                    },
                  ),
                  const SizedBox(height: 16),

                  // Entered PIN Dots Indicator (No PIN hints ever shown!)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(4, (i) {
                      final bool filled = i < _enteredPin.length;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        margin: const EdgeInsets.symmetric(horizontal: 8),
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: filled ? Colors.amberAccent : Colors.white12,
                          border: Border.all(
                            color: filled ? const Color(0xFF00E5FF) : Colors.white38,
                            width: 1.5,
                          ),
                          boxShadow: filled
                              ? [
                                  BoxShadow(
                                    color: Colors.amberAccent.withOpacity(0.6),
                                    blurRadius: 8,
                                  ),
                                ]
                              : null,
                        ),
                      );
                    }),
                  ),
                  if (_errorMsg.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      _errorMsg,
                      style: const TextStyle(fontSize: 12, color: Colors.redAccent, fontWeight: FontWeight.w900),
                    ),
                  ],
                  const SizedBox(height: 20),

                  // Glassmorphic Numeric Keypad
                  SizedBox(
                    width: 260,
                    child: GridView.count(
                      crossAxisCount: 3,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 1.32,
                      children: [
                        ...['1', '2', '3', '4', '5', '6', '7', '8', '9'].map((d) => _pinKeyBtn(d, () => _onDigitTap(d))),
                        _pinKeyBtn('CLR', () => setState(() => _enteredPin = ''), isAction: true),
                        _pinKeyBtn('0', () => _onDigitTap('0')),
                        _pinKeyBtn('⌫', _onBackspace, isAction: true),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _pinKeyBtn(String label, VoidCallback onTap, {bool isAction = false}) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isAction
                ? [const Color(0xFF1F2937), const Color(0xFF111827)]
                : [const Color(0xFF16274C), const Color(0xFF0D1830)],
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isAction ? Colors.amberAccent.withOpacity(0.5) : const Color(0x5500E5FF),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: isAction ? 14 : 20,
            fontWeight: FontWeight.w900,
            color: isAction ? Colors.amberAccent : Colors.white,
          ),
        ),
      ),
    );
  }
}

class MasterHomeShell extends StatefulWidget {
  final VoidCallback? onRelockRequested;

  const MasterHomeShell({super.key, this.onRelockRequested});

  @override
  State<MasterHomeShell> createState() => _MasterHomeShellState();
}

class _MasterHomeShellState extends State<MasterHomeShell> with WidgetsBindingObserver {
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AppSoundEngine.activeTabIndexNotifier.addListener(() {
      final int newIdx = AppSoundEngine.activeTabIndexNotifier.value;
      if (newIdx != 4) {
        // When leaving Karaoke Tab, ensure Hardware EQ is reset to Pure Normal Original Sound!
        AppSoundEngine.resetHardwareAudioToNormalFlat();
      }
      if (mounted && _selectedIndex != newIdx) {
        setState(() => _selectedIndex = newIdx);
      }
    });
    _checkPendingSharedIntent();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPendingSharedIntent();
      OtaUpdateEngine.syncInAppLiveCloudOta();
    }
  }

  Future<void> _checkPendingSharedIntent() async {
    try {
      final String? initial =
          await AppSoundEngine._nativeChannel.invokeMethod<String>('getInitialSharedMedia');
      if (initial != null && initial.trim().isNotEmpty) {
        AppSoundEngine.activeTabIndexNotifier.value = 1;
        AppSoundEngine.incomingSharedMediaNotifier.value =
            '${initial.trim()}##${DateTime.now().millisecondsSinceEpoch}';
      }
    } catch (_) {}
  }

  /// Security & Password Changer Dialog (Zero mention of the actual PIN anywhere!)
  Future<void> _openPinAndSecurityModal() async {
    final TextEditingController oldPinCtrl = TextEditingController();
    final TextEditingController newPinCtrl = TextEditingController();
    String feedback = '';

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
              child: GlassBox(
                margin: const EdgeInsets.all(10),
                padding: const EdgeInsets.all(16),
                borderRadius: 24,
                blur: 22,
                tintColor: const Color(0xFF0B1426),
                borderColor: Colors.amberAccent,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          '🔐 IMS Security & Access Code Manager',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Colors.amberAccent),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white60),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const Text(
                      'Access Code is synced via IMS Cloud OTA or can be updated locally below.',
                      style: TextStyle(fontSize: 11, color: Colors.white70),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: oldPinCtrl,
                      obscureText: true,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Enter Current Access Code',
                        filled: true,
                        fillColor: Color(0xFF141E33),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: newPinCtrl,
                      obscureText: true,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Enter New Access Code',
                        filled: true,
                        fillColor: Color(0xFF141E33),
                      ),
                    ),
                    if (feedback.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        feedback,
                        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Color(0xFF00E676)),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF00E5FF),
                              foregroundColor: Colors.black,
                            ),
                            icon: const Icon(Icons.save_rounded, size: 18),
                            label: const Text('Update Code', style: TextStyle(fontWeight: FontWeight.w900)),
                            onPressed: () async {
                              final bool ok = await ImsSecurityManager.verifyPin(oldPinCtrl.text);
                              if (!ok) {
                                setModalState(() => feedback = '❌ Current Access Code is incorrect!');
                                return;
                              }
                              if (newPinCtrl.text.trim().length < 4) {
                                setModalState(() => feedback = '⚠️ New Code must be at least 4 digits!');
                                return;
                              }
                              await ImsSecurityManager.setCustomPin(newPinCtrl.text.trim());
                              setModalState(() => feedback = '✅ Security Access Code Updated!');
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.amberAccent),
                          ),
                          icon: const Icon(Icons.lock_outline_rounded, size: 17, color: Colors.amberAccent),
                          label: const Text(
                            'Lock App',
                            style: TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold),
                          ),
                          onPressed: () {
                            Navigator.pop(ctx);
                            if (widget.onRelockRequested != null) {
                              widget.onRelockRequested!();
                            }
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _openVipMonetizationStudioModal() {
    final TextEditingController vipPinCtrl = TextEditingController();
    String statusMsg = '';
    bool isSuccessMsg = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final bool isVip = ImsSecurityManager.isVipProActive.value;
            final String hwId = ImsSecurityManager.currentDeviceId;
            final String shortHw = hwId.length > 18 ? hwId.substring(0, 18) : hwId;
            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
              child: GlassBox(
                margin: const EdgeInsets.all(10),
                padding: const EdgeInsets.all(16),
                borderRadius: 24,
                blur: 24,
                tintColor: const Color(0xFF0A1224),
                borderColor: Colors.amberAccent,
                borderWidth: 1.6,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.workspace_premium_rounded, color: Colors.amberAccent, size: 28),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  isVip ? '👑 IMS VIP PRO STUDIO (ACTIVE)' : '💎 IMS GOOGLE ADSENSE & 1-HOUR VIP PASS',
                                  style: const TextStyle(fontSize: 14.0, fontWeight: FontWeight.w900, color: Colors.amberAccent),
                                ),
                                ValueListenableBuilder<int>(
                                  valueListenable: ImsMonetizationEngine.vipRemainingSeconds,
                                  builder: (_, remSec, __) {
                                    final int m = remSec ~/ 60;
                                    final int s = remSec % 60;
                                    final String timeStr = remSec > 86400
                                        ? 'Full Pass Active'
                                        : (remSec > 0
                                            ? '⏱️ 1-Hr VIP Left: ${m.toString().padLeft(2, "0")}m ${s.toString().padLeft(2, "0")}s'
                                            : '🔒 1-Hr VIP Expired (Watch 1 Ad = +1 Hour)');
                                    return Text(
                                      '$timeStr • 18-Bit Key 0x2D396 Shield ON',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                        color: remSec > 0 ? const Color(0xFF00E676) : Colors.orangeAccent,
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: '18-Bit Encrypted Key Vault & Generator',
                            icon: const Icon(Icons.enhanced_encryption_rounded, color: Color(0xFF00E5FF), size: 22),
                            onPressed: () {
                              showModalBottomSheet(
                                context: context,
                                isScrollControlled: true,
                                backgroundColor: Colors.transparent,
                                builder: (_) => const OwnerVipKeyGeneratorSheet(),
                              );
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded, color: Colors.white70),
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                      if (statusMsg.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: (isSuccessMsg ? const Color(0xFF00E676) : Colors.redAccent).withOpacity(0.18),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isSuccessMsg ? const Color(0xFF00E676) : Colors.redAccent,
                              width: 1.4,
                            ),
                          ),
                          child: Text(
                            statusMsg,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w900,
                              color: isSuccessMsg ? const Color(0xFF00E676) : Colors.redAccent,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(11),
                        decoration: BoxDecoration(
                          color: const Color(0xFF132242),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.5)),
                        ),
                        child: const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '✨ Google AdSense Account (ca-pub-1729380220130058) • 18-Bit Encrypted:',
                              style: TextStyle(fontSize: 11.2, fontWeight: FontWeight.w900, color: Colors.white),
                            ),
                            SizedBox(height: 3),
                            Text(
                              '• Watch 1 AdSense Ad = Unlock 1 Full Hour (60m) of Song & DJ Playback',
                              style: TextStyle(fontSize: 10.5, color: Color(0xFF00E676), fontWeight: FontWeight.w700, height: 1.3),
                            ),
                            Text(
                              '• Pre-Expiry Alert 3 Mins Before 1 Hour Ends + Auto Re-Unlock Prompt',
                              style: TextStyle(fontSize: 10.5, color: Colors.white70, height: 1.3),
                            ),
                            Text(
                              '• 18-Bit Anti-Extraction Shield (Key 185238 / 101101001110010110) Active',
                              style: TextStyle(fontSize: 10.5, color: Colors.amberAccent, height: 1.3),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF00E676),
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 13),
                          ),
                          icon: const Icon(Icons.play_circle_fill_rounded, size: 22),
                          label: const Text(
                            '🎬 Watch 1 AdSense Ad → Unlock 1 Hour VIP Access Free',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
                          ),
                          onPressed: () {
                            ImsMonetizationEngine.instance.show15SecondRewardedAdExperience(
                              context,
                              onRewardGranted: () {
                                setModalState(() {
                                  statusMsg = '✅ +1 Hour (60m 00s) VIP Access Unlocked via Google AdSense (ca-pub-1729380220130058)!';
                                  isSuccessMsg = true;
                                });
                              },
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 10),
                      _vipPlanTile(
                        title: '⚡ Monthly Pro DJ Pass',
                        subtitle: 'Google AdSense Publisher Account (ca-pub-1729380220130058 • INCHARA MASTER SOUNDS)',
                        price: '₹49 / Month',
                        color: const Color(0xFF00E5FF),
                        onTap: () {
                          ImsMonetizationEngine.instance.openPassCheckoutDialog(
                            context,
                            planTitle: '⚡ Monthly Pro DJ Pass',
                            planSubtitle: '30-Day Full Ad-Free Studio + Unlimited 320K Offline Vaults (AdSense Linked)',
                            amountInr: 49,
                            productId: ImsMonetizationEngine.kProductMonthly49,
                            tierCode: 'MONTHLY',
                            accentColor: const Color(0xFF00E5FF),
                            onUnlocked: () => setModalState(() {
                              statusMsg = '👑 Monthly Pro DJ Pass Activated!';
                              isSuccessMsg = true;
                            }),
                          );
                        },
                      ),
                      const SizedBox(height: 7),
                      _vipPlanTile(
                        title: '🔥 Annual Wedding & Event Master',
                        subtitle: 'Google AdSense Publisher Account (ca-pub-1729380220130058 • 365-Day VIP)',
                        price: '₹299 / Year',
                        color: const Color(0xFF00E676),
                        onTap: () {
                          ImsMonetizationEngine.instance.openPassCheckoutDialog(
                            context,
                            planTitle: '🔥 Annual Wedding & Event Master',
                            planSubtitle: '365-Day Full Commercial Event & Wedding DJ License (AdSense Linked)',
                            amountInr: 299,
                            productId: ImsMonetizationEngine.kProductAnnual299,
                            tierCode: 'ANNUAL',
                            accentColor: const Color(0xFF00E676),
                            onUnlocked: () => setModalState(() {
                              statusMsg = '👑 Annual Wedding & Event Master Pass Activated!';
                              isSuccessMsg = true;
                            }),
                          );
                        },
                      ),
                      const SizedBox(height: 7),
                      _vipPlanTile(
                        title: '👑 Lifetime Studio VIP License',
                        subtitle: 'Google AdSense Account • 18-Bit Hardware License ($shortHw)',
                        price: '₹499 Lifetime',
                        color: Colors.amberAccent,
                        onTap: () {
                          ImsMonetizationEngine.instance.openPassCheckoutDialog(
                            context,
                            planTitle: '👑 Lifetime Studio VIP License',
                            planSubtitle: 'Permanent Hardware-Bound VIP Studio Master License (AdSense Linked)',
                            amountInr: 499,
                            productId: ImsMonetizationEngine.kProductLifetime499,
                            tierCode: 'LIFETIME',
                            accentColor: Colors.amberAccent,
                            onUnlocked: () => setModalState(() {
                              statusMsg = '👑 Lifetime Studio VIP License Activated!';
                              isSuccessMsg = true;
                            }),
                          );
                        },
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: vipPinCtrl,
                              decoration: const InputDecoration(
                                isDense: true,
                                labelText: 'Enter 6-Digit VIP Key or 18-Bit Key',
                                filled: true,
                                fillColor: Color(0xFF141E33),
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
                              final Duration? dur = await ImsMonetizationEngine.verifyVipActivationKey(
                                vipPinCtrl.text,
                                hwId,
                              );
                              if (dur != null) {
                                await ImsSecurityManager.unlockVipForDuration(dur);
                                await ImsMonetizationEngine.instance.refreshVipTimer();
                                AppSoundEngine.playSynthesizedSfx('BELL');
                                setModalState(() {
                                  statusMsg = '👑 VIP Pro Activated & Bound to Device $shortHw!';
                                  isSuccessMsg = true;
                                });
                              } else {
                                setModalState(() {
                                  statusMsg = '❌ Invalid Key! Watch 1 Ad above for 1 Hour VIP or enter valid key.';
                                  isSuccessMsg = false;
                                });
                              }
                            },
                            child: const Text('Activate', style: TextStyle(fontWeight: FontWeight.w900)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _vipPlanTile({
    required String title,
    required String subtitle,
    required String price,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: const Color(0xFF121F3D),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.75)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900, color: color)),
                  Text(subtitle, style: const TextStyle(fontSize: 10.5, color: Colors.white70)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                price,
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Colors.black),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openInAppOtaAndMasterMixerModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return GlassBox(
          margin: const EdgeInsets.all(10),
          padding: const EdgeInsets.all(16),
          borderRadius: 24,
          blur: 22,
          tintColor: const Color(0xFF0B1426),
          borderColor: const Color(0xFF00E5FF),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '⚡ IMS FULL AUTO-OTA & 4-CHANNEL MASTER MIXER',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w900, color: Color(0xFF00E5FF)),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF00E676).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF00E676).withOpacity(0.45)),
                ),
                child: const Text(
                  '✅ Automatic OTA Engine Active: Scans & applies both Live Cloud Updates and Full Release Updates automatically!',
                  style: TextStyle(fontSize: 10.5, color: Color(0xFF00E676), fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00E676),
                        foregroundColor: Colors.black,
                      ),
                      icon: const Icon(Icons.system_update_rounded, size: 18),
                      label: const Text(
                        'Scan & Auto-Update Now',
                        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900),
                      ),
                      onPressed: () async {
                        Navigator.pop(ctx);
                        await OtaUpdateEngine.checkAndAutoInstallOtaUpdate(forceManualCheck: true);
                      },
                    ),
                  ),
                ],
              ),
              const Divider(color: Colors.white24, height: 18),
              _volumeSliderRow('🎵 Tab 1 Music Master', MasterVolumeController.page1MusicVolume, const Color(0xFF00E5FF)),
              _volumeSliderRow('🎙 Tab 2 Commentary Voice', MasterVolumeController.page2VoiceVolume, Colors.amberAccent),
              _volumeSliderRow('📢 Tab 3 Stadium SFX Pads', MasterVolumeController.page3SfxVolume, const Color(0xFF00E676)),
            ],
          ),
        );
      },
    );
  }

  Widget _volumeSliderRow(String label, ValueNotifier<double> notifier, Color color) {
    return ValueListenableBuilder<double>(
      valueListenable: notifier,
      builder: (context, val, _) {
        return Row(
          children: [
            SizedBox(
              width: 145,
              child: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            ),
            Expanded(
              child: Slider(
                value: val.clamp(0.0, 1.0),
                activeColor: color,
                onChanged: (v) => notifier.value = v,
              ),
            ),
            Text('${(val * 100).toInt()}%', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900, color: color)),
          ],
        );
      },
    );
  }

  final List<Widget> _pages = const [
    AudioStudioScreen(),
    CricketCommentaryScreen(),
    VoiceCloneAndProHubScreen(),
    EntryMusicStudioScreen(),
    KaraokeStudioScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(56),
        child: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: AppBar(
              backgroundColor: const Color(0xFF0B1325).withOpacity(0.88),
              elevation: 0,
              title: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      gradient: const LinearGradient(
                        colors: [Color(0xFF10254C), Color(0xFF081226)],
                      ),
                      border: Border.all(color: Colors.amberAccent, width: 1.6),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF00E5FF).withOpacity(0.42),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: const Text(
                      'IMS',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w900,
                        color: Colors.amberAccent,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'IMS Pro Studio',
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF00E5FF),
                            letterSpacing: 0.4,
                          ),
                        ),
                        ValueListenableBuilder<String>(
                          valueListenable: OtaUpdateEngine.otaStatusBanner,
                          builder: (context, banner, _) {
                            return Text(
                              banner,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 9.5, color: Colors.amberAccent),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              actions: [
                GestureDetector(
                  onTap: _openVipMonetizationStudioModal,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 11, horizontal: 2),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Color(0xFFFFD700), Color(0xFFFF8F00)]),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: const Text(
                      '💎 VIP',
                      style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900, color: Colors.black),
                    ),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Auto-OTA & Master Mixer',
                  icon: const Icon(Icons.bolt_rounded, color: Color(0xFF00E676), size: 22),
                  onPressed: _openInAppOtaAndMasterMixerModal,
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Security Settings',
                  icon: const Icon(Icons.lock_person_rounded, color: Color(0xFF00E5FF), size: 20),
                  onPressed: _openPinAndSecurityModal,
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Panic Mute All',
                  icon: const Icon(Icons.volume_off_rounded, color: Colors.redAccent, size: 21),
                  onPressed: () => AppSoundEngine.panicMuteAll(),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'DJ Airhorn',
                  icon: const Icon(Icons.campaign_rounded, color: Colors.amberAccent, size: 22),
                  onPressed: () => AppSoundEngine.playSynthesizedSfx('AIRHORN'),
                ),
              ],
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          ValueListenableBuilder<double?>(
            valueListenable: OtaUpdateEngine.otaDownloadProgress,
            builder: (context, progress, _) {
              if (progress == null) return const SizedBox.shrink();
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                color: const Color(0xFF1E3A8A),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          '🚀 IMS Auto-OTA Updating...',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Colors.white),
                        ),
                        Text(
                          '${(progress * 100).toInt()}%',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            color: Colors.amberAccent,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    LinearProgressIndicator(
                      value: progress,
                      backgroundColor: Colors.white24,
                      color: const Color(0xFF00E676),
                    ),
                  ],
                ),
              );
            },
          ),
          Expanded(
            child: IndexedStack(
              index: _selectedIndex,
              children: _pages,
            ),
          ),
          LiveBottomAdBanner(onTapVipUpgrade: _openVipMonetizationStudioModal),
        ],
      ),
      bottomNavigationBar: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: BottomNavigationBar(
            currentIndex: _selectedIndex,
            onTap: (idx) {
              if (idx != 4) {
                AppSoundEngine.resetHardwareAudioToNormalFlat();
              }
              AppSoundEngine.activeTabIndexNotifier.value = idx;
              setState(() => _selectedIndex = idx);
            },
            backgroundColor: const Color(0xFF080E1E).withOpacity(0.92),
            selectedItemColor: const Color(0xFF00E5FF),
            unselectedItemColor: Colors.white54,
            type: BottomNavigationBarType.fixed,
            selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 10),
            unselectedLabelStyle: const TextStyle(fontSize: 9.5),
            items: const [
              BottomNavigationBarItem(icon: Icon(Icons.library_music_rounded), label: '1. Pro Music'),
              BottomNavigationBarItem(icon: Icon(Icons.sports_cricket_rounded), label: '2. Cricket'),
              BottomNavigationBarItem(icon: Icon(Icons.tune_rounded), label: '3. PA & Pads'),
              BottomNavigationBarItem(icon: Icon(Icons.bolt_rounded), label: '4. Entry BGM'),
              BottomNavigationBarItem(icon: Icon(Icons.mic_external_on_rounded), label: '5. Karaoke'),
            ],
          ),
        ),
      ),
    );
  }
}

