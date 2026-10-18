import 'dart:math';
import 'package:flutter/material.dart';
import 'main.dart';

class VoiceCloneProfile {
  String name;
  double pitch;
  double speed;
  String catchphrase;
  bool preferCloudVoiceOnly;

  VoiceCloneProfile({
    required this.name,
    required this.pitch,
    required this.speed,
    this.catchphrase = '',
    this.preferCloudVoiceOnly = false,
  });
}

class VoiceCloneProfileStore {
  static VoiceCloneProfile activeProfile = VoiceCloneProfile(
    name: 'Natural Human Studio Voice (1.0x)',
    pitch: 1.00,
    speed: 0.98,
    catchphrase: '',
    preferCloudVoiceOnly: false,
  );

  static final Map<String, String> recordedEventClips = {};

  static final List<VoiceCloneProfile> presets = [
    VoiceCloneProfile(name: 'Natural Human Studio Voice (1.0x)', pitch: 1.00, speed: 0.98),
    VoiceCloneProfile(name: 'Cloud Neural Broadcast Voice (Single)', pitch: 1.00, speed: 1.00, preferCloudVoiceOnly: true),
    VoiceCloneProfile(name: 'Kannada Stadium Commentator', pitch: 0.96, speed: 0.98, catchphrase: 'ಸೂಪರ್ ಶಾಟ್'),
    VoiceCloneProfile(name: 'Hindi IPL Anchor Voice', pitch: 0.98, speed: 1.00, catchphrase: 'क्या बात है'),
  ];
}

class VoiceCloneAndProHubScreen extends StatefulWidget {
  const VoiceCloneAndProHubScreen({super.key});

  @override
  State<VoiceCloneAndProHubScreen> createState() => _VoiceCloneAndProHubScreenState();
}

class _VoiceCloneAndProHubScreenState extends State<VoiceCloneAndProHubScreen> {
  final Random _rng = Random();
  String _selectedEventToRecord = 'SIX';
  bool _isRecordingMic = false;
  String _recordStatus = 'Tap Record to capture real human voice from your microphone';
  String _tossResultBanner = 'Tap Flip Toss to announce live coin toss!';

  double _subBass8118Gain = 0.85;
  double _fire57TopClarity = 0.78;
  final int _crossoverHz = 100;
  final bool _paLimiterActive = true;

  final List<String> _recordableEvents = ['SIX', 'FOUR', 'BOWLED', 'CAUGHT', 'RUN_OUT', 'NO_BALL', 'WIDE', 'DOT'];

  final List<Map<String, String>> _launchpadPads = const [
    {'label': '📢 AIRHORN', 'sfx': 'AIRHORN'},
    {'label': '🔊 S8118 SUB', 'sfx': 'SUB_DROP'},
    {'label': '🥁 DHOL BEAT', 'sfx': 'DHOL'},
    {'label': '🎺 TRUMPET', 'sfx': 'TRUMPET'},
    {'label': '⚡ LASER DROP', 'sfx': 'LASER'},
    {'label': '🏟 CROWD ROAR', 'sfx': 'CROWD'},
    {'label': '🪵 STUMP CRASH', 'sfx': 'BOWLED'},
    {'label': '🚨 NB SIREN', 'sfx': 'NO_BALL'},
    {'label': '💓 DRS HEART', 'sfx': 'HEARTBEAT'},
    {'label': '🔔 BELL GONG', 'sfx': 'BELL'},
    {'label': '🌪 BASS RISER', 'sfx': 'RISER'},
    {'label': '🛑 MUTE ALL', 'sfx': 'MUTE_ALL'},
  ];

  void _flipLiveCoinToss() {
    AppSoundEngine.playSynthesizedSfx('BELL');
    final bool heads = _rng.nextBool();
    final bool batFirst = _rng.nextBool();
    final String side = heads ? 'HEADS' : 'TAILS';
    final String decision = batFirst ? 'ಮೊದಲು ಬ್ಯಾಟಿಂಗ್ (BAT FIRST)' : 'ಮೊದಲು ಬೌಲಿಂಗ್ (BOWL FIRST)';
    setState(() {
      _tossResultBanner = '🪙 TOSS: ' + side + ' — Elected to ' + decision;
    });
    AppSoundEngine.speakRealVoice(
      'ಟಾಸ್ ಪ್ರಕಟಣೆ! ನಾಣ್ಯ ಚಿಮ್ಮಲಾಗಿದೆ... ' + side + ' ಬಂದಿದೆ! ಟಾಸ್ ಗೆದ್ದ ತಂಡ ' + decision + ' ಆಯ್ಕೆ ಮಾಡಿಕೊಂಡಿದೆ!',
      'KANNADA',
    );
  }

  Future<void> _toggleRealMicRecording() async {
    if (!_isRecordingMic) {
      final path = await AppSoundEngine.startMicRecording('real_voice_' + _selectedEventToRecord);
      setState(() {
        _isRecordingMic = true;
        _recordStatus = '🔴 RECORDING REAL VOICE FOR [' + _selectedEventToRecord + ']... Speak now!';
        if (path != null) {
          VoiceCloneProfileStore.recordedEventClips[_selectedEventToRecord] = path;
        }
      });
    } else {
      final savedPath = await AppSoundEngine.stopMicRecording();
      setState(() {
        _isRecordingMic = false;
        if (savedPath != null && savedPath.isNotEmpty) {
          VoiceCloneProfileStore.recordedEventClips[_selectedEventToRecord] = savedPath;
          _recordStatus = '✅ Saved Real Human Voice for [' + _selectedEventToRecord + ']!';
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = VoiceCloneProfileStore.activeProfile;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // 1. PA SYSTEM CROSSOVER & SPEAKER TEST RACK
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFF0F2027), Color(0xFF203A43)]),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.amberAccent, width: 1.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '🔊 PRO PA SYSTEM DSP & SPEAKER TEST RACK',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Colors.amberAccent),
                  ),
                  Chip(
                    backgroundColor: _paLimiterActive ? Colors.green.shade800 : Colors.grey.shade800,
                    label: const Text('PA 7.5 LIMITER ON',
                        style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              Text(
                'S8118 Subwoofer Punch (40Hz–' + _crossoverHz.toString() + 'Hz): ' + (_subBass8118Gain * 100).toInt().toString() + '%',
                style: const TextStyle(fontSize: 11, color: Colors.cyanAccent),
              ),
              Slider(
                value: _subBass8118Gain,
                onChanged: (v) => setState(() => _subBass8118Gain = v),
              ),
              Text(
                'Fire 57 Top Speaker Vocal Clarity (3.5kHz): ' + (_fire57TopClarity * 100).toInt().toString() + '%',
                style: const TextStyle(fontSize: 11, color: Colors.greenAccent),
              ),
              Slider(
                value: _fire57TopClarity,
                onChanged: (v) => setState(() => _fire57TopClarity = v),
              ),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => AppSoundEngine.playSynthesizedSfx('SUB_TEST_50HZ'),
                      child: const Text('🔊 50Hz S8118 Sub Test', style: TextStyle(fontSize: 10)),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => AppSoundEngine.playSynthesizedSfx('TOP_TEST_1KHZ'),
                      child: const Text('📢 1kHz Fire 57 Top Test', style: TextStyle(fontSize: 10)),
                    ),
                  ),
                ],
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Hardware Volume Button Entry Trigger (Pocket Mode)',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                subtitle: const Text('Use phone physical Volume Down/Up buttons to trigger Page 4 Entry BGM',
                    style: TextStyle(fontSize: 10, color: Colors.white70)),
                value: AppSoundEngine.hardwareVolumeEntryMode,
                onChanged: (v) => setState(() => AppSoundEngine.hardwareVolumeEntryMode = v),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // 2. 12-PAD LAUNCHPAD + COIN TOSS SIMULATOR
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFF11192B),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF00E5FF)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('🎛 12-PAD STADIUM & DJ LAUNCHPAD',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF00E5FF))),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, foregroundColor: Colors.black),
                    icon: const Icon(Icons.monetization_on, size: 15),
                    label: const Text('🪙 FLIP TOSS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900)),
                    onPressed: _flipLiveCoinToss,
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(_tossResultBanner, style: const TextStyle(fontSize: 11, color: Colors.greenAccent)),
              ),
              GridView.count(
                crossAxisCount: 4,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
                childAspectRatio: 1.45,
                children: _launchpadPads.map((pad) {
                  final bool isMute = pad['sfx'] == 'MUTE_ALL';
                  return ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isMute ? Colors.red.shade900 : const Color(0xFF1E293B),
                      foregroundColor: Colors.amberAccent,
                      padding: const EdgeInsets.all(4),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: BorderSide(color: isMute ? Colors.redAccent : Colors.cyanAccent),
                      ),
                    ),
                    onPressed: () => AppSoundEngine.playSynthesizedSfx(pad['sfx']!),
                    child: Text(
                      pad['label']!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // 3. REAL HUMAN MIC RECORDER & SINGLE-VOICE STUDIO
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFF1A103C), Color(0xFF0E172A)]),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF00E5FF)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '🎙 REAL HUMAN MIC RECORDER & NATURAL VOICE STUDIO',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: Color(0xFF00E5FF)),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Use Single Cloud Neural Broadcast Stream',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                value: active.preferCloudVoiceOnly,
                onChanged: (v) => setState(() => active.preferCloudVoiceOnly = v),
              ),
              Row(
                children: [
                  const Text('Event to Record: ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  const SizedBox(width: 8),
                  DropdownButton<String>(
                    value: _selectedEventToRecord,
                    items: _recordableEvents
                        .map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(fontWeight: FontWeight.bold))))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setState(() => _selectedEventToRecord = v);
                    },
                  ),
                ],
              ),
              Text(_recordStatus, style: const TextStyle(fontSize: 11, color: Color(0xFF00E676))),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isRecordingMic ? Colors.redAccent : const Color(0xFF00E676),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      icon: Icon(_isRecordingMic ? Icons.stop_circle : Icons.mic),
                      label: Text(
                        _isRecordingMic
                            ? '⏹ STOP & SAVE REAL VOICE'
                            : ('🎙 RECORD REAL VOICE FOR ' + _selectedEventToRecord),
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 11),
                      ),
                      onPressed: _toggleRealMicRecording,
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () {
                      final path = VoiceCloneProfileStore.recordedEventClips[_selectedEventToRecord];
                      if (path != null) {
                        AppSoundEngine.playRecordedFile(path);
                      } else {
                        AppSoundEngine.speakRealVoice('ನಮಸ್ಕಾರ ಗಜಾನನ ಪಟಗಾರ! ಅದ್ಭುತವಾದ ಸಿಕ್ಸರ್!', 'KANNADA');
                      }
                    },
                    child: const Text('🔊 Test'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
