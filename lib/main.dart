import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import 'audio_studio.dart';
import 'cricket_studio.dart';
import 'voice_and_pro_hub.dart';
import 'entry_music_data.dart';
import 'entry_music_studio.dart';
import 'karaoke_studio.dart';
import 'ota_update_engine.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  AppSoundEngine.initHardwareVolumeListener();
  runApp(const DjPlayCommentaryApp());
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
      title: 'DJ Play and Commentry App',
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
      home: const MasterHomeShell(),
    );
  }
}

class MasterHomeShell extends StatefulWidget {
  const MasterHomeShell({super.key});

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
      if (mounted && _selectedIndex != AppSoundEngine.activeTabIndexNotifier.value) {
        setState(() => _selectedIndex = AppSoundEngine.activeTabIndexNotifier.value);
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
      OtaUpdateEngine.checkAndAutoInstallOtaUpdate();
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
              backgroundColor: const Color(0xFF0B1325).withOpacity(0.86),
              elevation: 0,
              title: Row(
                children: [
                  Container(
                    width: 35,
                    height: 35,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFFAB00), Color(0xFF00E5FF)],
                      ),
                      border: Border.all(color: Colors.white, width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF00E5FF).withOpacity(0.45),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                    child: const Icon(Icons.album_rounded, color: Colors.black, size: 21),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'DJ Play & Commentary Pro v505',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF00E5FF),
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
                IconButton(
                  tooltip: 'Panic Mute All',
                  icon: const Icon(Icons.volume_off_rounded, color: Colors.redAccent),
                  onPressed: () => AppSoundEngine.panicMuteAll(),
                ),
                IconButton(
                  tooltip: 'DJ Airhorn',
                  icon: const Icon(Icons.campaign_rounded, color: Colors.amberAccent),
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
                          '🚀 Zero-Touch Auto-OTA Update in Progress...',
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
        ],
      ),
      bottomNavigationBar: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: BottomNavigationBar(
            currentIndex: _selectedIndex,
            onTap: (idx) {
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
