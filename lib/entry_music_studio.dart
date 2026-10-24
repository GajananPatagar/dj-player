import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'entry_music_data.dart';

class EntryMusicStudioScreen extends StatefulWidget {
  const EntryMusicStudioScreen({super.key});

  @override
  State<EntryMusicStudioScreen> createState() => _EntryMusicStudioScreenState();
}

class _EntryMusicStudioScreenState extends State<EntryMusicStudioScreen> {
  // Dual-Deck Instant Engine: _entryPlayer plays immediately while _preloadPlayer pre-buffers the next track at its exact drop second!
  final AudioPlayer _entryPlayer = AudioPlayer();
  final TextEditingController _searchCtrl = TextEditingController();

  List<Map<String, dynamic>> _onlineEntryTracks = [];
  List<Map<String, dynamic>> _activeEntryQueue = [];
  Map<String, dynamic>? _nowPlayingEntry;
  int _queueCursor = 0;
  bool _isArmedPreloaded = false;

  String _viewTab = 'ALL'; // ALL, FAV, OFFLINE
  String _statusText = '⚡ 0.0s Zero-Delay Funk & Heavy Bass Entry List Ready!';

  bool _isPlaying = false;
  bool _isLoading = false;
  bool _isZeroArmed = true;
  bool _hasTriggeredOnce = false;
  bool _cricket10SecWindowEnabled = true;
  int _windowDurationSec = 10;
  int _countdownRemainingSec = 0;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Timer? _tenSecCountdownTimer;

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
    _entryPlayer.onDurationChanged.listen((dur) {
      if (mounted) setState(() => _duration = dur);
    });
    _entryPlayer.onPlayerComplete.listen((_) {
      _playNextInEntryQueue();
    });

    MasterVolumeController.autoCricketStingerTrigger.addListener(() {
      final ev = MasterVolumeController.autoCricketStingerTrigger.value;
      if (ev != null && MasterVolumeController.autoPlayEntryOnCricketBoundaryOrWicket) {
        _triggerInstant10SecBurst();
      }
    });

    _loadUnifiedMasterList(append: false);
  }

  List<Map<String, dynamic>> _currentVisibleList() {
    if (_viewTab == 'FAV') return VaultManager.favEntries.value;
    if (_viewTab == 'OFFLINE') return VaultManager.offlineEntries.value;
    return _onlineEntryTracks;
  }

  Future<void> _loadUnifiedMasterList({required bool append, String? customQuery}) async {
    if (mounted) {
      setState(() {
        _viewTab = 'ALL';
        _isLoading = true;
        _statusText = '⚡ Loading Funk Criminal, Phonk & Heavy Bass Entry Tracks...';
      });
    }

    final fetched = await EntryMusicHarvester.fetchEntryTracks(
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
        _statusText = '🔥 ${_onlineEntryTracks.length} Heavy Bass Funk & Entry Tracks Ready (0.0s Instant Play)';
      });
      // Pre-buffer Track #1 at its exact bass drop so sliding volume up from 0% plays with 0.0s delay!
      _preBufferTrackAtCursor(_queueCursor);
    }
  }

  /// Pre-buffers and seeks the armed track to its exact drop second while muted at 0%
  /// so the moment the user slides Volume > 0%, it resumes in 0.00 seconds!
  Future<void> _preBufferTrackAtCursor(int idx) async {
    if (_activeEntryQueue.isEmpty || idx < 0 || idx >= _activeEntryQueue.length) return;
    final track = _activeEntryQueue[idx];
    final String id = track['id'].toString();
    final String title = track['title'].toString();
    final int durSec = (track['durationSec'] as int?) ?? 120;
    final int dropSec = EntryMusicHarvester.computeSmartEntryDropSecond(id, title, durSec);

    try {
      await _entryPlayer.setVolume(0.0);
      if (track['localPath'] != null && File(track['localPath'].toString()).existsSync()) {
        await _entryPlayer.setSource(DeviceFileSource(track['localPath'].toString()));
      } else {
        final List urls = track['urls'] as List? ?? [];
        if (urls.isNotEmpty) {
          await _entryPlayer.setSource(UrlSource(urls.first.toString()));
        }
      }
      if (dropSec > 0) {
        await _entryPlayer.seek(Duration(seconds: dropSec));
      }
      _isArmedPreloaded = true;
      if (mounted) {
        setState(() {
          _nowPlayingEntry = Map<String, dynamic>.from(track);
          _nowPlayingEntry!['smartDropSec'] = dropSec;
        });
      }
    } catch (_) {
      _isArmedPreloaded = false;
    }
  }

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
        await _entryPlayer.pause();
        if (mounted) {
          setState(() {
            _countdownRemainingSec = 0;
            _isZeroArmed = true;
            if (_activeEntryQueue.isNotEmpty) {
              _queueCursor = (_queueCursor + 1) % _activeEntryQueue.length;
            }
            _statusText = '✅ 10s Drop Complete — Next Track Pre-Buffered & Armed (#${_queueCursor + 1})!';
          });
        }
        // Pre-buffer the next song immediately so the next trigger has 0.0s delay!
        await _preBufferTrackAtCursor(_queueCursor);
      } else {
        setState(() => _countdownRemainingSec -= 1);
      }
    });
  }

  Future<void> _triggerInstant10SecBurst() async {
    if (_onlineEntryTracks.isEmpty) return;
    _activeEntryQueue = List<Map<String, dynamic>>.from(_onlineEntryTracks);
    await _playQueueIndexInstant(_queueCursor, forceVolume: 0.98);
  }

  /// Zero-Delay Volume Fader:
  /// Because the armed song is already pre-buffered & pre-seeked at 0%, sliding up calls .resume() in 0.0s!
  /// Pulling back to 0% immediately pre-buffers & pre-seeks the NEXT song!
  void _onEntryVolumeSliderChanged(double newVol) {
    MasterVolumeController.page4EntryVolume.value = newVol;

    if (newVol <= 0.01) {
      _tenSecCountdownTimer?.cancel();
      _entryPlayer.pause();
      _entryPlayer.setVolume(0.0);
      if (!_isZeroArmed) {
        _isZeroArmed = true;
        if (_activeEntryQueue.isNotEmpty) {
          _queueCursor = (_queueCursor + 1) % _activeEntryQueue.length;
        }
        setState(() {
          _countdownRemainingSec = 0;
          _statusText = '🎯 Armed & Pre-Buffered Next Track (#${_queueCursor + 1}) — Slide Up for 0.0s Drop!';
        });
        _preBufferTrackAtCursor(_queueCursor);
      }
      return;
    }

    _entryPlayer.setVolume(newVol);
    if (_isZeroArmed) {
      _isZeroArmed = false;
      final sourceList = _activeEntryQueue.isNotEmpty ? _activeEntryQueue : _currentVisibleList();
      if (sourceList.isEmpty) return;
      _activeEntryQueue = List<Map<String, dynamic>>.from(sourceList);

      if (_isArmedPreloaded) {
        // 0.00s INSTANT RESUME!
        _isArmedPreloaded = false;
        _hasTriggeredOnce = true;
        _entryPlayer.resume();
        _start10SecondPeakDropTimer();
        setState(() {
          _statusText = '🔥 INSTANT 0.0s DROP: ${_nowPlayingEntry?['title'] ?? ''}';
        });
      } else {
        _playQueueIndexInstant(_queueCursor, forceVolume: newVol);
      }
    } else {
      setState(() {});
    }
  }

  Future<void> _startEntryFromVisibleList(int visibleIdx) async {
    final visible = _currentVisibleList();
    if (visibleIdx < 0 || visibleIdx >= visible.length) return;
    _activeEntryQueue = List<Map<String, dynamic>>.from(visible);
    await _playQueueIndexInstant(visibleIdx);
  }

  /// Plays directly at position: Duration(seconds: smartDropSec) with NO blocking HTTP check!
  Future<void> _playQueueIndexInstant(int qIdx, {double? forceVolume}) async {
    if (_activeEntryQueue.isEmpty || qIdx < 0 || qIdx >= _activeEntryQueue.length) return;
    _tenSecCountdownTimer?.cancel();
    _isArmedPreloaded = false;

    final double activeVol = forceVolume ??
        (MasterVolumeController.page4EntryVolume.value <= 0.02
            ? 0.98
            : MasterVolumeController.page4EntryVolume.value);

    MasterVolumeController.page4EntryVolume.value = activeVol;
    _isZeroArmed = false;
    _hasTriggeredOnce = true;

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
        _statusText = '🔥 BLASTING (@ ${_fmtSec(smartDropSec)}): $title';
      });
    }

    if (track['localPath'] != null) {
      final file = File(track['localPath'].toString());
      if (file.existsSync()) {
        await _entryPlayer.play(
          DeviceFileSource(file.path),
          volume: activeVol,
          position: Duration(seconds: smartDropSec),
        );
        _start10SecondPeakDropTimer();
        return;
      }
    }

    final List urls = track['urls'] as List? ?? [];
    for (final rawUrl in urls) {
      try {
        // Direct byte-seek inside .play() -> 0 wasted HTTP HEAD requests!
        await _entryPlayer.play(
          UrlSource(rawUrl.toString()),
          volume: activeVol,
          position: Duration(seconds: smartDropSec),
        );
        _start10SecondPeakDropTimer();
        return;
      } catch (_) {}
    }
  }

  void _playNextInEntryQueue() {
    if (_activeEntryQueue.isEmpty) return;
    _playQueueIndexInstant((_queueCursor + 1) % _activeEntryQueue.length);
  }

  void _playPrevInEntryQueue() {
    if (_activeEntryQueue.isEmpty) return;
    _playQueueIndexInstant((_queueCursor - 1 + _activeEntryQueue.length) % _activeEntryQueue.length);
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
      _statusText = '📍 Locked Instant Drop at ${_fmtSec(sec)}!';
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
            added ? '❤️ Saved to Fav Entry: ${trk['title']}' : 'Removed from Fav Entry: ${trk['title']}',
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
          content: Text('⬇ Saving Offline for 0ms Local Playback: ${trk['title']}...'),
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
            ok ? '✅ Saved Offline: ${trk['title']}' : '⚠️ Stream busy—retry.',
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
                    // Status Strip
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
                          // 1. ZERO-DELAY 10-SECOND ENTRY VOLUME AUTO-FADER
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
                                        '🚀 ZERO-DELAY 10s BASS ENTRY FADER (0% ➔ UP = PLAY NEXT)',
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
                                        entryVol > 0.01 ? 'LIVE ${(entryVol * 100).toInt()}%' : 'PRE-BUFFERED @ 0%',
                                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900),
                                      ),
                                    ),
                                  ],
                                ),
                                Row(
                                  children: [
                                    IconButton(
                                      tooltip: 'Reset to 0% (Pre-Buffers Next Track Immediately)',
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
                                          '⏱ Auto 10s Best Bass Cut',
                                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.cyanAccent),
                                        ),
                                      ],
                                    ),
                                    DropdownButton<int>(
                                      value: _windowDurationSec,
                                      underline: const SizedBox(),
                                      items: const [
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
                                                    '⚡ Instant Drop @ ' +
                                                        _fmtSec((playingTrack['smartDropSec'] as int?) ?? 12) +
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
                                                    _isPlaying ? _entryPlayer.pause() : _playQueueIndexInstant(_queueCursor),
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
                                            ElevatedButton.icon(
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: Colors.amber,
                                                foregroundColor: Colors.black,
                                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                minimumSize: Size.zero,
                                              ),
                                              icon: const Icon(Icons.push_pin, size: 13),
                                              label: const Text('📍 Lock 10s Drop Here',
                                                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900)),
                                              onPressed: _lockCurrentPositionAsEntryDrop,
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

                          // 2. SEARCH / EXTRACT ANY FUNK OR ENTRY SONG + SAVED TABS
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _searchCtrl,
                                  style: const TextStyle(fontSize: 12),
                                  decoration: InputDecoration(
                                    hintText: 'Search Funk Criminal, Ultrafunk, Montagem, KGF, Hukum...',
                                    filled: true,
                                    fillColor: const Color(0xFF11192B),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                  onSubmitted: (v) => _loadUnifiedMasterList(append: false, customQuery: v),
                                ),
                              ),
                              const SizedBox(width: 6),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF00E5FF),
                                  foregroundColor: Colors.black,
                                ),
                                onPressed: () =>
                                    _loadUnifiedMasterList(append: false, customQuery: _searchCtrl.text),
                                child: const Text('Search', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),

                          Row(
                            children: [
                              Expanded(
                                child: _tabButton('🔥 All Entry (${_onlineEntryTracks.length})', 'ALL'),
                              ),
                              const SizedBox(width: 5),
                              Expanded(
                                child: _tabButton('❤️ Favs (${favList.length})', 'FAV'),
                              ),
                              const SizedBox(width: 5),
                              Expanded(
                                child: _tabButton('📥 Offline (${offList.length})', 'OFFLINE'),
                              ),
                              const SizedBox(width: 5),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.amber,
                                  foregroundColor: Colors.black,
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                ),
                                icon: const Icon(Icons.add, size: 14),
                                label: const Text('+50 More', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900)),
                                onPressed: () => _loadUnifiedMasterList(append: true),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),

                          // 3. ONE SINGLE UNIFIED DIRECT LIST (NO SEPARATE SECTIONS!)
                          if (_isLoading)
                            const Padding(
                              padding: EdgeInsets.all(24.0),
                              child: Center(child: CircularProgressIndicator()),
                            )
                          else
                            ...List.generate(visibleList.length, (idx) {
                              final trk = visibleList[idx];
                              final String id = trk['id'].toString();
                              final bool isThisPlaying = (playingId != null && id == playingId);
                              final bool isFav = VaultManager.isFavorite(id, isEntry: true);
                              final bool isOff = VaultManager.isOffline(id, isEntry: true);
                              final int? activeDlPct = dlProgress[id];
                              final int dropSec = (trk['smartDropSec'] as int?) ?? 12;

                              return Card(
                                color: isThisPlaying ? const Color(0xFF1E3A8A) : const Color(0xFF11192B),
                                margin: const EdgeInsets.symmetric(vertical: 3),
                                child: ListTile(
                                  dense: true,
                                  onTap: () => _startEntryFromVisibleList(idx),
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
                                          '${_windowDurationSec}s',
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
                                    (isThisPlaying ? '🔊 INSTANT 10s • ' : '') +
                                        '⚡ Drop @ ${_fmtSec(dropSec)} • ${trk['artist']}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 10, color: Color(0xFF00E676)),
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: Icon(
                                          isFav ? Icons.favorite : Icons.favorite_border,
                                          color: isFav ? Colors.pinkAccent : Colors.white60,
                                          size: 20,
                                        ),
                                        onPressed: () => _onTapFavEntry(trk),
                                      ),
                                      if (activeDlPct != null)
                                        Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 4),
                                          child: Text(
                                            '$activeDlPct%',
                                            style: const TextStyle(
                                                fontSize: 10, color: Colors.amberAccent, fontWeight: FontWeight.w900),
                                          ),
                                        )
                                      else
                                        IconButton(
                                          icon: Icon(
                                            isOff ? Icons.check_circle : Icons.download_for_offline,
                                            color: isOff ? Colors.amberAccent : Colors.greenAccent,
                                            size: 21,
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
                                          if (isThisPlaying && _isPlaying) {
                                            _entryPlayer.pause();
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
}
