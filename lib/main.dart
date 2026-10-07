import 'package:flutter/material.dart';
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
              title: 'DJ Pro Workstation',
              debugShowCheckedModeBanner: false,
              theme: ThemeData(
                brightness: Brightness.light,
                primaryColor: currentColor,
                colorScheme: ColorScheme.light(primary: currentColor, secondary: Colors.teal),
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
  
  String _activeSource = 'JioSaavn';
  List<dynamic> _searchResults = [];
  List<String> _searchHistory = [];
  List<Map<String, dynamic>> _djFavorites = [];
  bool _isLoading = false;
  bool _isGridView = false;
  bool _isShuffle = false;

  // Track & Playback State
  List<dynamic> _currentPlaylist = [];
  int _currentIndex = -1;
  String? _currentTitle;
  String? _currentArtist;
  String? _currentImage;
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  double _playbackSpeed = 1.0;
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
    });
  }

  Future<void> _saveHistory(String query) async {
    if (query.trim().isEmpty) return;
    if (!_searchHistory.contains(query)) {
      _searchHistory.insert(0, query);
      if (_searchHistory.length > 8) _searchHistory.removeLast();
      final prefs = await SharedPreferences.getInstance();
      prefs.setStringList('history', _searchHistory);
      setState((){});
    }
  }

  Map<String, String> _extractData(dynamic song) {
    if (song['source'] == 'YouTube') {
      return {
        'id': song['id'],
        'title': song['title'],
        'subtitle': song['subtitle'],
        'image': song['image'],
        'mediaUrl': song['id'], // We resolve YT stream at playback
        'source': 'YouTube'
      };
    }
    
    final title = song['title']?.toString().replaceAll(RegExp(r'<[^>]*>'), '') ?? 'Unknown';
    final subtitle = song['subtitle']?.toString().replaceAll(RegExp(r'<[^>]*>'), '') ?? 'Unknown Artist';
    final imageUrl = song['image']?.toString().replaceAll('150x150', '50x50') ?? '';
    final moreInfo = song['more_info'] ?? {};
    final mediaUrl = song['encrypted_media_url'] ?? moreInfo['encrypted_media_url'] ?? moreInfo['vlink'] ?? song['media_preview_url'] ?? '';
    return {'id': mediaUrl, 'title': title, 'subtitle': subtitle, 'image': imageUrl, 'mediaUrl': mediaUrl, 'source': 'JioSaavn'};
  }

  Future<void> _searchSongs(String query) async {
    if (query.trim().isEmpty) return;
    _saveHistory(query);
    setState(() {
      _isLoading = true;
      _searchResults = [];
    });

    try {
      if (_activeSource == 'YouTube') {
        final ytResults = await _yt.search.search(query);
        final parsed = ytResults.take(15).map((v) => {
          'source': 'YouTube',
          'id': v.id.value,
          'title': v.title,
          'subtitle': v.author,
          'image': v.thumbnails.highResUrl,
        }).toList();
        setState(() => _searchResults = parsed);
      } else {
        final url = Uri.parse('https://www.jiosaavn.com/api.php?__call=search.getResults&_format=json&_marker=0&ctx=web6dot0&api_version=4&q=${Uri.encodeComponent(query)}');
        final response = await http.get(url, headers: {'User-Agent': 'Mozilla/5.0', 'Accept': 'application/json'});
        if (response.statusCode == 200) {
          final data = json.decode(response.body.trim());
          List<dynamic> parsed = [];
          if (data is Map) {
            if (data['results'] != null) parsed = data['results'];
            else if (data['songs']?['data'] != null) parsed = data['songs']['data'];
          }
          setState(() => _searchResults = parsed);
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Search error: $e")));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  String _decryptJioUrl(String encryptedUrl) {
    try {
      final key = utf8.encode('38346591');
      final decodedBytes = base64.decode(encryptedUrl);
      final des = DES(key: key, mode: DESMode.ECB, paddingType: DESPaddingType.PKCS7);
      final decryptedUrl = utf8.decode(des.decrypt(decodedBytes));
      return decryptedUrl.replaceAll('_96', _selectedQuality);
    } catch (e) {
      return "";
    }
  }

  Future<String> _resolveDirectUrl(Map<String, String> data) async {
    if (data['source'] == 'YouTube') {
      try {
        var manifest = await _yt.videos.streamsClient.getManifest(data['id']);
        return manifest.audioOnly.withHighestBitrate().url.toString();
      } catch (e) {
        return "";
      }
    } else {
      return _decryptJioUrl(data['mediaUrl']!);
    }
  }

  Future<void> _playSong(int index, List<dynamic> list) async {
    if(index < 0 || index >= list.length) return;
    final data = _extractData(list[index]);
    
    final directUrl = await _resolveDirectUrl(data);
    if (directUrl.isNotEmpty) {
      setState(() {
        _currentPlaylist = list;
        _currentIndex = index;
        _currentTitle = data['title'];
        _currentArtist = data['subtitle'];
        _currentImage = data['image'];
      });
      
      await _audioPlayer.setUrl(directUrl);
      await _audioPlayer.setSpeed(_playbackSpeed);
      await _audioPlayer.setVolume(_volume);
      _audioPlayer.play();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Stream not available.")));
    }
  }

  void _playNext() {
    if (_currentPlaylist.isEmpty) return;
    int next = _currentIndex + 1;
    if (_isShuffle) next = Random().nextInt(_currentPlaylist.length);
    if (next < _currentPlaylist.length) _playSong(next, _currentPlaylist);
  }

  void _playPrev() {
    if (_currentIndex > 0) _playSong(_currentIndex - 1, _currentPlaylist);
  }

  Future<void> _downloadSong(Map<String, String> data) async {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Processing Download: ${data['title']}')));
    
    final directUrl = await _resolveDirectUrl(data);
    if (directUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cannot resolve media stream.')));
      return;
    }

    // LIFETIME FEATURE: Safe file naming with hardcoded credit to bypass fragile metadata packages
    final safeTitle = "Gajanan P - " + data['title']!.replaceAll(RegExp(r'[\\/:*?"<>|]'), '');
    final prefs = await SharedPreferences.getInstance();
    final saveLocation = prefs.getString('save_location') ?? 'Music';
    final sharedDir = saveLocation == 'Downloads' ? SharedStorage.downloads : SharedStorage.audio;

    final task = DownloadTask(
      url: directUrl,
      filename: '$safeTitle.m4a',
      directory: 'DJ_Downloads',
      baseDirectory: BaseDirectory.applicationDocuments,
      updates: Updates.statusAndProgress,
    );

    final result = await FileDownloader().download(task);
    if (result.status == TaskStatus.complete) {
      try {
        await FileDownloader().moveToSharedStorage(task, sharedDir, directory: 'DJ_Downloads');
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved: $safeTitle'), backgroundColor: Colors.green));
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

  void _showInspector(Map<String, String> data) {
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
                const Icon(Icons.verified, color: Colors.cyanAccent),
                const SizedBox(width: 8),
                Text("DJ Track Inspector", style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
            const Divider(height: 24),
            Text("Title: ${data['title']}", style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text("Artist: ${data['subtitle']}"),
            const SizedBox(height: 6),
            Text("Data Source: ${data['source']}"),
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
                  Icon(Icons.copyright, color: Colors.white70),
                  SizedBox(width: 8),
                  Expanded(child: Text("Copyright & DJ Credit:\nDownloaded By Gajanan P", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _sleepTimer?.cancel();
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
          PopupMenuButton<int>(
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
            onPressed: () => themeNotifier.value = themeNotifier.value == ThemeMode.light ? ThemeMode.dark : ThemeMode.light,
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
        onTap: (index) => setState(() => _currentTab = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.public), label: "Multi-Source"),
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
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search $_activeSource...',
                    filled: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
                    prefixIcon: const Icon(Icons.search),
                  ),
                  onSubmitted: _searchSongs,
                ),
              ),
              const SizedBox(width: 8),
              DropdownButton<String>(
                value: _activeSource,
                underline: const SizedBox(),
                items: ['JioSaavn', 'YouTube'].map((String value) {
                  return DropdownMenuItem<String>(value: value, child: Text(value));
                }).toList(),
                onChanged: (val) => setState(() => _activeSource = val!),
              ),
            ],
          ),
        ),
        if (_searchHistory.isNotEmpty && _searchResults.isEmpty && !_isLoading)
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Wrap(
              spacing: 8,
              children: [
                ..._searchHistory.map((q) => ActionChip(label: Text(q), onPressed: () { _searchController.text = q; _searchSongs(q); })).toList(),
                ActionChip(label: const Text("Clear", style: TextStyle(color: Colors.red)), onPressed: () async {
                  setState(() => _searchHistory.clear());
                  final prefs = await SharedPreferences.getInstance();
                  prefs.remove('history');
                })
              ]
            ),
          ),
        if (_isLoading) const Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()),
        Expanded(
          child: ListView.builder(
            itemCount: _searchResults.length,
            itemBuilder: (context, index) => _buildSongTile(index, _searchResults),
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
                  IconButton(icon: Icon(_isGridView ? Icons.view_list : Icons.grid_view), onPressed: () => setState(() => _isGridView = !_isGridView)),
                  IconButton(icon: const Icon(Icons.sort_by_alpha), onPressed: () => setState(() => _djFavorites.sort((a, b) => _extractData(a)['title']!.compareTo(_extractData(b)['title']!)))),
                ],
              ),
              TextButton.icon(
                icon: const Icon(Icons.delete_sweep, color: Colors.red),
                label: const Text("Clear Crate", style: TextStyle(color: Colors.red)),
                onPressed: () => setState(() => _djFavorites.clear()),
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
                : ListView.builder(
                    itemCount: _djFavorites.length,
                    itemBuilder: (context, index) => _buildSongTile(index, _djFavorites),
                  ),
        ),
      ],
    );
  }

  Widget _buildGridTile(int index, List<dynamic> list) {
    final data = _extractData(list[index]);
    return Card(
      child: InkWell(
        onTap: () => _playSong(index, list),
        child: Column(
          children: [
            Expanded(child: Image.network(data['image']!, fit: BoxFit.cover)),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(data['title']!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold)),
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

  Widget _buildSongTile(int index, List<dynamic> list) {
    final data = _extractData(list[index]);
    final isFav = _djFavorites.any((item) => _extractData(item)['title'] == data['title']);
    final isPlaying = _currentTitle == data['title'];

    return ListTile(
      leading: Stack(
        alignment: Alignment.center,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: data['image']!.isNotEmpty
                ? Image.network(data['image']!, width: 50, height: 50, fit: BoxFit.cover, errorBuilder: (c, e, s) => const Icon(Icons.music_note, size: 50))
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
      title: Text(data['title']!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.bold, color: isPlaying ? colorNotifier.value : null)),
      subtitle: Text(data['subtitle']!, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(isFav ? Icons.star : Icons.star_border, color: isFav ? Colors.amber : Colors.grey),
            onPressed: () => setState(() {
              if (isFav) _djFavorites.removeWhere((item) => _extractData(item)['title'] == data['title']);
              else _djFavorites.add(Map<String, dynamic>.from(list[index]));
            }),
          ),
          IconButton(icon: const Icon(Icons.info_outline, size: 22), onPressed: () => _showInspector(data)),
          IconButton(icon: const Icon(Icons.download, size: 26), onPressed: () => _downloadSong(data)),
        ],
      ),
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
        color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF1A1A1A) : Colors.white,
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
              IconButton(icon: Icon(_isShuffle ? Icons.shuffle : Icons.shuffle, color: _isShuffle ? colorNotifier.value : Colors.grey), onPressed: () => setState(() => _isShuffle = !_isShuffle)),
              IconButton(icon: const Icon(Icons.skip_previous), onPressed: _playPrev),
              IconButton(
                icon: Icon(_isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled, color: colorNotifier.value, size: 42),
                onPressed: () => _isPlaying ? _audioPlayer.pause() : _audioPlayer.play(),
              ),
              IconButton(icon: const Icon(Icons.skip_next), onPressed: _playNext),
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
                  value: _playbackSpeed, min: 0.5, max: 1.5, activeColor: colorNotifier.value,
                  onChanged: (v) { setState(() => _playbackSpeed = v); _audioPlayer.setSpeed(v); },
                ),
              ),
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

  Future<void> _saveSettings(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('save_location', value);
    setState(() => _selectedLocation = value);
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
            subtitle: const Text("Internal Storage/Music/DJ_Downloads"),
            value: 'Music',
            groupValue: _selectedLocation,
            onChanged: (val) => _saveSettings(val!),
          ),
          RadioListTile<String>(
            title: const Text("Downloads Folder"),
            subtitle: const Text("Internal Storage/Download/DJ_Downloads"),
            value: 'Downloads',
            groupValue: _selectedLocation,
            onChanged: (val) => _saveSettings(val!),
          ),
          const Divider(),
          const ListTile(
            leading: Icon(Icons.badge, color: Colors.cyanAccent),
            title: Text("DJ Credit Signature"),
            subtitle: Text("File Prefix: Gajanan P - [Track Name]"),
          ),
        ],
      ),
    );
  }
}
