import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:encrypt/encrypt.dart' as encrypt_lib;
import 'dart:convert';
import 'package:just_audio/just_audio.dart';
import 'package:background_downloader/background_downloader.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DJPlayerApp());
}

class DJPlayerApp extends MaterialApp {
  const DJPlayerApp({super.key}) : super(
    title: 'DJ Pro Player',
    themeMode: ThemeMode.dark,
    home: const SearchScreen(),
  );
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

  Future<void> _searchSongs(String query) async {
    final url = Uri.parse(
        'https://www.jiosaavn.com/api.php?__call=search.getResults&_format=json&_marker=0&ctx=web6dot0&api_version=4&q=$query');
    final response = await http.get(url);
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      setState(() {
        _searchResults = data['results'] ?? [];
      });
    }
  }

  String _decryptMediaUrl(String encryptedUrl) {
    final key = encrypt_lib.Key.fromUtf8('38346591');
    final encrypter = encrypt_lib.Encrypter(encrypt_lib.DES(key, mode: encrypt_lib.DESMode.ecb));
    final decodedBytes = base64.decode(encryptedUrl);
    final decrypted = encrypter.decrypt(encrypt_lib.Encrypted(decodedBytes), iv: encrypt_lib.IV.fromLength(0));
    return decrypted.replaceAll('_96', '_320').replaceAll('.mp4', '.mp3'); 
  }

  Future<void> _playSong(String encryptedUrl) async {
    final decryptedUrl = _decryptMediaUrl(encryptedUrl);
    await _audioPlayer.setUrl(decryptedUrl);
    _audioPlayer.play();
  }

  Future<void> _downloadSong(String encryptedUrl, String title) async {
    final decryptedUrl = _decryptMediaUrl(encryptedUrl);
    final task = DownloadTask(
      url: decryptedUrl,
      filename: '$title.mp3',
      directory: 'Music',
      updates: Updates.statusAndProgress,
      allowPause: true,
    );
    await FileDownloader().enqueue(task);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('DJ High-Res Sourcing')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: 'Search Global or Indian DJ Tracks',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: () => _searchSongs(_searchController.text),
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _searchResults.length,
              itemBuilder: (context, index) {
                final song = _searchResults[index];
                final mediaUrl = song['media_preview_url'] ?? song['encrypted_media_url'];
                return ListTile(
                  title: Text(song['title'] ?? 'Unknown'),
                  subtitle: Text(song['subtitle'] ?? 'Unknown Artist'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.play_arrow),
                        onPressed: () => _playSong(mediaUrl),
                      ),
                      IconButton(
                        icon: const Icon(Icons.download),
                        onPressed: () => _downloadSong(mediaUrl, song['title']),
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
