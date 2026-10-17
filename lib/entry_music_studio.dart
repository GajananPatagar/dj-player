import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'entry_music_data.dart';

class EntryMusicStudioScreen extends StatefulWidget {
  const EntryMusicStudioScreen({super.key});

  @override
  State<EntryMusicStudioScreen> createState() => _EntryMusicStudioScreenState();
}

class _EntryMusicStudioScreenState extends State<EntryMusicStudioScreen> {
  final AudioPlayer _entryPlayer = AudioPlayer();
  final TextEditingController _extractSearchCtrl = TextEditingController();

  // Separate Search/Category List vs Locked Active Queue (Fixes Playing Glitch!)
  List<Map<String, dynamic>> _onlineEntryTracks = [];
  List<Map<String, dynamic>> _favEntryTracks = [];
  List<Map<String, dynamic>> _offlineEntryTracks = [];
  List<Map<String, dynamic>> _activeEntryQueue = [];
  Map<String, dynamic>? _nowPlayingEntry;
  int _queueCursor = 0;

  String _viewTab = 'ONLINE'; // ONLINE, FAV, OFFLINE
  String _selectedCategory = 'ALL_1000';
  String _statusText = '⚡ Turn Entry Volume Up From 0% to Auto-Play Famous Entry BGM!';

  bool _isPlaying = false;
  bool _isLoading = false;
  bool _isZeroArmed = true;
  bool _hasTriggeredOnce = false;
  bool _smartAutoCutEnabled = true;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  final List<Map<String, String>> _categories = const [
    {'key': 'ALL_1000', 'label': '🔥 Famous Entry BGMs'},
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
    _entryPlayer.onPositionChanged.listen((pos) {
      if (mounted) setState(() => _position = pos);
    });
    _entryPlayer.onDurationChanged.listen((dur) {
      if (mounted) setState(() => _duration = dur);
    });
    _entryPlayer.onPlayerComplete.listen((_) {
      _playNextInEntryQueue();
    });
    _loadSavedEntryVaults();
    _loadCategoryTracks('ALL_1000', append: false);
  }

  Future<void> _loadSavedEntryVaults() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final favRaw = prefs.getStringList('entry_fav_v24') ?? [];
      final offRaw = prefs.getStringList('entry_offline_v24') ?? [];
      if (mounted) {
        setState(() {
          _favEntryTracks = favRaw.map((e) => Map<String, dynamic>.from(jsonDecode(e))).toList();
          _offlineEntryTracks = offRaw.map((e) => Map<String, dynamic>.from(jsonDecode(e))).toList();
        });
      }
    } catch (_) {}
  }

  List<Map<String, dynamic>> _currentVisibleList() {
    if (_viewTab == 'FAV') return _favEntryTracks;
    if (_viewTab == 'OFFLINE') return _offlineEntryTracks;
    return _onlineEntryTracks;
  }

  Future<void> _loadCategoryTracks(String catKey, {required bool append, String? customQuery}) async {
    if (mounted) {
      setState(() {
        _viewTab = 'ONLINE';
        _selectedCategory = catKey;
        _isLoading = true;
        _statusText = '🔄 Extracting Famous High-Bass Entry Tracks...';
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
          final existingIds = _onlineEntryTracks.map((e) => e['id']).toSet();
          for (final item in fetched) {
            if (!existingIds.contains(item['id'])) {
              _onlineEntryTracks.add(item);
            }
          }
        } else if (fetched.isNotEmpty) {
          _onlineEntryTracks = fetched;
          if (_activeEntryQueue.isEmpty) {
            _activeEntryQueue = List<Map<String, dynamic>>.from(fetched);
            _queueCursor = 0;
          }
        }
        _isLoading = false;
        _statusText = '🟢 ' +
            _onlineEntryTracks.length.toString() +
            ' Famous Entry BGMs Ready (Slide Volume > 0% to Auto-Play!)';
      });
    }
  }

  /// Smart Zero-Crossing Volume Fader:
  /// 0% -> Up = Plays Entry Track from its exact Smart Entry Drop Point!
  /// Up -> 0% = Pauses & Arms Next Entry Track in active queue!
  /// 0% -> Up Again = Automatically switches to & blasts the NEXT Entry Track!
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

    _entryPlayer.setVolume(newVol);
    if (_isZeroArmed) {
      _isZeroArmed = false;
      final sourceList = _activeEntryQueue.isNotEmpty ? _activeEntryQueue : _currentVisibleList();
      if (sourceList.isEmpty) return;
      _activeEntryQueue = List<Map<String, dynamic>>.from(sourceList);

      if (!_hasTriggeredOnce) {
        _hasTriggeredOnce = true;
        _playQueueIndex(_queueCursor, forceVolume: newVol);
      } else {
        final int nextIdx = (_queueCursor + 1) % _activeEntryQueue.length;
        _playQueueIndex(nextIdx, forceVolume: newVol);
      }
    } else {
      setState(() {});
    }
  }

  Future<void> _startEntryFromVisibleList(int visibleIdx) async {
    final visible = _currentVisibleList();
    if (visibleIdx < 0 || visibleIdx >= visible.length) return;
    _activeEntryQueue = List<Map<String, dynamic>>.from(visible);
    await _playQueueIndex(visibleIdx);
  }

  Future<void> _playQueueIndex(int qIdx, {double? forceVolume}) async {
    if (_activeEntryQueue.isEmpty || qIdx < 0 || qIdx >= _activeEntryQueue.length) return;

    final double activeVol = forceVolume ??
        (MasterVolumeController.page4EntryVolume.value <= 0.02
            ? 0.90
            : MasterVolumeController.page4EntryVolume.value);

    if (MasterVolumeController.page4EntryVolume.value <= 0.02) {
      MasterVolumeController.page4EntryVolume.value = activeVol;
      _isZeroArmed = false;
      _hasTriggeredOnce = true;
    }

    final track = _activeEntryQueue[qIdx];
    final String id = track['id'].toString();
    final String title = track['title'].toString();
    final int durSec = (track['durationSec'] as int?) ?? 120;
    final int smartDropSec = EntryMusicHarvester.computeSmartEntryDropSecond(id, title, durSec);

    if (mounted) {
      setState(() {
        _queueCursor = qIdx;
        _nowPlayingEntry = Map<String, dynamic>.from(track);
        _nowPlayingEntry!['smartDropSec'] = smartDropSec;
        _statusText = '🔥 Playing Entry: ' +
            title +
            (_smartAutoCutEnabled && smartDropSec > 0 ? ' (Auto-Cut @ ' + smartDropSec.toString() + 's)' : '');
      });
    }

    // 1. Play from Offline Entry Vault if downloaded
    if (track['isOffline'] == true && track['localPath'] != null) {
      final file = File(track['localPath'].toString());
      if (await file.exists()) {
        await _entryPlayer.stop();
        await _entryPlayer.setVolume(activeVol);
        await _entryPlayer.play(DeviceFileSource(file.path));
        if (_smartAutoCutEnabled && smartDropSec > 0) {
          await _entryPlayer.seek(Duration(seconds: smartDropSec));
        }
        return;
      }
    }

    // 2. Stream High-Res Online Entry BGM
    final List urls = track['urls'] as List? ?? [];
    for (final u in urls) {
      try {
        await _entryPlayer.stop();
        await _entryPlayer.setVolume(activeVol);
        await _entryPlayer.play(UrlSource(u.toString()));
        if (_smartAutoCutEnabled && smartDropSec > 0 && (durSec == 0 || durSec > smartDropSec + 8)) {
          await _entryPlayer.seek(Duration(seconds: smartDropSec));
        }
        return;
      } catch (_) {}
    }
  }

  void _playNextInEntryQueue() {
    if (_activeEntryQueue.isEmpty) return;
    _playQueueIndex((_queueCursor + 1) % _activeEntryQueue.length);
  }

  void _playPrevInEntryQueue() {
    if (_activeEntryQueue.isEmpty) return;
    _playQueueIndex((_queueCursor - 1 + _activeEntryQueue.length) % _activeEntryQueue.length);
  }

  /// Locks the current playback second as the permanent Entry Drop point for this song!
  Future<void> _lockCurrentPositionAsEntryDrop() async {
    if (_nowPlayingEntry == null) return;
    final String id = _nowPlayingEntry!['id'].toString();
    final int sec = _position.inSeconds;
    await EntryMusicHarvester.saveCustomCue(id, sec);
    setState(() {
      _nowPlayingEntry!['smartDropSec'] = sec;
      for (final list in [_onlineEntryTracks, _favEntryTracks, _offlineEntryTracks, _activeEntryQueue]) {
        for (final item in list) {
          if (item['id'].toString() == id) {
            item['smartDropSec'] = sec;
          }
        }
      }
      _statusText = '📍 Locked Entry Drop at ' + _fmtSec(sec) + ' for ' + _nowPlayingEntry!['title'].toString();
    });
  }

  Future<void> _toggleEntryFavorite(Map<String, dynamic> track) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList('entry_fav_v24') ?? [];
    final exists = raw.any((e) => jsonDecode(e)['id'] == track['id']);
    if (exists) {
      raw.removeWhere((e) => jsonDecode(e)['id'] == track['id']);
    } else {
      raw.insert(0, jsonEncode(track));
    }
    await prefs.setStringList('entry_fav_v24', raw);
    await _loadSavedEntryVaults();
  }

  Future<void> _downloadEntryTrackOffline(Map<String, dynamic> track) async {
    final List urls = track['urls'] as List? ?? [];
    if (urls.isEmpty) return;

    if (mounted) {
      setState(() => _statusText = '⬇ Downloading Entry BGM Offline: ' + track['title'].toString());
    }

    for (final rawUrl in urls) {
      try {
        final res = await http.get(Uri.parse(rawUrl.toString())).timeout(const Duration(seconds: 35));
        if (res.statusCode == 200 && res.bodyBytes.length > 25000) {
          final dir = await getApplicationDocumentsDirectory();
          final safeId = track['id'].toString().replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
          final file = File(dir.path + '/entry_bgm_' + safeId + '.mp4');
          await file.writeAsBytes(res.bodyBytes);

          final offlineEntry = {
            ...track,
            'localPath': file.path,
            'isOffline': true,
          };

          final prefs = await SharedPreferences.getInstance();
          final raw = prefs.getStringList('entry_offline_v24') ?? [];
          raw.removeWhere((e) => jsonDecode(e)['id'] == track['id']);
          raw.insert(0, jsonEncode(offlineEntry));
          await prefs.setStringList('entry_offline_v24', raw);
          await _loadSavedEntryVaults();

          if (mounted) {
            setState(() => _statusText = '✅ Saved to Offline Entry Playlist: ' + track['title'].toString());
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Entry Sound Saved Offline: ' + track['title'].toString())),
            );
          }
          return;
        }
      } catch (_) {}
    }
  }

  String _fmtSec(int sec) {
    final int m = sec ~/ 60;
    final int s = sec % 60;
    return m.toString() + ':' + (s < 10 ? '0' + s.toString() : s.toString());
  }

  @override
  Widget build(BuildContext context) {
    final visibleList = _currentVisibleList();
    final playingTrack = _nowPlayingEntry;
    final String? playingId = playingTrack?['id']?.toString();
    final double entryVol = MasterVolumeController.page4EntryVolume.value;

    return Column(
      children: [
        // Top Status Strip
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          color: const Color(0xFF0E172A),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  _statusText,
                  style: const TextStyle(fontSize: 11, color: Color(0xFF00E676), fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '❤️ ' + _favEntryTracks.length.toString() + '  📥 ' + _offlineEntryTracks.length.toString(),
                style: const TextStyle(fontSize: 11, color: Colors.amberAccent, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),

        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(10),
            children: [
              // ==================== 1. SMART ENTRY VOLUME TRIGGER & LOCKED DECK ====================
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
                            '🚀 SMART ENTRY VOLUME AUTO-FADER (0% ➔ UP = PLAY NEXT)',
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
                    Row(
                      children: [
                        IconButton(
                          tooltip: 'Reset to 0% (Arms Next Track)',
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

                    // Locked Now-Playing Entry Deck + Seek Bar + Custom Drop Lock
                    if (playingTrack != null)
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF090E1A),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.cyanAccent.withOpacity(0.5)),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: Image.network(
                                    playingTrack['cover'].toString(),
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
                                        playingTrack['title'].toString(),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                      ),
                                      Text(
                                        '⚡ Smart Drop @ ' +
                                            _fmtSec((playingTrack['smartDropSec'] as int?) ?? 0) +
                                            ' • ' +
                                            playingTrack['artist'].toString(),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 10, color: Colors.amberAccent),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.skip_previous, size: 22),
                                  onPressed: _playPrevInEntryQueue,
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
                                        _entryPlayer.resume();
                                      }
                                    },
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.skip_next, size: 22),
                                  onPressed: _playNextInEntryQueue,
                                ),
                              ],
                            ),
                            Slider(
                              value: _position.inSeconds
                                  .toDouble()
                                  .clamp(0, (_duration.inSeconds > 0 ? _duration.inSeconds : 1).toDouble()),
                              max: (_duration.inSeconds > 0 ? _duration.inSeconds : 1).toDouble(),
                              onChanged: (v) => _entryPlayer.seek(Duration(seconds: v.toInt())),
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(_fmtSec(_position.inSeconds), style: const TextStyle(fontSize: 10)),
                                Row(
                                  children: [
                                    ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.amber,
                                        foregroundColor: Colors.black,
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        minimumSize: Size.zero,
                                      ),
                                      icon: const Icon(Icons.push_pin, size: 13),
                                      label: const Text('📍 Lock Drop Here',
                                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900)),
                                      onPressed: _lockCurrentPositionAsEntryDrop,
                                    ),
                                    const SizedBox(width: 6),
                                    OutlinedButton(
                                      style: OutlinedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        minimumSize: Size.zero,
                                      ),
                                      onPressed: () => _entryPlayer.seek(Duration.zero),
                                      child: const Text('0:00 Start', style: TextStyle(fontSize: 10)),
                                    ),
                                  ],
                                ),
                                Text(_fmtSec(_duration.inSeconds), style: const TextStyle(fontSize: 10)),
                              ],
                            ),
                          ],
                        ),
                      ),

                    // Master Volume Sliders for All Other Pages
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: const Text(
                        '🎚 ALL-PAGE MASTER VOLUME MIXER & SMART DROP SETTINGS',
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
                          title: const Text('⚡ Smart Dynamic Entry Auto-Cut (Starts at Exact Beat Drop)',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                          subtitle: const Text(
                              'Automatically detects whether song is a pure BGM (0s) or full song (chorus drop)',
                              style: TextStyle(fontSize: 9, color: Colors.white70)),
                          value: _smartAutoCutEnabled,
                          onChanged: (v) => setState(() => _smartAutoCutEnabled = v),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              // ==================== 2. VIEW TABS: ONLINE 1000+ / FAV ENTRY / OFFLINE ENTRY PLAYLIST ====================
              Row(
                children: [
                  Expanded(
                    child: _tabButton('🔥 Famous (' + _onlineEntryTracks.length.toString() + ')', 'ONLINE'),
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: _tabButton('❤️ Fav Entry (' + _favEntryTracks.length.toString() + ')', 'FAV'),
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: _tabButton('📥 Offline Entry (' + _offlineEntryTracks.length.toString() + ')', 'OFFLINE'),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // ==================== 3. QUICK STADIUM ENCOURAGE PADS ====================
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

              // ==================== 4. ONLINE AUTO-EXTRACTOR SEARCH BAR ====================
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _extractSearchCtrl,
                      style: const TextStyle(fontSize: 12),
                      decoration: InputDecoration(
                        hintText: 'Extract any famous BGM (KGF, Salaar, Hukum, Rolex, Kantara)...',
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
                    onPressed: () =>
                        _loadCategoryTracks('CUSTOM', append: false, customQuery: _extractSearchCtrl.text),
                    child: const Text('Extract', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Category Chips
              SizedBox(
                height: 34,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _categories.length,
                  itemBuilder: (ctx, i) {
                    final cat = _categories[i];
                    final selected = (_selectedCategory == cat['key'] && _viewTab == 'ONLINE');
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

              // ==================== 5. ENTRY SOUNDS LIST (WITH FAV ❤️ + OFFLINE DOWNLOAD ⬇) ====================
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _viewTab == 'OFFLINE'
                        ? '📥 Offline Entry Playlist (' + visibleList.length.toString() + ')'
                        : (_viewTab == 'FAV'
                            ? '❤️ Favorite Entry Sounds (' + visibleList.length.toString() + ')'
                            : '🎵 Famous Entry Sounds (' + visibleList.length.toString() + ')'),
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.amberAccent),
                  ),
                  if (_viewTab == 'ONLINE')
                    TextButton.icon(
                      icon: const Icon(Icons.add_circle_outline, size: 16, color: Color(0xFF00E5FF)),
                      label: const Text('Load +100 More Famous',
                          style: TextStyle(fontSize: 11, color: Color(0xFF00E5FF))),
                      onPressed: () => _loadCategoryTracks(_selectedCategory, append: true),
                    ),
                ],
              ),

              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.all(24.0),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (visibleList.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(20.0),
                  child: Center(
                    child: Text(
                      'No tracks in this tab yet. Tap ❤️ or ⬇ on any Entry Sound to save it here!',
                      style: TextStyle(fontSize: 12, color: Colors.white70),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              else
                ...List.generate(visibleList.length, (idx) {
                  final trk = visibleList[idx];
                  final isThisPlaying = (playingId != null && trk['id'].toString() == playingId);
                  final isFav = _favEntryTracks.any((e) => e['id'] == trk['id']);
                  final isOff = _offlineEntryTracks.any((e) => e['id'] == trk['id']);
                  final int dropSec = (trk['smartDropSec'] as int?) ?? 0;

                  return Card(
                    color: isThisPlaying ? const Color(0xFF1E3A8A) : const Color(0xFF11192B),
                    margin: const EdgeInsets.symmetric(vertical: 3),
                    child: ListTile(
                      dense: true,
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.network(
                          trk['cover'].toString(),
                          width: 44,
                          height: 44,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Icon(Icons.music_note, color: Colors.amber),
                        ),
                      ),
                      title: Text(
                        '#' + (idx + 1).toString() + ' • ' + trk['title'].toString(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: isThisPlaying ? Colors.amberAccent : Colors.white,
                        ),
                      ),
                      subtitle: Text(
                        (isThisPlaying ? '🔊 PLAYING • ' : '') +
                            '⚡ Drop @ ' +
                            _fmtSec(dropSec) +
                            ' • ' +
                            trk['artist'].toString(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 10, color: Color(0xFF00E676)),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Favorite Entry Sound',
                            icon: Icon(
                              isFav ? Icons.favorite : Icons.favorite_border,
                              color: isFav ? Colors.pinkAccent : Colors.white54,
                              size: 20,
                            ),
                            onPressed: () => _toggleEntryFavorite(trk),
                          ),
                          IconButton(
                            tooltip: 'Download Offline Entry',
                            icon: Icon(
                              isOff ? Icons.offline_pin : Icons.download_for_offline,
                              color: isOff ? Colors.amberAccent : Colors.greenAccent,
                              size: 22,
                            ),
                            onPressed: () => _downloadEntryTrackOffline(trk),
                          ),
                          IconButton(
                            icon: Icon(
                              (isThisPlaying && _isPlaying) ? Icons.pause_circle_filled : Icons.play_circle_fill,
                              color: Colors.amberAccent,
                              size: 30,
                            ),
                            onPressed: () {
                              if (isThisPlaying) {
                                _isPlaying ? _entryPlayer.pause() : _entryPlayer.resume();
                              } else {
                                _startEntryFromVisibleList(idx);
                              }
                            },
                          ),
                        ],
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

  Widget _tabButton(String label, String tabKey) {
    final active = (_viewTab == tabKey);
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        backgroundColor: active ? const Color(0xFF1E3A8A) : const Color(0xFF0D1526),
        side: BorderSide(color: active ? const Color(0xFF00E5FF) : Colors.white24),
        padding: const EdgeInsets.symmetric(vertical: 8),
      ),
      onPressed: () => setState(() => _viewTab = tabKey),
      child: Text(label, style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold)),
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
