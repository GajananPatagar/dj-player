import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:audioplayers/audioplayers.dart';
import 'des_helper.dart';
import 'entry_music_data.dart';
import 'glass_widgets.dart';
import 'karaoke_engine.dart';
import 'ota_update_engine.dart';
import 'main.dart';

class AudioStudioScreen extends StatefulWidget {
  const AudioStudioScreen({super.key});

  @override
  State<AudioStudioScreen> createState() => _AudioStudioScreenState();
}

class _AudioStudioScreenState extends State<AudioStudioScreen> with WidgetsBindingObserver {
  static const MethodChannel _nativeChannel = MethodChannel('dj_native_tts');

  final AudioPlayer _player = AudioPlayer();
  final TextEditingController _searchCtrl = TextEditingController();

  final List<Map<String, String>> _onlineCategories = const [
    {'label': '👑 Kannada', 'key': 'Kannada', 'query': 'Kannada Superhit Songs'},
    {'label': '🇮🇳 Hindi', 'key': 'Hindi', 'query': 'Hindi Bollywood Hit Songs'},
    {'label': '💍 Marriage', 'key': 'Marriage', 'query': 'Indian Wedding Marriage Dance Songs Kannada Hindi'},
    {'label': '👗 Fashion Show', 'key': 'Fashion Show', 'query': 'Fashion Show Ramp Walk Bass Runway Music'},
    {'label': '🪔 Devotional', 'key': 'Devotional', 'query': 'Kannada Hindi Devotional Bhakti Songs Aarti'},
    {'label': '🔥 DJ Bass Remix', 'key': 'DJ Bass & Party', 'query': 'DJ Bass Boosted Nonstop Remix Songs'},
    {'label': '⚡ Mass Entry', 'key': 'Mass Entry', 'query': 'Mass Hero Entry BGM Funk Phonk Bass'},
    {'label': '🥁 Janapada Folk', 'key': 'Janapada & Folk', 'query': 'Kannada Janapada DJ Folk Songs'},
    {'label': '🌍 English & Phonk', 'key': 'English', 'query': 'English Viral Hits Phonk Pop Songs'},
    {'label': '🎬 Telugu', 'key': 'Telugu', 'query': 'Telugu Mass Hit Songs'},
    {'label': '🎬 Tamil', 'key': 'Tamil', 'query': 'Tamil Anirudh Superhit Songs'},
    {'label': '🎬 Malayalam', 'key': 'Malayalam', 'query': 'Malayalam Trending Hit Songs'},
    {'label': '🥁 Punjabi', 'key': 'Punjabi', 'query': 'Punjabi Party Bhangra Hit Songs'},
  ];

  String _selectedOnlineCat = 'Kannada';
  String _selectedOfflineCategory = 'Marriage';
  String _viewMode = 'SONGS'; // SONGS, FAVORITES, OFFLINE
  String _activeQueueScopeBanner = '🌐 Online Queue Active';
  String _statusBadge = '🟢 v505.0 Ultra Pro • Any-Song Engine & Screen-Off Lock Ready';

  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _isBusySwitching = false;
  bool _showQuickDjPads = false;
  bool _autoDjCrossfade = true;
  int _currentSearchPage = 1;
  List<String> _lastActiveQueries = ['Kannada Superhit Songs'];

  List<Map<String, dynamic>> _tracks = [];
  List<Map<String, dynamic>> _playbackQueue = [];
  Map<String, dynamic>? _nowPlayingTrack;
  int _queueIndex = -1;

  bool _isPlaying = false;
  bool _shouldBePlayingInBg = false;
  bool _loopCurrent = false;
  bool _shuffleMode = false;
  bool _isTalkoverDucked = false;
  double _playbackSpeed = 1.0;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  // Pro A-B Loop & Sleep Timer & Equalizer state
  int? _loopPointASec;
  int? _loopPointBSec;
  Timer? _sleepTimer;
  int? _sleepTimerMinutesLeft;
  String? _preCachedNextTrackId;
  String? _preCachedNextLocalPath;

  // Hardware 5-Band EQ & Bass Boost state
  double _bassBoostStrength = 0.80;
  double _loudnessGain = 0.65;
  List<double> _eqBands = [0.65, 0.55, 0.50, 0.60, 0.72];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    VaultManager.initVaults().then((_) {
      if (VaultManager.offlineCategories.value.isNotEmpty) {
        _selectedOfflineCategory = VaultManager.offlineCategories.value.first;
      }
      if (mounted) setState(() {});
    });
    _configureBackgroundAudioContext();
    _setupListeners();
    _registerNativeMediaCallbacks();

    MasterVolumeController.page1MusicVolume.addListener(() {
      if (!_isTalkoverDucked) {
        _player.setVolume(MasterVolumeController.page1MusicVolume.value);
      }
    });

    OtaUpdateEngine.initAutoOtaAndDailySelfUpdate(
      onDailyContentRefresh: () async {
        await _fetchCategoryOrTrending(_selectedOnlineCat, resetPage: true);
      },
    );

    _fetchCategoryOrTrending('Kannada', resetPage: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sleepTimer?.cancel();
    super.dispose();
  }

  Future<void> _configureBackgroundAudioContext() async {
    try {
      await AudioPlayer.global.setAudioContext(
        AudioContext(
          android: const AudioContextAndroid(
            isSpeakerphoneOn: false,
            stayAwake: true,
            contentType: AndroidContentType.music,
            usageType: AndroidUsageType.media,
            audioFocus: AndroidAudioFocus.gain,
          ),
        ),
      );
      await _player.setReleaseMode(ReleaseMode.stop);
    } catch (_) {}
  }

  void _registerNativeMediaCallbacks() {
    AppSoundEngine.mediaNotificationActionNotifier.addListener(() async {
      final String? raw = AppSoundEngine.mediaNotificationActionNotifier.value;
      if (raw != null && raw.isNotEmpty) {
        final String action = raw.split('##').first;
        if (action == 'NEXT') {
          _playNext();
        } else if (action == 'PREV') {
          _playPrev();
        } else if (action == 'TOGGLE') {
          if (_isPlaying) {
            _shouldBePlayingInBg = false;
            await _player.pause();
            _syncForegroundNotification();
          } else {
            _shouldBePlayingInBg = true;
            await _player.resume();
            _syncForegroundNotification();
          }
        } else if (action == 'HEARTBEAT') {
          if (_shouldBePlayingInBg && !_isBusySwitching && _nowPlayingTrack != null) {
            if (_duration.inMilliseconds > 4000 &&
                _position.inMilliseconds >= (_duration.inMilliseconds - 450)) {
              _handleTrackCompleted();
            } else if (!_isPlaying &&
                _duration.inMilliseconds > 4000 &&
                _position.inMilliseconds >= (_duration.inMilliseconds - 1500)) {
              _handleTrackCompleted();
            }
          }
        }
      }
    });
  }

  void _setupListeners() {
    _player.onPositionChanged.listen((pos) {
      if (mounted) {
        setState(() => _position = pos);
      } else {
        _position = pos;
      }

      if (_loopPointASec != null &&
          _loopPointBSec != null &&
          _loopPointBSec! > _loopPointASec! &&
          pos.inSeconds >= _loopPointBSec!) {
        _player.seek(Duration(seconds: _loopPointASec!));
        return;
      }

      if (_shouldBePlayingInBg &&
          !_isBusySwitching &&
          _duration.inMilliseconds > 5000 &&
          pos.inMilliseconds >= (_duration.inMilliseconds - 320)) {
        _handleTrackCompleted();
      }
    });

    _player.onDurationChanged.listen((dur) {
      if (mounted) {
        setState(() => _duration = dur);
      } else {
        _duration = dur;
      }
    });

    _player.onPlayerComplete.listen((_) {
      _handleTrackCompleted();
    });

    _player.onPlayerStateChanged.listen((state) {
      final bool playingNow = (state == PlayerState.playing);
      if (mounted) {
        setState(() => _isPlaying = playingNow);
      } else {
        _isPlaying = playingNow;
      }
      if (state == PlayerState.completed) {
        _handleTrackCompleted();
      }
    });
  }

  void _handleTrackCompleted() {
    if (_isBusySwitching || _playbackQueue.isEmpty) return;
    if (_loopCurrent && _nowPlayingTrack != null) {
      _playFromQueueIndex(_queueIndex);
    } else {
      _playNext();
    }
  }

  Future<void> _syncForegroundNotification() async {
    if (_nowPlayingTrack == null) return;
    try {
      await _nativeChannel.invokeMethod('updateMediaNotification', {
        'title': (_nowPlayingTrack!['title'] ?? 'DJ Pro Track').toString(),
        'artist': '${_nowPlayingTrack!['artist'] ?? 'DJ Player'} • $_activeQueueScopeBanner',
        'isPlaying': _isPlaying || _shouldBePlayingInBg,
      });
    } catch (_) {}
  }

  Future<void> _preCacheNextTrackInBackground() async {
    if (_playbackQueue.length < 2 || _queueIndex < 0) return;
    final int nextIdx = (_queueIndex + 1) % _playbackQueue.length;
    final Map<String, dynamic> nextTrack = _playbackQueue[nextIdx];
    final String nextId = (nextTrack['id'] ?? '').toString();
    if (nextId.isEmpty || nextId == _preCachedNextTrackId) return;

    if (nextTrack['localPath'] != null && File(nextTrack['localPath'].toString()).existsSync()) {
      _preCachedNextTrackId = nextId;
      _preCachedNextLocalPath = nextTrack['localPath'].toString();
      return;
    }

    final List urls = (nextTrack['urls'] as List?) ?? [];
    if (urls.isEmpty) return;

    try {
      final dir = await getTemporaryDirectory();
      final File cacheFile = File('${dir.path}/bg_next_cache.mp4');
      for (final rawUrl in urls) {
        try {
          final res = await http.get(
            Uri.parse(rawUrl.toString()),
            headers: {'User-Agent': 'Mozilla/5.0 (Linux; Android 14)'},
          ).timeout(const Duration(seconds: 25));
          if (res.statusCode == 200 && res.bodyBytes.length > 30000) {
            await cacheFile.writeAsBytes(res.bodyBytes, flush: true);
            _preCachedNextTrackId = nextId;
            _preCachedNextLocalPath = cacheFile.path;
            break;
          }
        } catch (_) {}
      }
    } catch (_) {}
  }

  Future<void> _fetchCategoryOrTrending(String catKey, {bool resetPage = true}) async {
    if (!mounted) return;
    setState(() {
      _selectedOnlineCat = catKey;
      _viewMode = 'SONGS';
      if (resetPage) _currentSearchPage = 1;
    });

    final DateTime now = DateTime.now();
    final int daySeed = now.year * 1000 + now.month * 35 + now.day;

    final Map<String, String> catObj = _onlineCategories.firstWhere(
      (c) => c['key'] == catKey,
      orElse: () => _onlineCategories.first,
    );
    final String baseQuery = catObj['query']!;

    final List<String> rotatingFlavors = [
      '2026 New Hits',
      'Superhit Songs',
      'Top Chartbusters',
      'Viral Trending Songs',
      'DJ Party Hits',
      'Evergreen Blockbusters',
    ];
    final String f1 = rotatingFlavors[daySeed % rotatingFlavors.length];
    final String f2 = rotatingFlavors[(daySeed + 2) % rotatingFlavors.length];

    final List<String> subQueries = [
      baseQuery,
      '$catKey $f1',
      '$catKey $f2',
      '$catKey Full Songs',
    ];
    _lastActiveQueries = subQueries;
    await _executeOmniSearch(subQueries, isTrendingMode: true, append: !resetPage);
  }

  Future<void> _searchAnySongWorldwide(String rawQuery) async {
    final String q = rawQuery.trim();
    if (q.isEmpty) {
      await _fetchCategoryOrTrending(_selectedOnlineCat, resetPage: true);
      return;
    }
    setState(() {
      _viewMode = 'SONGS';
      _currentSearchPage = 1;
    });
    final List<String> queries = [
      q,
      '$q Full Song',
      '$q $_selectedOnlineCat',
      '$q DJ Remix',
    ];
    _lastActiveQueries = queries;
    await _executeOmniSearch(queries, isTrendingMode: false, append: false);
  }

  Future<void> _loadMoreSongsNextPage() async {
    if (_isLoading || _isLoadingMore) return;
    setState(() {
      _isLoadingMore = true;
      _currentSearchPage += 2;
      _statusBadge = '🔄 Loading 50+ More Full Songs (Page $_currentSearchPage)...';
    });
    await _executeOmniSearch(_lastActiveQueries, isTrendingMode: false, append: true);
  }

  Future<void> _executeOmniSearch(
    List<String> queries, {
    required bool isTrendingMode,
    required bool append,
  }) async {
    if (mounted && !append) {
      setState(() {
        _isLoading = true;
        _statusBadge = isTrendingMode
            ? '🔄 Loading $_selectedOnlineCat Songs (Multi-Engine 320kbps)...'
            : '🔍 Searching Worldwide Catalog for "${queries.first}"...';
      });
    }

    final List<Map<String, dynamic>> fetched = await SaavnDesDecryptor.omniSearchSongs(
      queries,
      startPage: _currentSearchPage,
      pagesPerQuery: 2,
      isTrendingMode: isTrendingMode,
    );

    if (mounted) {
      setState(() {
        if (append) {
          final Set<String> existingIds = _tracks.map((e) => e['id'].toString()).toSet();
          for (final item in fetched) {
            if (!existingIds.contains(item['id'].toString())) {
              _tracks.add(item);
            }
          }
        } else {
          _tracks = fetched;
        }
        _isLoading = false;
        _isLoadingMore = false;
        _statusBadge = '🟢 ${_tracks.length} Full Songs Ready • Screen-Off Auto-Next Active';
      });
    }
  }

  List<Map<String, dynamic>> _currentVisibleList() {
    if (_viewMode == 'OFFLINE') {
      return VaultManager.getOfflineSongsByCategory(_selectedOfflineCategory);
    }
    if (_viewMode == 'FAVORITES') {
      return VaultManager.favSongs.value;
    }
    return _tracks;
  }

  /// Syncs `_playbackQueue` whenever the user changes Song Numbers inside the currently active Offline Folder or Favorites!
  void _refreshActiveQueueAfterReorder() {
    final List<Map<String, dynamic>> updatedVisible = _currentVisibleList();
    if (_playbackQueue.isEmpty || _nowPlayingTrack == null) return;
    final String currentPlayingId = _nowPlayingTrack!['id'].toString();
    final bool isCurrentInUpdated = updatedVisible.any((e) => e['id'].toString() == currentPlayingId);
    if (isCurrentInUpdated) {
      _playbackQueue = List<Map<String, dynamic>>.from(updatedVisible);
      _queueIndex = _playbackQueue.indexWhere((e) => e['id'].toString() == currentPlayingId);
    }
  }

  Future<void> _startPlaybackFromVisibleList(int index, {bool enableShuffle = false}) async {
    final List<Map<String, dynamic>> visible = _currentVisibleList();
    if (index < 0 || index >= visible.length) return;

    _playbackQueue = List<Map<String, dynamic>>.from(visible);
    if (_viewMode == 'OFFLINE') {
      _activeQueueScopeBanner =
          '🔒 Offline Folder Lock: $_selectedOfflineCategory Only (${_playbackQueue.length} Songs)';
    } else if (_viewMode == 'FAVORITES') {
      _activeQueueScopeBanner = '❤️ Favorites Queue (${_playbackQueue.length} Songs)';
    } else {
      _activeQueueScopeBanner = '🌐 $_selectedOnlineCat Queue (${_playbackQueue.length} Songs)';
    }

    if (enableShuffle) {
      _shuffleMode = true;
    }
    await _playFromQueueIndex(index);
  }

  Future<void> _playFromQueueIndex(int qIdx) async {
    if (_isBusySwitching) return;
    if (_playbackQueue.isEmpty || qIdx < 0 || qIdx >= _playbackQueue.length) return;

    _isBusySwitching = true;
    _shouldBePlayingInBg = true;
    _loopPointASec = null;
    _loopPointBSec = null;
    _position = Duration.zero;

    final Map<String, dynamic> track = _playbackQueue[qIdx];
    final String trackId = (track['id'] ?? '').toString();
    final int customStartSec = int.tryParse((track['customStartSec'] ?? '0').toString()) ?? 0;

    if (mounted) {
      setState(() {
        _queueIndex = qIdx;
        _nowPlayingTrack = Map<String, dynamic>.from(track);
        _statusBadge = '⚡ Playing #${qIdx + 1}: ${track['title']}';
      });
    } else {
      _queueIndex = qIdx;
      _nowPlayingTrack = Map<String, dynamic>.from(track);
    }

    _syncForegroundNotification();

    try {
      final double targetVol = _isTalkoverDucked ? 0.15 : MasterVolumeController.page1MusicVolume.value;

      if (track['localPath'] != null) {
        final File file = File(track['localPath'].toString());
        if (await file.exists()) {
          await _player.stop();
          await _player.setVolume(targetVol);
          await _player.play(DeviceFileSource(file.path));
          await _player.setPlaybackRate(_playbackSpeed);
          if (customStartSec > 0) {
            await _player.seek(Duration(seconds: customStartSec));
          }
          if (mounted) {
            setState(() {
              _statusBadge =
                  '🟢 Offline #${qIdx + 1} [${track['category'] ?? _selectedOfflineCategory}]: ${track['title']}';
            });
          }
          _isBusySwitching = false;
          _syncForegroundNotification();
          _preCacheNextTrackInBackground();
          return;
        }
      }

      if (_preCachedNextTrackId == trackId &&
          _preCachedNextLocalPath != null &&
          File(_preCachedNextLocalPath!).existsSync()) {
        await _player.stop();
        await _player.setVolume(targetVol);
        await _player.play(DeviceFileSource(_preCachedNextLocalPath!));
        await _player.setPlaybackRate(_playbackSpeed);
        if (customStartSec > 0) {
          await _player.seek(Duration(seconds: customStartSec));
        }
        if (mounted) {
          setState(() {
            _statusBadge = '🟢 Instant Cached #${qIdx + 1}: ${track['title']}';
          });
        }
        _isBusySwitching = false;
        _syncForegroundNotification();
        _preCacheNextTrackInBackground();
        return;
      }

      final List urls = (track['urls'] as List?) ?? [];
      bool started = false;
      for (final rawUrl in urls) {
        try {
          await _player.stop();
          await _player.play(UrlSource(rawUrl.toString()), volume: targetVol);
          await _player.setPlaybackRate(_playbackSpeed);
          if (customStartSec > 0) {
            await _player.seek(Duration(seconds: customStartSec));
          }
          started = true;
          if (mounted) {
            setState(() {
              _statusBadge = '🟢 Playing #${qIdx + 1}: ${track['title']}';
            });
          }
          break;
        } catch (_) {}
      }

      if (!started && _playbackQueue.length > 1) {
        _isBusySwitching = false;
        _playNext();
        return;
      }
    } finally {
      _isBusySwitching = false;
      _syncForegroundNotification();
      _preCacheNextTrackInBackground();
    }
  }

  void _playNext() {
    if (_playbackQueue.isEmpty) return;
    if (_shuffleMode && _playbackQueue.length > 1) {
      int next = DateTime.now().microsecond % _playbackQueue.length;
      if (next == _queueIndex) {
        next = (next + 1) % _playbackQueue.length;
      }
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

  /// Opens the Interactive Song Number Sequencer Modal!
  /// Lets the user change the exact Song Number (#1, #2, #3...) inside Offline Category Folders, Favorites, or Online list!
  Future<void> _promptChangeSongNumberDialog(Map<String, dynamic> trk, int currentIdx) async {
    final List<Map<String, dynamic>> currentList = _currentVisibleList();
    if (currentList.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least 2 songs in this section to change song numbers!')),
      );
      return;
    }

    final String id = (trk['id'] ?? '').toString();
    final int currentSongNumber = currentIdx + 1;
    final int totalSongs = currentList.length;
    final TextEditingController numCtrl = TextEditingController(text: '$currentSongNumber');

    final int? targetOneBasedNum = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: GlassBox(
            margin: const EdgeInsets.all(10),
            padding: const EdgeInsets.all(16),
            borderRadius: 24,
            blur: 20,
            tintColor: const Color(0xFF0B1426),
            borderColor: Colors.amberAccent,
            borderWidth: 1.5,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.format_list_numbered_rounded, color: Colors.amberAccent, size: 26),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '🔢 Change Song Number (Currently #$currentSongNumber of $totalSongs)',
                            style: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            trk['title'].toString(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11.5, color: Color(0xFF00E5FF)),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white60),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Quick Shift Buttons (Move to #1, Move Up, Move Down, Move to Last)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00E676),
                        foregroundColor: Colors.black,
                        visualDensity: VisualDensity.compact,
                      ),
                      icon: const Icon(Icons.vertical_align_top_rounded, size: 16),
                      label: const Text('Make #1 (Top)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900)),
                      onPressed: () => Navigator.pop(ctx, 1),
                    ),
                    if (currentSongNumber > 1)
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00E5FF),
                          foregroundColor: Colors.black,
                          visualDensity: VisualDensity.compact,
                        ),
                        icon: const Icon(Icons.arrow_upward_rounded, size: 16),
                        label: Text(
                          'Move Up (#${currentSongNumber - 1})',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
                        ),
                        onPressed: () => Navigator.pop(ctx, currentSongNumber - 1),
                      ),
                    if (currentSongNumber < totalSongs)
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.amberAccent,
                          foregroundColor: Colors.black,
                          visualDensity: VisualDensity.compact,
                        ),
                        icon: const Icon(Icons.arrow_downward_rounded, size: 16),
                        label: Text(
                          'Move Down (#${currentSongNumber + 1})',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
                        ),
                        onPressed: () => Navigator.pop(ctx, currentSongNumber + 1),
                      ),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.white38),
                        visualDensity: VisualDensity.compact,
                      ),
                      icon: const Icon(Icons.vertical_align_bottom_rounded, size: 16, color: Colors.white),
                      label: Text(
                        'Move Last (#$totalSongs)',
                        style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                      onPressed: () => Navigator.pop(ctx, totalSongs),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                const Text(
                  'Tap Any Number Below to Jump Directly:',
                  style: TextStyle(fontSize: 11, color: Colors.white70, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 150),
                  child: SingleChildScrollView(
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: List.generate(totalSongs > 60 ? 60 : totalSongs, (i) {
                        final int numVal = i + 1;
                        final bool isCurrent = (numVal == currentSongNumber);
                        return InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () => Navigator.pop(ctx, numVal),
                          child: Container(
                            width: 42,
                            height: 34,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: isCurrent ? Colors.amberAccent : const Color(0xFF172542),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isCurrent ? Colors.white : const Color(0x5500E5FF),
                              ),
                            ),
                            child: Text(
                              '#$numVal',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w900,
                                color: isCurrent ? Colors.black : Colors.white,
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Direct Number Input
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: numCtrl,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(fontSize: 13, color: Colors.white, fontWeight: FontWeight.bold),
                        decoration: InputDecoration(
                          labelText: 'Type Exact Song Number (1 to $totalSongs)',
                          labelStyle: const TextStyle(fontSize: 11, color: Colors.amberAccent),
                          filled: true,
                          fillColor: const Color(0xFF141E33),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00E5FF),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                      ),
                      onPressed: () {
                        final int? parsed = int.tryParse(numCtrl.text.trim());
                        if (parsed != null) {
                          Navigator.pop(ctx, parsed.clamp(1, totalSongs));
                        }
                      },
                      child: const Text('Set #', style: TextStyle(fontWeight: FontWeight.w900)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    if (targetOneBasedNum == null || targetOneBasedNum == currentSongNumber) return;

    await _applySongNumberChange(id, currentIdx, targetOneBasedNum);
  }

  Future<void> _applySongNumberChange(String trackId, int oldIdx, int targetOneBasedNumber) async {
    if (_viewMode == 'OFFLINE') {
      await VaultManager.changeSongNumberInCategory(
        _selectedOfflineCategory,
        trackId,
        targetOneBasedNumber,
      );
    } else if (_viewMode == 'FAVORITES') {
      await VaultManager.changeSongNumberInFavorites(trackId, targetOneBasedNumber);
    } else {
      final int targetIdx = (targetOneBasedNumber - 1).clamp(0, _tracks.length - 1);
      if (oldIdx >= 0 && oldIdx < _tracks.length && oldIdx != targetIdx) {
        setState(() {
          final item = _tracks.removeAt(oldIdx);
          _tracks.insert(targetIdx, item);
        });
      }
    }

    _refreshActiveQueueAfterReorder();
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 1),
          backgroundColor: Colors.amber.shade900,
          content: Text(
            '🔢 Song moved to #$targetOneBasedNumber in ${_viewMode == 'OFFLINE' ? _selectedOfflineCategory : _viewMode}!',
            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
          ),
        ),
      );
    }
  }

  Future<void> _pickLocalSongFromPhone() async {
    try {
      final String? pickedPath = await _nativeChannel.invokeMethod<String>(
        'pickMediaAndExtractAudio',
        {'isVideo': false},
      );
      if (pickedPath == null || pickedPath.isEmpty) return;
      final String fileName = pickedPath.split('/').last.replaceAll(RegExp(r'\.[a-zA-Z0-9]+$'), '');
      final Map<String, dynamic> localTrack = {
        'id': 'local_${DateTime.now().millisecondsSinceEpoch}',
        'title': fileName,
        'artist': 'Phone Storage Audio',
        'cover': '',
        'urls': <String>[],
        'durationStr': 'Local',
        'durationSec': 210,
        'year': 2026,
        'quality': 'PHONE MASTER AUDIO',
        'localPath': pickedPath,
        'isOffline': true,
        'category': _selectedOfflineCategory,
      };
      if (mounted) {
        await _promptCategoryAndSaveDownload(localTrack);
      }
    } catch (_) {}
  }

  Future<void> _promptCategoryAndSaveDownload(Map<String, dynamic> trk) async {
    final String id = (trk['id'] ?? '').toString();
    final bool alreadyOff = VaultManager.isOffline(id, isEntry: false);
    final String currentCat =
        VaultManager.getTrackOfflineCategory(id) ?? _selectedOfflineCategory;
    final TextEditingController newCatCtrl = TextEditingController();

    final String? chosenCategory = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final List<String> cats = VaultManager.offlineCategories.value;
            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
              child: GlassBox(
                margin: const EdgeInsets.all(10),
                padding: const EdgeInsets.all(16),
                borderRadius: 24,
                blur: 20,
                tintColor: const Color(0xFF0B1325),
                borderColor: const Color(0xFF00E5FF),
                borderWidth: 1.5,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.create_new_folder_rounded, color: Color(0xFF00E5FF), size: 26),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                alreadyOff
                                    ? '📂 Change Offline Category Folder'
                                    : '📥 Select Category to Download Song',
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                ),
                              ),
                              Text(
                                trk['title'].toString(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 11.5, color: Colors.amberAccent),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white60),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00E676).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF00E676).withOpacity(0.4)),
                      ),
                      child: const Text(
                        '🔒 Inside Offline Vault, each category section plays ONLY its own songs without mixing!',
                        style: TextStyle(fontSize: 10.5, color: Color(0xFF00E676), fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Tap a Category Folder to Save Instantly:',
                      style: TextStyle(fontSize: 11.5, color: Colors.white70, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: cats.map((cat) {
                        final bool isSelected = (cat.toLowerCase() == currentCat.toLowerCase());
                        final int countInCat = VaultManager.getOfflineSongsByCategory(cat).length;
                        return InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => Navigator.pop(ctx, cat),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: isSelected
                                    ? [const Color(0xFF00E5FF), const Color(0xFF2979FF)]
                                    : [const Color(0xFF162238), const Color(0xFF0F172A)],
                              ),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSelected ? Colors.amberAccent : const Color(0x5500E5FF),
                                width: isSelected ? 1.5 : 1.0,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '${VaultManager.categoryIcon(cat)} $cat',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w900,
                                    color: isSelected ? Colors.black : Colors.white,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: isSelected ? Colors.black26 : Colors.white12,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '$countInCat',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: isSelected ? Colors.white : Colors.amberAccent,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: newCatCtrl,
                            style: const TextStyle(fontSize: 12.5, color: Colors.white),
                            decoration: InputDecoration(
                              hintText: 'Or add new category (e.g. Haldi, Reception, Birthday)...',
                              hintStyle: const TextStyle(fontSize: 11, color: Colors.white54),
                              filled: true,
                              fillColor: const Color(0xFF141E33),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(color: Colors.white24),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.amberAccent,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                          ),
                          icon: const Icon(Icons.add_circle_outline, size: 16),
                          label: const Text('Add & Save', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900)),
                          onPressed: () async {
                            final String raw = newCatCtrl.text.trim();
                            if (raw.isEmpty) return;
                            final String created = await VaultManager.addCustomCategory(raw);
                            if (ctx.mounted) {
                              Navigator.pop(ctx, created);
                            }
                          },
                        ),
                      ],
                    ),
                    if (alreadyOff) ...[
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
                          label: const Text(
                            'Delete Offline Copy',
                            style: TextStyle(color: Colors.redAccent, fontSize: 11.5, fontWeight: FontWeight.bold),
                          ),
                          onPressed: () async {
                            await VaultManager.deleteOfflineSong(id, isEntry: false);
                            if (ctx.mounted) Navigator.pop(ctx, null);
                            if (mounted) setState(() {});
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (chosenCategory == null || chosenCategory.isEmpty) return;

    setState(() {
      _selectedOfflineCategory = chosenCategory;
    });

    if (alreadyOff) {
      await VaultManager.assignOfflineCategory(id, chosenCategory);
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.deepPurple.shade700,
            content: Text(
              '📂 Moved "${trk['title']}" to ${VaultManager.categoryIcon(chosenCategory)} $chosenCategory Folder!',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        );
      }
      return;
    }

    if (mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 2),
          backgroundColor: Colors.teal.shade800,
          content: Text(
            '⬇ Downloading "${trk['title']}" into [${VaultManager.categoryIcon(chosenCategory)} $chosenCategory]...',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      );
    }

    final bool ok = await VaultManager.downloadTrack(
      trk,
      isEntry: false,
      category: chosenCategory,
    );

    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: ok ? Colors.green.shade800 : Colors.red.shade800,
          content: Text(
            ok
                ? '✅ Saved to [${VaultManager.categoryIcon(chosenCategory)} $chosenCategory] Offline Folder!'
                : '⚠️ Mirror busy—tap Play first and tap Download again.',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      );
    }
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

  void _showSongOptionsModal(Map<String, dynamic> trk, int idx) {
    final String id = (trk['id'] ?? '').toString();
    final bool isOff = VaultManager.isOffline(id, isEntry: false);
    final String? cat = VaultManager.getTrackOfflineCategory(id);
    final int currentStartCue = int.tryParse((trk['customStartSec'] ?? '0').toString()) ?? 0;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return GlassBox(
          margin: const EdgeInsets.all(10),
          padding: const EdgeInsets.all(16),
          borderRadius: 22,
          blur: 20,
          tintColor: const Color(0xFF0D162B),
          borderColor: const Color(0xFF00E5FF),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '#${idx + 1} • ${trk['title']}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Colors.amberAccent),
              ),
              Text(
                trk['artist'].toString(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: Colors.cyanAccent),
              ),
              const Divider(color: Colors.white24, height: 18),
              ListTile(
                dense: true,
                leading: const Icon(Icons.format_list_numbered_rounded, color: Colors.amberAccent),
                title: Text(
                  'Change Song Number (Currently #${idx + 1})',
                  style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.amberAccent),
                ),
                subtitle: const Text(
                  'Move to #1, #2, #3 or any custom position in playlist',
                  style: TextStyle(fontSize: 10.5, color: Colors.white70),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _promptChangeSongNumberDialog(trk, idx);
                },
              ),
              ListTile(
                dense: true,
                leading: const Icon(Icons.timer_outlined, color: Color(0xFF00E676)),
                title: Text(
                  'Set Custom Start Second (Current: ${currentStartCue}s)',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: const Text(
                  'Skip slow intros automatically when this song plays',
                  style: TextStyle(fontSize: 10.5, color: Colors.white70),
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  _promptCustomStartCueDialog(trk);
                },
              ),
              ListTile(
                dense: true,
                leading: const Icon(Icons.playlist_play_rounded, color: Color(0xFF00E5FF)),
                title: const Text('Play Next in Queue', style: TextStyle(fontWeight: FontWeight.bold)),
                onTap: () {
                  Navigator.pop(ctx);
                  if (_playbackQueue.isEmpty) {
                    _startPlaybackFromVisibleList(idx);
                  } else {
                    final int insertPos = (_queueIndex + 1).clamp(0, _playbackQueue.length);
                    _playbackQueue.insert(insertPos, Map<String, dynamic>.from(trk));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('⏭ Queued Next: ${trk['title']}')),
                    );
                  }
                },
              ),
              ListTile(
                dense: true,
                leading: const Icon(Icons.folder_special_rounded, color: Colors.amberAccent),
                title: Text(
                  isOff
                      ? 'Change Offline Category (Current: $cat)'
                      : 'Download to Offline Category Folder (Marriage, Fashion Show, etc.)',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _promptCategoryAndSaveDownload(trk);
                },
              ),
              ListTile(
                dense: true,
                leading: const Icon(Icons.lyrics_rounded, color: Color(0xFF00E676)),
                title: const Text('Open Full-Screen DJ Deck & Live Synced Lyrics',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                onTap: () {
                  Navigator.pop(ctx);
                  _startPlaybackFromVisibleList(idx);
                  _openFullScreenGlassConsole();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _promptCustomStartCueDialog(Map<String, dynamic> trk) async {
    final String id = (trk['id'] ?? '').toString();
    final int existing = int.tryParse((trk['customStartSec'] ?? '0').toString()) ?? 0;
    final TextEditingController secCtrl = TextEditingController(text: '$existing');

    final int? chosenSec = await showDialog<int>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF0E172A),
          title: const Text(
            '⏱ Set Custom Start Second (Skip Intro)',
            style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w900, color: Color(0xFF00E5FF)),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(trk['title'].toString(), style: const TextStyle(fontSize: 12, color: Colors.amberAccent)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [0, 10, 15, 20, 30, 45].map((s) {
                  return ActionChip(
                    backgroundColor: const Color(0xFF172542),
                    label: Text(s == 0 ? '0s (Normal)' : 'Start @ ${s}s', style: const TextStyle(fontSize: 11)),
                    onPressed: () => Navigator.pop(ctx, s),
                  );
                }).toList(),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: secCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Or enter exact second (e.g. 18)',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00E676), foregroundColor: Colors.black),
              onPressed: () {
                final int v = int.tryParse(secCtrl.text.trim()) ?? 0;
                Navigator.pop(ctx, v.clamp(0, 300));
              },
              child: const Text('Save Cue', style: TextStyle(fontWeight: FontWeight.w900)),
            ),
          ],
        );
      },
    );

    if (chosenSec == null) return;
    trk['customStartSec'] = chosenSec;
    await VaultManager.setTrackCustomStartCue(id, chosenSec);
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('⏱ Saved Start Cue @ ${chosenSec}s for ${trk['title']}')),
      );
    }
  }

  void _openEqualizerAndSleepConsole() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final List<String> bandLabels = ['60Hz Sub', '230Hz Punch', '910Hz Mid', '3.6kHz Vocal', '14kHz Air'];
            return GlassBox(
              margin: const EdgeInsets.all(10),
              padding: const EdgeInsets.all(16),
              borderRadius: 24,
              blur: 20,
              tintColor: const Color(0xFF0B1325),
              borderColor: Colors.amberAccent,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        '🎚 5-BAND PRO EQUALIZER, BASS & SLEEP TIMER',
                        style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w900, color: Colors.amberAccent),
                      ),
                      TextButton(
                        onPressed: () {
                          setModalState(() {
                            _bassBoostStrength = 0.85;
                            _loudnessGain = 0.70;
                            _eqBands = [0.75, 0.65, 0.50, 0.65, 0.78];
                          });
                          _applyNativeDspSettings();
                        },
                        child: const Text('Reset DJ Bass', style: TextStyle(fontSize: 11, color: Color(0xFF00E5FF))),
                      ),
                    ],
                  ),
                  Text(
                    '🔊 Sub-Bass 8118 Boost: ${(_bassBoostStrength * 100).toInt()}%',
                    style: const TextStyle(fontSize: 11.5, color: Color(0xFF00E5FF), fontWeight: FontWeight.bold),
                  ),
                  Slider(
                    value: _bassBoostStrength,
                    activeColor: const Color(0xFF00E5FF),
                    onChanged: (v) {
                      setModalState(() => _bassBoostStrength = v);
                      _applyNativeDspSettings();
                    },
                  ),
                  Text(
                    '⚡ Master Stage Loudness Enhancer: ${(_loudnessGain * 100).toInt()}%',
                    style: const TextStyle(fontSize: 11.5, color: Color(0xFF00E676), fontWeight: FontWeight.bold),
                  ),
                  Slider(
                    value: _loudnessGain,
                    activeColor: const Color(0xFF00E676),
                    onChanged: (v) {
                      setModalState(() => _loudnessGain = v);
                      _applyNativeDspSettings();
                    },
                  ),
                  const SizedBox(height: 4),
                  ...List.generate(5, (i) {
                    return Row(
                      children: [
                        SizedBox(
                          width: 82,
                          child: Text(
                            bandLabels[i],
                            style: const TextStyle(fontSize: 10.5, color: Colors.white70, fontWeight: FontWeight.bold),
                          ),
                        ),
                        Expanded(
                          child: Slider(
                            value: _eqBands[i],
                            activeColor: Colors.amberAccent,
                            onChanged: (v) {
                              setModalState(() => _eqBands[i] = v);
                              _applyNativeDspSettings();
                            },
                          ),
                        ),
                        Text(
                          '${((_eqBands[i] - 0.5) * 24).toStringAsFixed(0)} dB',
                          style: const TextStyle(fontSize: 10, color: Colors.amberAccent, fontWeight: FontWeight.bold),
                        ),
                      ],
                    );
                  }),
                  const Divider(color: Colors.white24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _sleepTimerMinutesLeft != null
                            ? '🌙 Sleep Timer Active: $_sleepTimerMinutesLeft min left'
                            : '🌙 Auto-Sleep Timer: Off',
                        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      Wrap(
                        spacing: 6,
                        children: [0, 15, 30, 60].map((mins) {
                          final bool active = (_sleepTimerMinutesLeft == (mins == 0 ? null : mins));
                          return ChoiceChip(
                            label: Text(mins == 0 ? 'Off' : '${mins}m', style: const TextStyle(fontSize: 10)),
                            selected: active,
                            selectedColor: Colors.amber,
                            onSelected: (_) {
                              _setSleepTimer(mins);
                              setModalState(() {});
                            },
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _applyNativeDspSettings() async {
    try {
      await _nativeChannel.invokeMethod('setHardwareDsp', {
        'bass': (_bassBoostStrength * 1000).toInt(),
        'loudness': (_loudnessGain * 1200).toInt(),
        'bands': _eqBands.map((e) => ((e - 0.5) * 1500).toInt()).toList(),
      });
    } catch (_) {}
  }

  void _setSleepTimer(int minutes) {
    _sleepTimer?.cancel();
    if (minutes <= 0) {
      setState(() => _sleepTimerMinutesLeft = null);
      return;
    }
    setState(() => _sleepTimerMinutesLeft = minutes);
    _sleepTimer = Timer.periodic(const Duration(minutes: 1), (t) {
      if (_sleepTimerMinutesLeft == null) {
        t.cancel();
        return;
      }
      if (_sleepTimerMinutesLeft! <= 1) {
        t.cancel();
        _shouldBePlayingInBg = false;
        _player.pause();
        if (mounted) setState(() => _sleepTimerMinutesLeft = null);
      } else {
        if (mounted) setState(() => _sleepTimerMinutesLeft = _sleepTimerMinutesLeft! - 1);
      }
    });
  }

  Future<void> _openFullScreenGlassConsole() async {
    if (_nowPlayingTrack == null) return;
    final Map<String, dynamic> trk = _nowPlayingTrack!;
    List<LyricLine> syncedLyrics = [];
    bool loadingLyrics = true;
    bool showLyricsView = true;
    String scriptMode = 'KANGLISH (ಕನ್ನಡ-Eng)';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            if (loadingLyrics && syncedLyrics.isEmpty) {
              KaraokeEngine.fetchSyncedLyrics(
                trk['id'].toString(),
                trk['title'].toString(),
                trk['artist'].toString(),
                (trk['durationSec'] as int?) ?? 180,
              ).then((lines) {
                if (ctx.mounted) {
                  setModalState(() {
                    syncedLyrics = lines;
                    loadingLyrics = false;
                  });
                }
              });
            }

            final Map<String, dynamic> currentTrk = _nowPlayingTrack ?? trk;
            final int posMs = _position.inMilliseconds;
            int activeLineIdx = 0;
            for (int i = 0; i < syncedLyrics.length; i++) {
              if (posMs >= syncedLyrics[i].timeMs) {
                activeLineIdx = i;
              } else {
                break;
              }
            }

            return Container(
              height: MediaQuery.of(ctx).size.height * 0.88,
              padding: const EdgeInsets.all(12),
              child: GlassBox(
                padding: const EdgeInsets.all(16),
                borderRadius: 28,
                blur: 24,
                tintColor: const Color(0xFF091122),
                borderColor: const Color(0xFF00E5FF),
                borderWidth: 1.6,
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white, size: 28),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                        Expanded(
                          child: Column(
                            children: [
                              const Text(
                                '🎛 PRO GLASS DJ CONSOLE & LIVE LYRICS',
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Color(0xFF00E5FF)),
                              ),
                              Text(
                                _activeQueueScopeBanner,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 9.5, color: Colors.amberAccent),
                              ),
                            ],
                          ),
                        ),
                        TextButton.icon(
                          icon: Icon(
                            showLyricsView ? Icons.album_rounded : Icons.lyrics_rounded,
                            color: Colors.amberAccent,
                            size: 16,
                          ),
                          label: Text(
                            showLyricsView ? 'Art' : 'Lyrics',
                            style: const TextStyle(fontSize: 11, color: Colors.amberAccent, fontWeight: FontWeight.bold),
                          ),
                          onPressed: () => setModalState(() => showLyricsView = !showLyricsView),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      currentTrk['title'].toString(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: Colors.white),
                    ),
                    Text(
                      currentTrk['artist'].toString(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: Color(0xFF00E5FF)),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: showLyricsView
                          ? Column(
                              children: [
                                SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    children: [
                                      'KANGLISH (ಕನ್ನಡ-Eng)',
                                      'HINGLISH (हिन्दी-Eng)',
                                      'ENGLISH / ORIGINAL',
                                      'KANNADA (ಕನ್ನಡ)',
                                      'HINDI (हिन्दी)',
                                    ].map((mode) {
                                      final bool sel = (scriptMode == mode);
                                      return Padding(
                                        padding: const EdgeInsets.only(right: 6),
                                        child: ChoiceChip(
                                          label: Text(mode, style: const TextStyle(fontSize: 9.5)),
                                          selected: sel,
                                          selectedColor: const Color(0xFF00E5FF),
                                          labelStyle: TextStyle(
                                            color: sel ? Colors.black : Colors.white,
                                            fontWeight: FontWeight.bold,
                                          ),
                                          onSelected: (_) => setModalState(() => scriptMode = mode),
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Expanded(
                                  child: Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withOpacity(0.35),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(color: Colors.white12),
                                    ),
                                    child: loadingLyrics
                                        ? const Center(child: CircularProgressIndicator())
                                        : ListView.builder(
                                            itemCount: syncedLyrics.length,
                                            itemBuilder: (ctx, i) {
                                              final bool isCurrent = (i == activeLineIdx);
                                              final String formatted = KaraokeEngine.formatLineForLanguageMode(
                                                syncedLyrics[i].text,
                                                scriptMode,
                                              );
                                              return GestureDetector(
                                                onTap: () {
                                                  _player.seek(Duration(milliseconds: syncedLyrics[i].timeMs));
                                                },
                                                child: Padding(
                                                  padding: const EdgeInsets.symmetric(vertical: 6),
                                                  child: Text(
                                                    formatted,
                                                    textAlign: TextAlign.center,
                                                    style: TextStyle(
                                                      fontSize: isCurrent ? 16 : 12.5,
                                                      fontWeight: isCurrent ? FontWeight.w900 : FontWeight.w500,
                                                      color: isCurrent ? Colors.amberAccent : Colors.white60,
                                                    ),
                                                  ),
                                                ),
                                              );
                                            },
                                          ),
                                  ),
                                ),
                              ],
                            )
                          : Center(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(24),
                                child: Image.network(
                                  currentTrk['cover'].toString(),
                                  width: 220,
                                  height: 220,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => const Icon(
                                    Icons.album_rounded,
                                    size: 160,
                                    color: Color(0xFF00E5FF),
                                  ),
                                ),
                              ),
                            ),
                    ),
                    const SizedBox(height: 10),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _hotCueChip('⚡ Drop 15s', () => _player.seek(const Duration(seconds: 15))),
                          _hotCueChip('🔥 Hook 45s', () => _player.seek(const Duration(seconds: 45))),
                          _hotCueChip('🎶 Verse 90s', () => _player.seek(const Duration(seconds: 90))),
                          _hotCueChip(
                            _loopPointASec == null ? '🅰 Set Loop A' : '🅰 A=${_loopPointASec}s',
                            () => setModalState(() => _loopPointASec = _position.inSeconds),
                          ),
                          _hotCueChip(
                            _loopPointBSec == null ? '🅱 Set Loop B' : '🅱 B=${_loopPointBSec}s',
                            () => setModalState(() => _loopPointBSec = _position.inSeconds),
                          ),
                          if (_loopPointASec != null || _loopPointBSec != null)
                            _hotCueChip(
                              '❌ Clear A-B',
                              () => setModalState(() {
                                _loopPointASec = null;
                                _loopPointBSec = null;
                              }),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Slider(
                      value: _position.inSeconds
                          .toDouble()
                          .clamp(0, (_duration.inSeconds > 0 ? _duration.inSeconds : 1).toDouble()),
                      max: (_duration.inSeconds > 0 ? _duration.inSeconds : 1).toDouble(),
                      activeColor: const Color(0xFF00E5FF),
                      onChanged: (v) {
                        _player.seek(Duration(seconds: v.toInt()));
                        setModalState(() {});
                      },
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(_fmtDuration(_position), style: const TextStyle(fontSize: 11, color: Colors.white70)),
                        Text(_fmtDuration(_duration), style: const TextStyle(fontSize: 11, color: Colors.white70)),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        IconButton(
                          icon: Icon(Icons.shuffle_rounded, color: _shuffleMode ? Colors.amber : Colors.white54),
                          onPressed: () {
                            setState(() => _shuffleMode = !_shuffleMode);
                            setModalState(() {});
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.skip_previous_rounded, size: 34, color: Colors.white),
                          onPressed: () {
                            _playPrev();
                            setModalState(() {});
                          },
                        ),
                        GestureDetector(
                          onTap: () {
                            if (_isPlaying) {
                              _shouldBePlayingInBg = false;
                              _player.pause();
                            } else {
                              _shouldBePlayingInBg = true;
                              _player.resume();
                            }
                            setModalState(() {});
                          },
                          child: Container(
                            width: 58,
                            height: 58,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(colors: [Color(0xFF00E5FF), Color(0xFF2979FF)]),
                            ),
                            child: Icon(
                              _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                              color: Colors.black,
                              size: 34,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.skip_next_rounded, size: 34, color: Colors.white),
                          onPressed: () {
                            _playNext();
                            setModalState(() {});
                          },
                        ),
                        IconButton(
                          icon: Icon(Icons.repeat_one_rounded, color: _loopCurrent ? Colors.amber : Colors.white54),
                          onPressed: () {
                            setState(() => _loopCurrent = !_loopCurrent);
                            setModalState(() {});
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _hotCueChip(String label, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ActionChip(
        backgroundColor: const Color(0xFF172542),
        side: const BorderSide(color: Color(0x6600E5FF)),
        label: Text(label, style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold)),
        onPressed: onTap,
      ),
    );
  }

  String _fmtDuration(Duration d) {
    final mins = d.inMinutes;
    final secs = d.inSeconds % 60;
    return '$mins:${secs < 10 ? '0$secs' : '$secs'}';
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<Map<String, dynamic>>>(
      valueListenable: VaultManager.favSongs,
      builder: (context, favList, _) {
        return ValueListenableBuilder<List<Map<String, dynamic>>>(
          valueListenable: VaultManager.offlineSongs,
          builder: (context, offList, _) {
            return ValueListenableBuilder<List<String>>(
              valueListenable: VaultManager.offlineCategories,
              builder: (context, categoriesList, _) {
                return ValueListenableBuilder<Map<String, int>>(
                  valueListenable: VaultManager.downloadProgressMap,
                  builder: (context, dlProgress, _) {
                    final List<Map<String, dynamic>> visibleList = _currentVisibleList();
                    final Map<String, dynamic>? playingTrack = _nowPlayingTrack;
                    final String? playingId = playingTrack?['id']?.toString();

                    return Column(
                      children: [
                        // 1. Glass Status & Quick Pro Tool Strip (EQ, Live SFX Bar, Phone MP3)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Color(0xFF0A1224), Color(0xFF132242)],
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _statusBadge,
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    color: Color(0xFF00E676),
                                    fontWeight: FontWeight.w800,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 5),
                              GestureDetector(
                                onTap: () => setState(() => _showQuickDjPads = !_showQuickDjPads),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: _showQuickDjPads
                                        ? const Color(0xFF00E676).withOpacity(0.28)
                                        : Colors.pinkAccent.withOpacity(0.18),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: _showQuickDjPads ? const Color(0xFF00E676) : Colors.pinkAccent,
                                    ),
                                  ),
                                  child: const Text(
                                    '🎛 DJ FX',
                                    style: TextStyle(
                                      fontSize: 9.2,
                                      color: Colors.white,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 5),
                              GestureDetector(
                                onTap: _openEqualizerAndSleepConsole,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.amberAccent.withOpacity(0.16),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: Colors.amberAccent.withOpacity(0.6)),
                                  ),
                                  child: const Text(
                                    '🎚 EQ & Sleep',
                                    style: TextStyle(
                                      fontSize: 9.2,
                                      color: Colors.amberAccent,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 5),
                              GestureDetector(
                                onTap: _pickLocalSongFromPhone,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF00E5FF).withOpacity(0.16),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.6)),
                                  ),
                                  child: const Text(
                                    '📱 Phone MP3',
                                    style: TextStyle(
                                      fontSize: 9.2,
                                      color: Color(0xFF00E5FF),
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Optional Instant Live DJ Stinger Pads Strip right inside Tab 1!
                        if (_showQuickDjPads)
                          Container(
                            height: 36,
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            color: const Color(0xFF0B152A),
                            child: ListView(
                              scrollDirection: Axis.horizontal,
                              children: [
                                _quickSfxBtn('📢 Airhorn', 'AIRHORN', Colors.amberAccent),
                                _quickSfxBtn('🔊 Sub Drop', 'SUB_DROP', const Color(0xFF00E5FF)),
                                _quickSfxBtn('🥁 Dhol Beat', 'DHOL', const Color(0xFF00E676)),
                                _quickSfxBtn('🎺 Trumpet', 'TRUMPET', Colors.orangeAccent),
                                _quickSfxBtn('⚡ Laser', 'LASER', Colors.pinkAccent),
                                _quickSfxBtn('🏟 Crowd Roar', 'CROWD', Colors.cyanAccent),
                                _quickSfxBtn('🌪 Bass Riser', 'RISER', Colors.purpleAccent),
                              ],
                            ),
                          ),

                        // 2. Glassmorphic Search Bar + 3 Main Mode Tabs (Online / Favs / Offline Categories)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(10, 7, 10, 4),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: GlassBox(
                                      borderRadius: 12,
                                      blur: 10,
                                      padding: EdgeInsets.zero,
                                      tintColor: const Color(0xFF101B33),
                                      borderColor: const Color(0x4400E5FF),
                                      child: TextField(
                                        controller: _searchCtrl,
                                        style: const TextStyle(fontSize: 13, color: Colors.white),
                                        decoration: InputDecoration(
                                          hintText: 'Search ANY song, movie, Marriage, Devotional, artist...',
                                          hintStyle: const TextStyle(fontSize: 11.5, color: Colors.white54),
                                          prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF00E5FF), size: 20),
                                          suffixIcon: _searchCtrl.text.isNotEmpty
                                              ? IconButton(
                                                  icon: const Icon(Icons.clear_rounded, size: 18),
                                                  onPressed: () {
                                                    _searchCtrl.clear();
                                                    _fetchCategoryOrTrending(_selectedOnlineCat, resetPage: true);
                                                  },
                                                )
                                              : null,
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                          border: InputBorder.none,
                                        ),
                                        onSubmitted: (val) => _searchAnySongWorldwide(val),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 7),
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF00E5FF),
                                      foregroundColor: Colors.black,
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                    onPressed: () => _searchAnySongWorldwide(_searchCtrl.text),
                                    child: const Text('Search', style: TextStyle(fontWeight: FontWeight.w900)),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Expanded(
                                    child: _modeButton('🔥 Online (${_tracks.length})', 'SONGS', () {
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
                                    child: _modeButton('📂 Offline (${offList.length})', 'OFFLINE', () {
                                      setState(() => _viewMode = 'OFFLINE');
                                    }),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        // 3. Dynamic Sub-Navigation Bar
                        if (_viewMode == 'OFFLINE')
                          _buildOfflineCategoryFolderBar(categoriesList, visibleList)
                        else if (_viewMode == 'SONGS')
                          SizedBox(
                            height: 36,
                            child: ListView.builder(
                              scrollDirection: Axis.horizontal,
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              itemCount: _onlineCategories.length,
                              itemBuilder: (ctx, i) {
                                final cat = _onlineCategories[i];
                                final bool selected = (cat['key'] == _selectedOnlineCat);
                                return Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: ChoiceChip(
                                    label: Text(
                                      cat['label']!,
                                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
                                    ),
                                    selected: selected,
                                    selectedColor: Colors.amberAccent,
                                    backgroundColor: const Color(0xFF111C33),
                                    labelStyle: TextStyle(color: selected ? Colors.black : Colors.white),
                                    onSelected: (_) => _fetchCategoryOrTrending(cat['key']!, resetPage: true),
                                  ),
                                );
                              },
                            ),
                          ),

                        // 4. Glassmorphic Master Mini-Deck
                        if (playingTrack != null)
                          GestureDetector(
                            onTap: _openFullScreenGlassConsole,
                            child: GlassBox(
                              margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
                              borderRadius: 18,
                              blur: 18,
                              tintColor: const Color(0xFF142447),
                              borderColor: const Color(0xFF00E5FF),
                              borderWidth: 1.4,
                              child: Column(
                                children: [
                                  Row(
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(10),
                                        child: Image.network(
                                          playingTrack['cover'].toString(),
                                          width: 46,
                                          height: 46,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) => Container(
                                            width: 46,
                                            height: 46,
                                            color: const Color(0xFF1E3A8A),
                                            child: const Icon(Icons.music_note_rounded, color: Color(0xFF00E5FF)),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 9),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              '#${_queueIndex + 1} • ${playingTrack['title']}',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w900,
                                                fontSize: 13,
                                                color: Colors.white,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            Text(
                                              _activeQueueScopeBanner,
                                              style: const TextStyle(
                                                fontSize: 10,
                                                color: Colors.amberAccent,
                                                fontWeight: FontWeight.bold,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ),
                                      ),
                                      IconButton(
                                        visualDensity: VisualDensity.compact,
                                        icon: const Icon(Icons.skip_previous_rounded, color: Colors.white),
                                        onPressed: _playPrev,
                                      ),
                                      CircleAvatar(
                                        radius: 19,
                                        backgroundColor: const Color(0xFF00E5FF),
                                        child: IconButton(
                                          padding: EdgeInsets.zero,
                                          icon: Icon(
                                            _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                            color: Colors.black,
                                            size: 24,
                                          ),
                                          onPressed: () {
                                            if (_isPlaying) {
                                              _shouldBePlayingInBg = false;
                                              _player.pause();
                                            } else {
                                              _shouldBePlayingInBg = true;
                                              _player.resume();
                                            }
                                            _syncForegroundNotification();
                                          },
                                        ),
                                      ),
                                      IconButton(
                                        visualDensity: VisualDensity.compact,
                                        icon: const Icon(Icons.skip_next_rounded, color: Colors.white),
                                        onPressed: _playNext,
                                      ),
                                    ],
                                  ),
                                  SliderTheme(
                                    data: SliderTheme.of(context).copyWith(
                                      trackHeight: 2.5,
                                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                                    ),
                                    child: Slider(
                                      value: _position.inSeconds
                                          .toDouble()
                                          .clamp(0, (_duration.inSeconds > 0 ? _duration.inSeconds : 1).toDouble()),
                                      max: (_duration.inSeconds > 0 ? _duration.inSeconds : 1).toDouble(),
                                      activeColor: const Color(0xFF00E5FF),
                                      onChanged: (v) => _player.seek(Duration(seconds: v.toInt())),
                                    ),
                                  ),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(_fmtDuration(_position), style: const TextStyle(fontSize: 9.5)),
                                      Wrap(
                                        spacing: 4,
                                        crossAxisAlignment: WrapCrossAlignment.center,
                                        children: [
                                          InkWell(
                                            onTap: _toggleTalkoverDuck,
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: _isTalkoverDucked ? Colors.redAccent : Colors.white12,
                                                borderRadius: BorderRadius.circular(5),
                                              ),
                                              child: Text(
                                                _isTalkoverDucked ? '🎙 DUCK ON' : '🎙 DUCK 15%',
                                                style: const TextStyle(
                                                  fontSize: 8.5,
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ),
                                          InkWell(
                                            onTap: _openFullScreenGlassConsole,
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF00E5FF).withOpacity(0.18),
                                                borderRadius: BorderRadius.circular(5),
                                              ),
                                              child: const Text(
                                                '⛶ Lyrics & Loop',
                                                style: TextStyle(
                                                  fontSize: 8.5,
                                                  color: Color(0xFF00E5FF),
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ),
                                          IconButton(
                                            visualDensity: VisualDensity.compact,
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                                            icon: Icon(
                                              Icons.shuffle_rounded,
                                              size: 15,
                                              color: _shuffleMode ? Colors.amber : Colors.white54,
                                            ),
                                            onPressed: () => setState(() => _shuffleMode = !_shuffleMode),
                                          ),
                                          IconButton(
                                            visualDensity: VisualDensity.compact,
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                                            icon: Icon(
                                              Icons.repeat_one_rounded,
                                              size: 15,
                                              color: _loopCurrent ? Colors.amber : Colors.white54,
                                            ),
                                            onPressed: () => setState(() => _loopCurrent = !_loopCurrent),
                                          ),
                                          DropdownButton<double>(
                                            value: _playbackSpeed,
                                            isDense: true,
                                            underline: const SizedBox(),
                                            items: const [
                                              DropdownMenuItem(
                                                value: 0.85,
                                                child: Text('0.85x', style: TextStyle(fontSize: 9.5)),
                                              ),
                                              DropdownMenuItem(
                                                value: 1.0,
                                                child: Text('1.0x', style: TextStyle(fontSize: 9.5)),
                                              ),
                                              DropdownMenuItem(
                                                value: 1.15,
                                                child: Text('1.15x', style: TextStyle(fontSize: 9.5)),
                                              ),
                                              DropdownMenuItem(
                                                value: 1.25,
                                                child: Text('1.25x', style: TextStyle(fontSize: 9.5)),
                                              ),
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
                                      Text(_fmtDuration(_duration), style: const TextStyle(fontSize: 9.5)),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),

                        // 5. Ultra-Premium Glassmorphic Song Cards List + Interactive Song Number Sequencer
                        Expanded(
                          child: _isLoading
                              ? const Center(child: CircularProgressIndicator(color: Color(0xFF00E5FF)))
                              : visibleList.isEmpty
                                  ? Center(
                                      child: Padding(
                                        padding: const EdgeInsets.all(24.0),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.folder_open_rounded, color: Color(0xFF00E5FF), size: 44),
                                            const SizedBox(height: 10),
                                            Text(
                                              _viewMode == 'OFFLINE'
                                                  ? 'No songs saved in [${VaultManager.categoryIcon(_selectedOfflineCategory)} $_selectedOfflineCategory] yet.\nTap ⬇ on any song online (or import from Phone MP3) and pick "$_selectedOfflineCategory"!'
                                                  : 'No songs in this tab yet. Tap ❤️ or ⬇ on any song!',
                                              textAlign: TextAlign.center,
                                              style: const TextStyle(color: Colors.white70, fontSize: 12.5),
                                            ),
                                          ],
                                        ),
                                      ),
                                    )
                                  : ListView.builder(
                                      padding: const EdgeInsets.only(bottom: 24),
                                      itemCount: visibleList.length + (_viewMode == 'SONGS' ? 1 : 0),
                                      itemBuilder: (ctx, idx) {
                                        if (idx == visibleList.length) {
                                          return Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                            child: ElevatedButton.icon(
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: const Color(0xFF172B54),
                                                foregroundColor: const Color(0xFF00E5FF),
                                                padding: const EdgeInsets.symmetric(vertical: 13),
                                                side: const BorderSide(color: Color(0xFF00E5FF)),
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                              ),
                                              icon: _isLoadingMore
                                                  ? const SizedBox(
                                                      width: 16,
                                                      height: 16,
                                                      child: CircularProgressIndicator(strokeWidth: 2),
                                                    )
                                                  : const Icon(Icons.add_circle_outline_rounded),
                                              label: Text(
                                                _isLoadingMore
                                                    ? 'Loading More Songs...'
                                                    : '➕ Load 50 More Songs (Unlimited Catalog)',
                                                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12.5),
                                              ),
                                              onPressed: _loadMoreSongsNextPage,
                                            ),
                                          );
                                        }

                                        final Map<String, dynamic> trk = visibleList[idx];
                                        final String id = trk['id'].toString();
                                        final bool isThisPlaying = (playingId != null && id == playingId);
                                        final bool isFav = VaultManager.isFavorite(id, isEntry: false);
                                        final bool isOff = VaultManager.isOffline(id, isEntry: false);
                                        final String? offCat = VaultManager.getTrackOfflineCategory(id);
                                        final int? activeDlPct = dlProgress[id];

                                        return PremiumGlassSongCard(
                                          index: idx,
                                          track: trk,
                                          isPlayingThis: isThisPlaying,
                                          isActivelyPlaying: _isPlaying,
                                          isFavorite: isFav,
                                          isOffline: isOff,
                                          allowSongNumberEdit: (_viewMode == 'OFFLINE' || _viewMode == 'FAVORITES'),
                                          offlineCategory: offCat,
                                          downloadProgressPct: activeDlPct,
                                          onPlayTap: () {
                                            if (isThisPlaying) {
                                              if (_isPlaying) {
                                                _shouldBePlayingInBg = false;
                                                _player.pause();
                                              } else {
                                                _shouldBePlayingInBg = true;
                                                _player.resume();
                                              }
                                              _syncForegroundNotification();
                                            } else {
                                              _startPlaybackFromVisibleList(idx);
                                            }
                                          },
                                          onFavoriteTap: () => _onTapFavorite(trk),
                                          onDownloadOrCategoryTap: () => _promptCategoryAndSaveDownload(trk),
                                          onMoreOptionsTap: () => _showSongOptionsModal(trk, idx),
                                          onSongNumberTap: () => _promptChangeSongNumberDialog(trk, idx),
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
      },
    );
  }

  Widget _quickSfxBtn(String label, String sfxKey, Color color) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          backgroundColor: color.withOpacity(0.14),
          side: BorderSide(color: color.withOpacity(0.65)),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          visualDensity: VisualDensity.compact,
        ),
        onPressed: () => AppSoundEngine.playSynthesizedSfx(sfxKey),
        child: Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w900)),
      ),
    );
  }

  Widget _buildOfflineCategoryFolderBar(
    List<String> categoriesList,
    List<Map<String, dynamic>> currentCategorySongs,
  ) {
    return Column(
      children: [
        SizedBox(
          height: 38,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            children: [
              ...categoriesList.map((cat) {
                final bool selected = (cat.toLowerCase() == _selectedOfflineCategory.toLowerCase());
                final int count = VaultManager.getOfflineSongsByCategory(cat).length;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(
                      '${VaultManager.categoryIcon(cat)} $cat ($count)',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
                    ),
                    selected: selected,
                    selectedColor: const Color(0xFF00E676),
                    backgroundColor: const Color(0xFF101C33),
                    labelStyle: TextStyle(color: selected ? Colors.black : Colors.white),
                    onSelected: (_) {
                      setState(() {
                        _selectedOfflineCategory = cat;
                      });
                    },
                  ),
                );
              }),
              ActionChip(
                backgroundColor: Colors.amberAccent,
                label: const Text(
                  '+ Add Category',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Colors.black),
                ),
                onPressed: _promptCreateNewOfflineCategoryFolder,
              ),
            ],
          ),
        ),
        GlassBox(
          margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          borderRadius: 12,
          blur: 12,
          tintColor: const Color(0xFF0F243C),
          borderColor: const Color(0xFF00E676),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${VaultManager.categoryIcon(_selectedOfflineCategory)} $_selectedOfflineCategory Folder (${currentCategorySongs.length} Songs)',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: Colors.amberAccent,
                      ),
                    ),
                    const Text(
                      '🔢 Tap any #Number badge on a song card to change its Song Number (#1, #2, #3...)!',
                      style: TextStyle(fontSize: 9.5, color: Color(0xFF00E676), fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              if (currentCategorySongs.isNotEmpty) ...[
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00E676),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: const Icon(Icons.play_arrow_rounded, size: 16),
                  label: const Text('Play #1..N', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900)),
                  onPressed: () => _startPlaybackFromVisibleList(0, enableShuffle: false),
                ),
                const SizedBox(width: 6),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.amberAccent),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () => _startPlaybackFromVisibleList(0, enableShuffle: true),
                  child: const Text('🔀', style: TextStyle(fontSize: 11)),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _promptCreateNewOfflineCategoryFolder() async {
    final TextEditingController ctrl = TextEditingController();
    final String? created = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF0E172A),
          title: const Text(
            '📂 Create New Offline Category Folder',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Color(0xFF00E5FF)),
          ),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'e.g. Marriage, Fashion Show, Haldi, Sangeet, Birthday...',
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00E5FF), foregroundColor: Colors.black),
              onPressed: () async {
                final String name = ctrl.text.trim();
                if (name.isEmpty) return;
                final String saved = await VaultManager.addCustomCategory(name);
                if (ctx.mounted) Navigator.pop(ctx, saved);
              },
              child: const Text('Create Folder', style: TextStyle(fontWeight: FontWeight.w900)),
            ),
          ],
        );
      },
    );
    if (created != null && created.isNotEmpty && mounted) {
      setState(() => _selectedOfflineCategory = created);
    }
  }

  Widget _modeButton(String label, String mode, VoidCallback onTap) {
    final bool active = (_viewMode == mode);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: active
                ? [const Color(0xFF00E5FF), const Color(0xFF1E40AF)]
                : [const Color(0xFF0E1729), const Color(0xFF0A101D)],
          ),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: active ? Colors.amberAccent : Colors.white24,
            width: active ? 1.3 : 0.8,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: active ? Colors.white : Colors.white70,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}
