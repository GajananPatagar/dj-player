import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  String _statusBadge = '🟢 Direct 320kbps Full-Song Engine Ready';
  bool _isLoading = false;
  bool _isBusySwitching = false;

  // Separate Search List vs Active Playback Queue (Fixes the Now-Playing Glitch!)
  List<Map<String, dynamic>> _tracks = [];
  List<Map<String, dynamic>> _offlineTracks = [];
  List<Map<String, dynamic>> _favoriteTracks = [];
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
  Duration? _abLoopStart;
  Duration? _abLoopEnd;

  @override
  void initState() {
    super.initState();
    _setupListeners();
    MasterVolumeController.page1MusicVolume.addListener(() {
      if (!_isTalkoverDucked) {
        _player.setVolume(MasterVolumeController.page1MusicVolume.value);
      }
    });
    _loadSavedVaults();
    _fetchDailyTop50('Kannada');
  }

  void _setupListeners() {
    _player.onPositionChanged.listen((pos) {
      if (!mounted) return;
      if (_abLoopStart != null && _abLoopEnd != null && pos >= _abLoopEnd!) {
        _player.seek(_abLoopStart!);
      }
      setState(() => _position = pos);
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

  Future<void> _loadSavedVaults() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final offRaw = prefs.getStringList('offline_vault_v22') ?? [];
      final favRaw = prefs.getStringList('fav_vault_v22') ?? [];
      if (mounted) {
        setState(() {
          _offlineTracks = offRaw.map((e) => Map<String, dynamic>.from(jsonDecode(e))).toList();
          _favoriteTracks = favRaw.map((e) => Map<String, dynamic>.from(jsonDecode(e))).toList();
        });
      }
    } catch (_) {}
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

  Future<void> _fetchDailyTop50(String lang) async {
    if (!mounted) return;
    setState(() {
      _selectedLang = lang;
      _viewMode = 'SONGS';
    });

    final List<String> subQueries = [
      lang + ' Top 50 Superhit Songs',
      lang + ' Latest Blockbuster Hits',
      lang + ' DJ Remix Nonstop Hits',
    ];
    await _runDirectFullSongSearch(subQueries, isTop50: true);
  }

  Future<void> _searchUserQuery(String rawQuery) async {
    final q = rawQuery.trim();
    if (q.isEmpty) return;
    setState(() => _viewMode = 'SONGS');
    await _runDirectFullSongSearch([
      q,
      q + ' Hit Song',
    ], isTop50: false);
  }

  Future<void> _runDirectFullSongSearch(List<String> queries, {required bool isTop50}) async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _statusBadge = isTop50
            ? '🔄 Loading Daily Top 50 Famous ' + _selectedLang + ' Full Songs...'
            : '🔄 Searching Famous Full-Length 320kbps Songs...';
      });
    }

    final List<Map<String, dynamic>> aggregated = [];
    final Set<String> seenIds = {};

    final Map<String, String> headers = {
      'User-Agent': 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/124.0 Mobile Safari/537.36',
      'Accept': 'application/json, text/plain, */*',
    };

    for (final q in queries) {
      for (int page = 1; page <= 2; page++) {
        if (aggregated.length >= 65) break;
        try {
          final String directUrl =
              'https://www.jiosaavn.com/api.php?__call=search.getResults&_format=json&_marker=0&api_version=4&ctx=web6dot0&n=40&p=' +
                  page.toString() +
                  '&q=' +
                  Uri.encodeComponent(q);
          final res = await http.get(Uri.parse(directUrl), headers: headers).timeout(const Duration(seconds: 7));
          if (res.statusCode == 200) {
            final decoded = jsonDecode(res.body);
            final List results = decoded['results'] ?? [];
            for (final item in results) {
              final String id = (item['id'] ?? '').toString();
              if (id.isEmpty || seenIds.contains(id)) continue;

              final Map moreInfo = (item['more_info'] is Map) ? item['more_info'] : {};
              final String? encUrl = (moreInfo['encrypted_media_url'] ?? item['encrypted_media_url'])?.toString();
              final String? prevUrl = (moreInfo['vlink'] ?? item['media_preview_url'])?.toString();
              final int durSec = int.tryParse((moreInfo['duration'] ?? item['duration'] ?? '0').toString()) ?? 0;
              final int playCount = int.tryParse((item['play_count'] ?? moreInfo['play_count'] ?? '10000').toString()) ?? 10000;

              if (durSec > 0 && durSec <= 40) continue;

              final List<String> fullUrls = SaavnDesDecryptor.decryptToFullUrls(encUrl, prevUrl);
              if (fullUrls.isEmpty) continue;

              seenIds.add(id);
              final String title = _cleanStr((item['title'] ?? item['song'] ?? 'Track').toString());
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
                'playCount': playCount,
                'quality': '320kbps FULL (' + _formatSecs(durSec) + ')',
                'isOffline': false,
              });
            }
          }
        } catch (_) {}
      }
    }

    // Sort by popularity so famous hits appear first
    if (isTop50) {
      aggregated.sort((a, b) => ((b['playCount'] ?? 0) as int).compareTo((a['playCount'] ?? 0) as int));
    }

    if (mounted) {
      setState(() {
        _tracks = aggregated;
        _isLoading = false;
        _statusBadge = '🟢 Loaded ' + aggregated.length.toString() + ' Famous Full-Length Songs';
      });
    }
  }

  List<Map<String, dynamic>> _currentVisibleList() {
    if (_viewMode == 'OFFLINE') return _offlineTracks;
    if (_viewMode == 'FAVORITES') return _favoriteTracks;
    return _tracks;
  }

  /// Locks the clicked list into _playbackQueue and sets _nowPlayingTrack independently
  /// so searching new songs NEVER changes the currently playing song display!
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
        _abLoopStart = null;
        _abLoopEnd = null;
        _statusBadge = '⚡ Starting Full Song: ' + track['title'].toString();
      });
    }

    try {
      final double targetVol = _isTalkoverDucked ? 0.15 : MasterVolumeController.page1MusicVolume.value;

      if (track['isOffline'] == true && track['localPath'] != null) {
        final file = File(track['localPath'].toString());
        if (await file.exists()) {
          await _player.stop();
          await _player.setVolume(targetVol);
          await _player.play(DeviceFileSource(file.path));
          await _player.setPlaybackRate(_playbackSpeed);
          if (mounted) setState(() => _statusBadge = '🟢 Playing Offline Full Song: ' + track['title'].toString());
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

  Future<void> _toggleFavorite(Map<String, dynamic> track) async {
    final prefs = await SharedPreferences.getInstance();
    final favRaw = prefs.getStringList('fav_vault_v22') ?? [];
    final exists = favRaw.any((e) => jsonDecode(e)['id'] == track['id']);
    if (exists) {
      favRaw.removeWhere((e) => jsonDecode(e)['id'] == track['id']);
    } else {
      favRaw.insert(0, jsonEncode(track));
    }
    await prefs.setStringList('fav_vault_v22', favRaw);
    await _loadSavedVaults();
  }

  Future<void> _downloadFullTrackOffline(Map<String, dynamic> track) async {
    final List urls = track['urls'] as List? ?? [];
    if (urls.isEmpty) return;

    if (mounted) {
      setState(() => _statusBadge = '⬇ Saving Full 320kbps Song: ' + track['title'].toString());
    }

    for (final rawUrl in urls) {
      try {
        final res = await http.get(Uri.parse(rawUrl.toString())).timeout(const Duration(seconds: 40));
        if (res.statusCode == 200 && res.bodyBytes.length > 50000) {
          final dir = await getApplicationDocumentsDirectory();
          final safeId = track['id'].toString().replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
          final file = File(dir.path + '/full_320k_' + safeId + '.mp4');
          await file.writeAsBytes(res.bodyBytes);

          final offlineEntry = {
            ...track,
            'localPath': file.path,
            'quality': 'OFFLINE FULL 320K',
            'isOffline': true,
          };

          final prefs = await SharedPreferences.getInstance();
          final raw = prefs.getStringList('offline_vault_v22') ?? [];
          raw.removeWhere((e) => jsonDecode(e)['id'] == track['id']);
          raw.insert(0, jsonEncode(offlineEntry));
          await prefs.setStringList('offline_vault_v22', raw);
          await _loadSavedVaults();

          if (mounted) {
            setState(() => _statusBadge = '✅ Full Song Saved Offline: ' + track['title'].toString());
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Full 320kbps Song Saved Offline: ' + track['title'].toString())),
            );
          }
          return;
        }
      } catch (_) {}
    }
  }

  String _fmtDuration(Duration d) {
    final mins = d.inMinutes;
    final secs = d.inSeconds % 60;
    return mins.toString() + ':' + (secs < 10 ? '0' + secs.toString() : secs.toString());
  }

  @override
  Widget build(BuildContext context) {
    final visibleList = _currentVisibleList();
    final playingTrack = _nowPlayingTrack;
    final String? playingId = playingTrack?['id']?.toString();

    return Column(
      children: [
        // Top Status Bar
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
                '❤️ ' + _favoriteTracks.length.toString() + '  📥 ' + _offlineTracks.length.toString(),
                style: const TextStyle(fontSize: 11, color: Colors.amberAccent, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),

        // Search Input + Filter Buttons
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
                    child: const Text('Search 50+', style: TextStyle(fontWeight: FontWeight.w900)),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _modeButton('🔥 Top 50 (' + _tracks.length.toString() + ')', 'SONGS', () {
                      setState(() => _viewMode = 'SONGS');
                    }),
                    const SizedBox(width: 6),
                    _modeButton('❤️ Favorites (' + _favoriteTracks.length.toString() + ')', 'FAVORITES', () {
                      setState(() => _viewMode = 'FAVORITES');
                    }),
                    const SizedBox(width: 6),
                    _modeButton('📥 Offline (' + _offlineTracks.length.toString() + ')', 'OFFLINE', () {
                      setState(() => _viewMode = 'OFFLINE');
                    }),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Daily Top 50 Language Selector
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
                  label: Text('🔥 ' + lang + ' Top 50',
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

        // Locked Master DJ Deck (Never glitches when searching new songs!)
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
                          tooltip: 'Shuffle',
                          icon: Icon(Icons.shuffle, size: 16, color: _shuffleMode ? Colors.amber : Colors.white54),
                          onPressed: () => setState(() => _shuffleMode = !_shuffleMode),
                        ),
                        IconButton(
                          tooltip: 'Loop Song',
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

        // Track List
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : ListView.builder(
                  itemCount: visibleList.length,
                  itemBuilder: (ctx, idx) {
                    final trk = visibleList[idx];
                    final isThisPlaying = (playingId != null && trk['id'].toString() == playingId);
                    final isFav = _favoriteTracks.any((e) => e['id'] == trk['id']);
                    final isOff = _offlineTracks.any((e) => e['id'] == trk['id']);
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
                                errorBuilder: (_, __, ___) => const Icon(Icons.music_note, color: Colors.cyanAccent),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                              color: Colors.black87,
                              child: Text(
                                (trk['durationStr'] ?? 'Full').toString(),
                                style: const TextStyle(fontSize: 8, color: Colors.greenAccent, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                        title: Text(
                          (idx + 1).toString() + '. ' + trk['title'].toString(),
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
                              trk['artist'].toString() +
                              ' • ' +
                              trk['quality'].toString(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11, color: Colors.cyanAccent),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: Icon(isFav ? Icons.favorite : Icons.favorite_border,
                                  color: isFav ? Colors.pinkAccent : Colors.white54, size: 20),
                              onPressed: () => _toggleFavorite(trk),
                            ),
                            IconButton(
                              icon: Icon(
                                isOff ? Icons.offline_pin : Icons.download_for_offline,
                                color: isOff ? Colors.amberAccent : Colors.greenAccent,
                                size: 22,
                              ),
                              onPressed: () => _downloadFullTrackOffline(trk),
                            ),
                            IconButton(
                              icon: Icon(
                                (isThisPlaying && _isPlaying) ? Icons.pause_circle_filled : Icons.play_circle_fill,
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
  }

  Widget _modeButton(String label, String mode, VoidCallback onTap) {
    final active = (_viewMode == mode);
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        backgroundColor: active ? const Color(0xFF1E3A8A) : const Color(0xFF0D1526),
        side: BorderSide(color: active ? const Color(0xFF00E5FF) : Colors.white24),
      ),
      onPressed: onTap,
      child: Text(label, style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold)),
    );
  }
}
