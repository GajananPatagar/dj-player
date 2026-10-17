import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'des_helper.dart';
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

  List<Map<String, dynamic>> _onlineEntryTracks = [];
  List<Map<String, dynamic>> _activeEntryQueue = [];
  Map<String, dynamic>? _nowPlayingEntry;
  int _queueCursor = 0;
  int? _pendingSeekSec;

  String _viewTab = 'ONLINE'; // ONLINE, FAV, OFFLINE
  String _selectedCategory = 'ALL_1000';
  String _statusText = '⚡ Verified Full-Length Mass Entry & Encourage Studio Ready';

  bool _isPlaying = false;
  bool _isLoading = false;
  bool _isZeroArmed = true;
  bool _hasTriggeredOnce = false;
  bool _smartAutoCutEnabled = true;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Timer? _autoStingerStopTimer;

  final List<Map<String, String>> _categories = const [
    {'key': 'ALL_1000', 'label': '🔥 All Mass Entry BGMs'},
    {'key': 'KANNADA_MASS', 'label': '🎺 Kannada Mass Entry'},
    {'key': 'HERO_ENTRY', 'label': '👑 Hero Walkout (KGF/Salaar)'},
    {'key': 'ENCOURAGE', 'label': '💪 Player Encourage Anthems'},
    {'key': 'SIXER_DROP', 'label': '6️⃣ Sixer Bass Drops'},
    {'key': 'FOUR_HORN', 'label': '4️⃣ Boundary Horns'},
    {'key': 'WICKET_OUT', 'label': '🎯 Wicket / Out BGM'},
  ];

  @override
  void initState() {
    super.initState();
    VaultManager.initVaults();
    _entryPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() => _isPlaying = (state == PlayerState.playing));
      }
    });
    _entryPlayer.onPositionChanged.listen((pos) {
      if (mounted) setState(() => _position = pos);
    });
    // Wait until the stream is buffered and reports duration BEFORE seeking!
    // This prevents Android MediaPlayer from crashing or stopping on start!
    _entryPlayer.onDurationChanged.listen((dur) {
      if (mounted) setState(() => _duration = dur);
      if (_pendingSeekSec != null && _pendingSeekSec! > 0 && dur.inSeconds > _pendingSeekSec! + 10) {
        final int targetSec = _pendingSeekSec!;
        _pendingSeekSec = null;
        _entryPlayer.seek(Duration(seconds: targetSec));
      } else {
        _pendingSeekSec = null;
      }
    });
    _entryPlayer.onPlayerComplete.listen((_) {
      _playNextInEntryQueue();
    });

    MasterVolumeController.autoCricketStingerTrigger.addListener(() {
      final ev = MasterVolumeController.autoCricketStingerTrigger.value;
      if (ev != null && MasterVolumeController.autoPlayEntryOnCricketBoundaryOrWicket) {
        _triggerShortStadiumBurst();
      }
    });

    _loadCategoryTracks('ALL_1000', append: false);
  }

  Future<void> _triggerShortStadiumBurst() async {
    if (_onlineEntryTracks.isEmpty) return;
    _autoStingerStopTimer?.cancel();
    final int nextIdx = (_queueCursor + 1) % _onlineEntryTracks.length;
    _activeEntryQueue = List<Map<String, dynamic>>.from(_onlineEntryTracks);
    await _playQueueIndex(nextIdx, forceVolume: 0.85);
    _autoStingerStopTimer = Timer(const Duration(seconds: 8), () {
      _entryPlayer.pause();
    });
  }

  List<Map<String, dynamic>> _currentVisibleList() {
    if (_viewTab == 'FAV') return VaultManager.favEntries.value;
    if (_viewTab == 'OFFLINE') return VaultManager.offlineEntries.value;
    return _onlineEntryTracks;
  }

  Future<void> _loadCategoryTracks(String catKey, {required bool append, String? customQuery}) async {
    if (mounted) {
      setState(() {
        _viewTab = 'ONLINE';
        _selectedCategory = catKey;
        _isLoading = true;
        _statusText = '🔄 Loading Verified Full-Length Mass Entry & Encourage Tracks...';
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
            ' Full-Length Mass Entry Tracks Ready (0 Short Clips, 0 Normal Songs)';
      });
    }
  }

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
    _autoStingerStopTimer?.cancel();

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
    final int durSec = (track['durationSec'] as int?) ?? 180;
    final int smartDropSec = EntryMusicHarvester.computeSmartEntryDropSecond(id, title, durSec);

    if (mounted) {
      setState(() {
        _queueCursor = qIdx;
        _nowPlayingEntry = Map<String, dynamic>.from(track);
        _nowPlayingEntry!['smartDropSec'] = smartDropSec;
        _statusText = '⚡ Connecting Full-Length Stream: $title...';
      });
    }

    // 1. Check Offline Saved File First
    if (track['localPath'] != null) {
      final file = File(track['localPath'].toString());
      if (await file.exists()) {
        _pendingSeekSec = _smartAutoCutEnabled ? smartDropSec : 0;
        await _entryPlayer.stop();
        await _entryPlayer.setVolume(activeVol);
        await _entryPlayer.play(DeviceFileSource(file.path));
        if (mounted) setState(() => _statusText = '🔥 Blasting Offline Entry: $title');
        return;
      }
    }

    // 2. Verify Live HTTP 200 CDN Stream Before ExoPlayer Plays (Zero 404 Failures!)
    final List urls = track['urls'] as List? ?? [];
    final String? workingUrl = await SaavnDesDecryptor.resolvePlayableStreamUrl(urls);
    if (workingUrl != null) {
      try {
        _pendingSeekSec = _smartAutoCutEnabled ? smartDropSec : 0;
        await _entryPlayer.stop();
        await _entryPlayer.setVolume(activeVol);
        await _entryPlayer.play(UrlSource(workingUrl));
        if (mounted) {
          setState(() => _statusText = '🔥 Blasting Full Entry BGM: $title');
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

  Future<void> _lockCurrentPositionAsEntryDrop() async {
    if (_nowPlayingEntry == null) return;
    final String id = _nowPlayingEntry!['id'].toString();
    final int sec = _position.inSeconds;
    await EntryMusicHarvester.saveCustomCue(id, sec);
    setState(() {
      _nowPlayingEntry!['smartDropSec'] = sec;
      for (final item in _onlineEntryTracks) {
        if (item['id'].toString() == id) item['smartDropSec'] = sec;
      }
      _statusText = '📍 Locked Entry Drop at ' + _fmtSec(sec) + ' for ' + _nowPlayingEntry!['title'].toString();
    });
  }

  Future<void> _onTapFavEntry(Map<String, dynamic> trk) async {
    final added = await VaultManager.toggleFavorite(trk, isEntry: true);
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 1),
          backgroundColor: added ? Colors.pinkAccent.shade700 : Colors.blueGrey.shade800,
          content: Text(
            added ? '❤️ Saved to Fav Entry Sounds: ${trk['title']}' : 'Removed from Fav Entry: ${trk['title']}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      );
    }
  }

  Future<void> _onTapDownloadEntry(Map<String, dynamic> trk) async {
    if (mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 2),
          backgroundColor: Colors.teal.shade800,
          content: Text('⬇ Downloading Full Entry Track Offline: ${trk['title']}...'),
        ),
      );
    }
    final ok = await VaultManager.downloadTrack(trk, isEntry: true);
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: ok ? Colors.green.shade800 : Colors.red.shade800,
          content: Text(
            ok
                ? '✅ Saved to Offline Entry Playlist: ${trk['title']}'
                : '⚠️ Stream busy—tap play first or retry.',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      );
    }
  }

  String _fmtSec(int sec) {
    final int m = sec ~/ 60;
    final int s = sec % 60;
    return m.toString() + ':' + (s < 10 ? '0' + s.toString() : s.toString());
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<Map<String, dynamic>>>(
      valueListenable: VaultManager.favEntries,
      builder: (context, favList, _) {
        return ValueListenableBuilder<List<Map<String, dynamic>>>(
          valueListenable: VaultManager.offlineEntries,
          builder: (context, offList, _) {
            return ValueListenableBuilder<Map<String, int>>(
              valueListenable: VaultManager.downloadProgressMap,
              builder: (context, dlProgress, _) {
                final visibleList = _currentVisibleList();
                final playingTrack = _nowPlayingEntry;
                final String? playingId = playingTrack?['id']?.toString();
                final double entryVol = MasterVolumeController.page4EntryVolume.value;

                return Column(
                  children: [
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
                            '❤️ ${favList.length}   📥 ${offList.length}',
                            style: const TextStyle(fontSize: 11, color: Colors.amberAccent, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),

                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.all(10),
                        children: [
                          // 1. SMART ENTRY VOLUME AUTO-FADER
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
                                        entryVol > 0.01 ? 'LIVE ${(entryVol * 100).toInt()}%' : 'ARMED AT 0%',
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
                                                    '⚡ Drop @ ' +
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
                                                onPressed: () =>
                                                    _isPlaying ? _entryPlayer.pause() : _entryPlayer.resume(),
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

                                ExpansionTile(
                                  tilePadding: EdgeInsets.zero,
                                  title: const Text(
                                    '🎚 ALL-PAGE MASTER VOLUME MIXER & CRICKET AUTO-STINGER',
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
                                      title: const Text('⚡ Smart Dynamic Entry Auto-Cut (Seeks After Buffer)',
                                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                      value: _smartAutoCutEnabled,
                                      onChanged: (v) => setState(() => _smartAutoCutEnabled = v),
                                    ),
                                    SwitchListTile(
                                      contentPadding: EdgeInsets.zero,
                                      title: const Text('🏏 Auto-Blast 8s Entry BGM on Cricket 6, 4 & Wickets',
                                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.amberAccent)),
                                      value: MasterVolumeController.autoPlayEntryOnCricketBoundaryOrWicket,
                                      onChanged: (v) => setState(
                                          () => MasterVolumeController.autoPlayEntryOnCricketBoundaryOrWicket = v),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),

                          // 2. VIEW TABS: ONLINE / FAV ENTRY / OFFLINE ENTRY PLAYLIST
                          Row(
                            children: [
                              Expanded(
                                child: _tabButton('🔥 Entry (${_onlineEntryTracks.length})', 'ONLINE'),
                              ),
                              const SizedBox(width: 5),
                              Expanded(
                                child: _tabButton('❤️ Fav Entry (${favList.length})', 'FAV'),
                              ),
                              const SizedBox(width: 5),
                              Expanded(
                                child: _tabButton('📥 Offline Entry (${offList.length})', 'OFFLINE'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),

                          // 3. INSTANT OFFLINE STADIUM SYNTH + ONLINE CATEGORY PADS
                          Row(
                            children: [
                              _quickTriggerButton('🎺 KANNADA MASS', Colors.amber.shade800, () {
                                _loadCategoryTracks('KANNADA_MASS', append: false);
                              }),
                              const SizedBox(width: 5),
                              _quickTriggerButton('6️⃣ SIXER BASS', Colors.deepPurpleAccent, () {
                                AppSoundEngine.playSynthesizedSfx('AIRHORN');
                                _loadCategoryTracks('SIXER_DROP', append: false);
                              }),
                              const SizedBox(width: 5),
                              _quickTriggerButton('💪 ENCOURAGE', Colors.teal.shade700, () {
                                _loadCategoryTracks('ENCOURAGE', append: false);
                              }),
                              const SizedBox(width: 5),
                              _quickTriggerButton('🎯 OUT BGM', Colors.redAccent, () {
                                AppSoundEngine.playSynthesizedSfx('BOWLED');
                                _loadCategoryTracks('WICKET_OUT', append: false);
                              }),
                            ],
                          ),
                          const SizedBox(height: 8),

                          // 4. STRICT ENTRY-ONLY AUTO-EXTRACTOR SEARCH BAR
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _extractSearchCtrl,
                                  style: const TextStyle(fontSize: 12),
                                  decoration: InputDecoration(
                                    hintText: 'Search Entry/Encourage only (e.g. Kannada, KGF, Salaar, Hukum)...',
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
                                onPressed: () => _loadCategoryTracks('CUSTOM',
                                    append: false, customQuery: _extractSearchCtrl.text),
                                child: const Text('Extract Entry',
                                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11)),
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
                                    label: Text(cat['label']!,
                                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
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

                          // 5. ENTRY SOUNDS LIST
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _viewTab == 'OFFLINE'
                                    ? '📥 Offline Entry Playlist (${visibleList.length})'
                                    : (_viewTab == 'FAV'
                                        ? '❤️ Favorite Entry Sounds (${visibleList.length})'
                                        : '🎵 Verified Full Entry & Encourage Sounds (${visibleList.length})'),
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.amberAccent),
                              ),
                              if (_viewTab == 'ONLINE')
                                TextButton.icon(
                                  icon: const Icon(Icons.add_circle_outline, size: 16, color: Color(0xFF00E5FF)),
                                  label: const Text('Load +50 More Entry',
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
                                  'No Entry tracks in this tab yet. Tap ❤️ or ⬇ on any Entry Sound to save it here!',
                                  style: TextStyle(fontSize: 12, color: Colors.white70),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            )
                          else
                            ...List.generate(visibleList.length, (idx) {
                              final trk = visibleList[idx];
                              final String id = trk['id'].toString();
                              final bool isThisPlaying = (playingId != null && id == playingId);
                              final bool isFav = VaultManager.isFavorite(id, isEntry: true);
                              final bool isOff = VaultManager.isOffline(id, isEntry: true);
                              final int? activeDlPct = dlProgress[id];
                              final int dropSec = (trk['smartDropSec'] as int?) ?? 0;

                              return Card(
                                color: isThisPlaying ? const Color(0xFF1E3A8A) : const Color(0xFF11192B),
                                margin: const EdgeInsets.symmetric(vertical: 3),
                                child: ListTile(
                                  dense: true,
                                  leading: Stack(
                                    alignment: Alignment.bottomRight,
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(6),
                                        child: Image.network(
                                          trk['cover'].toString(),
                                          width: 44,
                                          height: 44,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) => const Icon(Icons.bolt, color: Colors.amber),
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                                        color: Colors.black87,
                                        child: Text(
                                          (trk['durationStr'] ?? 'Full').toString(),
                                          style: const TextStyle(
                                              fontSize: 8, color: Colors.greenAccent, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    ],
                                  ),
                                  title: Text(
                                    '#${idx + 1} • ${trk['title']}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                      color: isThisPlaying ? Colors.amberAccent : Colors.white,
                                    ),
                                  ),
                                  subtitle: Text(
                                    (isThisPlaying ? '🔊 BLASTING • ' : '') +
                                        '⚡ Drop @ ${_fmtSec(dropSec)} • ${trk['quality'] ?? '320kbps FULL'}',
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
                                          color: isFav ? Colors.pinkAccent : Colors.white60,
                                          size: 21,
                                        ),
                                        onPressed: () => _onTapFavEntry(trk),
                                      ),
                                      if (activeDlPct != null)
                                        Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 6),
                                          child: Text(
                                            '$activeDlPct%',
                                            style: const TextStyle(
                                                fontSize: 11, color: Colors.amberAccent, fontWeight: FontWeight.w900),
                                          ),
                                        )
                                      else
                                        IconButton(
                                          tooltip: 'Download Offline Entry',
                                          icon: Icon(
                                            isOff ? Icons.check_circle : Icons.download_for_offline,
                                            color: isOff ? Colors.amberAccent : Colors.greenAccent,
                                            size: 22,
                                          ),
                                          onPressed: () => _onTapDownloadEntry(trk),
                                        ),
                                      IconButton(
                                        icon: Icon(
                                          (isThisPlaying && _isPlaying)
                                              ? Icons.pause_circle_filled
                                              : Icons.play_circle_fill,
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
              },
            );
          },
        );
      },
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
                Text('${(val * 100).toInt()}%',
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
