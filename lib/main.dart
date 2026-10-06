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
            scaffoldBackgroundColor: Colors.grey[100],
          ),
          darkTheme: ThemeData(
            brightness: Brightness.dark,
            primaryColor: Colors.deepPurpleAccent,
            scaffoldBackgroundColor: Colors.black,
            appBarTheme: const AppBarTheme(backgroundColor: Colors.black87),
          ),
          themeMode: currentMode,
          home: const SearchScreen(),
        );
      },
    );
  }
}

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final AudioPlayer _audioPlayer = AudioPlayer();
  List<dynamic> _searchResults = [];
  bool _isLoading = false;
  
  String? _currentTitle;
  String? _currentImage;
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

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
      debugPrint("Search failed: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  String _decryptMediaUrl(String encryptedUrl) {
    try {
      final key = utf8.encode('38346591');
      final decodedBytes = base64.decode(encryptedUrl);
      final des = DES(key: key, mode: DESMode.ECB, paddingType: DESPaddingType.PKCS7);
      final decryptedUrl = utf8.decode(des.decrypt(decodedBytes));
      return decryptedUrl.replaceAll('_96', '_320');
    } catch (e) {
      return "";
    }
  }

  Future<void> _playSong(String encryptedUrl, String title, String imageUrl) async {
    final decryptedUrl = _decryptMediaUrl(encryptedUrl);
    if (decryptedUrl.isNotEmpty) {
      setState(() {
        _currentTitle = title;
        _currentImage = imageUrl;
      });
      await _audioPlayer.setUrl(decryptedUrl);
      _audioPlayer.play();
    }
  }

  Future<void> _downloadSong(String encryptedUrl, String title, String subtitle) async {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Starting Download: $title')));
    
    final decryptedUrl = _decryptMediaUrl(encryptedUrl);
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
        
        // Correct, stable audiotags syntax for 1.4.5
        Tag tag = Tag(
          title: title,
          trackArtist: subtitle,
          album: "DJ High-Res Downloads",
          albumArtist: "Downloaded By Gajanan P",
          pictures: [], // Empty list required by the compiler
        );
        await AudioTags.write(filePath, tag);

        final prefs = await SharedPreferences.getInstance();
        final saveLocation = prefs.getString('save_location') ?? 'Music';
        final sharedDir = saveLocation == 'Downloads' ? SharedStorage.downloads : SharedStorage.audio;

        await FileDownloader().moveToSharedStorage(task, sharedDir, directory: 'DJ_Downloads');
        
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved to $saveLocation: $safeTitle'), backgroundColor: Colors.green));
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Download processing error: $e'), backgroundColor: Colors.red));
      }
    }
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
        title: const Text('DJ Pro Player'),
        actions: [
          IconButton(
            icon: Icon(themeNotifier.value == ThemeMode.light ? Icons.dark_mode : Icons.light_mode),
            onPressed: () => themeNotifier.value = themeNotifier.value == ThemeMode.light ? ThemeMode.dark : ThemeMode.light,
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
          )
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search High-Res Tracks...',
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
                final title = song['title']?.toString().replaceAll(RegExp(r'<[^>]*>'), '') ?? 'Unknown';
                final subtitle = song['subtitle']?.toString().replaceAll(RegExp(r'<[^>]*>'), '') ?? 'Unknown Artist';
                final mediaUrl = song['media_preview_url'] ?? song['encrypted_media_url'];
                final imageUrl = song['image']?.toString().replaceAll('150x150', '50x50') ?? '';

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
                      IconButton(icon: const Icon(Icons.play_circle_fill, color: Colors.deepPurpleAccent, size: 35), onPressed: mediaUrl != null ? () => _playSong(mediaUrl, title, imageUrl) : null),
                      IconButton(icon: const Icon(Icons.download, size: 28), onPressed: mediaUrl != null ? () => _downloadSong(mediaUrl, title, subtitle) : null),
                    ],
                  ),
                );
              },
            ),
          ),
          if (_currentTitle != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColorDark,
                boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, -5))],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      if (_currentImage != null) ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.network(_currentImage!, width: 40, height: 40, errorBuilder: (c, e, s) => const Icon(Icons.music_note))),
                      const SizedBox(width: 12),
                      Expanded(child: Text(_currentTitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white))),
                      IconButton(
                        icon: Icon(_isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled, color: Colors.white, size: 40),
                        onPressed: () => _isPlaying ? _audioPlayer.pause() : _audioPlayer.play(),
                      ),
                    ],
                  ),
                  Slider(
                    value: _position.inSeconds.toDouble().clamp(0.0, _duration.inSeconds.toDouble()),
                    max: _duration.inSeconds.toDouble() > 0 ? _duration.inSeconds.toDouble() : 1.0,
                    activeColor: Colors.white,
                    inactiveColor: Colors.white30,
                    onChanged: (val) => _audioPlayer.seek(Duration(seconds: val.toInt())),
                  )
                ],
              ),
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
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const Padding(padding: EdgeInsets.all(16.0), child: Text("Download Location", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
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
        ],
      ),
    );
  }
}
