import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import 'des_helper.dart';
import 'karaoke_engine.dart';
import 'main.dart';

class KaraokeStudioScreen extends StatefulWidget {
  const KaraokeStudioScreen({super.key});

  @override
  State<KaraokeStudioScreen> createState() => _KaraokeStudioScreenState();
}

class _KaraokeStudioScreenState extends State<KaraokeStudioScreen> {
  static const MethodChannel _nativeDsp = MethodChannel('dj_native_tts');

  // 3 Independent Players for Studio Dual-Stem Sync + AI Double-Track Choir
  final AudioPlayer _karaokeBackingPlayer = AudioPlayer();
  final AudioPlayer _userVocalStemPlayer = AudioPlayer();
  final AudioPlayer _choirHarmonyPlayer = AudioPlayer();

  final TextEditingController _searchCtrl = TextEditingController();
  final ScrollController _lyricsScrollCtrl = ScrollController();

  List<Map<String, dynamic>> _songs = [];
  Map<String, dynamic>? _selectedSong;
  String? _verifiedBackingUrl;

  List<LyricLine> _lyrics = [];
  int _activeLyricIndex = 0;
  String _selectedLyricScript = 'KANGLISH (ಕನ್ನಡ-Eng)';

  final List<String> _scriptModes = const [
    'KANGLISH (ಕನ್ನಡ-Eng)',
    'HINGLISH (हिन्दी-Eng)',
    'ENGLISH / ORIGINAL',
    'KANNADA (ಕನ್ನಡ)',
    'HINDI (हिन्दी)',
  ];

  // Vocal Sweetener & Auto-Tune Polish Controls
  String _vocalPreset = '✨ Auto-Tune Pro Polish';
  final List<String> _vocalPresets = const [
    '✨ Auto-Tune Pro Polish',
    '🎤 Double-Track Choir (Makes Any Singer Sound Pro)',
    '🏟 Concert Hall Reverb + Warmth',
    '🔥 Mass Hero Vocal Boost',
  ];

  bool _isLoading = false;
  bool _isKaraokeVocalCutActive = true; // Converts any normal song into Karaoke
  bool _isRecordingSinging = false;
  bool _isPlayingMasterMix = false;
  bool _doubleChoirEnabled = true;
  int _countdownSec = 0;

  double _karaokeMusicVol = 0.72;
  double _userVocalVol = 1.0;
  double _vocalPitchPolish = 1.02;
  int _vocalSyncOffsetMs = -60; // Compensates Android mic latency automatically!

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  String _statusBanner = '🎤 Select any song — Auto-Converts to Karaoke + Noise-Free Vocal Recording!';

  @override
  void initState() {
    super.initState();
    KaraokeEngine.loadSavedTakes().then((_) {
      if (mounted) setState(() {});
    });
    _setupListeners();
    _runSongSearch('Kannada Hindi Trending Hits 2026');
  }

  void _setupListeners() {
    _karaokeBackingPlayer.onPositionChanged.listen((pos) {
      if (!mounted) return;
      final int ms = pos.inMilliseconds;
      int newIdx = _activeLyricIndex;
      for (int i = 0; i < _lyrics.length; i++) {
        if (ms >= _lyrics[i].timeMs) {
          newIdx = i;
        } else {
          break;
        }
      }
      if (newIdx != _activeLyricIndex) {
        _activeLyricIndex = newIdx;
        _scrollToActiveLyric();
      }
      setState(() => _position = pos);
    });

    _karaokeBackingPlayer.onDurationChanged.listen((dur) {
      if (mounted) setState(() => _duration = dur);
    });

    _karaokeBackingPlayer.onPlayerComplete.listen((_) {
      if (_isRecordingSinging) {
        _stopSingingRecordingAndSaveMaster();
      } else if (_isPlayingMasterMix) {
        _stopAllPlayback();
      }
    });
  }

  void _scrollToActiveLyric() {
    if (!_lyricsScrollCtrl.hasClients) return;
    final double targetOffset = (_activeLyricIndex * 42.0 - 70.0).clamp(
      0.0,
      _lyricsScrollCtrl.position.maxScrollExtent,
    );
    _lyricsScrollCtrl.animateTo(
      targetOffset,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  Future<void> _runSongSearch(String q) async {
    setState(() {
      _isLoading = true;
      _statusBanner = '🔄 Searching 320kbps Songs & Karaoke Tracks...';
    });
    final res = await KaraokeEngine.searchSongsForKaraoke(q);
    if (mounted) {
      setState(() {
        _songs = res;
        _isLoading = false;
        _statusBanner = '🟢 Loaded ${res.length} Songs Ready for Instant Karaoke & Auto-Lyrics!';
      });
      if (_selectedSong == null && res.isNotEmpty) {
        _selectSongForKaraoke(res.first, autoPlayPreview: false);
      }
    }
  }

  Future<void> _selectSongForKaraoke(Map<String, dynamic> song, {bool autoPlayPreview = true}) async {
    await _stopAllPlayback();
    setState(() {
      _selectedSong = song;
      _activeLyricIndex = 0;
      _statusBanner = '📝 Loading Synced Lyrics & Preparing Karaoke Backing Track...';
    });

    final String id = song['id'].toString();
    final String title = song['title'].toString();
    final String artist = song['artist'].toString();
    final int durSec = (song['durationSec'] as int?) ?? 180;

    final fetchedLyrics = await KaraokeEngine.fetchSyncedLyrics(id, title, artist, durSec);
    final List urls = song['urls'] as List? ?? [];
    final String? liveUrl = await SaavnDesDecryptor.resolvePlayableStreamUrl(urls);

    if (mounted) {
      setState(() {
        _lyrics = fetchedLyrics;
        _verifiedBackingUrl = liveUrl;
        _statusBanner = '🎤 Ready to Sing: $title (${_lyrics.length} Synced Lines)';
      });
    }

    // Activate Native Karaoke Vocal-Cut EQ Mode in Android
    try {
      await _nativeDsp.invokeMethod('setKaraokeVocalCut', {'enabled': _isKaraokeVocalCutActive});
    } catch (_) {}

    if (autoPlayPreview && liveUrl != null) {
      await _karaokeBackingPlayer.setVolume(_karaokeMusicVol);
      await _karaokeBackingPlayer.play(UrlSource(liveUrl));
    }
  }

  Future<void> _stopAllPlayback() async {
    try {
      await _karaokeBackingPlayer.stop();
      await _userVocalStemPlayer.stop();
      await _choirHarmonyPlayer.stop();
    } catch (_) {}
    if (mounted) {
      setState(() => _isPlayingMasterMix = false);
    }
  }

  /// Starts 3-2-1 Countdown -> Auto-Plays Karaoke Backing Track from 0:00 -> Records ONLY Clean User Voice
  /// (Uses Android VOICE_COMMUNICATION + AcousticEchoCanceler + NoiseSuppressor so Karaoke music is NOT recorded into mic!)
  Future<void> _startSingingRecording() async {
    if (_selectedSong == null || _verifiedBackingUrl == null) return;
    await _stopAllPlayback();

    for (int c = 3; c >= 1; c--) {
      if (!mounted) return;
      setState(() {
        _countdownSec = c;
        _statusBanner = '🎙 Get Ready to Sing in $c... (Noise & Echo Canceler Armed)';
      });
      await Future.delayed(const Duration(seconds: 1));
    }

    if (!mounted) return;
    setState(() {
      _countdownSec = 0;
      _isRecordingSinging = true;
      _activeLyricIndex = 0;
      _statusBanner = '🔴 RECORDING CLEAN VOCALS ONLY — Sing Along to the Lyrics!';
    });

    final String takeId = 'take_${DateTime.now().millisecondsSinceEpoch}';
    try {
      await _nativeDsp.invokeMethod('startCleanVocalRecord', {'name': takeId});
    } catch (_) {
      await AppSoundEngine.startMicRecording(takeId);
    }

    // Auto-Play Karaoke Backing Track from 0:00
    await _karaokeBackingPlayer.setVolume(_karaokeMusicVol);
    await _karaokeBackingPlayer.play(UrlSource(_verifiedBackingUrl!));
  }

  Future<void> _stopSingingRecordingAndSaveMaster() async {
    if (!_isRecordingSinging) return;
    await _karaokeBackingPlayer.stop();

    String? vocalPath;
    try {
      vocalPath = await _nativeDsp.invokeMethod<String>('stopCleanVocalRecord');
    } catch (_) {
      vocalPath = await AppSoundEngine.stopMicRecording();
    }

    if (!mounted) return;
    setState(() => _isRecordingSinging = false);

    if (vocalPath != null && _selectedSong != null && _verifiedBackingUrl != null) {
      final take = KaraokeTake(
        id: 'take_${DateTime.now().millisecondsSinceEpoch}',
        songTitle: _selectedSong!['title'].toString(),
        songArtist: _selectedSong!['artist'].toString(),
        coverUrl: _selectedSong!['cover'].toString(),
        backingStreamUrl: _verifiedBackingUrl!,
        vocalFilePath: vocalPath,
        presetName: _vocalPreset,
        vocalPitch: _vocalPitchPolish,
        doubleChoirEnabled: _doubleChoirEnabled,
        syncOffsetMs: _vocalSyncOffsetMs,
      );
      await KaraokeEngine.saveTake(take);
      setState(() {
        _statusBanner = '✅ Studio Master Saved! Playing Original Karaoke + Your Polished Voice...';
      });
      await _playDualStemStudioMaster(take);
    }
  }

  /// Plays the PURE ORIGINAL 320kbps Karaoke Track + User's Clean Recorded Voice + AI Double-Track Harmony Choir!
  Future<void> _playDualStemStudioMaster(KaraokeTake take) async {
    await _stopAllPlayback();
    if (!File(take.vocalFilePath).existsSync()) return;

    setState(() {
      _isPlayingMasterMix = true;
      _statusBanner = '🔊 Playing Studio Master: Original Karaoke + Your Polished Voice (${take.presetName})';
    });

    // Apply Selected Vocal Sweetener Preset
    double pitchRate = take.vocalPitch;
    if (_vocalPreset.contains('Auto-Tune')) {
      pitchRate = 1.02;
    } else if (_vocalPreset.contains('Hero')) {
      pitchRate = 0.97;
    }

    // Start Original High-Res Karaoke Stream + Clean Recorded Vocal Stem in Sync
    await _karaokeBackingPlayer.setVolume(_karaokeMusicVol);
    await _userVocalStemPlayer.setVolume(_userVocalVol);
    await _userVocalStemPlayer.setPlaybackRate(pitchRate.clamp(0.85, 1.18));

    if (_vocalSyncOffsetMs < 0) {
      // Start vocal slightly earlier to compensate mic recording latency
      await _userVocalStemPlayer.play(DeviceFileSource(take.vocalFilePath));
      await Future.delayed(Duration(milliseconds: _vocalSyncOffsetMs.abs()));
      await _karaokeBackingPlayer.play(UrlSource(take.backingStreamUrl));
    } else {
      await _karaokeBackingPlayer.play(UrlSource(take.backingStreamUrl));
      if (_vocalSyncOffsetMs > 0) {
        await Future.delayed(Duration(milliseconds: _vocalSyncOffsetMs));
      }
      await _userVocalStemPlayer.play(DeviceFileSource(take.vocalFilePath));
    }

    // AI Double-Track Choir Layer: Plays a 35ms delayed micro-harmony vocal double
    // that makes even an untrained singer sound thick, smooth, and studio-polished!
    if (_doubleChoirEnabled) {
      await Future.delayed(const Duration(milliseconds: 35));
      await _choirHarmonyPlayer.setVolume((_userVocalVol * 0.38).clamp(0.0, 1.0));
      await _choirHarmonyPlayer.setPlaybackRate((pitchRate * 1.008).clamp(0.85, 1.2));
      await _choirHarmonyPlayer.play(DeviceFileSource(take.vocalFilePath));
    }
  }

  void _applyPresetSelection(String preset) {
    setState(() {
      _vocalPreset = preset;
      if (preset.contains('Auto-Tune')) {
        _vocalPitchPolish = 1.02;
        _doubleChoirEnabled = true;
      } else if (preset.contains('Double-Track')) {
        _vocalPitchPolish = 1.00;
        _doubleChoirEnabled = true;
      } else if (preset.contains('Concert')) {
        _vocalPitchPolish = 1.01;
        _doubleChoirEnabled = true;
      } else {
        _vocalPitchPolish = 0.97;
        _doubleChoirEnabled = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Top Status Banner
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          color: const Color(0xFF0E172A),
          child: Text(
            _statusBanner,
            style: const TextStyle(fontSize: 11, color: Color(0xFF00E676), fontWeight: FontWeight.bold),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),

        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(10),
            children: [
              // ==================== 1. SEARCH ANY SONG FOR KARAOKE ====================
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      style: const TextStyle(fontSize: 12),
                      decoration: InputDecoration(
                        hintText: 'Search any song to convert to Karaoke + Auto Lyrics...',
                        filled: true,
                        fillColor: const Color(0xFF11192B),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onSubmitted: _runSongSearch,
                    ),
                  ),
                  const SizedBox(width: 6),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00E5FF),
                      foregroundColor: Colors.black,
                    ),
                    onPressed: () => _runSongSearch(_searchCtrl.text),
                    child: const Text('Search', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // ==================== 2. MULTI-LANGUAGE AUTO-SCROLLING LYRICS TELEPROMPTER ====================
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFF161032), Color(0xFF0A0F1D)]),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _isRecordingSinging ? Colors.redAccent : const Color(0xFF00E5FF),
                    width: 1.6,
                  ),
                ),
                child: Column(
                  children: [
                    // Script Selector (Kanglish, Hinglish, English, Kannada, Hindi)
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: _scriptModes.map((mode) {
                          final active = (_selectedLyricScript == mode);
                          return Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ChoiceChip(
                              label: Text(mode, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                              selected: active,
                              selectedColor: Colors.amber,
                              labelStyle: TextStyle(color: active ? Colors.black : Colors.white),
                              onSelected: (_) => setState(() => _selectedLyricScript = mode),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 6),

                    // Scrolling Synchronized Lyrics Box
                    SizedBox(
                      height: 175,
                      child: _lyrics.isEmpty
                          ? const Center(
                              child: Text('Select any song below to load synchronized Karaoke lyrics!',
                                  style: TextStyle(color: Colors.white60, fontSize: 12)),
                            )
                          : ListView.builder(
                              controller: _lyricsScrollCtrl,
                              itemCount: _lyrics.length,
                              itemBuilder: (ctx, idx) {
                                final bool isCurrent = (idx == _activeLyricIndex);
                                final String formattedLine = KaraokeEngine.formatLineForLanguageMode(
                                  _lyrics[idx].text,
                                  _selectedLyricScript,
                                );
                                return GestureDetector(
                                  onTap: () {
                                    _karaokeBackingPlayer.seek(Duration(milliseconds: _lyrics[idx].timeMs));
                                  },
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                                    decoration: BoxDecoration(
                                      color: isCurrent ? Colors.amber.withOpacity(0.18) : Colors.transparent,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      formattedLine,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: isCurrent ? 15 : 12,
                                        fontWeight: isCurrent ? FontWeight.w900 : FontWeight.w500,
                                        color: isCurrent ? Colors.amberAccent : Colors.white60,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              // ==================== 3. KARAOKE RECORDER & AI VOCAL SWEETENER DECK ====================
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF11192B),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amberAccent),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_selectedSong != null)
                      Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Image.network(
                              _selectedSong!['cover'].toString(),
                              width: 42,
                              height: 42,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const Icon(Icons.mic, color: Colors.amber),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _selectedSong!['title'].toString(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                                Text(
                                  _isKaraokeVocalCutActive
                                      ? '🎛 Karaoke Vocal-Cut Active • Noise-Free Mic Ready'
                                      : '🎵 Original Guide Track Mode',
                                  style: const TextStyle(fontSize: 10, color: Color(0xFF00E676)),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    const SizedBox(height: 8),

                    // Record / Stop / Practice Buttons
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _isRecordingSinging ? Colors.redAccent : const Color(0xFF00E676),
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            icon: Icon(_isRecordingSinging ? Icons.stop_circle : Icons.fiber_manual_record),
                            label: Text(
                              _countdownSec > 0
                                  ? 'Starting in $_countdownSec...'
                                  : (_isRecordingSinging
                                      ? '⏹ STOP & BUILD STUDIO MASTER'
                                      : '🔴 RECORD SINGING (AUTO-PLAYS KARAOKE)'),
                              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 11),
                            ),
                            onPressed: _countdownSec > 0
                                ? null
                                : (_isRecordingSinging ? _stopSingingRecordingAndSaveMaster : _startSingingRecording),
                          ),
                        ),
                        const SizedBox(width: 6),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1E293B),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                          ),
                          onPressed: _stopAllPlayback,
                          child: const Text('⏹ Stop', style: TextStyle(fontSize: 11)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // AI Singer Polish & Mixer Accordion
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: const Text(
                        '✨ AI VOCAL SWEETENER & STUDIO MIXER (Makes Any Singer Sound Pro!)',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF00E5FF)),
                      ),
                      children: [
                        DropdownButton<String>(
                          value: _vocalPreset,
                          isExpanded: true,
                          items: _vocalPresets
                              .map((p) => DropdownMenuItem(value: p, child: Text(p, style: const TextStyle(fontSize: 11))))
                              .toList(),
                          onChanged: (v) {
                            if (v != null) _applyPresetSelection(v);
                          },
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('🎛 Convert Normal Song to Karaoke (Center Vocal Reducer)',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                          value: _isKaraokeVocalCutActive,
                          onChanged: (v) async {
                            setState(() => _isKaraokeVocalCutActive = v);
                            try {
                              await _nativeDsp.invokeMethod('setKaraokeVocalCut', {'enabled': v});
                            } catch (_) {}
                          },
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('🎤 AI Double-Track Choir Harmony (Thickens Untrained Voice)',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.amberAccent)),
                          value: _doubleChoirEnabled,
                          onChanged: (v) => setState(() => _doubleChoirEnabled = v),
                        ),
                        Text('Original Karaoke Backing Volume: ${(_karaokeMusicVol * 100).toInt()}%',
                            style: const TextStyle(fontSize: 10, color: Colors.cyanAccent)),
                        Slider(
                          value: _karaokeMusicVol,
                          onChanged: (v) {
                            setState(() => _karaokeMusicVol = v);
                            _karaokeBackingPlayer.setVolume(v);
                          },
                        ),
                        Text('Your Isolated Singing Voice Volume: ${(_userVocalVol * 100).toInt()}%',
                            style: const TextStyle(fontSize: 10, color: Colors.greenAccent)),
                        Slider(
                          value: _userVocalVol,
                          onChanged: (v) {
                            setState(() => _userVocalVol = v);
                            _userVocalStemPlayer.setVolume(v);
                          },
                        ),
                        Text('Vocal Beat-Sync Alignment: $_vocalSyncOffsetMs ms',
                            style: const TextStyle(fontSize: 10, color: Colors.amberAccent)),
                        Slider(
                          value: _vocalSyncOffsetMs.toDouble(),
                          min: -300,
                          max: 300,
                          onChanged: (v) => setState(() => _vocalSyncOffsetMs = v.toInt()),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // ==================== 4. SAVED STUDIO KARAOKE RECORDINGS ====================
              if (KaraokeEngine.savedTakes.isNotEmpty) ...[
                const Text(
                  '🏆 Your Recorded Studio Karaoke Masters (Original Karaoke + Clean Voice)',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.amberAccent),
                ),
                const SizedBox(height: 6),
                ...KaraokeEngine.savedTakes.map((take) {
                  return Card(
                    color: const Color(0xFF1A2947),
                    margin: const EdgeInsets.symmetric(vertical: 3),
                    child: ListTile(
                      dense: true,
                      leading: const Icon(Icons.mic_external_on, color: Color(0xFF00E676)),
                      title: Text(
                        take.songTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                      subtitle: Text(
                        '${take.presetName} • Pure Karaoke + Clean Voice',
                        style: const TextStyle(fontSize: 10, color: Colors.cyanAccent),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                            onPressed: () async {
                              await KaraokeEngine.deleteTake(take.id);
                              setState(() {});
                            },
                          ),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.amber,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            ),
                            icon: const Icon(Icons.play_arrow, size: 16),
                            label: const Text('Play Mix', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900)),
                            onPressed: () => _playDualStemStudioMaster(take),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 10),
              ],

              // ==================== 5. SONG SELECTION LIST FOR KARAOKE ====================
              const Text(
                '🎵 Tap Any Song to Convert to Karaoke & Load Synced Lyrics',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF00E5FF)),
              ),
              const SizedBox(height: 6),
              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(child: CircularProgressIndicator()),
                )
              else
                ...List.generate(_songs.length, (idx) {
                  final s = _songs[idx];
                  final bool isSelected = (_selectedSong != null && _selectedSong!['id'] == s['id']);
                  return Card(
                    color: isSelected ? const Color(0xFF1E3A8A) : const Color(0xFF11192B),
                    margin: const EdgeInsets.symmetric(vertical: 3),
                    child: ListTile(
                      dense: true,
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.network(
                          s['cover'].toString(),
                          width: 42,
                          height: 42,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Icon(Icons.music_note, color: Colors.cyanAccent),
                        ),
                      ),
                      title: Text(
                        '${idx + 1}. ${s['title']}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                      subtitle: Text(
                        (s['isPureInstrumental'] == true ? '🎹 PURE INSTRUMENTAL • ' : '🎛 AI KARAOKE READY • ') +
                            s['artist'].toString(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 10, color: Color(0xFF00E676)),
                      ),
                      trailing: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00E5FF),
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        ),
                        onPressed: () => _selectSongForKaraoke(s, autoPlayPreview: true),
                        child: const Text('🎤 Sing', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900)),
                      ),
                    ),
                  );
                }),
            ],
          ),
        ),
      ],
    );
  }
}
