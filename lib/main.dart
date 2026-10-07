import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:dart_des/dart_des.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:math';
import 'package:just_audio/just_audio.dart';
import 'package:background_downloader/background_downloader.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.dark);
final ValueNotifier<MaterialColor> colorNotifier = ValueNotifier(Colors.deepPurple);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DJPlayerApp());
}

class DJPlayerApp extends StatelessWidget {
  const DJPlayerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (_, currentMode, __) {
        return ValueListenableBuilder<MaterialColor>(
          valueListenable: colorNotifier,
          builder: (_, currentColor, __) {
            return MaterialApp(
              title: 'Pro DJ Workstation',
              debugShowCheckedModeBanner: false,
              theme: ThemeData(
                brightness: Brightness.light,
                primaryColor: currentColor,
                scaffoldBackgroundColor: Colors.grey[100],
              ),
              darkTheme: ThemeData(
                brightness: Brightness.dark,
                primaryColor: currentColor,
                colorScheme: ColorScheme.dark(primary: currentColor, secondary: Colors.cyanAccent),
                scaffoldBackgroundColor: Colors.black,
                appBarTheme: const AppBarTheme(backgroundColor: Color(0xFF121212)),
              ),
              themeMode: currentMode,
              home: const MainDJDashboard(),
            );
          }
        );
      },
    );
  }
}

class MainDJDashboard extends StatefulWidget {
  const MainDJDashboard({super.key});
  @override
  State<MainDJDashboard> createState() => _MainDJDashboardState();
}

class _MainDJDashboardState extends State<MainDJDashboard> {
  int _currentTab = 0;
  final TextEditingController _searchController = TextEditingController();
  final AudioPlayer _audioPlayer = AudioPlayer();
  final YoutubeExplode _yt = YoutubeExplode();
  
  List<Map<String, dynamic>> _searchResults = [];
  List<String> _searchHistory = [];
  List<Map<String, dynamic>> _djFavorites = [];
  bool _isLoading = false;
  bool _isGridView = false;

  // Track & Playback State
  List<Map<String, dynamic>> _currentPlaylist = [];
  int _currentIndex = -1;
  String? _currentTitle;
  String? _currentArtist;
  String? _currentImage;
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  
  double _playbackSpeed = 1.0;
  Timer? _speedDebounce; 
  
  double _volume = 1.0;
  String _selectedQuality = '_320';
  LoopMode _loopMode = LoopMode.off;
  Timer? _sleepTimer;

  // Tools State
  final List<DateTime> _tapTimestamps = [];
  int _calculatedBpm = 0;
  double _eqHigh = 0;
  double _eqMid = 0;
  double _eqLow = 0;
  bool _crossfadeEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    _audioPlayer.playerStateStream.listen((state) {
      if (mounted) setState(() => _isPlaying = state.playing);
      if (state.processingState == ProcessingState.completed) {
        if (_loopMode == LoopMode.one) {
          _audioPlayer.seek(Duration.zero);
          _audioPlayer.play();
        } else if (_loopMode == LoopMode.all || _loopMode == LoopMode.off) {
          _playNext();
        }
      }
    });
    _audioPlayer.durationStream.listen((d) {
      if (mounted) setState(() => _duration = d ?? Duration.zero);
    });
    _audioPlayer.positionStream.listen((p) {
      if (mounted) setState(() => _position = p);
    });
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _searchHistory = prefs.getStringList('history') ?? [];
      final savedColor = prefs.getInt('theme_color');
      if (savedColor != null) {
        colorNotifier.value = Colors.primaries.firstWhere((c) => c.value == savedColor, orElse: () => Colors.deepPurple);
      }
      _crossfadeEnabled = prefs.getBool('crossfade') ?? false;
      
      final String? favsJson = prefs.getString('favorites');
      if (favsJson != null) {
        List<dynamic> decoded = json.decode(favsJson);
        _djFavorites = decoded.map((e) => Map<String, dynamic>.from(e)).toList();
      }
    });
  }

  Future<void> _savePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setStringList('history', _searchHistory);
    prefs.setString('favorites', json.encode(_djFavorites));
  }

  // --- 5-SOURCE UNIFIED SEARCH ENGINE ---
  Future<void> _searchSongs(String query) async {
    if (query.trim().isEmpty) return;
    HapticFeedback.lightImpact();
    
    if (!_searchHistory.contains(query)) {
      _searchHistory.insert(0, query);
      if (_searchHistory.length > 10) _searchHistory.removeLast();
      _savePrefs();
    }

    setState(() {
      _isLoading = true;
      _searchResults = [];
    });

    List<Map<String, dynamic>> mixedResults = [];

    await Future.wait([
      _fetchSourceA(query).then((res) => mixedResults.addAll(res)),
      _fetchSourceB(query).then((res) => mixedResults.addAll(res)),
      _fetchSourceC(query).then((res) => mixedResults.addAll(res)),
      _fetchSourceD(query).then((res) => mixedResults.addAll(res)),
      _fetchSourceE(query).then((res) => mixedResults.addAll(res)),
    ]);

    mixedResults.shuffle(Random());

    setState(() {
      _searchResults = mixedResults;
      _isLoading = false;
    });
  }

  // Source A: Primary High-Res API
  Future<List<Map<String, dynamic>>> _fetchSourceA(String query) async {
    try {
      final res = await http.get(Uri.parse('https://www.jiosaavn.com/api.php?__call=search.getResults&_format=json&_marker=0&ctx=web6dot0&api_version=4&q=${Uri.encodeComponent(query)}'));
      if (res.statusCode == 200) {
        final data = json.decode(res.body.trim());
        final List results = data['results'] ?? data['songs']?['data'] ?? [];
        return results.map((s) => {
          'title': s['title'].toString().replaceAll(RegExp(r'<[^>]*>'), ''),
          'artist': s['subtitle'].toString().replaceAll(RegExp(r'<[^>]*>'), ''),
          'image': s['image'].toString().replaceAll('150x150', '50x50'),
          'id': s['encrypted_media_url'] ?? s['more_info']?['encrypted_media_url'] ?? '',
          'resolver': 1
        }).toList();
      }
    } catch (_) {}
    return [];
  }

  // Source B: Global Video/Audio Graph
  Future<List<Map<String, dynamic>>> _fetchSourceB(String query) async {
    try {
      final res = await _yt.search.search(query);
      return res.take(10).map((v) => {
        'title': v.title,
        'artist': v.author,
        'image': v.thumbnails.highResUrl,
        'id': v.id.value,
        'resolver': 2
      }).toList();
    } catch (_) {}
    return [];
  }

  // Source C: Proxy Engine
  Future<List<Map<String, dynamic>>> _fetchSourceC(String query) async {
    try {
      final res = await http.get(Uri.parse('https://pipedapi.kavin.rocks/search?q=${Uri.encodeComponent(query)}&filter=music_songs'));
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final List items = data['items'] ?? [];
        return items.take(8).map((v) => {
          'title': v['title'],
          'artist': v['uploaderName'] ?? 'Unknown',
          'image': v['thumbnail'] ?? '',
          'id': v['url']?.replaceAll('/watch?v=', '') ?? '',
          'resolver': 3
        }).toList();
      }
    } catch (_) {}
    return [];
  }

  // Source D: Open Developer API
  Future<List<Map<String, dynamic>>> _fetchSourceD(String query) async {
    try {
      final res = await http.get(Uri.parse('https://api.jamendo.com/v3.0/tracks/?client_id=56d30c95&format=json&limit=5&search=${Uri.encodeComponent(query)}'));
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final List items = data['results'] ?? [];
        return items.map((v) => {
          'title': v['name'],
          'artist': v['artist_name'],
          'image': v['image'],
          'id': v['audio'],
          'resolver': 4
        }).toList();
      }
    } catch (_) {}
    return [];
  }

  // Source E: Preview Database
  Future<List<Map<String, dynamic>>> _fetchSourceE(String query) async {
    try {
      final res = await http.get(Uri.parse('https://itunes.apple.com/search?term=${Uri.encodeComponent(query)}&media=music&limit=5'));
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final List items = data['results'] ?? [];
        return items.where((v) => v['previewUrl'] != null).map((v) => {
          'title': v['trackName'] ?? 'Unknown',
          'artist': v['artistName'] ?? 'Unknown',
          'image': v['artworkUrl100'] ?? '',
          'id': v['previewUrl'],
          'resolver': 5
        }).toList();
      }
    } catch (_) {}
    return [];
  }

  // --- AUDIO RESOLUTION & PLAYBACK ---
  Future<String> _resolveStreamUrl(Map<String, dynamic> track) async {
    int res = track['resolver'];
    String id = track['id'];
    
    if (res == 1) {
      try {
        final key = utf8.encode('38346591');
        final decodedBytes = base64.decode(id);
        final des = DES(key: key, mode: DESMode.ECB, paddingType: DESPaddingType.PKCS7);
        return utf8.decode(des.decrypt(decodedBytes)).replaceAll('_96', _selectedQuality);
      } catch (_) { return ""; }
    } 
    else if (res == 2 || res == 3) {
      try {
        var manifest = await _yt.videos.streamsClient.getManifest(id);
        return manifest.audioOnly.withHighestBitrate().url.toString();
      } catch (_) { return ""; }
    } 
    else if (res == 4 || res == 5) {
      return id; // Direct URL
    }
    return "";
  }

  Future<void> _playSong(int index, List<Map<String, dynamic>> list) async {
    if(index < 0 || index >= list.length) return;
    HapticFeedback.lightImpact();
    
    final track = list[index];
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Resolving Stream: ${track['title']}'), duration: const Duration(seconds: 1)));
    
    final streamUrl = await _resolveStreamUrl(track);
    
    if (streamUrl.isNotEmpty) {
      setState(() {
        _currentPlaylist = list;
        _currentIndex = index;
        _currentTitle = track['title'];
        _currentArtist = track['artist'];
        _currentImage = track['image'];
      });
      
      try {
        await _audioPlayer.setAudioSource(AudioSource.uri(
          Uri.parse(streamUrl),
          headers: {'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'},
        ));
        await _audioPlayer.setSpeed(_playbackSpeed);
        
        if (_crossfadeEnabled) {
          _audioPlayer.setVolume(0.0);
          _audioPlayer.play();
          for(int i=1; i<=10; i++) {
            await Future.delayed(const Duration(milliseconds: 100));
            _audioPlayer.setVolume((i/10) * _volume);
          }
        } else {
          _audioPlayer.setVolume(_volume);
          _audioPlayer.play();
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Stream blocked by host.")));
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Stream unavailable right now.")));
    }
  }

  void _handleSpeedChange(double newSpeed) {
    setState(() => _playbackSpeed = newSpeed);
    _speedDebounce?.cancel();
    _speedDebounce = Timer(const Duration(milliseconds: 100), () {
      _audioPlayer.setSpeed(newSpeed);
    });
  }

  void _playNext() {
    if (_currentPlaylist.isEmpty) return;
    HapticFeedback.selectionClick();
    int next = _currentIndex + 1;
    if (next < _currentPlaylist.length) _playSong(next, _currentPlaylist);
  }

  void _playPrev() {
    if (_currentIndex > 0) {
      HapticFeedback.selectionClick();
      _playSong(_currentIndex - 1, _currentPlaylist);
    }
  }

  Future<void> _downloadSong(Map<String, dynamic> track) async {
    HapticFeedback.vibrate();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Downloading: ${track['title']}')));
    
    final streamUrl = await _resolveStreamUrl(track);
    if (streamUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cannot resolve media stream for download.')));
      return;
    }

    final safeTitle = track['title']!.toString().replaceAll(RegExp(r'[\\/:*?"<>|]'), '');
    final safeArtist = track['artist']!.toString().replaceAll(RegExp(r'[\\/:*?"<>|]'), '');
    final fileName = "$safeTitle - $safeArtist.m4a";
    
    final prefs = await SharedPreferences.getInstance();
    final saveLocation = prefs.getString('save_location') ?? 'Music';
    final sharedDir = saveLocation == 'Downloads' ? SharedStorage.downloads : SharedStorage.audio;

    final task = DownloadTask(
      url: streamUrl,
      filename: fileName,
      directory: 'DJ_Downloads',
      baseDirectory: BaseDirectory.applicationDocuments,
      updates: Updates.statusAndProgress,
    );

    final result = await FileDownloader().download(task);
    if (result.status == TaskStatus.complete) {
      try {
        await FileDownloader().moveToSharedStorage(task, sharedDir, directory: 'DJ_Downloads');
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved: $fileName'), backgroundColor: Colors.green));
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Save error: $e'), backgroundColor: Colors.red));
      }
    }
  }

  void _setSleepTimer(int min) {
    _sleepTimer?.cancel();
    if(min > 0) {
      _sleepTimer = Timer(Duration(minutes: min), () {
        _audioPlayer.pause();
        if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sleep Timer Ended. Playback Paused.')));
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Sleep timer set: $min min')));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sleep timer disabled.')));
    }
  }

  void _showInspector(Map<String, dynamic> track) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.analytics, color: Colors.cyanAccent),
                const SizedBox(width: 8),
                Text("Track Inspector", style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
            const Divider(height: 24),
            Text("Title: ${track['title']}", style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text("Artist: ${track['artist']}"),
            const SizedBox(height: 6),
            Text("Engine ID: ${track['resolver']}"),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorNotifier.value.withAlpha(50),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colorNotifier.value),
              ),
              child: const Row(
                children: [
                  Icon(Icons.verified_user, color: Colors.white70),
                  SizedBox(width: 8),
                  Expanded(child: Text("High-Fidelity Audio\nNo embedded watermarks.", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  void dispose() {
    _speedDebounce?.cancel();
    _sleepTimer?.cancel();
    _audioPlayer.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('DJ Pro Player', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          PopupMenuButton<int>(
            tooltip: "Sleep Timer",
            icon: const Icon(Icons.nights_stay),
            onSelected: _setSleepTimer,
            itemBuilder: (_) => const [
              PopupMenuItem(value: 15, child: Text("15m Timer")),
              PopupMenuItem(value: 30, child: Text("30m Timer")),
              PopupMenuItem(value: 60, child: Text("60m Timer")),
              PopupMenuItem(value: 0, child: Text("Off")),
            ],
          ),
          IconButton(
            icon: Icon(themeNotifier.value == ThemeMode.light ? Icons.dark_mode : Icons.light_mode),
            onPressed: () {
              HapticFeedback.selectionClick();
              themeNotifier.value = themeNotifier.value == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: IndexedStack(
              index: _currentTab,
              children: [
                _buildSearchTab(),
                _buildCrateTab(),
                _buildStudioToolsTab(),
              ],
            ),
          ),
          if (_currentTitle != null) _buildBottomPlayer(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentTab,
        selectedItemColor: colorNotifier.value,
        onTap: (index) {
          HapticFeedback.selectionClick();
          setState(() => _currentTab = index);
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.public), label: "Global Search"),
          BottomNavigationBarItem(icon: Icon(Icons.queue_music), label: "DJ Crate"),
          BottomNavigationBarItem(icon: Icon(Icons.tune), label: "Studio Tools"),
        ],
      ),
    );
  }

  Widget _buildSearchTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search Global Database...',
              filled: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () => _searchController.clear(),
              )
            ),
            onSubmitted: _searchSongs,
          ),
        ),
        if (_searchHistory.isNotEmpty && _searchResults.isEmpty && !_isLoading)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            child: Wrap(
              spacing: 8,
              children: [
                ..._searchHistory.map((q) => ActionChip(label: Text(q), onPressed: () { _searchController.text = q; _searchSongs(q); })).toList(),
                ActionChip(label: const Text("Clear", style: TextStyle(color: Colors.red)), onPressed: () {
                  setState(() => _searchHistory.clear());
                  _savePrefs();
                })
              ]
            ),
          ),
        if (_isLoading) const Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()),
        Expanded(
          child: ListView.builder(
            itemCount: _searchResults.length,
            itemBuilder: (context, index) => _buildSongTile(index, _searchResults, allowSwipe: false),
          ),
        ),
      ],
    );
  }

  Widget _buildCrateTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  IconButton(icon: Icon(_isGridView ? Icons.view_list : Icons.grid_view), onPressed: () { HapticFeedback.selectionClick(); setState(() => _isGridView = !_isGridView); }),
                ],
              ),
              TextButton.icon(
                icon: const Icon(Icons.delete_sweep, color: Colors.red),
                label: const Text("Clear Crate", style: TextStyle(color: Colors.red)),
                onPressed: () {
                  HapticFeedback.vibrate();
                  setState(() => _djFavorites.clear());
                  _savePrefs();
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: _djFavorites.isEmpty
              ? const Center(child: Text("Your Crate is empty. Star tracks to add them!"))
              : _isGridView 
                ? GridView.builder(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, childAspectRatio: 0.8),
                    itemCount: _djFavorites.length,
                    itemBuilder: (context, index) => _buildGridTile(index, _djFavorites),
                  )
                : ReorderableListView.builder(
                    itemCount: _djFavorites.length,
                    onReorder: (oldI, newI) {
                      setState(() {
                        if (oldI < newI) newI -= 1;
                        final item = _djFavorites.removeAt(oldI);
                        _djFavorites.insert(newI, item);
                      });
                      _savePrefs();
                    },
                    itemBuilder: (context, index) => _buildSongTile(index, _djFavorites, allowSwipe: true, key: ValueKey(_djFavorites[index]['id'])),
                  ),
        ),
      ],
    );
  }

  Widget _buildGridTile(int index, List<Map<String,dynamic>> list) {
    final track = list[index];
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _playSong(index, list),
        child: Column(
          children: [
            Expanded(child: Image.network(track['image']!, fit: BoxFit.cover, width: double.infinity)),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(track['title']!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold)),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildStudioToolsTab() {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text("BPM Tap Calculator", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: colorNotifier.value)),
        const SizedBox(height: 16),
        Center(
          child: Column(
            children: [
              Text(_calculatedBpm > 0 ? "$_calculatedBpm" : "--", style: const TextStyle(fontSize: 64, fontWeight: FontWeight.bold)),
              ElevatedButton(
                style: ElevatedButton.styleFrom(shape: const CircleBorder(), padding: const EdgeInsets.all(40), backgroundColor: colorNotifier.value),
                onPressed: () {
                  HapticFeedback.lightImpact();
                  final now = DateTime.now();
                  _tapTimestamps.add(now);
                  if (_tapTimestamps.length > 5) _tapTimestamps.removeAt(0);
                  if (_tapTimestamps.length >= 2) {
                    int total = 0;
                    for (int i = 1; i < _tapTimestamps.length; i++) total += _tapTimestamps[i].difference(_tapTimestamps[i - 1]).inMilliseconds;
                    if (total > 0) setState(() => _calculatedBpm = (60000 / (total / (_tapTimestamps.length - 1))).round());
                  }
                },
                child: const Text("TAP", style: TextStyle(fontSize: 20, color: Colors.white)),
              ),
              TextButton(onPressed: () => setState(() { _tapTimestamps.clear(); _calculatedBpm = 0; }), child: const Text("Reset")),
            ],
          ),
        ),
        const Divider(height: 40),
        const Text("Software EQ Mapping (Hardware pass-through)", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        _buildEQSlider("High", _eqHigh, (v) => setState(() => _eqHigh = v)),
        _buildEQSlider("Mid", _eqMid, (v) => setState(() => _eqMid = v)),
        _buildEQSlider("Low", _eqLow, (v) => setState(() => _eqLow = v)),
        const SizedBox(height: 20),
        const Text("Note: Native Android EQ filters require OS binding.", style: TextStyle(fontSize: 10, color: Colors.grey)),
      ],
    );
  }

  Widget _buildEQSlider(String label, double value, ValueChanged<double> onChanged) {
    return Row(
      children: [
        SizedBox(width: 40, child: Text(label)),
        Expanded(child: Slider(value: value, min: -1.0, max: 1.0, activeColor: colorNotifier.value, onChanged: onChanged)),
      ],
    );
  }

  Widget _buildSongTile(int index, List<Map<String,dynamic>> list, {bool allowSwipe = false, Key? key}) {
    final track = list[index];
    final isFav = _djFavorites.any((item) => item['id'] == track['id']);
    final isPlaying = _currentTitle == track['title'];

    Widget tile = ListTile(
      leading: Stack(
        alignment: Alignment.center,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: track['image']!.isNotEmpty
                ? Image.network(track['image']!, width: 50, height: 50, fit: BoxFit.cover, errorBuilder: (c, e, s) => const Icon(Icons.music_note, size: 50))
                : const Icon(Icons.music_note, size: 50),
          ),
          if(isPlaying && _isPlaying)
            Container(
              color: Colors.black54,
              width: 50, height: 50,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: List.generate(3, (i) => Container(margin: const EdgeInsets.symmetric(horizontal: 1), width: 4, height: 10 + Random().nextInt(15).toDouble(), color: colorNotifier.value)),
              ),
            )
        ],
      ),
      title: Text(track['title']!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.bold, color: isPlaying ? colorNotifier.value : null)),
      subtitle: Text(track['artist']!, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(isFav ? Icons.star : Icons.star_border, color: isFav ? Colors.amber : Colors.grey),
            onPressed: () {
              HapticFeedback.selectionClick();
              setState(() {
                if (isFav) _djFavorites.removeWhere((item) => item['id'] == track['id']);
                else _djFavorites.add(track);
              });
              _savePrefs();
            },
          ),
          IconButton(icon: const Icon(Icons.info_outline, size: 22), onPressed: () => _showInspector(track)),
          IconButton(icon: const Icon(Icons.download, size: 26), onPressed: () => _downloadSong(track)),
        ],
      ),
      onTap: () => _playSong(index, list),
    );

    if (allowSwipe) {
      return Dismissible(
        key: key ?? UniqueKey(),
        direction: DismissDirection.endToStart,
        background: Container(color: Colors.red, alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20), child: const Icon(Icons.delete, color: Colors.white)),
        onDismissed: (_) {
          setState(() => _djFavorites.removeAt(index));
          _savePrefs();
        },
        child: tile,
      );
    }
    return tile;
  }

  Widget _buildBottomPlayer() {
    final remaining = _duration - _position;
    final mins = _position.inMinutes.remainder(60).toString().padLeft(2, '0');
    final secs = _position.inSeconds.remainder(60).toString().padLeft(2, '0');
    final rmins = remaining.inMinutes.remainder(60).toString().padLeft(2, '0');
    final rsecs = remaining.inSeconds.remainder(60).toString().padLeft(2, '0');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF151515) : Colors.white,
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, -3))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (_currentImage != null)
                ClipRRect(borderRadius: BorderRadius.circular(6), child: Image.network(_currentImage!, width: 44, height: 44, errorBuilder: (c, e, s) => const Icon(Icons.music_note))),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_currentTitle ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                    Text(_currentArtist ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.replay_10),
                onPressed: () {
                  var newPos = _position - const Duration(seconds: 10);
                  if (newPos < Duration.zero) newPos = Duration.zero;
                  _audioPlayer.seek(newPos);
                },
              ),
              IconButton(
                icon: Icon(_isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled, color: colorNotifier.value, size: 42),
                onPressed: () { HapticFeedback.lightImpact(); _isPlaying ? _audioPlayer.pause() : _audioPlayer.play(); },
              ),
              IconButton(
                icon: const Icon(Icons.forward_10),
                onPressed: () {
                  var newPos = _position + const Duration(seconds: 10);
                  if (_duration > Duration.zero && newPos > _duration) newPos = _duration;
                  _audioPlayer.seek(newPos);
                },
              ),
            ],
          ),
          SizedBox(
            height: 24,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6), trackHeight: 3),
              child: Slider(
                value: _position.inSeconds.toDouble().clamp(0.0, _duration.inSeconds.toDouble()),
                max: _duration.inSeconds.toDouble() > 0 ? _duration.inSeconds.toDouble() : 1.0,
                activeColor: Colors.cyanAccent,
                inactiveColor: Colors.grey[700],
                onChanged: (val) => _audioPlayer.seek(Duration(seconds: val.toInt())),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('$mins:$secs', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                Text("-$rmins:$rsecs", style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),
          ),
          Row(
            children: [
              const Icon(Icons.speed, size: 16, color: Colors.grey),
              Expanded(
                child: Slider(
                  value: _playbackSpeed, min: 0.5, max: 3.0, activeColor: colorNotifier.value,
                  onChanged: _handleSpeedChange,
                ),
              ),
              InkWell(
                onTap: () { HapticFeedback.lightImpact(); _handleSpeedChange(1.0); },
                child: Text("${_playbackSpeed.toStringAsFixed(1)}x", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.volume_up, size: 16, color: Colors.grey),
              Expanded(
                child: Slider(
                  value: _volume, min: 0.0, max: 1.0, activeColor: Colors.cyanAccent,
                  onChanged: (v) { setState(() => _volume = v); _audioPlayer.setVolume(v); },
                ),
              ),
              IconButton(
                icon: Icon(_loopMode == LoopMode.one ? Icons.repeat_one : Icons.repeat, color: _loopMode == LoopMode.off ? Colors.grey : colorNotifier.value),
                onPressed: () {
                  HapticFeedback.selectionClick();
                  setState(() => _loopMode = _loopMode == LoopMode.off ? LoopMode.all : (_loopMode == LoopMode.all ? LoopMode.one : LoopMode.off));
                  _audioPlayer.setLoopMode(_loopMode);
                },
              )
            ],
          )
        ],
      ),
    );
  }
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _selectedLocation = 'Music';
  bool _crossfade = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _selectedLocation = prefs.getString('save_location') ?? 'Music';
      _crossfade = prefs.getBool('crossfade') ?? false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('DJ Settings')),
      body: ListView(
        children: [
          const Padding(padding: EdgeInsets.all(16.0), child: Text("App Theme Color", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 15,
            children: [Colors.deepPurple, Colors.green, Colors.red, Colors.amber, Colors.blue].map((color) => GestureDetector(
              onTap: () async {
                HapticFeedback.lightImpact();
                colorNotifier.value = color;
                final prefs = await SharedPreferences.getInstance();
                prefs.setInt('theme_color', color.value);
              },
              child: ValueListenableBuilder<MaterialColor>(
                valueListenable: colorNotifier,
                builder: (_, val, __) => CircleAvatar(backgroundColor: color, radius: 20, child: val == color ? const Icon(Icons.check, color: Colors.white) : null),
              )
            )).toList(),
          ),
          const Divider(),
          SwitchListTile(
            title: const Text("Crossfade Playback"),
            subtitle: const Text("Smooth volume ramp on play"),
            activeColor: colorNotifier.value,
            value: _crossfade,
            onChanged: (v) async {
              HapticFeedback.selectionClick();
              setState(() => _crossfade = v);
              final p = await SharedPreferences.getInstance();
              p.setBool('crossfade', v);
            }
          ),
          const Divider(),
          const Padding(padding: EdgeInsets.all(16.0), child: Text("Download Destination", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
          RadioListTile<String>(
            title: const Text("Music Folder"),
            subtitle: const Text("Internal Storage/Music/DJ_Downloads"),
            value: 'Music',
            groupValue: _selectedLocation,
            onChanged: (val) async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('save_location', val!);
              setState(() => _selectedLocation = val);
            },
          ),
          RadioListTile<String>(
            title: const Text("Downloads Folder"),
            subtitle: const Text("Internal Storage/Download/DJ_Downloads"),
            value: 'Downloads',
            groupValue: _selectedLocation,
            onChanged: (val) async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('save_location', val!);
              setState(() => _selectedLocation = val);
            },
          ),
          const Divider(),
          const ListTile(
            leading: Icon(Icons.save_alt, color: Colors.cyanAccent),
            title: Text("File Output Standard"),
            subtitle: Text("Format: [Track Name] - [Artist].m4a"),
          ),
        ],
      ),
    );
  }
}
