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

  // Maps ball event keys ('SIX', 'FOUR', 'BOWLED', 'CAUGHT', 'RUN_OUT', 'NO_BALL') to real recorded human .m4a file paths
  static final Map<String, String> recordedEventClips = {};

  static final List<VoiceCloneProfile> presets = [
    VoiceCloneProfile(name: 'Natural Human Studio Voice (1.0x)', pitch: 1.00, speed: 0.98, catchphrase: ''),
    VoiceCloneProfile(name: 'Cloud Neural Broadcast Voice (Single)', pitch: 1.00, speed: 1.00, catchphrase: '', preferCloudVoiceOnly: true),
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
  final TextEditingController _speakerNameCtrl = TextEditingController(text: 'My Real Voice Profile');
  final TextEditingController _catchphraseCtrl = TextEditingController(text: '');

  String _selectedEventToRecord = 'SIX';
  bool _isRecordingMic = false;
  String _recordStatus = 'Tap Record to capture real human voice from your microphone';

  final List<String> _recordableEvents = ['SIX', 'FOUR', 'BOWLED', 'CAUGHT', 'RUN_OUT', 'NO_BALL', 'WIDE', 'DOT'];

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
        } else {
          _recordStatus = '✅ Voice Profile Calibrated!';
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
        // 1. Real Human Microphone Recorder & Single-Voice Engine Control
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
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Color(0xFF00E5FF)),
              ),
              const SizedBox(height: 4),
              const Text(
                'Zero Double-Voice Echo! Record anyone speaking into the mic for any cricket shot/wicket—or switch between Single Device Neural Voice and Single Cloud Broadcast Voice.',
                style: TextStyle(fontSize: 11, color: Colors.white70),
              ),
              const SizedBox(height: 10),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Use Cloud Neural Broadcast Stream (Single Voice)',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                subtitle: const Text('OFF = Android HD Neural Voice • ON = Cloud Neural Stream (Never plays both together)',
                    style: TextStyle(fontSize: 10, color: Colors.amberAccent)),
                value: active.preferCloudVoiceOnly,
                onChanged: (v) => setState(() => active.preferCloudVoiceOnly = v),
              ),
              const Divider(color: Colors.white24),
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
                  const Spacer(),
                  if (VoiceCloneProfileStore.recordedEventClips.containsKey(_selectedEventToRecord))
                    TextButton.icon(
                      icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 16),
                      label: const Text('Clear Clip', style: TextStyle(fontSize: 11, color: Colors.redAccent)),
                      onPressed: () {
                        setState(() {
                          VoiceCloneProfileStore.recordedEventClips.remove(_selectedEventToRecord);
                        });
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
                            : '🎙 RECORD REAL VOICE FOR ' + _selectedEventToRecord,
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
                        AppSoundEngine.speakRealVoice(
                          'ಅದ್ಭುತವಾದ ಸಿಕ್ಸರ್! ನೇರ ಕ್ರಿಕೆಟ್ ವೀಕ್ಷಕ ವಿವರಣೆ!',
                          'KANNADA',
                        );
                      }
                    },
                    child: const Text('🔊 Play Test'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text('Natural Voice Pitch (' + active.pitch.toStringAsFixed(2) + 'x — 1.00 is Natural Human)',
                  style: const TextStyle(fontSize: 11, color: Colors.amberAccent)),
              Slider(
                value: active.pitch,
                min: 0.75,
                max: 1.25,
                onChanged: (v) => setState(() => active.pitch = v),
              ),
              Text('Natural Speaking Speed (' + active.speed.toStringAsFixed(2) + 'x — 0.98 is Natural Human)',
                  style: const TextStyle(fontSize: 11, color: Colors.amberAccent)),
              Slider(
                value: active.speed,
                min: 0.75,
                max: 1.25,
                onChanged: (v) => setState(() => active.speed = v),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // 2. Instant Stadium & DJ FX Pad
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFF11192B),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.amber),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('🎛 STADIUM & DJ FX SOUNDBOARD',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.amberAccent)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ElevatedButton(
                    onPressed: () => AppSoundEngine.playSynthesizedSfx('AIRHORN'),
                    child: const Text('📢 DJ Airhorn'),
                  ),
                  ElevatedButton(
                    onPressed: () => AppSoundEngine.playSynthesizedSfx('LASER'),
                    child: const Text('⚡ Laser Drop'),
                  ),
                  ElevatedButton(
                    onPressed: () => AppSoundEngine.playSynthesizedSfx('CROWD'),
                    child: const Text('🏟 Crowd Roar'),
                  ),
                  ElevatedButton(
                    onPressed: () => AppSoundEngine.playSynthesizedSfx('BOWLED'),
                    child: const Text('🪵 Stump Crash'),
                  ),
                  ElevatedButton(
                    onPressed: () => AppSoundEngine.playSynthesizedSfx('NO_BALL'),
                    child: const Text('🚨 No-Ball Siren'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // 3. Voice Presets
        const Text('🎭 Natural Commentator Voice Presets',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.amber)),
        const SizedBox(height: 6),
        ...VoiceCloneProfileStore.presets.map((p) {
          final isSelected = (p.name == active.name);
          return Card(
            color: isSelected ? const Color(0xFF1E3A8A) : const Color(0xFF11192B),
            child: ListTile(
              leading: const Icon(Icons.record_voice_over, color: Color(0xFF00E5FF)),
              title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              subtitle: Text('Pitch: ' + p.pitch.toStringAsFixed(2) + 'x • Speed: ' + p.speed.toStringAsFixed(2) + 'x'),
              trailing: isSelected
                  ? const Chip(label: Text('ACTIVE', style: TextStyle(fontSize: 10)))
                  : TextButton(
                      onPressed: () => setState(() => VoiceCloneProfileStore.activeProfile = p),
                      child: const Text('Select'),
                    ),
            ),
          );
        }),
      ],
    );
  }
}
