import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:audioplayers/audioplayers.dart';
import 'des_helper.dart';
import 'entry_music_data.dart';

class AudioStudioScreen extends StatefulWidget {
  const AudioStudioScreen({super.key});

  @override
  State<AudioStudioScreen> createState() => _AudioStudioScreenState();
}

class _AudioStudioScreenState extends State<AudioStudioScreen> {
  final AudioPlayer _player = AudioPlayer();
  final TextEditingController _searchCtrl = TextEditingController();

  final List<String> _languages = [
    'Kannada',
    'Hindi',
    'English',
    'Tamil',
    'Telugu',
    'Malayalam',
    'Punjabi',
    'Marathi',
    'Bhojpuri',
    'DJ Bass Remix'
  ];

  String _selectedLang = 'Kannada';
  String _viewMode = 'SONGS'; // SONGS, FAVORITES, OFFLINE
  String _statusBadge = '🟢 v50.0 2026 Trending & 320kbps Full-Song Engine';
  bool _isLoading = false;
  bool _isBusySwitching = false;

  List<Map<String, dynamic>> _tracks = [];
  List<Map<String, dynamic>> _playbackQueue = [];
  Map<String, dynamic>? _nowPlayingTrack;
  int _queueIndex = -1;

  bool _isPlaying = false;
  bool _loopCurrent = false;
  bool _shuffleMode = false;
  bool _isTalkoverDucked = false;
  double _playbackSpeed = 1.0;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    VaultManager.initVaults();
    _setupListeners();
    MasterVolumeController.page1MusicVolume.addListener(() {
      if (!_isTalkoverDucked) {
        _player.setVolume(MasterVolumeController.page1MusicVolume.value);
      }
    });
    _fetchDailyTop50('Kannada');
  }

  void _setupListeners() {
    _player.onPositionChanged.listen((pos) {
      if (mounted) setState(() => _position = pos);
    });
    _player.onDurationChanged.listen((dur) {
      if (mounted) setState(() => _duration = dur);
    });
    _player.onPlayerComplete.listen((_) {
      if (_loopCurrent && _nowPlayingTrack != null) {
        _playFromQueueIndex(_queueIndex);
      } else {
        _playNext();
      }
    });
    _player.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() => _isPlaying = (state == PlayerState.playing));
      }
    });
  }

  String _cleanStr(String s) {
    return s
        .replaceAll('&quot;', '"')
        .replaceAll('&amp;', '&')
        .replaceAll('&#039;', "'")
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .trim();
  }

  String _formatSecs(int totalSec) {
    if (totalSec <= 0) return 'Full';
    final int m = totalSec ~/ 60;
    final int s = totalSec % 60;
    return m.toString() + ':' + (s < 10 ? '0' + s.toString() : s.toString());
  }

  /// Queries specifically for 2026 & 2025 New Releases so Old Songs never flood Daily Trending!
  Future<void> _fetchDailyTop50(String lang) async {
    if (!mounted) return;
    setState(() {
      _selectedLang = lang;
      _viewMode = 'SONGS';
    });

    final List<String> subQueries = [
      '$lang New Hit Songs 2026',
      '$lang Latest Trending Songs 2025 2026',
      '$lang Top Chartbusters 2026',
      '$lang DJ Remix 2026',
    ];
    await _runDirectFullSongSearch(subQueries, isTrendingMode: true);
  }

  Future<void> _searchUserQuery(String rawQuery) async {
    final q = rawQuery.trim();
    if (q.isEmpty) return;
    setState(() => _viewMode = 'SONGS');
    await _runDirectFullSongSearch([
      q,
      '$q Full Song',
    ], isTrendingMode: false);
  }

  Future<void> _runDirectFullSongSearch(List<String> queries, {required bool isTrendingMode}) async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _statusBadge = isTrendingMode
            ? '🔄 Loading 2025-2026 New Trending $_selectedLang Songs (0 Duplicates)...'
            : '🔄 Searching Full-Length 320kbps Songs (0 Duplicates)...';
      });
    }

    final List<Map<String, dynamic>> aggregated = [];
    final Set<String> seenIds = {};
    final Set<String> seenFingerprints = {};

    final Map<String, String> headers = {
      'User-Agent': 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/124.0 Mobile Safari/537.36',
      'Accept': 'application/json, text/plain, */*',
    };

    for (final q in queries) {
      if (aggregated.length >= 60) break;
      try {
        final String directUrl =
            'https://www.jiosaavn.com/api.php?__call=search.getResults&_format=json&_marker=0&api_version=4&ctx=web6dot0&n=40&p=1&q=' +
                Uri.encodeComponent(q);
        final res = await http.get(Uri.parse(directUrl), headers: headers).timeout(const Duration(seconds: 7));
        if (res.statusCode == 200) {
          final decoded = jsonDecode(res.body);
          final List results = decoded['results'] ?? [];
          for (final item in results) {
            final String id = (item['id'] ?? '').toString();
            if (id.isEmpty || seenIds.contains(id)) continue;

            final Map moreInfo = (item['more_info'] is Map) ? item['more_info'] : {};
            final String title = _cleanStr((item['title'] ?? item['song'] ?? 'Track').toString());
            final int durSec = int.tryParse((moreInfo['duration'] ?? item['duration'] ?? '0').toString()) ?? 0;
            final int year = int.tryParse((item['year'] ?? moreInfo['year'] ?? '2025').toString()) ?? 2025;
            final int playCount =
                int.tryParse((item['play_count'] ?? moreInfo['play_count'] ?? '25000').toString()) ?? 25000;

            if (durSec > 0 && durSec <= 42) continue;

            // In Trending Mode, block old pre-2023 songs so only fresh 2024-2026 hits appear!
            if (isTrendingMode && year < 2023) continue;

            // Canonical Fingerprint Check (Blocks Duplicate Songs 100%!)
            final String fp = SaavnDesDecryptor.canonicalFingerprint(title);
            if (seenFingerprints.contains(fp)) continue;

            final String? encUrl = (moreInfo['encrypted_media_url'] ?? item['encrypted_media_url'])?.toString();
            final String? prevUrl = (moreInfo['vlink'] ?? item['media_preview_url'])?.toString();
            final List<String> fullUrls = SaavnDesDecryptor.decryptToFullUrls(encUrl, prevUrl);
            if (fullUrls.isEmpty) continue;

            seenIds.add(id);
            seenFingerprints.add(fp);

            final String subtitle = _cleanStr((item['subtitle'] ?? moreInfo['music'] ?? 'Full 320kbps').toString());
            final String cover = (item['image'] ?? 'https://via.placeholder.com/150')
                .toString()
                .replaceAll('150x150', '500x500')
                .replaceAll('50x50', '500x500');

            aggregated.add({
              'id': id,
              'title': title,
              'artist': subtitle,
              'cover': cover,
              'urls': fullUrls,
              'durationStr': _formatSecs(durSec),
              'durationSec': durSec,
              'year': year,
              'playCount': playCount,
              'quality': '$year • 320kbps (' + _formatSecs(durSec) + ')',
              'isOffline': false,
            });
          }
        }
      } catch (_) {}
    }

    // In Trending Mode: Sort newest release years (2026, 2025) to the top, then by popularity!
    if (isTrendingMode) {
      aggregated.sort((a, b) {
        final int yA = (a['year'] ?? 2025) as int;
        final int yB = (b['year'] ?? 2025) as int;
        if (yB != yA) return yB.compareTo(yA);
        return ((b['playCount'] ?? 0) as int).compareTo((a['playCount'] ?? 0) as int);
      });
    }

    if (mounted) {
      setState(() {
        _tracks = aggregated;
        _isLoading = false;
        _statusBadge = '🟢 Loaded ' + aggregated.length.toString() + ' Unique Full Songs (0 Duplicates)';
      });
    }
  }

  List<Map<String, dynamic>> _currentVisibleList() {
    if (_viewMode == 'OFFLINE') return VaultManager.offlineSongs.value;
    if (_viewMode == 'FAVORITES') return VaultManager.favSongs.value;
    return _tracks;
  }

  Future<void> _startPlaybackFromVisibleList(int index) async {
    final visible = _currentVisibleList();
    if (index < 0 || index >= visible.length) return;
    _playbackQueue = List<Map<String, dynamic>>.from(visible);
    await _playFromQueueIndex(index);
  }

  Future<void> _playFromQueueIndex(int qIdx) async {
    if (_isBusySwitching) return;
    if (_playbackQueue.isEmpty || qIdx < 0 || qIdx >= _playbackQueue.length) return;

    _isBusySwitching = true;
    final track = _playbackQueue[qIdx];

    if (mounted) {
      setState(() {
        _queueIndex = qIdx;
        _nowPlayingTrack = Map<String, dynamic>.from(track);
        _statusBadge = '⚡ Playing Full Song: ' + track['title'].toString();
      });
    }

    try {
      final double targetVol = _isTalkoverDucked ? 0.15 : MasterVolumeController.page1MusicVolume.value;

      if (track['localPath'] != null) {
        final file = File(track['localPath'].toString());
        if (await file.exists()) {
          await _player.stop();
          await _player.setVolume(targetVol);
          await _player.play(DeviceFileSource(file.path));
          await _player.setPlaybackRate(_playbackSpeed);
          if (mounted) setState(() => _statusBadge = '🟢 Playing Offline 320kbps Master: ' + track['title'].toString());
          _isBusySwitching = false;
          return;
        }
      }

      final List urls = track['urls'] as List? ?? [];
      for (int i = 0; i < urls.length; i++) {
        try {
          final targetUrl = urls[i].toString();
          await _player.stop();
          await _player.setVolume(targetVol);
          await _player.play(UrlSource(targetUrl));
          await _player.setPlaybackRate(_playbackSpeed);
          if (mounted) {
            setState(() {
              _statusBadge = '🟢 Playing: ' + track['title'].toString() + ' [320kbps]';
            });
          }
          _isBusySwitching = false;
          return;
        } catch (_) {}
      }
    } finally {
      _isBusySwitching = false;
    }
  }

  void _playNext() {
    if (_playbackQueue.isEmpty) return;
    if (_shuffleMode && _playbackQueue.length > 1) {
      final next = DateTime.now().millisecond % _playbackQueue.length;
      _playFromQueueIndex(next);
    } else {
      _playFromQueueIndex((_queueIndex + 1) % _playbackQueue.length);
    }
  }

  void _playPrev() {
    if (_playbackQueue.isEmpty) return;
    _playFromQueueIndex((_queueIndex - 1 + _playbackQueue.length) % _playbackQueue.length);
  }

  void _toggleTalkoverDuck() {
    setState(() {
      _isTalkoverDucked = !_isTalkoverDucked;
      final double v = _isTalkoverDucked ? 0.15 : MasterVolumeController.page1MusicVolume.value;
      _player.setVolume(v);
    });
  }

  Future<void> _onTapFavorite(Map<String, dynamic> trk) async {
    final added = await VaultManager.toggleFavorite(trk, isEntry: false);
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 1),
          backgroundColor: added ? Colors.pinkAccent.shade700 : Colors.blueGrey.shade800,
          content: Text(
            added ? '❤️ Added to Favorites: ${trk['title']}' : 'Removed from Favorites: ${trk['title']}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      );
    }
  }

  Future<void> _onTapDownload(Map<String, dynamic> trk) async {
    if (mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 2),
          backgroundColor: Colors.teal.shade800,
          content: Text('⬇ Downloading 320kbps Full Song: ${trk['title']}...'),
        ),
      );
    }
    final ok = await VaultManager.downloadTrack(trk, isEntry: false);
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: ok ? Colors.green.shade800 : Colors.red.shade800,
          content: Text(
            ok
                ? '✅ Saved to Offline Vault: ${trk['title']} (Plays without internet!)'
                : '⚠️ Download busy on this mirror—tap play first or retry.',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      );
    }
  }

  String _fmtDuration(Duration d) {
    final mins = d.inMinutes;
    final secs = d.inSeconds % 60;
    return mins.toString() + ':' + (secs < 10 ? '0' + secs.toString() : secs.toString());
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<Map<String, dynamic>>>(
      valueListenable: VaultManager.favSongs,
      builder: (context, favList, _) {
        return ValueListenableBuilder<List<Map<String, dynamic>>>(
          valueListenable: VaultManager.offlineSongs,
          builder: (context, offList, _) {
            return ValueListenableBuilder<Map<String, int>>(
              valueListenable: VaultManager.downloadProgressMap,
              builder: (context, dlProgress, _) {
                final visibleList = _currentVisibleList();
                final playingTrack = _nowPlayingTrack;
                final String? playingId = playingTrack?['id']?.toString();

                return Column(
                  children: [
                    // Status Strip
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      color: const Color(0xFF0E172A),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              _statusBadge,
                              style: const TextStyle(fontSize: 11, color: Color(0xFF00E676), fontWeight: FontWeight.bold),
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

                    // Search Bar + Mode Tabs
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _searchCtrl,
                                  style: const TextStyle(fontSize: 13),
                                  decoration: InputDecoration(
                                    hintText: 'Search any song, movie, DJ remix or artist...',
                                    filled: true,
                                    fillColor: const Color(0xFF11192B),
                                    suffixIcon: _searchCtrl.text.isNotEmpty
                                        ? IconButton(
                                            icon: const Icon(Icons.clear, size: 18),
                                            onPressed: () {
                                              _searchCtrl.clear();
                                              _fetchDailyTop50(_selectedLang);
                                            },
                                          )
                                        : null,
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                  onSubmitted: (val) => _searchUserQuery(val),
                                ),
                              ),
                              const SizedBox(width: 6),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF00E5FF),
                                  foregroundColor: Colors.black,
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                ),
                                onPressed: () => _searchUserQuery(_searchCtrl.text),
                                child: const Text('Search', style: TextStyle(fontWeight: FontWeight.w900)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Expanded(
                                child: _modeButton('🔥 2026 Top (${_tracks.length})', 'SONGS', () {
                                  setState(() => _viewMode = 'SONGS');
                                }),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: _modeButton('❤️ Favs (${favList.length})', 'FAVORITES', () {
                                  setState(() => _viewMode = 'FAVORITES');
                                }),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: _modeButton('📥 Offline (${offList.length})', 'OFFLINE', () {
                                  setState(() => _viewMode = 'OFFLINE');
                                }),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Language Daily Trending Bar
                    SizedBox(
                      height: 36,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        itemCount: _languages.length,
                        itemBuilder: (ctx, i) {
                          final lang = _languages[i];
                          final selected = (lang == _selectedLang && _viewMode == 'SONGS');
                          return Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ChoiceChip(
                              label: Text('🔥 $lang 2026',
                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                              selected: selected,
                              selectedColor: Colors.amber,
                              labelStyle: TextStyle(color: selected ? Colors.black : Colors.white),
                              onSelected: (_) => _fetchDailyTop50(lang),
                            ),
                          );
                        },
                      ),
                    ),

                    // Locked Master DJ Deck
                    if (playingTrack != null)
                      Container(
                        margin: const EdgeInsets.all(8),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [Color(0xFF141E33), Color(0xFF0B1120)]),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF00E5FF), width: 1.2),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.network(
                                    playingTrack['cover'].toString(),
                                    width: 48,
                                    height: 48,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Container(
                                      width: 48,
                                      height: 48,
                                      color: Colors.blueGrey,
                                      child: const Icon(Icons.music_note),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        playingTrack['title'].toString(),
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text(
                                        playingTrack['artist'].toString(),
                                        style: const TextStyle(fontSize: 11, color: Colors.amberAccent),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(icon: const Icon(Icons.skip_previous), onPressed: _playPrev),
                                CircleAvatar(
                                  backgroundColor: const Color(0xFF00E5FF),
                                  child: IconButton(
                                    icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.black),
                                    onPressed: () => _isPlaying ? _player.pause() : _player.resume(),
                                  ),
                                ),
                                IconButton(icon: const Icon(Icons.skip_next), onPressed: _playNext),
                              ],
                            ),
                            Slider(
                              value: _position.inSeconds
                                  .toDouble()
                                  .clamp(0, (_duration.inSeconds > 0 ? _duration.inSeconds : 1).toDouble()),
                              max: (_duration.inSeconds > 0 ? _duration.inSeconds : 1).toDouble(),
                              onChanged: (v) => _player.seek(Duration(seconds: v.toInt())),
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(_fmtDuration(_position), style: const TextStyle(fontSize: 10)),
                                Wrap(
                                  spacing: 4,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    TextButton(
                                      style: TextButton.styleFrom(
                                        backgroundColor: _isTalkoverDucked ? Colors.redAccent : Colors.white10,
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      ),
                                      onPressed: _toggleTalkoverDuck,
                                      child: Text(
                                        _isTalkoverDucked ? '🎙 MIC DUCK ON' : '🎙 DUCK 15%',
                                        style: const TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                    IconButton(
                                      icon: Icon(Icons.shuffle, size: 16, color: _shuffleMode ? Colors.amber : Colors.white54),
                                      onPressed: () => setState(() => _shuffleMode = !_shuffleMode),
                                    ),
                                    IconButton(
                                      icon: Icon(Icons.repeat_one, size: 16, color: _loopCurrent ? Colors.amber : Colors.white54),
                                      onPressed: () => setState(() => _loopCurrent = !_loopCurrent),
                                    ),
                                    DropdownButton<double>(
                                      value: _playbackSpeed,
                                      underline: const SizedBox(),
                                      items: const [
                                        DropdownMenuItem(value: 0.85, child: Text('0.85x', style: TextStyle(fontSize: 10))),
                                        DropdownMenuItem(value: 1.0, child: Text('1.0x', style: TextStyle(fontSize: 10))),
                                        DropdownMenuItem(value: 1.15, child: Text('1.15x', style: TextStyle(fontSize: 10))),
                                        DropdownMenuItem(value: 1.25, child: Text('1.25x', style: TextStyle(fontSize: 10))),
                                      ],
                                      onChanged: (val) {
                                        if (val != null) {
                                          setState(() => _playbackSpeed = val);
                                          _player.setPlaybackRate(val);
                                        }
                                      },
                                    ),
                                  ],
                                ),
                                Text(_fmtDuration(_duration), style: const TextStyle(fontSize: 10)),
                              ],
                            ),
                          ],
                        ),
                      ),

                    // Song List
                    Expanded(
                      child: _isLoading
                          ? const Center(child: CircularProgressIndicator())
                          : visibleList.isEmpty
                              ? const Center(
                                  child: Padding(
                                    padding: EdgeInsets.all(24.0),
                                    child: Text(
                                      'No songs in this tab yet. Tap ❤️ or ⬇ on any song to save it here!',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(color: Colors.white70),
                                    ),
                                  ),
                                )
                              : ListView.builder(
                                  itemCount: visibleList.length,
                                  itemBuilder: (ctx, idx) {
                                    final trk = visibleList[idx];
                                    final String id = trk['id'].toString();
                                    final bool isThisPlaying = (playingId != null && id == playingId);
                                    final bool isFav = VaultManager.isFavorite(id, isEntry: false);
                                    final bool isOff = VaultManager.isOffline(id, isEntry: false);
                                    final int? activeDlPct = dlProgress[id];

                                    return Card(
                                      color: isThisPlaying ? const Color(0xFF1E3A8A) : const Color(0xFF11192B),
                                      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      child: ListTile(
                                        leading: Stack(
                                          alignment: Alignment.bottomRight,
                                          children: [
                                            ClipRRect(
                                              borderRadius: BorderRadius.circular(6),
                                              child: Image.network(
                                                trk['cover'].toString(),
                                                width: 46,
                                                height: 46,
                                                fit: BoxFit.cover,
                                                errorBuilder: (_, __, ___) =>
                                                    const Icon(Icons.music_note, color: Colors.cyanAccent),
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
                                          '${idx + 1}. ${trk['title']}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                            color: isThisPlaying ? Colors.amberAccent : Colors.white,
                                          ),
                                        ),
                                        subtitle: Text(
                                          (isThisPlaying ? '🔊 NOW PLAYING • ' : '') +
                                              '${trk['artist']} • ${trk['quality']}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontSize: 11, color: Colors.cyanAccent),
                                        ),
                                        trailing: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                              tooltip: 'Favorite',
                                              icon: Icon(
                                                isFav ? Icons.favorite : Icons.favorite_border,
                                                color: isFav ? Colors.pinkAccent : Colors.white60,
                                                size: 22,
                                              ),
                                              onPressed: () => _onTapFavorite(trk),
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
                                                tooltip: 'Download Offline 320kbps',
                                                icon: Icon(
                                                  isOff ? Icons.check_circle : Icons.download_for_offline,
                                                  color: isOff ? Colors.amberAccent : Colors.greenAccent,
                                                  size: 23,
                                                ),
                                                onPressed: () => _onTapDownload(trk),
                                              ),
                                            IconButton(
                                              icon: Icon(
                                                (isThisPlaying && _isPlaying)
                                                    ? Icons.pause_circle_filled
                                                    : Icons.play_circle_fill,
                                                color: const Color(0xFF00E5FF),
                                                size: 30,
                                              ),
                                              onPressed: () {
                                                if (isThisPlaying) {
                                                  _isPlaying ? _player.pause() : _player.resume();
                                                } else {
                                                  _startPlaybackFromVisibleList(idx);
                                                }
                                              },
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
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

  Widget _modeButton(String label, String mode, VoidCallback onTap) {
    final active = (_viewMode == mode);
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        backgroundColor: active ? const Color(0xFF1E3A8A) : const Color(0xFF0D1526),
        side: BorderSide(color: active ? const Color(0xFF00E5FF) : Colors.white24),
        padding: const EdgeInsets.symmetric(vertical: 8),
      ),
      onPressed: onTap,
      child: Text(label, style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold)),
    );
  }
}
