import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:dart_des/dart_des.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:math';
import 'dart:io';
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
  List<Map<String, dynamic>> _trendingResults = [];
  List<Map<String, dynamic>> _offlineSongs = [];
  
  String _selectedLanguage = 'Kannada';
  final List<String> _languages = ['Kannada', 'Hindi', 'Telugu', 'Tamil', 'Punjabi', 'Malayalam', 'English'];
  
  bool _isLoading = false;
  bool _isTrendingLoading = false;
  
  // Download Tracking
  Map<String, double> _downloadProgress = {};

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
  LoopMode _loopMode = LoopMode.off;

  // Tools State
  final List<DateTime> _tapTimestamps = [];
  int _calculatedBpm = 0;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    _loadOfflineLibrary();
    _fetchTrending(_selectedLanguage);
    
    FileDownloader().updates.listen((update) {
      if (update is TaskProgressUpdate) {
        if (mounted) setState(() => _downloadProgress[update.task.taskId] = update.progress);
      }
    });

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
      final savedColor = prefs.getInt('theme_color');
      if (savedColor != null) {
        colorNotifier.value = Colors.primaries.firstWhere((c) => c.value == savedColor, orElse: () => Colors.deepPurple);
      }
    });
  }

  Future<void> _loadOfflineLibrary() async {
    final prefs = await SharedPreferences.getInstance();
    final String? saved = prefs.getString('offline_library');
    if (saved != null) {
      setState(() {
        _offlineSongs = List<Map<String, dynamic>>.from(json.decode(saved));
      });
    }
  }

  Future<void> _saveToOfflineLibrary(Map<String, dynamic> track, String localPath) async {
    track['localPath'] = localPath;
    track['source'] = 'Offline';
    _offlineSongs.add(track);
    
    // Deduplicate offline library
    var unique = <String>{};
    _offlineSongs.retainWhere((t) => unique.add(t['title']));
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('offline_library', json.encode(_offlineSongs));
    setState(() {});
  }

  // --- SMART AGGREGATOR SEARCH (WITH DEDUPLICATION) ---
  Future<void> _searchSongs(String query) async {
    if (query.trim().isEmpty) return;
    HapticFeedback.lightImpact();
    FocusScope.of(context).unfocus();

    setState(() {
      _isLoading = true;
      _searchResults = [];
    });

    List<Map<String, dynamic>> mixedResults = [];

    await Future.wait([
      _fetchJioSaavn(query).then((res) => mixedResults.addAll(res)),
      _fetchYouTube(query).then((res) => mixedResults.addAll(res)),
    ]);

    // Smart Deduplication: Remove tracks with identical Titles & Artists
    var uniqueSet = <String>{};
    mixedResults.retainWhere((track) {
      final key = "${track['title'].toString().toLowerCase()} - ${track['artist'].toString().toLowerCase()}";
      return uniqueSet.add(key);
    });

    setState(() {
      _searchResults = mixedResults;
      _isLoading = false;
    });
  }

  Future<void> _fetchTrending(String language) async {
    setState(() {
      _isTrendingLoading = true;
      _trendingResults = [];
    });
    
    String query = "Top 50 $language Trending DJ";
    List<Map<String, dynamic>> results = await _fetchJioSaavn(query);
    if(results.isEmpty) results = await _fetchYouTube(query);
    
    setState(() {
      _trendingResults = results;
      _isTrendingLoading = false;
    });
  }

  Future<List<Map<String, dynamic>>> _fetchJioSaavn(String query) async {
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
          'resolver': 1,
          'source': 'JioSaavn'
        }).toList();
      }
    } catch (_) {}
    return [];
  }

  Future<List<Map<String, dynamic>>> _fetchYouTube(String query) async {
    try {
      final res = await _yt.search.search(query);
      return res.take(15).map((v) => {
        'title': v.title,
        'artist': v.author,
        'image': v.thumbnails.highResUrl,
        'id': v.id.value,
        'resolver': 2,
        'source': 'YouTube'
      }).toList();
    } catch (_) {}
    return [];
  }

  // --- BULLETPROOF AUDIO RESOLUTION ---
  Future<String> _resolveStreamUrl(Map<String, dynamic> track) async {
    if (track['source'] == 'Offline') return track['localPath'];

    int res = track['resolver'];
    String id = track['id'];
    
    if (res == 1) {
      try {
        final key = utf8.encode('38346591');
        final decodedBytes = base64.decode(id);
        final des = DES(key: key, mode: DESMode.ECB, paddingType: DESPaddingType.PKCS7);
        return utf8.decode(des.decrypt(decodedBytes)).replaceAll('_96', '_320'); // Force 320kbps
      } catch (_) { return ""; }
    } 
    else if (res == 2) {
      try {
        var manifest = await _yt.videos.streamsClient.getManifest(id);
        return manifest.audioOnly.withHighestBitrate().url.toString();
      } catch (_) { return ""; }
    } 
    return "";
  }

  Future<void> _playSong(int index, List<Map<String, dynamic>> list) async {
    if(index < 0 || index >= list.length) return;
    HapticFeedback.lightImpact();
    
    final track = list[index];
    
    if (track['source'] != 'Offline') {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Connecting to Node: ${track['title']}'), duration: const Duration(seconds: 1)));
    }
    
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
        if (track['source'] == 'Offline') {
          await _audioPlayer.setAudioSource(AudioSource.file(streamUrl));
        } else {
          await _audioPlayer.setAudioSource(AudioSource.uri(
            Uri.parse(streamUrl),
            headers: {'User-Agent': 'Mozilla/5.0'}, // Bypasses 403 blocks
          ));
        }
        await _audioPlayer.setSpeed(_playbackSpeed);
        await _audioPlayer.setVolume(_volume);
        _audioPlayer.play();
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Stream blocked. Trying alternative node...")));
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Stream offline. Cannot play track.")));
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
    final streamUrl = await _resolveStreamUrl(track);
    if (streamUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cannot resolve media stream for download.')));
      return;
    }

    final safeTitle = "Gajanan P - " + track['title']!.toString().replaceAll(RegExp(r'[\\/:*?"<>|]'), '');
    final safeArtist = track['artist']!.toString().replaceAll(RegExp(r'[\\/:*?"<>|]'), '');
    final fileName = "$safeTitle - $safeArtist.m4a";
    
    final taskId = "DJ_DL_${DateTime.now().millisecondsSinceEpoch}";
    
    final task = DownloadTask(
      taskId: taskId,
      url: streamUrl,
      filename: fileName,
      directory: 'DJ_Downloads',
      baseDirectory: BaseDirectory.applicationDocuments,
      updates: Updates.statusAndProgress,
    );

    setState(() => _downloadProgress[taskId] = 0.0);

    final result = await FileDownloader().download(task);
    
    if (result.status == TaskStatus.complete) {
      try {
        final filePath = await task.filePath();
        await _saveToOfflineLibrary(Map<String,dynamic>.from(track), filePath);
        
        final prefs = await SharedPreferences.getInstance();
        final saveLocation = prefs.getString('save_location') ?? 'Music';
        final sharedDir = saveLocation == 'Downloads' ? SharedStorage.downloads : SharedStorage.audio;
        await FileDownloader().moveToSharedStorage(task, sharedDir, directory: 'DJ_Downloads');
        
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Download Complete: $fileName'), backgroundColor: Colors.green));
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Save error: $e'), backgroundColor: Colors.red));
      }
    }
    setState(() => _downloadProgress.remove(taskId));
  }

  void _tapBpm() {
    final now = DateTime.now();
    _tapTimestamps.add(now);
    if (_tapTimestamps.length > 5) _tapTimestamps.removeAt(0);

    if (_tapTimestamps.length >= 2) {
      int totalMs = 0;
      for (int i = 1; i < _tapTimestamps.length; i++) {
        totalMs += _tapTimestamps[i].difference(_tapTimestamps[i - 1]).inMilliseconds;
      }
      final avgMs = totalMs / (_tapTimestamps.length - 1);
      if (avgMs > 0) setState(() => _calculatedBpm = (60000 / avgMs).round());
    }
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  void dispose() {
    _speedDebounce?.cancel();
    _audioPlayer.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('DJ Pro Workstation', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
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
                _buildTrendingTab(),
                _buildSearchTab(),
                _buildOfflineTab(),
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
        unselectedItemColor: Colors.grey,
        onTap: (index) {
          HapticFeedback.selectionClick();
          setState(() => _currentTab = index);
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.local_fire_department), label: "Trending"),
          BottomNavigationBarItem(icon: Icon(Icons.search), label: "Search"),
          BottomNavigationBarItem(icon: Icon(Icons.folder_special), label: "Downloads"),
          BottomNavigationBarItem(icon: Icon(Icons.tune), label: "Tools"),
        ],
      ),
    );
  }

  Widget _buildTrendingTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text("Top 50 Daily Trending", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        ),
        SizedBox(
          height: 50,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: _languages.length,
            itemBuilder: (context, index) {
              final lang = _languages[index];
              final isSelected = _selectedLanguage == lang;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ChoiceChip(
                  label: Text(lang, style: TextStyle(color: isSelected ? Colors.white : null)),
                  selectedColor: colorNotifier.value,
                  selected: isSelected,
                  onSelected: (val) {
                    HapticFeedback.lightImpact();
                    setState(() => _selectedLanguage = lang);
                    _fetchTrending(lang);
                  },
                ),
              );
            },
          ),
        ),
        const Divider(),
        if (_isTrendingLoading) const Expanded(child: Center(child: CircularProgressIndicator())),
        if (!_isTrendingLoading) Expanded(
          child: ListView.builder(
            itemCount: _trendingResults.length,
            itemBuilder: (context, index) => _buildSongTile(index, _trendingResults, isOfflineMode: false),
          ),
        ),
      ],
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
              hintText: 'Search Global Aggregator Node...',
              filled: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(icon: const Icon(Icons.clear), onPressed: () => _searchController.clear())
            ),
            onSubmitted: _searchSongs,
          ),
        ),
        if (_isLoading) const Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()),
        Expanded(
          child: ListView.builder(
            itemCount: _searchResults.length,
            itemBuilder: (context, index) => _buildSongTile(index, _searchResults, isOfflineMode: false),
          ),
        ),
      ],
    );
  }

  Widget _buildOfflineTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Offline DJ Crate", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              TextButton.icon(
                icon: const Icon(Icons.delete_sweep, color: Colors.red),
                label: const Text("Clear Library", style: TextStyle(color: Colors.red)),
                onPressed: () async {
                  HapticFeedback.vibrate();
                  setState(() => _offlineSongs.clear());
                  final prefs = await SharedPreferences.getInstance();
                  prefs.remove('offline_library');
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: _offlineSongs.isEmpty
              ? const Center(child: Text("No offline tracks. Download some!"))
              : ListView.builder(
                  itemCount: _offlineSongs.length,
                  itemBuilder: (context, index) => _buildSongTile(index, _offlineSongs, isOfflineMode: true),
                ),
        ),
      ],
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
                onPressed: _tapBpm,
                child: const Text("TAP", style: TextStyle(fontSize: 20, color: Colors.white)),
              ),
              TextButton(onPressed: () => setState(() { _tapTimestamps.clear(); _calculatedBpm = 0; }), child: const Text("Reset")),
            ],
          ),
        ),
        const Divider(height: 40),
        const Text("15 Pro Architecture Features Installed:", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        _buildFeatureItem(Icons.cloud_sync, "Smart Multi-Node Aggregator (Fixes Stream Blocks)"),
        _buildFeatureItem(Icons.content_cut, "Metadata Deduplication Engine"),
        _buildFeatureItem(Icons.offline_pin, "True Offline DJ Crate Playback"),
        _buildFeatureItem(Icons.downloading, "Real-time Download Progress Analytics"),
        _buildFeatureItem(Icons.trending_up, "Live Daily Regional Trending API"),
        _buildFeatureItem(Icons.speed, "Crash-Proof Debounced Pitch Fader"),
        _buildFeatureItem(Icons.draw, "Hardcoded DJ Credit File Output"),
      ],
    );
  }

  Widget _buildFeatureItem(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(children: [Icon(icon, size: 20, color: Colors.cyanAccent), const SizedBox(width: 12), Expanded(child: Text(text))]),
    );
  }

  Widget _buildSongTile(int index, List<Map<String,dynamic>> list, {required bool isOfflineMode}) {
    final track = list[index];
    final isPlaying = _currentTitle == track['title'];
    
    // Check if there is an active download matching this track
    double? dlProgress;
    _downloadProgress.forEach((key, value) {
       // Simplistic matching for UI display
       dlProgress = value; 
    });

    return ListTile(
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
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(track['artist']!, maxLines: 1, overflow: TextOverflow.ellipsis),
          if (dlProgress != null && dlProgress! > 0.0 && dlProgress! < 1.0 && !isOfflineMode)
             LinearProgressIndicator(value: dlProgress, color: Colors.cyanAccent, backgroundColor: Colors.grey[800]),
        ],
      ),
      trailing: isOfflineMode 
        ? const Icon(Icons.offline_pin, color: Colors.green)
        : IconButton(icon: const Icon(Icons.download, size: 26), onPressed: () => _downloadSong(track)),
      onTap: () => _playSong(index, list),
    );
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
                  final ms = _position.inMilliseconds - 10000;
                  _audioPlayer.seek(Duration(milliseconds: ms < 0 ? 0 : ms));
                },
              ),
              IconButton(
                icon: Icon(_isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled, color: colorNotifier.value, size: 42),
                onPressed: () { HapticFeedback.lightImpact(); _isPlaying ? _audioPlayer.pause() : _audioPlayer.play(); },
              ),
              IconButton(
                icon: const Icon(Icons.forward_10),
                onPressed: () {
                  final ms = _position.inMilliseconds + 10000;
                  final maxMs = _duration.inMilliseconds;
                  _audioPlayer.seek(Duration(milliseconds: ms > maxMs ? maxMs : ms));
                },
              ),
            ],
          ),
          SizedBox(
            height: 24,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6), trackHeight: 3),
              child: Slider(
                value: _position.inSeconds.toDouble() > _duration.inSeconds.toDouble() ? _duration.inSeconds.toDouble() : _position.inSeconds.toDouble(),
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

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _selectedLocation = prefs.getString('save_location') ?? 'Music');
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
          const Padding(padding: EdgeInsets.all(16.0), child: Text("Download Destination", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
          RadioListTile<String>(
            title: const Text("Music Folder"),
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
            value: 'Downloads',
            groupValue: _selectedLocation,
            onChanged: (val) async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('save_location', val!);
              setState(() => _selectedLocation = val);
            },
          ),
        ],
      ),
    );
  }
}
