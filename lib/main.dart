import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import 'audio_studio.dart';
import 'cricket_studio.dart';
import 'voice_and_pro_hub.dart';
import 'entry_music_data.dart';
import 'entry_music_studio.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DjPlayCommentaryApp());
}

class AppSoundEngine {
  static const MethodChannel _nativeChannel = MethodChannel('dj_native_tts');
  static final AudioPlayer _voicePlayer = AudioPlayer();
  static final AudioPlayer _sfxPlayer = AudioPlayer();
  static bool _isSpeakingLock = false;

  static Future<void> speakRealVoice(String text, String langMode, {String? eventKey}) async {
    if (text.trim().isEmpty) return;
    final double voiceVol = MasterVolumeController.page2VoiceVolume.value;
    if (voiceVol <= 0.01) return;

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
          'text': text,
          'lang': locale,
          'pitch': profile.pitch,
          'rate': profile.speed,
        });
        if (nativeSpoke == true) {
          _isSpeakingLock = false;
          return;
        }
      }

      final String cleanText = text.length > 185 ? text.substring(0, 185) : text;
      final String url = 'https://translate.google.com/translate_tts?ie=UTF-8&client=tw-ob&tl=' +
          tl +
          '&q=' +
          Uri.encodeComponent(cleanText);
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
    final double durationSec = (type == 'CROWD' || type == 'SIX') ? 0.9 : 0.35;
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
        sample = (sin(2 * pi * (175 - t * 220) * t) * 0.55 + (rng.nextDouble() * 2 - 1) * 0.35) * env;
      } else if (type == 'NO_BALL') {
        final freq = 460 + 280 * sin(2 * pi * 6 * t);
        sample = sin(2 * pi * freq * t) * 0.65 * env;
      } else if (type == 'AIRHORN') {
        sample = (sin(2 * pi * 390 * t) + 0.6 * sin(2 * pi * 780 * t)) * 0.45 * env;
      } else if (type == 'LASER') {
        final freq = 1350 - (t * 2300);
        sample = sin(2 * pi * freq.clamp(110, 1500) * t) * 0.6 * env;
      } else {
        final crack = (t < 0.045) ? sin(2 * pi * 520 * t) * 0.85 : 0.0;
        final roar = (rng.nextDouble() * 2 - 1) * 0.25 * env;
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
        scaffoldBackgroundColor: const Color(0xFF070B14),
        primaryColor: const Color(0xFF00E5FF),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00E5FF),
          secondary: Color(0xFFFFAB00),
          surface: Color(0xFF11192B),
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

class _MasterHomeShellState extends State<MasterHomeShell> {
  int _selectedIndex = 0;

  final List<Widget> _pages = const [
    AudioStudioScreen(),
    CricketCommentaryScreen(),
    VoiceCloneAndProHubScreen(),
    EntryMusicStudioScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1526),
        elevation: 4,
        title: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(colors: [Color(0xFFFFAB00), Color(0xFF00E5FF)]),
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              child: const Icon(Icons.album, color: Colors.black, size: 20),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'DJ Play and Commentry App',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Color(0xFF00E5FF)),
                  ),
                  Text(
                    '320kbps Top 50 • Live Commentary • Smart Entry BGM',
                    style: TextStyle(fontSize: 10, color: Colors.amberAccent),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'DJ Airhorn',
            icon: const Icon(Icons.campaign, color: Colors.amberAccent),
            onPressed: () => AppSoundEngine.playSynthesizedSfx('AIRHORN'),
          ),
        ],
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: _pages,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (idx) => setState(() => _selectedIndex = idx),
        backgroundColor: const Color(0xFF0B1120),
        selectedItemColor: const Color(0xFF00E5FF),
        unselectedItemColor: Colors.white54,
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10),
        unselectedLabelStyle: const TextStyle(fontSize: 10),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.library_music), label: '1. Top 50 Audio'),
          BottomNavigationBarItem(icon: Icon(Icons.sports_cricket), label: '2. Commentary'),
          BottomNavigationBarItem(icon: Icon(Icons.record_voice_over), label: '3. Real Voice'),
          BottomNavigationBarItem(icon: Icon(Icons.bolt), label: '4. Entry & Mixer'),
        ],
      ),
    );
  }
}
