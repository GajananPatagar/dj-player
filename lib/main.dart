import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:dart_des/dart_des.dart';
import 'dart:convert';
import 'package:just_audio/just_audio.dart';
import 'package:background_downloader/background_downloader.dart';

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
          theme: ThemeData(
            brightness: Brightness.light,
            primarySwatch: Colors.blue,
            scaffoldBackgroundColor: Colors.white,
          ),
          darkTheme: ThemeData(
            brightness: Brightness.dark,
            scaffoldBackgroundColor: Colors.black,
            appBarTheme: const AppBarTheme(backgroundColor: Colors.black),
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
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        'Accept': 'application/json'
      });

      if (response.statusCode == 200) {
        final data = json.decode(response.body.trim());
        
        List<dynamic> parsedResults = [];
        if (data is Map) {
          if (data['results'] != null) {
            parsedResults = data['results'];
          } else if (data['songs'] != null && data['songs']['data'] != null) {
            parsedResults = data['songs']['data'];
          }
        }

        setState(() {
          _searchResults = parsedResults;
        });

        if (parsedResults.isEmpty && mounted) {
           ScaffoldMessenger.of(context).showSnackBar(
             const SnackBar(content: Text('No songs found.')),
           );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Network Error: App missing internet. $e')),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  String _decryptMediaUrl(String encryptedUrl) {
    try {
      final key = utf8.encode('38346591');
      final decodedBytes = base64.decode(encryptedUrl);
      
      final des = DES(key: key, mode: DESMode.ECB, paddingType: DESPaddingType.PKCS7);
      final decryptedBytes = des.decrypt(decodedBytes);
      final decryptedUrl = utf8.decode(decryptedBytes);
      
      return decryptedUrl.replaceAll('_96', '_320').replaceAll('.mp4', '.mp3');
    } catch (e) {
      return "";
    }
  }

  Future<void> _playSong(String encryptedUrl) async {
    try {
      final decryptedUrl = _decryptMediaUrl(encryptedUrl);
      if (decryptedUrl.isNotEmpty) {
        await _audioPlayer.setUrl(decryptedUrl);
        _audioPlayer.play();
      }
    } catch (e) {
      debugPrint("Error playing: $e");
    }
  }

  Future<void> _downloadSong(String encryptedUrl, String title) async {
    try {
      final decryptedUrl = _decryptMediaUrl(encryptedUrl);
      if (decryptedUrl.isNotEmpty) {
        final safeTitle = title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '');
        final task = DownloadTask(
          url: decryptedUrl,
          filename: '$safeTitle.mp3',
          directory: 'Music',
          updates: Updates.statusAndProgress,
          allowPause: true,
        );
        await FileDownloader().enqueue(task);
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Downloading: $safeTitle')),
          );
        }
      }
    } catch (e) {
      debugPrint("Error downloading: $e");
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
        title: const Text('DJ High-Res Player'),
        actions: [
          IconButton(
            icon: Icon(themeNotifier.value == ThemeMode.light 
                ? Icons.dark_mode 
                : Icons.light_mode),
            onPressed: () {
              themeNotifier.value = themeNotifier.value == ThemeMode.light 
                  ? ThemeMode.dark 
                  : ThemeMode.light;
            },
          )
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: 'Search Tracks...',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: () => _searchSongs(_searchController.text),
                ),
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (value) => _searchSongs(value),
            ),
          ),
          if (_isLoading) 
            const Padding(
              padding: EdgeInsets.all(20.0),
              child: CircularProgressIndicator(),
            ),
          Expanded(
            child: ListView.builder(
              itemCount: _searchResults.length,
              itemBuilder: (context, index) {
                final song = _searchResults[index];
                
                final title = song['title']?.toString().replaceAll(RegExp(r'<[^>]*>'), '') ?? 'Unknown';
                final subtitle = song['subtitle']?.toString().replaceAll(RegExp(r'<[^>]*>'), '') ?? 'Unknown Artist';
                final mediaUrl = song['media_preview_url'] ?? song['encrypted_media_url'];
                final imageUrl = song['image']?.toString().replaceAll('150x150', '50x50');

                return ListTile(
                  leading: imageUrl != null 
                      ? Image.network(imageUrl, width: 50, height: 50, fit: BoxFit.cover, errorBuilder: (c, e, s) => const Icon(Icons.music_note)) 
                      : const Icon(Icons.music_note),
                  title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.play_arrow),
                        onPressed: mediaUrl != null ? () => _playSong(mediaUrl) : null,
                      ),
                      IconButton(
                        icon: const Icon(Icons.download),
                        onPressed: mediaUrl != null ? () => _downloadSong(mediaUrl, title) : null,
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
