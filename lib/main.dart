import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:dio/dio.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:math';
import 'dart:io';
import 'package:permission_handler/permission_handler.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:dart_des/dart_des.dart';
import 'package:ffmpeg_kit_flutter_audio/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_audio/return_code.dart';
import 'package:path_provider/path_provider.dart';

final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.dark);
final ValueNotifier<MaterialColor> colorNotifier = ValueNotifier(Colors.deepPurple);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.djplayer.app.audio',
    androidNotificationChannelName: 'DJ Playback',
    androidNotificationOngoing: true,
  );
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
  final Dio _dio = Dio();
  
  List<Map<String, dynamic>> _searchResults = [];
  List<Map<String, dynamic>> _trendingResults = [];
  List<Map<String, dynamic>> _offlineSongs = [];
  
  String _selectedLanguage = 'Kannada';
  final List<String> _languages = ['Kannada', 'Hindi', 'Telugu', 'Tamil', 'Punjabi', 'Malayalam', 'Marathi', 'Bhojpuri'];
  
  bool _isLoading = false;
  bool _isTrendingLoading = false;
  
  Map<String, double> _downloadProgress = {};
  Set<String> _downloadedFileIds = {};

  List<Map<String, dynamic>> _currentPlaylist = [];
  int _currentIndex = -1;
  String? _currentTitle;
  String? _currentArtist;
  String? _currentImage;
  String _currentLyrics = "Searching LRC Database...";
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  
  double _playbackSpeed = 1.0;
  Timer? _speedDebounce; 
  double _volume = 1.0;
  LoopMode _loopMode = LoopMode.off;
  Timer? _sleepTimer;

  final List<DateTime> _tapTimestamps = [];
  int _calculatedBpm = 0;

  @override
  void initState() {
    super.initState();
    _requestPermissions();
    _loadPrefs();
    _scanOfflineLibrary();
    _fetchFederatedTrending(_selectedLanguage);
    
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

  Future<void> _requestPermissions() async {
    await [Permission.storage, Permission.audio, Permission.manageExternalStorage].request();
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

  Future<void> _scanOfflineLibrary() async {
    try {
      final List<Directory> searchDirectories = [
        Directory('/storage/emulated/0/Download/DJ_Downloads'),
        Directory('/storage/emulated/0/Music/DJ_Downloads'),
      ];
      
      Set<String> foundIds = {};
      List<Map<String, dynamic>> loadedOffline = [];
      
      for (var dir in searchDirectories) {
        if (await dir.exists()) {
          final files = dir.listSync();
          for (var file in files) {
            if (file is File && (file.path.endsWith('.m4a') || file.path.endsWith('.mp3'))) {
              String filename = file.path.split('/').last.replaceAll('.m4a', '').replaceAll('.mp3', '');
              String trackName = filename.replaceAll('Gajanan Patkar - ', '');
              
              if (!foundIds.contains(trackName)) {
                foundIds.add(trackName);
                loadedOffline.add({
                  'title': trackName,
                  'artist': 'Offline Crate',
                  'id': trackName,
                  'image': '',
                  'localPath': file.path,
                  'source': 'Offline'
                });
              }
            }
          }
        }
      }
      
      setState(() {
        _downloadedFileIds = foundIds;
        _offlineSongs = loadedOffline;
      });
    } catch (e) {
      debugPrint("Scan error: $e");
    }
  }

  // --- LAYER 1: FEDERATED METADATA ---
  Future<void> _searchFederated(String query) async {
    if (query.trim().isEmpty) return;
    HapticFeedback.lightImpact();
    FocusScope.of(context).unfocus();

    setState(() {
      _isLoading = true;
      _searchResults = [];
    });

    List<Map<String, dynamic>> results = [];

    // Prioritize structured JSON via JioSaavn API to guarantee pristine ID3 tags
    try {
      final res = await http.get(Uri.parse('https://www.jiosaavn.com/api.php?__call=search.getResults&_format=json&_marker=0&ctx=web6dot0&api_version=4&q=${Uri.encodeComponent(query)}'));
      if (res.statusCode == 200) {
        final data = json.decode(res.body.trim());
        final List list = data['results'] ?? data['songs']?['data'] ?? [];
        results.addAll(list.map((s) {
          final moreInfo = s['more_info'] ?? {};
          return {
            'title': s['title'].toString().replaceAll(RegExp(r'<[^>]*>'), ''),
            'artist': s['subtitle'].toString().replaceAll(RegExp(r'<[^>]*>'), ''),
            'image': s['image'].toString().replaceAll('150x150', '500x500'),
            'id': s['encrypted_media_url'] ?? moreInfo['encrypted_media_url'] ?? '',
            'source': 'JioSaavn'
          };
        }).toList());
      }
    } catch (_) {}

    // Fallback to Global Graph
    if (results.isEmpty) {
      try {
        final ytRes = await _yt.search.search(query);
        results.addAll(ytRes.take(20).map((v) => {
          'title': v.title,
          'artist': v.author,
          'image': v.thumbnails.highResUrl,
          'id': v.id.value,
          'source': 'YouTube'
        }).toList());
      } catch (_) {}
    }

    setState(() {
      _searchResults = results;
      _isLoading = false;
    });
    _scanOfflineLibrary();
  }

  Future<void> _fetchFederatedTrending(String language) async {
    setState(() {
      _isTrendingLoading = true;
      _trendingResults = [];
    });
    
    try {
      final ytRes = await _yt.search.search("Top 50 $language Hit Songs");
      final List<Map<String, dynamic>> results = ytRes.take(25).map((v) => {
        'title': v.title,
        'artist': v.author,
        'image': v.thumbnails.highResUrl,
        'id': v.id.value,
        'source': 'YouTube'
      }).toList();
      
      setState(() {
        _trendingResults = results;
        _isTrendingLoading = false;
      });
      _scanOfflineLibrary();
    } catch (_) {
      setState(() => _isTrendingLoading = false);
    }
  }

  Future<void> _fetchLRCLyrics(String title, String artist) async {
    setState(() => _currentLyrics = "Searching LRCLib Database...");
    try {
      final res = await http.get(Uri.parse('https://lrclib.net/api/get?track_name=${Uri.encodeComponent(title)}&artist_name=${Uri.encodeComponent(artist)}'));
      if (res.statusCode == 200) {
         setState(() => _currentLyrics = json.decode(res.body)['syncedLyrics'] ?? json.decode(res.body)['plainLyrics'] ?? "No Sync Lyrics Available.");
      } else {
         setState(() => _currentLyrics = "Instrumental / No Lyrics Found.");
      }
    } catch(_) { setState(() => _currentLyrics = "Lyrics API Offline"); }
  }

  // --- LAYER 2: CLIENT-SIDE EXTRACTION & DECENTRALIZED FALLBACK ---
  Future<String> _extractStreamUrl(Map<String, dynamic> track) async {
    if (track['source'] == 'Offline') return track['localPath'];
    
    if (track['source'] == 'JioSaavn' && track['id'].isNotEmpty) {
      try {
        final key = utf8.encode('38346591');
        final decodedBytes = base64.decode(track['id']);
        final des = DES(key: key, mode: DESMode.ECB, paddingType: DESPaddingType.PKCS7);
        return utf8.decode(des.decrypt(decodedBytes)).replaceAll('_96', '_320'); 
      } catch (_) {}
    } 
    else if (track['source'] == 'YouTube') {
      try {
        // Primary Client-Side Extraction
        var manifest = await _yt.videos.streamsClient.getManifest(track['id']);
        return manifest.audioOnly.withHighestBitrate().url.toString();
      } catch (e) {
        // Decentralized Fallback Mechanism (Piped API)
        try {
          final res = await http.get(Uri.parse('https://pipedapi.kavin.rocks/streams/${track['id']}'));
          final data = json.decode(res.body);
          final audioStreams = data['audioStreams'] as List;
          if (audioStreams.isNotEmpty) return audioStreams.first['url'];
        } catch (_) { return ""; }
      }
    } 
    return "";
  }

  // --- LAYER 3: UNIFIED PLAYBACK & CACHING ENGINE ---
  Future<void> _playSong(int index, List<Map<String, dynamic>> list) async {
    if(index < 0 || index >= list.length) return;
    HapticFeedback.lightImpact();
    final track = list[index];
    
    String safeName = track['title'].toString().replaceAll(RegExp(r'[\\/:*?"<>|]'), '');
    if (_downloadedFileIds.contains(safeName)) {
      final dir = Directory('/storage/emulated/0/Download/DJ_Downloads');
      final localFile = File('${dir.path}/Gajanan Patkar - $safeName.m4a');
      if (await localFile.exists()) {
        track['source'] = 'Offline';
        track['localPath'] = localFile.path;
      }
    }

    if (track['source'] != 'Offline') {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Client Extraction: ${track['title']}'), duration: const Duration(seconds: 1)));
    }
    
    final streamUrl = await _extractStreamUrl(track);
    
    if (streamUrl.isNotEmpty) {
      setState(() {
        _currentPlaylist = list;
        _currentIndex = index;
        _currentTitle = track['title'];
        _currentArtist = track['artist'];
        _currentImage = track['image'];
      });
      
      _fetchLRCLyrics(track['title'], track['artist']);
      
      try {
        if (track['source'] == 'Offline') {
          await _audioPlayer.setAudioSource(AudioSource.file(
            streamUrl,
            tag: MediaItem(id: track['id'], title: track['title'], artist: track['artist'])
          ));
        } else {
          // Utilizing LockCachingAudioSource to create a SimpleCache equivalent
          await _audioPlayer.setAudioSource(LockCachingAudioSource(
            Uri.parse(streamUrl),
            tag: MediaItem(id: track['id'], title: track['title'], artist: track['artist'], artUri: track['image'].isNotEmpty ? Uri.parse(track['image']) : null)
          ));
        }
        await _audioPlayer.setSpeed(_playbackSpeed);
        await _audioPlayer.setVolume(_volume);
        _audioPlayer.play();
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Stream blocked. Decentralized fallback failed.")));
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Stream completely offline across all nodes.")));
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

  // --- LAYER 4: FFMPEG POST-PROCESSING PIPELINE ---
  Future<void> _downloadAndProcess(Map<String, dynamic> track) async {
    HapticFeedback.vibrate();
    final taskId = track['id'];
    
    if (_downloadProgress.containsKey(taskId)) return;

    final streamUrl = await _extractStreamUrl(track);
    if (streamUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cannot resolve media stream for download.')));
      return;
    }

    setState(() => _downloadProgress[taskId] = 0.1);

    try {
      final safeTitle = track['title']!.toString().replaceAll(RegExp(r'[\\/:*?"<>|]'), '');
      final safeArtist = track['artist']!.toString().replaceAll(RegExp(r'[\\/:*?"<>|]'), '');
      
      final Directory pubDir = Directory('/storage/emulated/0/Download/DJ_Downloads');
      if (!await pubDir.exists()) await pubDir.create(recursive: true);
      
      final Directory tempDir = await getTemporaryDirectory();
      final String rawAudioPath = '${tempDir.path}/${taskId}_raw.mp4';
      final String coverPath = '${tempDir.path}/${taskId}_cover.jpg';
      final String finalOutPath = '${pubDir.path}/Gajanan Patkar - $safeTitle.m4a';

      // 1. Download Cover Art
      if (track['image'].isNotEmpty) {
        final imgRes = await http.get(Uri.parse(track['image']));
        await File(coverPath).writeAsBytes(imgRes.bodyBytes);
      }

      setState(() => _downloadProgress[taskId] = 0.4);

      // 2. Download Raw Audio Stream
      await _dio.download(streamUrl, rawAudioPath);
      
      setState(() => _downloadProgress[taskId] = 0.7);

      // 3. FFmpeg Muxing & ID3 Injection
      String command = "-y -i '$rawAudioPath' ";
      if (await File(coverPath).exists()) command += "-i '$coverPath' -map 0:a -map 1:v -disposition:v attached_pic ";
      else command += "-map 0:a ";
      
      command += "-c copy -id3v2_version 3 -metadata title='$safeTitle' -metadata artist='$safeArtist' -metadata album='DJ Pro Workstation Crate' '$finalOutPath'";
      
      var session = await FFmpegKit.execute(command);
      var returnCode = await session.getReturnCode();
      
      if (ReturnCode.isSuccess(returnCode)) {
         _scanOfflineLibrary();
         if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('FFmpeg Exported: Gajanan Patkar - $safeTitle'), backgroundColor: Colors.green));
      } else {
         if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('FFmpeg Muxing Failed'), backgroundColor: Colors.red));
      }

      // Cleanup
      if (await File(rawAudioPath).exists()) await File(rawAudioPath).delete();
      if (await File(coverPath).exists()) await File(coverPath).delete();
      
      setState(() => _downloadProgress.remove(taskId));
      
    } catch (e) {
      if (mounted) {
        setState(() => _downloadProgress.remove(taskId));
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Processing Pipeline Error'), backgroundColor: Colors.red));
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
      if (avgMs > 0) setState(() => _calculatedBpm = (60000 / avgMs).round());
    }
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  void _showLyricsModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.black.withOpacity(0.9),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Container(
        height: MediaQuery.of(context).size.height * 0.75,
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.lyrics, color: Colors.cyanAccent),
                const SizedBox(width: 8),
                Text("LRCLib Sync", style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, color: Colors.white)),
              ],
            ),
            const Divider(color: Colors.white24, height: 30),
            Expanded(child: SingleChildScrollView(child: Text(_currentLyrics, style: const TextStyle(fontSize: 16, height: 1.8, color: Colors.white)))),
          ],
        ),
      ),
    );
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
        title: const Text('DJ Architect Engine', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: Icon(themeNotifier.value == ThemeMode.light ? Icons.dark_mode : Icons.light_mode),
            onPressed: () {
              HapticFeedback.selectionClick();
              themeNotifier.value = themeNotifier.value == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
            },
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
        type: BottomNavigationBarType.fixed,
        onTap: (index) {
          HapticFeedback.selectionClick();
          setState(() => _currentTab = index);
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.local_fire_department), label: "Trending"),
          BottomNavigationBarItem(icon: Icon(Icons.search), label: "Federated"),
          BottomNavigationBarItem(icon: Icon(Icons.folder_special), label: "Offline"),
          BottomNavigationBarItem(icon: Icon(Icons.tune), label: "Studio"),
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
          child: Text("Daily Indian Top 50", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
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
                    _fetchFederatedTrending(lang);
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
              hintText: 'Search Federated Metadata APIs...',
              filled: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(icon: const Icon(Icons.clear), onPressed: () => _searchController.clear())
            ),
            onSubmitted: _searchFederated,
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
              const Text("Media3 Cache Lib", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              TextButton.icon(
                icon: const Icon(Icons.refresh, color: Colors.cyanAccent),
                label: const Text("Scan Files", style: TextStyle(color: Colors.cyanAccent)),
                onPressed: () {
                  HapticFeedback.vibrate();
                  _scanOfflineLibrary();
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: _offlineSongs.isEmpty
              ? const Center(child: Text("No offline tracks found. Run FFmpeg Engine!"))
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
        const Text("Active Decoupled Architectural Layers:", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        _buildFeatureItem(Icons.cloud_sync, "Layer 1: Federated Metadata Graph API"),
        _buildFeatureItem(Icons.security, "Layer 2: Decentralized Piped Fallbacks"),
        _buildFeatureItem(Icons.memory, "Layer 3: LockCachingAudioSource (Media3)"),
        _buildFeatureItem(Icons.build_circle, "Layer 4: FFmpegKit Native ID3 Muxing"),
        _buildFeatureItem(Icons.lyrics, "Layer 5: LRCLib Synchronized Data Extraction"),
      ],
    );
  }

  Widget _buildFeatureItem(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(children: [Icon(icon, size: 20, color: Colors.cyanAccent), const SizedBox(width: 12), Expanded(child: Text(text, style: const TextStyle(fontSize: 13)))]),
    );
  }

  Widget _buildSongTile(int index, List<Map<String,dynamic>> list, {required bool isOfflineMode}) {
    final track = list[index];
    final isPlaying = _currentTitle == track['title'];
    
    final taskId = track['id'];
    final isDownloading = _downloadProgress.containsKey(taskId);
    
    String safeName = track['title']!.toString().replaceAll(RegExp(r'[\\/:*?"<>|]'), '');
    bool isDownloaded = _downloadedFileIds.contains(safeName) || isOfflineMode;

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
      subtitle: Text(track['artist']!, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: isDownloaded
        ? const Icon(Icons.check_circle, color: Colors.green)
        : IconButton(
            icon: Icon(isDownloading ? Icons.settings_applications : Icons.download, size: 26, color: isDownloading ? Colors.cyanAccent : null), 
            onPressed: isDownloading ? null : () => _downloadAndProcess(track),
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
              IconButton(icon: const Icon(Icons.lyrics, color: Colors.cyanAccent), onPressed: _showLyricsModal),
              IconButton(
                icon: Icon(_isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled, color: colorNotifier.value, size: 42),
                onPressed: () { HapticFeedback.lightImpact(); _isPlaying ? _audioPlayer.pause() : _audioPlayer.play(); },
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
            ],
          )
        ],
      ),
    );
  }
}
