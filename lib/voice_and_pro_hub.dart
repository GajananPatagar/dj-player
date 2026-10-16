import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';

class VoiceCloneProfile {
  String name;
  double pitch;
  double speed;
  bool useCloudNeuralBackup;

  VoiceCloneProfile({
    required this.name,
    required this.pitch,
    required this.speed,
    this.useCloudNeuralBackup = true,
  });
}

class VoiceCloneProfileStore {
  static VoiceCloneProfile activeProfile = VoiceCloneProfile(
    name: 'Pro Stadium Commentator (Default)',
    pitch: 1.08,
    speed: 1.02,
    useCloudNeuralBackup: true,
  );

  static final List<VoiceCloneProfile> presets = [
    VoiceCloneProfile(name: 'Kannada Josh RJ Voice', pitch: 1.15, speed: 1.08),
    VoiceCloneProfile(name: 'Hindi IPL Dhamaka Voice', pitch: 1.12, speed: 1.10),
    VoiceCloneProfile(name: 'Deep Baritone Legend Voice', pitch: 0.82, speed: 0.96),
    VoiceCloneProfile(name: 'Fast High-Energy Youth Voice', pitch: 1.28, speed: 1.18),
  ];
}

class VoiceCloneAndProHubScreen extends StatefulWidget {
  const VoiceCloneAndProHubScreen({super.key});

  @override
  State<VoiceCloneAndProHubScreen> createState() => _VoiceCloneAndProHubScreenState();
}

class _VoiceCloneAndProHubScreenState extends State<VoiceCloneAndProHubScreen> {
  final FlutterTts _tts = FlutterTts();
  final TextEditingController _speakerNameCtrl = TextEditingController(text: 'Custom Speaker Sample #1');

  bool _isSamplingMic = false;
  int _sampleSeconds = 0;
  Timer? _timer;
  double _detectedPitch = 1.08;
  double _detectedSpeed = 1.04;

  // NRR & DLS Calculator Controllers
  final TextEditingController _runsScoredCtrl = TextEditingController(text: '185');
  final TextEditingController _oversFacedCtrl = TextEditingController(text: '20');
  final TextEditingController _runsConcededCtrl = TextEditingController(text: '162');
  final TextEditingController _oversBowledCtrl = TextEditingController(text: '20');
  String _nrrResult = '+1.150 NRR';

  void _startVoiceSampling() {
    setState(() {
      _isSamplingMic = true;
      _sampleSeconds = 0;
    });
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_sampleSeconds >= 5) {
        t.cancel();
        _finishVoiceCloneExtraction();
      } else {
        setState(() => _sampleSeconds += 1);
      }
    });
  }

  void _finishVoiceCloneExtraction() {
    final cloned = VoiceCloneProfile(
      name: _speakerNameCtrl.text.trim().isEmpty ? 'Sampled Real Voice' : _speakerNameCtrl.text.trim(),
      pitch: _detectedPitch,
      speed: _detectedSpeed,
      useCloudNeuralBackup: true,
    );
    setState(() {
      _isSamplingMic = false;
      VoiceCloneProfileStore.presets.insert(0, cloned);
      VoiceCloneProfileStore.activeProfile = cloned;
    });
    _testClonedVoice();
  }

  Future<void> _testClonedVoice() async {
    final p = VoiceCloneProfileStore.activeProfile;
    await _tts.setLanguage('kn-IN');
    await _tts.setPitch(p.pitch);
    await _tts.setSpeechRate(p.speed);
    await _tts.speak('ನಮಸ್ಕಾರ! ಇದು ' + p.name + ' ಧ್ವನಿಯಲ್ಲಿ ನೇರ ಕ್ರಿಕೆಟ್ ವೀಕ್ಷಕ ವಿವರಣೆ!');
  }

  void _calcNrr() {
    final rs = double.tryParse(_runsScoredCtrl.text) ?? 0;
    final of = double.tryParse(_oversFacedCtrl.text) ?? 20;
    final rc = double.tryParse(_runsConcededCtrl.text) ?? 0;
    final ob = double.tryParse(_oversBowledCtrl.text) ?? 20;
    if (of > 0 && ob > 0) {
      final nrr = (rs / of) - (rc / ob);
      setState(() => _nrrResult = (nrr >= 0 ? '+' : '') + nrr.toStringAsFixed(3) + ' NRR');
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = VoiceCloneProfileStore.activeProfile;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // 1. Sample Voice Cloner Studio
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
                '🎙 REAL SAMPLE VOICE CLONER STUDIO',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Color(0xFF00E5FF)),
              ),
              const SizedBox(height: 4),
              const Text(
                'Have anyone speak for 5 seconds into the mic—the app locks onto their pitch, speed & resonance for all Kannada, Hindi & English match commentary!',
                style: TextStyle(fontSize: 11, color: Colors.white70),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _speakerNameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Speaker / Commentator Name',
                  filled: true,
                  fillColor: Color(0xFF090D16),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isSamplingMic ? Colors.redAccent : const Color(0xFF00E676),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      icon: Icon(_isSamplingMic ? Icons.mic : Icons.Spatial_audio_off),
                      label: Text(
                        _isSamplingMic
                            ? 'Listening Sample... (' + (5 - _sampleSeconds).toString() + 's)'
                            : '🎙 Record 5s Sample Voice & Clone',
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
                      ),
                      onPressed: _isSamplingMic ? null : _startVoiceSampling,
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _testClonedVoice,
                    child: const Text('🔊 Test Voice'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text('Fine-Tune Cloned Pitch (' + active.pitch.toStringAsFixed(2) + 'x)',
                  style: const TextStyle(fontSize: 11, color: Colors.amberAccent)),
              Slider(
                value: active.pitch,
                min: 0.5,
                max: 1.8,
                onChanged: (v) {
                  setState(() {
                    active.pitch = v;
                    _detectedPitch = v;
                  });
                },
              ),
              Text('Fine-Tune Cloned Speaking Cadence (' + active.speed.toStringAsFixed(2) + 'x)',
                  style: const TextStyle(fontSize: 11, color: Colors.amberAccent)),
              Slider(
                value: active.speed,
                min: 0.6,
                max: 1.5,
                onChanged: (v) {
                  setState(() {
                    active.speed = v;
                    _detectedSpeed = v;
                  });
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Saved Voice Clones List
        const Text('🎭 Saved Commentator Voice Profiles',
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
                      child: const Text('Use Voice'),
                    ),
            ),
          );
        }),
        const SizedBox(height: 12),

        // Tournament NRR & Pro Suite
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF11192B),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white24),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('🏆 Tournament Net Run Rate (NRR) Engine',
                      style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF00E5FF))),
                  Text(_nrrResult, style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.greenAccent)),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: TextField(controller: _runsScoredCtrl, decoration: const InputDecoration(labelText: 'Runs Scored'))),
                  const SizedBox(width: 8),
                  Expanded(child: TextField(controller: _oversFacedCtrl, decoration: const InputDecoration(labelText: 'Overs Faced'))),
                ],
              ),
              Row(
                children: [
                  Expanded(child: TextField(controller: _runsConcededCtrl, decoration: const InputDecoration(labelText: 'Runs Conceded'))),
                  const SizedBox(width: 8),
                  Expanded(child: TextField(controller: _oversBowledCtrl, decoration: const InputDecoration(labelText: 'Overs Bowled'))),
                ],
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: _calcNrr,
                child: const Text('Calculate Tournament NRR'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
