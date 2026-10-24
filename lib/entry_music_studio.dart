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
  String _selectedCategory = 'FUNK_BASS';
  String _statusText = '⚡ 10-Sec Peak Bass-Drop Mode Ready (Funk, Phonk & Mass Entry)';

  bool _isPlaying = false;
  bool _isLoading = false;
  bool _isZeroArmed = true;
  bool _hasTriggeredOnce = false;
  bool _smartAutoCutEnabled = true;
  bool _cricket10SecWindowEnabled = true; // Automatically plays the best 10 seconds for 4/6/Out/Entry!
  int _windowDurationSec = 10;
  int _countdownRemainingSec = 0;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Timer? _tenSecCountdownTimer;

  final List<Map<String, String>> _categories = const [
    {'key': 'FUNK_BASS', 'label': '🔥 Funk & Phonk Bass Drops'},
    {'key': 'ALL_1000', 'label': '⚡ All Mass + Funk Entry'},
    {'key': 'KANNADA_MASS', 'label': '🎺 Kannada Mass Entry'},
    {'key': 'HERO_ENTRY', 'label': '👑 Hero Walkout (KGF/Salaar)'},
    {'key': 'SIXER_DROP', 'label': '6️⃣ Sixer 10s Bass Drops'},
    {'key': 'FOUR_HORN', 'label': '4️⃣ Boundary 10s Funk'},
    {'key': 'WICKET_OUT', 'label': '🎯 Wicket / Out Dark Funk'},
    {'key': 'ENCOURAGE', 'label': '💪 Player Encourage'},
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
    // Wait until buffered, jump straight to the Peak Bass Drop, then start the 10-Second Cricket Timer!
    _entryPlayer.onDurationChanged.listen((dur) {
      if (mounted) setState(() => _duration = dur);
      if (_pendingSeekSec != null && _pendingSeekSec! > 0 && dur.inSeconds > _pendingSeekSec! + 8) {
        final int targetSec = _pendingSeekSec!;
        _pendingSeekSec = null;
        _entryPlayer.seek(Duration(seconds: targetSec));
      } else {
        _pendingSeekSec = null;
      }
      if (_cricket10SecWindowEnabled) {
        _start10SecondPeakDropTimer();
      }
    });
    _entryPlayer.onPlayerComplete.listen((_) {
      _playNextInEntryQueue();
    });

    MasterVolumeController.autoCricketStingerTrigger.addListener(() {
      final ev = MasterVolumeController.autoCricketStingerTrigger.value;
      if (ev != null && MasterVolumeController.autoPlayEntryOnCricketBoundaryOrWicket) {
        _trigger10SecCricketBurst();
      }
    });

    _loadCategoryTracks('FUNK_BASS', append: false);
  }

  /// Counts down 10 seconds of the song's best peak drop, fades out smoothly, and arms the NEXT track!
  void _start10SecondPeakDropTimer() {
    _tenSecCountdownTimer?.cancel();
    if (!_cricket10SecWindowEnabled) return;

    setState(() => _countdownRemainingSec = _windowDurationSec);
    _tenSecCountdownTimer = Timer.periodic(const Duration(seconds: 1), (t) async {
      if (!mounted || !_isPlaying) {
        t.cancel();
        return;
      }
      if (_countdownRemainingSec <= 1) {
        t.cancel();
        // Smooth fade-out and pause, then advance cursor so next 6/4/Player gets a brand new song!
        await _entryPlayer.setVolume(0.25);
        await Future.delayed(const Duration(milliseconds: 350));
        await _entryPlayer.pause();
        final double restoreVol = MasterVolumeController.page4EntryVolume.value <= 0.05
            ? 0.90
            : MasterVolumeController.page4EntryVolume.value;
        await _entryPlayer.setVolume(restoreVol);
        if (mounted) {
          setState(() {
            _countdownRemainingSec = 0;
            if (_activeEntryQueue.isNotEmpty) {
              _queueCursor = (_queueCursor + 1) % _activeEntryQueue.length;
            }
            _statusText = '✅ 10s Peak Drop Complete — Next Track Armed (#${_queueCursor + 1})!';
          });
        }
      } else {
        setState(() => _countdownRemainingSec -= 1);
      }
    });
  }

  Future<void> _trigger10SecCricketBurst() async {
    if (_onlineEntryTracks.isEmpty) return;
    _activeEntryQueue = List<Map<String, dynamic>>.from(_onlineEntryTracks);
    await _playQueueIndex(_queueCursor, forceVolume: 0.95);
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
        _statusText = '🔄 Harvesting Fresh Online Funk, Phonk & Mass Entry Drops...';
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
          _activeEntryQueue = List<Map<String, dynamic>>.from(fetched);
          _queueCursor = 0;
        }
        _isLoading = false;
        _statusText = '🟢 ${_onlineEntryTracks.length} Fresh 10s Peak-Drop Funk & Entry Tracks Ready!';
      });
    }
  }

  void _onEntryVolumeSliderChanged(double newVol) {
    MasterVolumeController.page4EntryVolume.value = newVol;

    if (newVol <= 0.01) {
      _tenSecCountdownTimer?.cancel();
      _entryPlayer.setVolume(0.0);
      if (!_isZeroArmed) {
        _entryPlayer.pause();
        setState(() {
          _isZeroArmed = true;
          _countdownRemainingSec = 0;
          _statusText = '🎯 Armed at 0%! Slide Volume Up to Blast NEXT 10s Peak Entry Drop!';
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
    _tenSecCountdownTimer?.cancel();

    final double activeVol = forceVolume ??
        (MasterVolumeController.page4EntryVolume.value <= 0.02
            ? 0.95
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
        _statusText = '🔥 Playing 10s Peak Bass Drop (@ ${_fmtSec(smartDropSec)}): $title';
      });
    }

    if (track['localPath'] != null) {
      final file = File(track['localPath'].toString());
      if (await file.exists()) {
        _pendingSeekSec = _smartAutoCutEnabled ? smartDropSec : 0;
        await _entryPlayer.stop();
        await _entryPlayer.setVolume(activeVol);
        await _entryPlayer.play(DeviceFileSource(file.path));
        return;
      }
    }

    final List urls = track['urls'] as List? ?? [];
    final String? workingUrl = await SaavnDesDecryptor.resolvePlayableStreamUrl(urls);
    if (workingUrl != null) {
      try {
        _pendingSeekSec = _smartAutoCutEnabled ? smartDropSec : 0;
        await _entryPlayer.stop();
        await _entryPlayer.setVolume(activeVol);
        await _entryPlayer.play(UrlSource(workingUrl));
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
      _statusText = '📍 Locked 10s Peak Drop Start at ${_fmtSec(sec)}!';
    });
    if (_cricket10SecWindowEnabled) _start10SecondPeakDropTimer();
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
          content: Text('⬇ Downloading Entry Track Offline: ${trk['title']}...'),
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
            ok ? '✅ Saved to Offline Entry Playlist: ${trk['title']}' : '⚠️ Stream busy—tap play first or retry.',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      );
    }
  }

  String _fmtSec(int sec) {
    final int m = sec ~/ 60;
    final int s = sec % 60;
    return '$m:${s < 10 ? '0$s' : '$s'}';
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
                          if (_countdownRemainingSec > 0)
                            Container(
                              margin: const EdgeInsets.only(right: 8),
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.redAccent,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '⏱ ${_countdownRemainingSec}s',
                                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.white),
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
                          // 1. SMART 10-SECOND ENTRY VOLUME AUTO-FADER
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
                                        '🚀 10-SEC PEAK BASS ENTRY FADER (0% ➔ UP = PLAY NEXT)',
                                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Colors.amberAccent),
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

                                // 10-Second Cricket Window Toggle + Duration Selector
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        Switch(
                                          value: _cricket10SecWindowEnabled,
                                          activeColor: const Color(0xFF00E676),
                                          onChanged: (v) {
                                            setState(() => _cricket10SecWindowEnabled = v);
                                            if (!v) _tenSecCountdownTimer?.cancel();
                                          },
                                        ),
                                        const Text(
                                          '⏱ Play Best 10s Peak Drop Only',
                                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.cyanAccent),
                                        ),
                                      ],
                                    ),
                                    DropdownButton<int>(
                                      value: _windowDurationSec,
                                      underline: const SizedBox(),
                                      items: const [
                                        DropdownMenuItem(value: 8, child: Text('8 Sec', style: TextStyle(fontSize: 11))),
                                        DropdownMenuItem(value: 10, child: Text('10 Sec (Cricket)', style: TextStyle(fontSize: 11))),
                                        DropdownMenuItem(value: 15, child: Text('15 Sec (Walkout)', style: TextStyle(fontSize: 11))),
                                        DropdownMenuItem(value: 30, child: Text('30 Sec', style: TextStyle(fontSize: 11))),
                                      ],
                                      onChanged: (val) {
                                        if (val != null) setState(() => _windowDurationSec = val);
                                      },
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
                                                    '⚡ Peak Drop @ ' +
                                                        _fmtSec((playingTrack['smartDropSec'] as int?) ?? 22) +
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
                                                  label: const Text('📍 Lock 10s Drop Here',
                                                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900)),
                                                  onPressed: _lockCurrentPositionAsEntryDrop,
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
                                    '🎚 ALL-PAGE MASTER VOLUME MIXER',
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
                                child: _tabButton('🔥 Funk & Entry (${_onlineEntryTracks.length})', 'ONLINE'),
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

                          // 3. QUICK 10-SECOND CRICKET & FUNK PADS
                          Row(
                            children: [
                              _quickTriggerButton('🔥 FUNK & PHONK', Colors.pinkAccent.shade700, () {
                                _loadCategoryTracks('FUNK_BASS', append: false);
                              }),
                              const SizedBox(width: 5),
                              _quickTriggerButton('🎺 KANNADA MASS', Colors.amber.shade800, () {
                                _loadCategoryTracks('KANNADA_MASS', append: false);
                              }),
                              const SizedBox(width: 5),
                              _quickTriggerButton('6️⃣ SIXER 10s', Colors.deepPurpleAccent, () {
                                _loadCategoryTracks('SIXER_DROP', append: false);
                              }),
                              const SizedBox(width: 5),
                              _quickTriggerButton('🎯 OUT 10s', Colors.redAccent, () {
                                _loadCategoryTracks('WICKET_OUT', append: false);
                              }),
                            ],
                          ),
                          const SizedBox(height: 8),

                          // 4. ONLINE FUNK & ENTRY EXTRACTOR SEARCH BAR
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _extractSearchCtrl,
                                  style: const TextStyle(fontSize: 12),
                                  decoration: InputDecoration(
                                    hintText: 'Search any Funk, Phonk, Bass Drop, KGF, Salaar, Hukum...',
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
                                child: const Text('Extract 10s',
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

                          // 5. ENTRY SOUNDS LIST + REFRESH / LOAD MORE LAKHS OF TRACKS
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  _viewTab == 'OFFLINE'
                                      ? '📥 Offline 10s Entry Playlist (${visibleList.length})'
                                      : (_viewTab == 'FAV'
                                          ? '❤️ Favorite 10s Entry Drops (${visibleList.length})'
                                          : '🎵 10s Peak-Drop Funk & Entry Queue (${visibleList.length})'),
                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.amberAccent),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (_viewTab == 'ONLINE')
                                Row(
                                  children: [
                                    TextButton.icon(
                                      icon: const Icon(Icons.casino, size: 15, color: Colors.amberAccent),
                                      label: const Text('New Batch',
                                          style: TextStyle(fontSize: 11, color: Colors.amberAccent)),
                                      onPressed: () => _loadCategoryTracks(_selectedCategory, append: false),
                                    ),
                                    TextButton.icon(
                                      icon: const Icon(Icons.add_circle_outline, size: 15, color: Color(0xFF00E5FF)),
                                      label: const Text('+50 More',
                                          style: TextStyle(fontSize: 11, color: Color(0xFF00E5FF))),
                                      onPressed: () => _loadCategoryTracks(_selectedCategory, append: true),
                                    ),
                                  ],
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
                              final int dropSec = (trk['smartDropSec'] as int?) ?? 22;

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
                                          '${_windowDurationSec}s Cut',
                                          style: const TextStyle(
                                              fontSize: 8, color: Colors.amberAccent, fontWeight: FontWeight.bold),
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
                                    (isThisPlaying ? '🔊 BLASTING 10s • ' : '') +
                                        '⚡ Peak @ ${_fmtSec(dropSec)} ➔ ${_fmtSec(dropSec + _windowDurationSec)} • ${trk['artist']}',
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
