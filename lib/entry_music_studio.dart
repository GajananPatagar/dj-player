import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'entry_music_data.dart';
import 'main.dart';

class EntryMusicStudioScreen extends StatefulWidget {
  const EntryMusicStudioScreen({super.key});

  @override
  State<EntryMusicStudioScreen> createState() => _EntryMusicStudioScreenState();
}

class _EntryMusicStudioScreenState extends State<EntryMusicStudioScreen> {
  final AudioPlayer _entryPlayer = AudioPlayer();
  final TextEditingController _extractSearchCtrl = TextEditingController();

  List<Map<String, dynamic>> _entryTracks = [];
  int _currentIndex = 0;
  bool _isPlaying = false;
  bool _isLoading = false;
  bool _isZeroArmed = true; // True whenever Entry Volume is at 0%
  bool _hasTriggeredOnce = false;
  bool _autoSeekToBassDrop = false;
  int _bassDropOffsetSec = 15;
  String _selectedCategory = 'ALL_1000';
  String _statusText = '⚡ Turn Entry Volume Up From 0% to Auto-Play Entry BGM!';

  final List<Map<String, String>> _categories = const [
    {'key': 'ALL_1000', 'label': '🔥 Daily 1000+ Entry BGMs'},
    {'key': 'HERO_ENTRY', 'label': '👑 Hero Walkout (KGF/Salaar)'},
    {'key': 'SIXER_DROP', 'label': '6️⃣ Sixer Bass Drops'},
    {'key': 'FOUR_HORN', 'label': '4️⃣ Boundary Horns'},
    {'key': 'WICKET_OUT', 'label': '🎯 Wicket / Out BGM'},
    {'key': 'ENCOURAGE', 'label': '💪 Player Encourage'},
    {'key': 'KANNADA_MASS', 'label': '🎺 Kannada Mass BGMs'},
  ];

  @override
  void initState() {
    super.initState();
    _entryPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() => _isPlaying = (state == PlayerState.playing));
      }
    });
    _entryPlayer.onPlayerComplete.listen((_) {
      _playNextEntryTrack();
    });
    _loadCategoryTracks('ALL_1000', append: false);
  }

  Future<void> _loadCategoryTracks(String catKey, {required bool append, String? customQuery}) async {
    if (mounted) {
      setState(() {
        _selectedCategory = catKey;
        _isLoading = true;
        _statusText = '🔄 Auto-Extracting High-Bass Entry Tracks Online...';
      });
    }

    final fetched = await EntryMusicHarvester.fetchEntryTracks(
      categoryKey: catKey,
      customQuery: customQuery,
      loadNextBatch: append,
    );

    if (mounted) {
      setState(() {
        if (append) {
          final existingIds = _entryTracks.map((e) => e['id']).toSet();
          for (final item in fetched) {
            if (!existingIds.contains(item['id'])) {
              _entryTracks.add(item);
            }
          }
        } else {
          if (fetched.isNotEmpty) {
            _entryTracks = fetched;
            _currentIndex = 0;
          }
        }
        _isLoading = false;
        _statusText = '🟢 Ready: ' +
            _entryTracks.length.toString() +
            ' Entry Tracks Loaded (Slide Volume > 0% to Auto-Play!)';
      });
    }
  }

  /// Smart Zero-Crossing Fader Logic:
  /// 0% -> Up = Plays Current Entry Sound
  /// Up -> 0% = Stops & Arms Next Track
  /// 0% -> Up Again = Automatically Switches & Plays NEXT Entry Sound!
  void _onEntryVolumeSliderChanged(double newVol) {
    MasterVolumeController.page4EntryVolume.value = newVol;

    if (newVol <= 0.01) {
      _entryPlayer.setVolume(0.0);
      if (!_isZeroArmed) {
        _entryPlayer.pause();
        setState(() {
          _isZeroArmed = true;
          _statusText = '🎯 Armed at 0%! Turn Volume Up to Auto-Play NEXT Entry BGM!';
        });
      }
      return;
    }

    // Volume is > 0.01
    _entryPlayer.setVolume(newVol);
    if (_isZeroArmed) {
      _isZeroArmed = false;
      if (_entryTracks.isEmpty) return;

      if (!_hasTriggeredOnce) {
        _hasTriggeredOnce = true;
        _playEntryTrackAtIndex(_currentIndex, forceVolume: newVol);
      } else {
        final int nextIdx = (_currentIndex + 1) % _entryTracks.length;
        _playEntryTrackAtIndex(nextIdx, forceVolume: newVol);
      }
    } else {
      setState(() {});
    }
  }

  Future<void> _playEntryTrackAtIndex(int index, {double? forceVolume}) async {
    if (_entryTracks.isEmpty || index < 0 || index >= _entryTracks.length) return;

    final double activeVol = forceVolume ??
        (MasterVolumeController.page4EntryVolume.value <= 0.02
            ? 0.85
            : MasterVolumeController.page4EntryVolume.value);

    if (MasterVolumeController.page4EntryVolume.value <= 0.02) {
      MasterVolumeController.page4EntryVolume.value = activeVol;
      _isZeroArmed = false;
      _hasTriggeredOnce = true;
    }

    setState(() {
      _currentIndex = index;
      _statusText = '🔥 Playing Entry BGM: ' + _entryTracks[index]['title'].toString();
    });

    final track = _entryTracks[index];
    final List urls = track['urls'] as List? ?? [];
    for (final u in urls) {
      try {
        await _entryPlayer.stop();
        await _entryPlayer.setVolume(activeVol);
        await _entryPlayer.play(UrlSource(u.toString()));
        if (_autoSeekToBassDrop) {
          final int dur = (track['durationSec'] as int?) ?? 120;
          if (dur > _bassDropOffsetSec + 15) {
            await _entryPlayer.seek(Duration(seconds: _bassDropOffsetSec));
          }
        }
        return;
      } catch (_) {}
    }
  }

  void _playNextEntryTrack() {
    if (_entryTracks.isEmpty) return;
    _playEntryTrackAtIndex((_currentIndex + 1) % _entryTracks.length);
  }

  void _playPrevEntryTrack() {
    if (_entryTracks.isEmpty) return;
    _playEntryTrackAtIndex((_currentIndex - 1 + _entryTracks.length) % _entryTracks.length);
  }

  @override
  Widget build(BuildContext context) {
    final currentTrack = (_entryTracks.isNotEmpty && _currentIndex < _entryTracks.length)
        ? _entryTracks[_currentIndex]
        : null;
    final double entryVol = MasterVolumeController.page4EntryVolume.value;

    return Column(
      children: [
        // Top Status Strip
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          color: const Color(0xFF0E172A),
          child: Text(
            _statusText,
            style: const TextStyle(fontSize: 11, color: Color(0xFF00E676), fontWeight: FontWeight.bold),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),

        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(10),
            children: [
              // ==================== 1. SMART ENTRY VOLUME TRIGGER & MASTER MIXER ====================
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFF1E1136), Color(0xFF0D1526)]),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: entryVol > 0.01 ? const Color(0xFF00E676) : Colors.amber,
                    width: 1.8,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Expanded(
                          child: Text(
                            '🚀 SMART ENTRY MUSIC AUTO-FADER (0% ➔ UP = PLAY NEXT)',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Colors.amberAccent),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: entryVol > 0.01 ? Colors.green.shade800 : Colors.red.shade900,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            entryVol > 0.01
                                ? 'LIVE ' + (entryVol * 100).toInt().toString() + '%'
                                : 'ARMED AT 0%',
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Slide up from 0% to instantly blast Entry Music! Pull back to 0% and slide up again to automatically play the NEXT Entry BGM!',
                      style: TextStyle(fontSize: 10, color: Colors.white70),
                    ),
                    Row(
                      children: [
                        IconButton(
                          tooltip: 'Mute to 0% (Arms Next Track)',
                          icon: Icon(
                            entryVol <= 0.01 ? Icons.volume_off : Icons.volume_up,
                            color: entryVol <= 0.01 ? Colors.redAccent : const Color(0xFF00E676),
                          ),
                          onPressed: () => _onEntryVolumeSliderChanged(0.0),
                        ),
                        Expanded(
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 8,
                              activeTrackColor: const Color(0xFF00E676),
                              thumbColor: Colors.amber,
                            ),
                            child: Slider(
                              value: entryVol.clamp(0.0, 1.0),
                              min: 0.0,
                              max: 1.0,
                              onChanged: _onEntryVolumeSliderChanged,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () => _onEntryVolumeSliderChanged(1.0),
                          child: const Text('MAX', style: TextStyle(fontWeight: FontWeight.w900, color: Colors.amber)),
                        ),
                      ],
                    ),

                    // Current Entry Track Deck + Play / Pause / Next / Bass-Drop Skip
                    if (currentTrack != null)
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF090E1A),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: Image.network(
                                currentTrack['cover'].toString(),
                                width: 44,
                                height: 44,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const Icon(Icons.bolt, color: Colors.amber),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '#' + (_currentIndex + 1).toString() + ' ' + currentTrack['title'].toString(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                  ),
                                  Text(
                                    currentTrack['artist'].toString(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 10, color: Colors.cyanAccent),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.skip_previous, size: 22),
                              onPressed: _playPrevEntryTrack,
                            ),
                            CircleAvatar(
                              radius: 18,
                              backgroundColor: const Color(0xFF00E5FF),
                              child: IconButton(
                                padding: EdgeInsets.zero,
                                icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.black),
                                onPressed: () {
                                  if (_isPlaying) {
                                    _entryPlayer.pause();
                                  } else {
                                    _playEntryTrackAtIndex(_currentIndex);
                                  }
                                },
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.skip_next, size: 22),
                              onPressed: _playNextEntryTrack,
                            ),
                          ],
                        ),
                      ),

                    const SizedBox(height: 8),
                    // Master Volume Sliders for Page 1, Page 2, and Page 3
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: const Text(
                        '🎚 ALL-PAGE MASTER VOLUME CONTROLLER (Page 1, 2 & SFX)',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF00E5FF)),
                      ),
                      children: [
                        _buildMasterVolumeRow(
                          '🎧 Page 1: World DJ Audio Volume',
                          MasterVolumeController.page1MusicVolume,
                          Colors.cyanAccent,
                        ),
                        _buildMasterVolumeRow(
                          '🎙 Page 2: Commentary Voice Volume',
                          MasterVolumeController.page2VoiceVolume,
                          Colors.amberAccent,
                        ),
                        _buildMasterVolumeRow(
                          '🏟 Page 3: Stadium Crowd & Horn SFX',
                          MasterVolumeController.page3SfxVolume,
                          Colors.pinkAccent,
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('⚡ Auto-Skip Intro Straight to Bass Drop (+15s)',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                          value: _autoSeekToBassDrop,
                          onChanged: (v) => setState(() => _autoSeekToBassDrop = v),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // ==================== 2. QUICK STADIUM ENCOURAGE PADS (6 / 4 / OUT / ENTRY) ====================
              Row(
                children: [
                  _quickTriggerButton('👑 HERO ENTRY', Colors.amber.shade800, () {
                    _loadCategoryTracks('HERO_ENTRY', append: false);
                  }),
                  const SizedBox(width: 5),
                  _quickTriggerButton('6️⃣ SIXER BASS', Colors.deepPurpleAccent, () {
                    _loadCategoryTracks('SIXER_DROP', append: false);
                  }),
                  const SizedBox(width: 5),
                  _quickTriggerButton('4️⃣ FOUR HORN', Colors.blueAccent, () {
                    _loadCategoryTracks('FOUR_HORN', append: false);
                  }),
                  const SizedBox(width: 5),
                  _quickTriggerButton('🎯 OUT BGM', Colors.redAccent, () {
                    _loadCategoryTracks('WICKET_OUT', append: false);
                  }),
                ],
              ),
              const SizedBox(height: 8),

              // ==================== 3. ONLINE AUTO-EXTRACTOR SEARCH BAR ====================
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _extractSearchCtrl,
                      style: const TextStyle(fontSize: 12),
                      decoration: InputDecoration(
                        hintText: 'Extract any movie BGM, KGF, Salaar, IPL or player entry song...',
                        filled: true,
                        fillColor: const Color(0xFF11192B),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onSubmitted: (v) => _loadCategoryTracks('CUSTOM', append: false, customQuery: v),
                    ),
                  ),
                  const SizedBox(width: 6),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00E5FF),
                      foregroundColor: Colors.black,
                    ),
                    onPressed: () => _loadCategoryTracks('CUSTOM', append: false, customQuery: _extractSearchCtrl.text),
                    child: const Text('Extract', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Category Filter Chips
              SizedBox(
                height: 34,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _categories.length,
                  itemBuilder: (ctx, i) {
                    final cat = _categories[i];
                    final selected = (_selectedCategory == cat['key']);
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(cat['label']!, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        selected: selected,
                        selectedColor: Colors.amber,
                        labelStyle: TextStyle(color: selected ? Colors.black : Colors.white),
                        onSelected: (_) => _loadCategoryTracks(cat['key']!, append: false),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),

              // ==================== 4. ALL ENTRY SOUNDS LIST + LOAD MORE ====================
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '🎵 Auto-Extracted Entry Queue (' + _entryTracks.length.toString() + '+ Tracks)',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.amberAccent),
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.add_circle_outline, size: 16, color: Color(0xFF00E5FF)),
                    label: const Text('Load +100 More Online', style: TextStyle(fontSize: 11, color: Color(0xFF00E5FF))),
                    onPressed: () => _loadCategoryTracks(_selectedCategory, append: true),
                  ),
                ],
              ),

              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.all(24.0),
                  child: Center(child: CircularProgressIndicator()),
                )
              else
                ...List.generate(_entryTracks.length, (idx) {
                  final trk = _entryTracks[idx];
                  final isCurrent = (idx == _currentIndex);
                  return Card(
                    color: isCurrent ? const Color(0xFF1E3A8A) : const Color(0xFF11192B),
                    margin: const EdgeInsets.symmetric(vertical: 3),
                    child: ListTile(
                      dense: true,
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.network(
                          trk['cover'].toString(),
                          width: 42,
                          height: 42,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Icon(Icons.music_note, color: Colors.amber),
                        ),
                      ),
                      title: Text(
                        '#' + (idx + 1).toString() + ' • ' + trk['title'].toString(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                      subtitle: Text(
                        trk['artist'].toString() + ' • BASS ENTRY READY',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 10, color: Color(0xFF00E676)),
                      ),
                      trailing: IconButton(
                        icon: Icon(
                          (isCurrent && _isPlaying) ? Icons.pause_circle_filled : Icons.play_circle_fill,
                          color: Colors.amberAccent,
                          size: 30,
                        ),
                        onPressed: () {
                          if (isCurrent && _isPlaying) {
                            _entryPlayer.pause();
                          } else {
                            _playEntryTrackAtIndex(idx);
                          }
                        },
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

  Widget _buildMasterVolumeRow(String label, ValueNotifier<double> notifier, Color color) {
    return ValueListenableBuilder<double>(
      valueListenable: notifier,
      builder: (context, val, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(label, style: const TextStyle(fontSize: 11, color: Colors.white70)),
                Text((val * 100).toInt().toString() + '%',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color)),
              ],
            ),
            Slider(
              value: val.clamp(0.0, 1.0),
              min: 0.0,
              max: 1.0,
              activeColor: color,
              onChanged: (v) => notifier.value = v,
            ),
          ],
        );
      },
    );
  }

  Widget _quickTriggerButton(String label, Color bg, VoidCallback onTap) {
    return Expanded(
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        onPressed: onTap,
        child: Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900)),
      ),
    );
  }
}
