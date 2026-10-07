import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:dart_des/dart_des.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:math';
import 'package:just_audio/just_audio.dart';
import 'package:background_downloader/background_downloader.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Global Notifiers for instant UI updates
final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.dark);
final ValueNotifier<MaterialColor> colorNotifier = ValueNotifier(Colors.deepPurple);
final ValueNotifier<bool> fadeInNotifier = ValueNotifier(false);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Load saved preferences
  final prefs = await SharedPreferences.getInstance();
  fadeInNotifier.value = prefs.getBool('fade') ?? false;
  
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
              title: 'DJ Pro Player',
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
  
  List<dynamic> _searchResults = [];
  List<String> _searchHistory = [];
  List<Map<String, dynamic>> _djFavorites = [];
  bool _isLoading = false;

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

  // Tap-to-BPM State
  final List<DateTime> _tapTimestamps = [];
  int _calculatedBpm = 0;

  @override
  void initState() {
    super.initState();
    _loadHistory();
    _audioPlayer.playerStateStream.listen((state) {
      if (mounted) setState(() => _isPlaying = state.playing);
      if (state.processingState == ProcessingState.completed) {
        if (_loopMode == LoopMode.all || _loopMode == LoopMode.off) {
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

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _searchHistory = prefs.getStringList('history') ?? []);
  }

  Future<void> _saveHistory(String query) async {
    if (query.trim().isEmpty) return;
    if (!_searchHistory.contains(query)) {
      _searchHistory.insert(0, query);
      if (_searchHistory.length > 5) _searchHistory.removeLast();
      final prefs = await SharedPreferences.getInstance();
      prefs.setStringList('history', _searchHistory);
    }
  }

  // Feature 1: Intelligent API Parser
  Map<String, String> _extractData(dynamic song) {
    final title = song['title']?.toString().replaceAll(RegExp(r'<[^>]*>'), '') ?? 'Unknown';
    final subtitle = song['subtitle']?.toString().replaceAll(RegExp(r'<[^>]*>'), '') ?? 'Unknown Artist';
    final imageUrl = song['image']?.toString().replaceAll('150x150', '50x50') ?? '';
    final moreInfo = song['more_info'] ?? {};
    
    // Deep hunt for the URL across multiple possible API responses
    final mediaUrl = song['encrypted_media_url'] ?? 
                     moreInfo['encrypted_media_url'] ?? 
                     moreInfo['vlink'] ?? 
                     song['media_preview_url'] ?? '';
                     
    return {'title': title, 'subtitle': subtitle, 'image': imageUrl, 'mediaUrl': mediaUrl};
  }

  Future<void> _searchSongs(String query) async {
    if (query.trim().isEmpty) return;
    _saveHistory(query);
    setState(() {
      _isLoading = true;
      _searchResults = [];
    });

    try {
      final url = Uri.parse(
          'https://www.jiosaavn.com/api.php?__call=search.getResults&_format=json&_marker=0&ctx=web6dot0&api_version=4&q=${Uri.encodeComponent(query)}');
      
      final response = await http.get(url, headers: {
        'User-Agent': 'Mozilla/5.0',
        'Accept': 'application/json'
      });

      if (response.statusCode == 200) {
        final data = json.decode(response.body.trim());
        List<dynamic> parsed = [];
        if (data is Map) {
          if (data['results'] != null) parsed = data['results'];
          else if (data['songs']?['data'] != null) parsed = data['songs']['data'];
        }
        setState(() => _searchResults = parsed);
      }
    } catch (e) {
      debugPrint("Search error: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  String _decryptMediaUrl(String encryptedUrl, String quality) {
    try {
      final key = utf8.encode('38346591');
      final decodedBytes = base64.decode(encryptedUrl);
      final des = DES(key: key, mode: DESMode.ECB, paddingType: DESPaddingType.PKCS7);
      final decryptedUrl = utf8.decode(des.decrypt(decodedBytes));
      return decryptedUrl.replaceAll('_96', quality);
    } catch (e) {
      return "";
    }
  }

  Future<void> _playSong(int index, List<dynamic> list) async {
    if(index < 0 || index >= list.length) return;
    final song = list[index];
    final data = _extractData(song);
    if(data['mediaUrl']!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Stream not available for this track.")));
      return;
    }

    final directUrl = _decryptMediaUrl(data['mediaUrl']!, _selectedQuality);
    if (directUrl.isNotEmpty) {
      setState(() {
        _currentPlaylist = list;
        _currentIndex = index;
        _currentTitle = data['title'];
        _currentArtist = data['subtitle'];
        _currentImage = data['image'];
        _currentEncryptedUrl = data['mediaUrl'];
      });
      
      await _audioPlayer.setUrl(directUrl);
      await _audioPlayer.setSpeed(_playbackSpeed);
      
      // Feature 9: Fade-In Playback
      if(fadeInNotifier.value) {
        _audioPlayer.setVolume(0.0);
        _audioPlayer.play();
        for(int i=1; i<=10; i++){
          await Future.delayed(const Duration(milliseconds: 150));
          _audioPlayer.setVolume((i/10) * _volume);
        }
      } else {
        _audioPlayer.setVolume(_volume);
        _audioPlayer.play();
      }
    }
  }

  void _playNext() {
    if (_currentIndex < _currentPlaylist.length - 1) _playSong(_currentIndex + 1, _currentPlaylist);
  }

  void _playPrev() {
    if (_currentIndex > 0) _playSong(_currentIndex - 1, _currentPlaylist);
  }

  Future<void> _downloadSong(String encryptedUrl, String title, String subtitle) async {
    if(encryptedUrl.isEmpty) {
       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error: Stream locked.')));
       return;
    }
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Downloading High-Res: $title ($_selectedQuality kbps)')),
    );
    
    final decryptedUrl = _decryptMediaUrl(encryptedUrl, _selectedQuality);
    if (decryptedUrl.isEmpty) return;

    final safeTitle = "Gajanan P - " + title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '');
    final prefs = await SharedPreferences.getInstance();
    final saveLocation = prefs.getString('save_location') ?? 'Music';
    final sharedDir = saveLocation == 'Downloads' ? SharedStorage.downloads : SharedStorage.audio;

    final task = DownloadTask(
      url: decryptedUrl,
      filename: '$safeTitle.m4a',
      directory: 'DJ_Downloads',
      baseDirectory: BaseDirectory.applicationDocuments,
      updates: Updates.statusAndProgress,
    );

    final result = await FileDownloader().download(task);
    if (result.status == TaskStatus.complete) {
      try {
        await FileDownloader().moveToSharedStorage(task, sharedDir, directory: 'DJ_Downloads');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Saved to $saveLocation/DJ_Downloads: $safeTitle'),
              backgroundColor: Colors.green,
            ),
          );
        }
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

  void _showTrackDetails(Map<String, String> data) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) {
        return Padding(
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
              Text("Audio Stream: High-Fidelity AAC / ${_selectedQuality.replaceAll('_', '')} kbps"),
              const SizedBox(height: 6),
              const Text("Acoustic Headroom: 24-bit studio equivalent"),
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
        );
      },
    );
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
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
        title: const Text('DJ Pro Player', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          PopupMenuButton<int>(
            tooltip: "Sleep Timer",
            icon: const Icon(Icons.nights_stay),
            onSelected: _setSleepTimer,
            itemBuilder: (_) => const [
              PopupMenuItem(value: 15, child: Text("15 Minutes")),
              PopupMenuItem(value: 30, child: Text("30 Minutes")),
              PopupMenuItem(value: 60, child: Text("60 Minutes")),
              PopupMenuItem(value: 0, child: Text("Off")),
            ],
          ),
          PopupMenuButton<String>(
            tooltip: "Stream Quality",
            icon: const Icon(Icons.high_quality),
            onSelected: (val) {
              setState(() => _selectedQuality = val);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Quality set to ${val.replaceAll('_', '')} kbps')));
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: '_320', child: Text("320 kbps (High-Res)")),
              PopupMenuItem(value: '_160', child: Text("160 kbps (Standard)")),
              PopupMenuItem(value: '_96', child: Text("96 kbps (Data Saver)")),
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
                _buildBpmToolTab(),
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
          BottomNavigationBarItem(icon: Icon(Icons.search), label: "Discover"),
          BottomNavigationBarItem(icon: Icon(Icons.queue_music), label: "DJ Crate"),
          BottomNavigationBarItem(icon: Icon(Icons.speed), label: "BPM Tap"),
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
              hintText: 'Search Tracks...',
              filled: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
              prefixIcon: const Icon(Icons.search),
            ),
            onSubmitted: _searchSongs,
          ),
        ),
        if (_searchHistory.isNotEmpty && _searchResults.isEmpty && !_isLoading)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            child: Wrap(
              spacing: 8,
              children: _searchHistory.map((q) => ActionChip(
                label: Text(q),
                onPressed: () { _searchController.text = q; _searchSongs(q); }
              )).toList(),
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
    return _djFavorites.isEmpty
        ? const Center(child: Text("Your DJ Crate is empty. Star tracks to add them!"))
        : Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    icon: const Icon(Icons.delete_sweep, color: Colors.red),
                    label: const Text("Clear Crate", style: TextStyle(color: Colors.red)),
                    onPressed: () => setState(() => _djFavorites.clear()),
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: _djFavorites.length,
                  itemBuilder: (context, index) => _buildSongTile(index, _djFavorites),
                ),
              ),
            ],
          );
  }

  Widget _buildBpmToolTab() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            _calculatedBpm > 0 ? "$_calculatedBpm" : "--",
            style: TextStyle(fontSize: 72, fontWeight: FontWeight.bold, color: colorNotifier.value),
          ),
          const Text("BPM (Beats Per Minute)", style: TextStyle(fontSize: 18, color: Colors.grey)),
          const SizedBox(height: 36),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              shape: const CircleBorder(),
              padding: const EdgeInsets.all(48),
              backgroundColor: colorNotifier.value,
            ),
            onPressed: _tapBpm,
            child: const Text("TAP", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
          ),
          const SizedBox(height: 20),
          TextButton(
            onPressed: () => setState(() { _tapTimestamps.clear(); _calculatedBpm = 0; }),
            child: const Text("Reset BPM"),
          ),
        ],
      ),
    );
  }

  Widget _buildSongTile(int index, List<dynamic> list) {
    final data = _extractData(list[index]);
    final title = data['title']!;
    final subtitle = data['subtitle']!;
    final mediaUrl = data['mediaUrl']!;
    final imageUrl = data['image']!;
    
    final isFav = _djFavorites.any((item) => _extractData(item)['title'] == title);
    final isCurrentlyPlaying = _currentTitle == title;

    return ListTile(
      leading: Stack(
        alignment: Alignment.center,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: imageUrl.isNotEmpty
                ? Image.network(imageUrl, width: 50, height: 50, fit: BoxFit.cover, errorBuilder: (c, e, s) => const Icon(Icons.music_note, size: 50))
                : const Icon(Icons.music_note, size: 50),
          ),
          if(isCurrentlyPlaying && _isPlaying)
             AnimatedEQ(color: colorNotifier.value), // Feature 8: EQ Visualizer
        ],
      ),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.bold, color: isCurrentlyPlaying ? colorNotifier.value : null)),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(isFav ? Icons.star : Icons.star_border, color: isFav ? Colors.amber : Colors.grey),
            onPressed: () {
              setState(() {
                if (isFav) _djFavorites.removeWhere((item) => _extractData(item)['title'] == title);
                else _djFavorites.add(Map<String, dynamic>.from(list[index]));
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.info_outline, size: 22),
            onPressed: () => _showTrackDetails(data),
          ),
          IconButton(
            icon: Icon(Icons.play_circle_fill, color: mediaUrl.isNotEmpty ? colorNotifier.value : Colors.grey, size: 35),
            onPressed: mediaUrl.isNotEmpty ? () => _playSong(index, list) : null,
          ),
          IconButton(
            icon: const Icon(Icons.download, size: 26),
            color: mediaUrl.isNotEmpty ? null : Colors.grey,
            onPressed: mediaUrl.isNotEmpty ? () => _downloadSong(mediaUrl, title, subtitle) : null,
          ),
        ],
      ),
    );
  }

  Widget _buildBottomPlayer() {
    final remaining = _duration - _position;
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
                Text(_formatDuration(_position), style: const TextStyle(fontSize: 11, color: Colors.grey)),
                Text("-${_formatDuration(remaining > Duration.zero ? remaining : Duration.zero)}", style: const TextStyle(fontSize: 11, color: Colors.grey)),
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

// EQ Animation Helper
class AnimatedEQ extends StatefulWidget {
  final Color color;
  const AnimatedEQ({required this.color, super.key});
  @override
  State<AnimatedEQ> createState() => _AnimatedEQState();
}
class _AnimatedEQState extends State<AnimatedEQ> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 400))..repeat(reverse: true);
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (c, w) {
        return Container(
          color: Colors.black54,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(4, (i) => Container(
              margin: const EdgeInsets.symmetric(horizontal: 1),
              width: 4, height: 10 + Random().nextInt(15).toDouble(), color: widget.color,
            )),
          ),
        );
      }
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
              onTap: () => colorNotifier.value = color,
              child: CircleAvatar(backgroundColor: color, radius: 20, child: colorNotifier.value == color ? const Icon(Icons.check, color: Colors.white) : null),
            )).toList(),
          ),
          const Divider(),
          SwitchListTile(
            title: const Text("Fade-In Playback"),
            subtitle: const Text("Smooth volume ramp on play"),
            activeColor: colorNotifier.value,
            value: fadeInNotifier.value,
            onChanged: (v) async {
              fadeInNotifier.value = v;
              final p = await SharedPreferences.getInstance();
              p.setBool('fade', v);
              setState((){});
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
        ],
      ),
    );
  }
}
