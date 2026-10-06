import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:dart_des/dart_des.dart';
import 'dart:convert';
import 'package:just_audio/just_audio.dart';
import 'package:background_downloader/background_downloader.dart';
import 'package:audiotags/audiotags.dart';
import 'package:shared_preferences/shared_preferences.dart';

final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.dark);

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
      builder: (_, ThemeMode currentMode, __) {
        return MaterialApp(
          title: 'DJ Pro Player',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            brightness: Brightness.light,
            primaryColor: Colors.deepPurple,
            colorScheme: const ColorScheme.light(primary: Colors.deepPurple, secondary: Colors.teal),
            scaffoldBackgroundColor: Colors.grey[100],
          ),
          darkTheme: ThemeData(
            brightness: Brightness.dark,
            primaryColor: Colors.deepPurpleAccent,
            colorScheme: const ColorScheme.dark(primary: Colors.deepPurpleAccent, secondary: Colors.cyanAccent),
            scaffoldBackgroundColor: Colors.black,
            appBarTheme: const AppBarTheme(backgroundColor: Color(0xFF121212)),
          ),
          themeMode: currentMode,
          home: const MainDJDashboard(),
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
  final List<Map<String, dynamic>> _djFavorites = [];
  bool _isLoading = false;

  // Track & Playback State
  String? _currentTitle;
  String? _currentArtist;
  String? _currentImage;
  String? _currentEncryptedUrl;
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  double _playbackSpeed = 1.0;
  String _selectedQuality = '_320';

  // Tap-to-BPM State
  final List<DateTime> _tapTimestamps = [];
  int _calculatedBpm = 0;

  @override
  void initState() {
    super.initState();
    _audioPlayer.playerStateStream.listen((state) {
      if (mounted) setState(() => _isPlaying = state.playing);
    });
    _audioPlayer.durationStream.listen((d) {
      if (mounted) setState(() => _duration = d ?? Duration.zero);
    });
    _audioPlayer.positionStream.listen((p) {
      if (mounted) setState(() => _position = p);
    });
  }

  Future<void> _searchSongs(String query) async {
    if (query.trim().isEmpty) return;
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

  Future<void> _playSong(String encryptedUrl, String title, String artist, String imageUrl) async {
    final directUrl = _decryptMediaUrl(encryptedUrl, _selectedQuality);
    if (directUrl.isNotEmpty) {
      setState(() {
        _currentTitle = title;
        _currentArtist = artist;
        _currentImage = imageUrl;
        _currentEncryptedUrl = encryptedUrl;
      });
      await _audioPlayer.setUrl(directUrl);
      await _audioPlayer.setSpeed(_playbackSpeed);
      _audioPlayer.play();
    }
  }

  Future<void> _downloadSong(String encryptedUrl, String title, String subtitle) async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Downloading High-Res: $title ($_selectedQuality kbps)')),
    );
    
    final decryptedUrl = _decryptMediaUrl(encryptedUrl, _selectedQuality);
    if (decryptedUrl.isEmpty) return;

    final safeTitle = title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '');
    
    final task = DownloadTask(
      url: decryptedUrl,
      filename: '$safeTitle.m4a',
      directory: 'temp_dj',
      baseDirectory: BaseDirectory.applicationDocuments,
      updates: Updates.statusAndProgress,
    );

    final result = await FileDownloader().download(task);
    
    if (result.status == TaskStatus.complete) {
      try {
        final filePath = await task.filePath();
        
        Tag tag = Tag(
          title: title,
          trackArtist: subtitle,
          album: "DJ High-Res Downloads",
          albumArtist: "Downloaded By Gajanan P",
          pictures: const [],
        );
        await AudioTags.write(filePath, tag);

        final prefs = await SharedPreferences.getInstance();
        final saveLocation = prefs.getString('save_location') ?? 'Music';
        final sharedDir = saveLocation == 'Downloads' ? SharedStorage.downloads : SharedStorage.audio;

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
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Tagging error: $e'), backgroundColor: Colors.red),
          );
        }
      }
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
      if (avgMs > 0) {
        setState(() {
          _calculatedBpm = (60000 / avgMs).round();
        });
      }
    }
  }

  void _showTrackDetails(String title, String artist) {
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
              Text("Title: $title", style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text("Artist: $artist"),
              const SizedBox(height: 6),
              Text("Audio Stream: High-Fidelity AAC / ${_selectedQuality.replaceAll('_', '')} kbps"),
              const SizedBox(height: 6),
              const Text("Acoustic Headroom: 24-bit studio equivalent"),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.deepPurple.withAlpha(50),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.deepPurpleAccent),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.copyright, color: Colors.white70),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "Copyright & DJ Credit:\nDownloaded By Gajanan P",
                        style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ),
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
          PopupMenuButton<String>(
            tooltip: "Stream Quality",
            icon: const Icon(Icons.high_quality),
            onSelected: (val) {
              setState(() => _selectedQuality = val);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Quality set to ${val.replaceAll('_', '')} kbps')),
              );
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: '_320', child: Text("320 kbps (High-Res DJ)")),
              const PopupMenuItem(value: '_160', child: Text("160 kbps (Standard)")),
              const PopupMenuItem(value: '_96', child: Text("96 kbps (Data Saver)")),
            ],
          ),
          IconButton(
            icon: Icon(themeNotifier.value == ThemeMode.light ? Icons.dark_mode : Icons.light_mode),
            onPressed: () {
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
                _buildBpmToolTab(),
              ],
            ),
          ),
          if (_currentTitle != null) _buildBottomPlayer(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentTab,
        selectedItemColor: Colors.deepPurpleAccent,
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
              hintText: 'Search Indian DJ Edits, Bollytech, Kannada...',
              filled: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
              prefixIcon: const Icon(Icons.search),
            ),
            onSubmitted: _searchSongs,
          ),
        ),
        if (_isLoading) const Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()),
        Expanded(
          child: ListView.builder(
            itemCount: _searchResults.length,
            itemBuilder: (context, index) {
              final song = _searchResults[index];
              return _buildSongTile(song);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCrateTab() {
    return _djFavorites.isEmpty
        ? const Center(child: Text("Your DJ Crate is empty. Star tracks to add them!"))
        : ListView.builder(
            itemCount: _djFavorites.length,
            itemBuilder: (context, index) {
              final song = _djFavorites[index];
              return _buildSongTile(song);
            },
          );
  }

  Widget _buildBpmToolTab() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            _calculatedBpm > 0 ? "$_calculatedBpm" : "--",
            style: const TextStyle(fontSize: 72, fontWeight: FontWeight.bold, color: Colors.cyanAccent),
          ),
          const Text("BPM (Beats Per Minute)", style: TextStyle(fontSize: 18, color: Colors.grey)),
          const SizedBox(height: 36),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              shape: const CircleBorder(),
              padding: const EdgeInsets.all(48),
              backgroundColor: Colors.deepPurpleAccent,
            ),
            onPressed: _tapBpm,
            child: const Text("TAP", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
          ),
          const SizedBox(height: 20),
          TextButton(
            onPressed: () => setState(() {
              _tapTimestamps.clear();
              _calculatedBpm = 0;
            }),
            child: const Text("Reset BPM"),
          ),
        ],
      ),
    );
  }

  Widget _buildSongTile(dynamic song) {
    final title = song['title']?.toString().replaceAll(RegExp(r'<[^>]*>'), '') ?? 'Unknown';
    final subtitle = song['subtitle']?.toString().replaceAll(RegExp(r'<[^>]*>'), '') ?? 'Unknown Artist';
    final mediaUrl = song['media_preview_url'] ?? song['encrypted_media_url'];
    final imageUrl = song['image']?.toString().replaceAll('150x150', '50x50') ?? '';
    final isFav = _djFavorites.any((item) => item['title'] == title);

    return ListTile(
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: imageUrl.isNotEmpty
            ? Image.network(imageUrl, width: 50, height: 50, fit: BoxFit.cover, errorBuilder: (c, e, s) => const Icon(Icons.music_note, size: 50))
            : const Icon(Icons.music_note, size: 50),
      ),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(isFav ? Icons.star : Icons.star_border, color: isFav ? Colors.amber : Colors.grey),
            onPressed: () {
              setState(() {
                if (isFav) {
                  _djFavorites.removeWhere((item) => item['title'] == title);
                } else {
                  _djFavorites.add(Map<String, dynamic>.from(song));
                }
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.info_outline, size: 22),
            onPressed: () => _showTrackDetails(title, subtitle),
          ),
          IconButton(
            icon: const Icon(Icons.play_circle_fill, color: Colors.deepPurpleAccent, size: 35),
            onPressed: mediaUrl != null ? () => _playSong(mediaUrl, title, subtitle, imageUrl) : null,
          ),
          IconButton(
            icon: const Icon(Icons.download, size: 26),
            onPressed: mediaUrl != null ? () => _downloadSong(mediaUrl, title, subtitle) : null,
          ),
        ],
      ),
    );
  }

  Widget _buildBottomPlayer() {
    final remaining = _duration - _position;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF1A1A1A) : Colors.deepPurple[50],
        boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 10, offset: Offset(0, -3))],
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
                  final newPos = _position - const Duration(seconds: 10);
                  _audioPlayer.seek(newPos < Duration.zero ? Duration.zero : newPos);
                },
              ),
              IconButton(
                icon: Icon(_isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled, color: Colors.deepPurpleAccent, size: 42),
                onPressed: () => _isPlaying ? _audioPlayer.pause() : _audioPlayer.play(),
              ),
              IconButton(
                icon: const Icon(Icons.forward_10),
                onPressed: () {
                  final newPos = _position + const Duration(seconds: 10);
                  if (newPos < _duration) _audioPlayer.seek(newPos);
                },
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6)),
            child: Slider(
              value: _position.inSeconds.toDouble().clamp(0.0, _duration.inSeconds.toDouble()),
              max: _duration.inSeconds.toDouble() > 0 ? _duration.inSeconds.toDouble() : 1.0,
              activeColor: Colors.cyanAccent,
              inactiveColor: Colors.grey[700],
              onChanged: (val) => _audioPlayer.seek(Duration(seconds: val.toInt())),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_formatDuration(_position), style: const TextStyle(fontSize: 11, color: Colors.grey)),
                Row(
                  children: [
                    const Text("DJ Pitch: ", style: TextStyle(fontSize: 11, color: Colors.grey)),
                    Text("${_playbackSpeed.toStringAsFixed(2)}x", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.cyanAccent)),
                    const SizedBox(width: 6),
                    InkWell(
                      onTap: () {
                        setState(() => _playbackSpeed = 1.0);
                        _audioPlayer.setSpeed(1.0);
                      },
                      child: const Text("(Reset)", style: TextStyle(fontSize: 10, color: Colors.deepPurpleAccent)),
                    ),
                  ],
                ),
                Text("-${_formatDuration(remaining > Duration.zero ? remaining : Duration.zero)}", style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),
          ),
          Slider(
            min: 0.5,
            max: 1.5,
            divisions: 20,
            value: _playbackSpeed,
            activeColor: Colors.deepPurpleAccent,
            onChanged: (speed) {
              setState(() => _playbackSpeed = speed);
              _audioPlayer.setSpeed(speed);
            },
          ),
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
            subtitle: Text("Downloaded By Gajanan P"),
          ),
        ],
      ),
    );
  }
}
