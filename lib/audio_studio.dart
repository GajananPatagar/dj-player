import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'des_helper.dart';

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
  String _viewMode = 'SONGS'; // SONGS, FAVORITES, OFFLINE, YT_PLAYLISTS
  String _statusBadge = '🟢 Direct 320kbps Full-Song Engine Ready';
  String _eqPreset = 'Bass Boost';
  bool _isLoading = false;
  bool _isBusySwitching = false;

  List<Map<String, dynamic>> _tracks = [];
  List<Map<String, dynamic>> _offlineTracks = [];
  List<Map<String, dynamic>> _favoriteTracks = [];
  int _currentIndex = -1;
  bool _isPlaying = false;
  bool _loopCurrent = false;
  bool _shuffleMode = false;
  double _playbackSpeed = 1.0;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration? _abLoopStart;
  Duration? _abLoopEnd;
  Timer? _sleepTimer;
  int _sleepMinutesLeft = 0;

  @override
  void initState() {
    super.initState();
    _setupListeners();
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
      if (_loopCurrent && _currentIndex >= 0) {
        _playTrackAtIndex(_currentIndex);
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
    if (totalSec <= 0) return 'Full Song';
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

    // Multi-query aggregation to guarantee 50+ full-length trending tracks for each language
    final List<String> subQueries = [
      lang + ' Top 50 Superhit Songs',
      lang + ' Latest Hit Songs 2026',
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
      q + ' Full Song',
      q + ' Remix',
    ], isTop50: false);
  }

  /// Queries Official JioSaavn API directly (Pages 1 & 2, n=50) + decrypts full-length 320kbps URLs
  Future<void> _runDirectFullSongSearch(List<String> queries, {required bool isTop50}) async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _statusBadge = isTop50
            ? '🔄 Loading Daily Top 50 Full-Length ' + _selectedLang + ' Songs...'
            : '🔄 Searching 50+ Full-Length 320kbps Songs...';
      });
    }

    final List<Map<String, dynamic>> aggregated = [];
    final Set<String> seenIds = {};

    final Map<String, String> headers = {
      'User-Agent': 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/124.0 Mobile Safari/537.36',
      'Accept': 'application/json, text/plain, */*',
    };

    // Method 1: Official Direct www.jiosaavn.com/api.php (v4 + v3 with DES-ECB Decryption)
    for (final q in queries) {
      for (int page = 1; page <= 2; page++) {
        if (aggregated.length >= 60) break;
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

              // Skip short 30s clips—only keep full songs!
              if (durSec > 0 && durSec <= 35) continue;

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
                'quality': '320kbps FULL (' + _formatSecs(durSec) + ')',
                'isOffline': false,
              });
            }
          }
        } catch (_) {}
      }
    }

    // Method 2: Community High-Res Full-Song Mirrors if additional tracks needed
    final List<String> mirrorBases = [
      'https://saavn.sumit.co/api',
      'https://saavn.dev/api',
      'https://jiosaavn-api-privatecvc2.vercel.app'
    ];
    if (aggregated.length < 35) {
      for (final base in mirrorBases) {
        try {
          final uri = Uri.parse(
              base + '/search/songs?query=' + Uri.encodeComponent(queries.first) + '&limit=40');
          final res = await http.get(uri).timeout(const Duration(seconds: 6));
          if (res.statusCode == 200) {
            final body = jsonDecode(res.body);
            final List rawList = (body['data'] != null && body['data']['results'] != null)
                ? body['data']['results']
                : (body['results'] ?? []);
            for (final item in rawList) {
              final String id = (item['id'] ?? '').toString();
              if (id.isEmpty || seenIds.contains(id)) continue;
              final List<String> urls = [];
              if (item['downloadUrl'] is List) {
                final dList = item['downloadUrl'] as List;
                for (int i = dList.length - 1; i >= 0; i--) {
                  final u = dList[i]['url'] ?? dList[i]['link'];
                  if (u != null && u.toString().startsWith('http')) urls.add(u.toString());
                }
              }
              if (urls.isEmpty) continue;
              final int durSec = int.tryParse((item['duration'] ?? '240').toString()) ?? 240;
              seenIds.add(id);

              String cover = 'https://via.placeholder.com/150';
              if (item['image'] is List && (item['image'] as List).isNotEmpty) {
                final lastImg = (item['image'] as List).last;
                cover = (lastImg['url'] ?? lastImg['link'] ?? cover).toString();
              }

              aggregated.add({
                'id': id,
                'title': _cleanStr((item['name'] ?? item['title'] ?? 'Song').toString()),
                'artist': _cleanStr((item['primaryArtists'] ?? item['subtitle'] ?? 'Artist').toString()),
                'cover': cover,
                'urls': urls,
                'durationStr': _formatSecs(durSec),
                'quality': '320kbps FULL (' + _formatSecs(durSec) + ')',
                'isOffline': false,
              });
            }
          }
          if (aggregated.length >= 50) break;
        } catch (_) {}
      }
    }

    if (mounted) {
      setState(() {
        _tracks = aggregated;
        _isLoading = false;
        _statusBadge = '🟢 Loaded ' + aggregated.length.toString() + ' FULL-LENGTH 320kbps Songs';
      });
    }
  }

  List<Map<String, dynamic>> _currentActiveList() {
    if (_viewMode == 'OFFLINE') return _offlineTracks;
    if (_viewMode == 'FAVORITES') return _favoriteTracks;
    return _tracks;
  }

  Future<void> _playTrackAtIndex(int index) async {
    if (_isBusySwitching) return;
    final list = _currentActiveList();
    if (index < 0 || index >= list.length) return;

    _isBusySwitching = true;
    if (mounted) {
      setState(() {
        _currentIndex = index;
        _abLoopStart = null;
        _abLoopEnd = null;
        _statusBadge = '⚡ Starting Full-Length 320kbps Stream...';
      });
    }

    final track = list[index];
    try {
      if (track['isOffline'] == true && track['localPath'] != null) {
        final file = File(track['localPath'].toString());
        if (await file.exists()) {
          await _player.stop();
          await _player.play(DeviceFileSource(file.path));
          await _player.setPlaybackRate(_playbackSpeed);
          if (mounted) setState(() => _statusBadge = '🟢 Playing Full Song From Offline Vault');
          _isBusySwitching = false;
          return;
        }
      }

      final List urls = track['urls'] as List? ?? [];
      for (int i = 0; i < urls.length; i++) {
        try {
          final targetUrl = urls[i].toString();
          await _player.stop();
          await _player.play(UrlSource(targetUrl));
          await _player.setPlaybackRate(_playbackSpeed);
          if (mounted) {
            setState(() {
              _statusBadge = '🟢 Playing Full Song: ' + track['title'].toString() + ' [320kbps]';
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
    final list = _currentActiveList();
    if (list.isEmpty) return;
    if (_shuffleMode && list.length > 1) {
      final next = DateTime.now().millisecond % list.length;
      _playTrackAtIndex(next);
    } else {
      _playTrackAtIndex((_currentIndex + 1) % list.length);
    }
  }

  void _playPrev() {
    final list = _currentActiveList();
    if (list.isEmpty) return;
    _playTrackAtIndex((_currentIndex - 1 + list.length) % list.length);
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

  void _setSleepTimer(int mins) {
    _sleepTimer?.cancel();
    setState(() => _sleepMinutesLeft = mins);
    if (mins <= 0) return;
    _sleepTimer = Timer.periodic(const Duration(minutes: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_sleepMinutesLeft <= 1) {
        t.cancel();
        _player.pause();
        setState(() => _sleepMinutesLeft = 0);
      } else {
        setState(() => _sleepMinutesLeft -= 1);
      }
    });
  }

  String _fmtDuration(Duration d) {
    final mins = d.inMinutes;
    final secs = d.inSeconds % 60;
    return mins.toString() + ':' + (secs < 10 ? '0' + secs.toString() : secs.toString());
  }

  @override
  Widget build(BuildContext context) {
    final activeList = _currentActiveList();
    final currentTrack = (_currentIndex >= 0 && _currentIndex < activeList.length)
        ? activeList[_currentIndex]
        : null;

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

        // Search Input + Quick Filter Buttons
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
                        hintText: 'Search any full song, movie, DJ remix or artist...',
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
                    _modeButton('📺 YT Nonstop Mix', 'YT', () {
                      final q = _searchCtrl.text.trim().isEmpty
                          ? _selectedLang + ' DJ Nonstop Jukebox'
                          : _searchCtrl.text.trim();
                      _searchUserQuery(q);
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

        // Full-Length Master DJ Deck
        if (currentTrack != null)
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
                        currentTrack['cover'].toString(),
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
                            currentTrack['title'].toString(),
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            currentTrack['artist'].toString(),
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
                        TextButton(
                          onPressed: () {
                            setState(() {
                              if (_abLoopStart == null) {
                                _abLoopStart = _position;
                              } else if (_abLoopEnd == null) {
                                _abLoopEnd = _position;
                              } else {
                                _abLoopStart = null;
                                _abLoopEnd = null;
                              }
                            });
                          },
                          child: Text(
                            _abLoopStart == null
                                ? 'A-B'
                                : (_abLoopEnd == null ? 'A Set' : 'A-B ON'),
                            style: const TextStyle(fontSize: 10, color: Colors.cyanAccent),
                          ),
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

        // Full-Length Track List (50+ items)
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : ListView.builder(
                  itemCount: activeList.length,
                  itemBuilder: (ctx, idx) {
                    final trk = activeList[idx];
                    final isFav = _favoriteTracks.any((e) => e['id'] == trk['id']);
                    return Card(
                      color: (_currentIndex == idx) ? const Color(0xFF1A2947) : const Color(0xFF11192B),
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
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        subtitle: Text(
                          trk['artist'].toString() + ' • ' + trk['quality'].toString(),
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
                              icon: const Icon(Icons.download_for_offline, color: Colors.greenAccent, size: 22),
                              onPressed: () => _downloadFullTrackOffline(trk),
                            ),
                            IconButton(
                              icon: const Icon(Icons.play_circle_fill, color: Color(0xFF00E5FF), size: 30),
                              onPressed: () => _playTrackAtIndex(idx),
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
