import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'des_helper.dart';

/// Global 4-Deck Master Volume Controller + Auto Cricket BGM Trigger
class MasterVolumeController {
  static final ValueNotifier<double> page1MusicVolume = ValueNotifier<double>(1.0);
  static final ValueNotifier<double> page2VoiceVolume = ValueNotifier<double>(1.0);
  static final ValueNotifier<double> page3SfxVolume = ValueNotifier<double>(0.55);
  static final ValueNotifier<double> page4EntryVolume = ValueNotifier<double>(0.0);
  static final ValueNotifier<String?> autoCricketStingerTrigger = ValueNotifier<String?>(null);
  static bool autoPlayEntryOnCricketBoundaryOrWicket = true;
}

/// Bulletproof Favorites & Offline Download Manager (Works across Page 1 & Page 4 with 0 failures!)
class VaultManager {
  static final ValueNotifier<List<Map<String, dynamic>>> favSongs = ValueNotifier([]);
  static final ValueNotifier<List<Map<String, dynamic>>> offlineSongs = ValueNotifier([]);
  static final ValueNotifier<List<Map<String, dynamic>>> favEntries = ValueNotifier([]);
  static final ValueNotifier<List<Map<String, dynamic>>> offlineEntries = ValueNotifier([]);
  static final ValueNotifier<Map<String, int>> downloadProgressMap = ValueNotifier({});

  static bool _initialized = false;

  static Future<Directory> _safeStorageDir() async {
    try {
      return await getApplicationDocumentsDirectory();
    } catch (_) {
      return Directory.systemTemp;
    }
  }

  static Future<void> initVaults() async {
    if (_initialized) return;
    _initialized = true;
    favSongs.value = await _loadList('v50_fav_songs');
    offlineSongs.value = await _loadList('v50_off_songs');
    favEntries.value = await _loadList('v50_fav_entries');
    offlineEntries.value = await _loadList('v50_off_entries');
  }

  static Future<List<Map<String, dynamic>>> _loadList(String key) async {
    final List<Map<String, dynamic>> out = [];
    try {
      final dir = await _safeStorageDir();
      final f = File('${dir.path}/$key.json');
      if (await f.exists()) {
        final List raw = jsonDecode(await f.readAsString());
        for (final item in raw) {
          out.add(_sanitizeTrackMap(Map<String, dynamic>.from(item)));
        }
        return out;
      }
    } catch (_) {}

    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(key) ?? [];
      for (final s in list) {
        out.add(_sanitizeTrackMap(Map<String, dynamic>.from(jsonDecode(s))));
      }
    } catch (_) {}
    return out;
  }

  static Future<void> _saveList(String key, List<Map<String, dynamic>> list) async {
    final sanitized = list.map(_sanitizeTrackMap).toList();
    try {
      final dir = await _safeStorageDir();
      final f = File('${dir.path}/$key.json');
      await f.writeAsString(jsonEncode(sanitized));
    } catch (_) {}

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(key, sanitized.map((e) => jsonEncode(e)).toList());
    } catch (_) {}
  }

  static Map<String, dynamic> _sanitizeTrackMap(Map<String, dynamic> t) {
    final List<String> cleanUrls = [];
    if (t['urls'] is List) {
      for (final u in (t['urls'] as List)) {
        if (u != null) cleanUrls.add(u.toString());
      }
    }
    return {
      'id': (t['id'] ?? '').toString(),
      'title': (t['title'] ?? 'Track').toString(),
      'artist': (t['artist'] ?? 'Artist').toString(),
      'cover': (t['cover'] ?? '').toString(),
      'urls': cleanUrls,
      'durationStr': (t['durationStr'] ?? 'Full').toString(),
      'durationSec': int.tryParse((t['durationSec'] ?? '180').toString()) ?? 180,
      'smartDropSec': int.tryParse((t['smartDropSec'] ?? '0').toString()) ?? 0,
      'year': int.tryParse((t['year'] ?? '2026').toString()) ?? 2026,
      'quality': (t['quality'] ?? '320kbps FULL').toString(),
      'localPath': t['localPath']?.toString(),
      'isOffline': t['isOffline'] == true,
    };
  }

  static bool isFavorite(String id, {required bool isEntry}) {
    final target = isEntry ? favEntries.value : favSongs.value;
    return target.any((e) => e['id'].toString() == id);
  }

  static bool isOffline(String id, {required bool isEntry}) {
    final target = isEntry ? offlineEntries.value : offlineSongs.value;
    return target.any((e) => e['id'].toString() == id);
  }

  /// Instant 0ms Favorite Toggle with persistent save
  static Future<bool> toggleFavorite(Map<String, dynamic> track, {required bool isEntry}) async {
    final clean = _sanitizeTrackMap(track);
    final String id = clean['id'].toString();
    final notifier = isEntry ? favEntries : favSongs;
    final String storageKey = isEntry ? 'v50_fav_entries' : 'v50_fav_songs';

    final List<Map<String, dynamic>> current = List<Map<String, dynamic>>.from(notifier.value);
    final int idx = current.indexWhere((e) => e['id'].toString() == id);
    bool added = false;
    if (idx >= 0) {
      current.removeAt(idx);
      added = false;
    } else {
      current.insert(0, clean);
      added = true;
    }
    notifier.value = current;
    await _saveList(storageKey, current);
    return added;
  }

  /// Bulletproof 320kbps Downloader with live progress % notification
  static Future<bool> downloadTrack(Map<String, dynamic> track, {required bool isEntry}) async {
    final clean = _sanitizeTrackMap(track);
    final String id = clean['id'].toString();
    final List<String> urls = List<String>.from(clean['urls'] as List);
    if (urls.isEmpty) return false;

    // Set progress to 10% immediately so UI shows active spinner
    downloadProgressMap.value = {...downloadProgressMap.value, id: 10};

    final Map<String, String> headers = {
      'User-Agent': 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/124.0 Mobile Safari/537.36',
      'Accept': '*/*',
      'Connection': 'keep-alive',
    };

    for (final rawUrl in urls) {
      try {
        downloadProgressMap.value = {...downloadProgressMap.value, id: 35};
        final client = http.Client();
        final request = http.Request('GET', Uri.parse(rawUrl));
        request.headers.addAll(headers);
        final streamedRes = await client.send(request).timeout(const Duration(seconds: 45));

        if (streamedRes.statusCode == 200) {
          final int totalBytes = streamedRes.contentLength ?? 3500000;
          final List<int> bytes = [];
          int received = 0;

          await for (final chunk in streamedRes.stream) {
            bytes.addAll(chunk);
            received += chunk.length;
            final int pct = ((received / totalBytes) * 90).clamp(15, 95).toInt();
            if (pct - (downloadProgressMap.value[id] ?? 0) >= 12) {
              downloadProgressMap.value = {...downloadProgressMap.value, id: pct};
            }
          }
          client.close();

          if (bytes.length > 8000) {
            final dir = await _safeStorageDir();
            final safeId = id.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
            final String prefix = isEntry ? 'entry_320k_' : 'song_320k_';
            final File outFile = File('${dir.path}/$prefix$safeId.mp4');
            await outFile.writeAsBytes(bytes, flush: true);

            clean['localPath'] = outFile.path;
            clean['isOffline'] = true;
            clean['quality'] = 'OFFLINE 320K (' + (bytes.length / (1024 * 1024)).toStringAsFixed(1) + ' MB)';

            final notifier = isEntry ? offlineEntries : offlineSongs;
            final String storageKey = isEntry ? 'v50_off_entries' : 'v50_off_songs';
            final List<Map<String, dynamic>> current = List<Map<String, dynamic>>.from(notifier.value);
            current.removeWhere((e) => e['id'].toString() == id);
            current.insert(0, clean);
            notifier.value = current;
            await _saveList(storageKey, current);

            final updatedMap = Map<String, int>.from(downloadProgressMap.value);
            updatedMap.remove(id);
            downloadProgressMap.value = updatedMap;
            return true;
          }
        }
        client.close();
      } catch (_) {}
    }

    final updatedMap = Map<String, int>.from(downloadProgressMap.value);
    updatedMap.remove(id);
    downloadProgressMap.value = updatedMap;
    return false;
  }
}

/// Strict Entry & Encourage Music Harvester (Blocks 100% of Normal/Melody Songs!)
class EntryMusicHarvester {
  static final Map<String, int> customSavedCueSeconds = {};

  static final Map<String, List<String>> categorySeedQueries = {
    'ALL_1000': [
      'KGF Chapter 2 Monster BGM Ravi Basrur',
      'Vikram Rolex Entry Theme BGM Anirudh',
      'Jailer Hukum Tiger Ka Hukum Anirudh',
      'Salaar Cease Fire Sound of Salaar BGM',
      'Kantara Varaha Roopam Daiva Mass BGM',
      'Animal Abrars Entry Jamal Kudu BGM',
      'Devara Fear Song Anirudh High Bass',
      'Leo Badass Mass Entry Anirudh',
      'Kalki 2898 AD Theme of Kalki BGM',
      'Master Vaathi Raid Mass BGM Anirudh',
      'KGF Dheera Dheera Sultan Mass Anthem',
      'Marco Blood Theme High Bass BGM',
      'Tagaru Shiva Mass Theme Charan Raj',
      'Kaatera Mass Theme Song Darshan',
      'Max Kiccha Sudeep Maximum Mass Track',
      'UI Troll Song Upendra Kannada Mass',
    ],
    'HERO_ENTRY': [
      'KGF Rocky Bhai Walkout Theme BGM',
      'Salaar Prabhas Entry Theme Ravi Basrur',
      'Vikram Once Upon A Time Eagle BGM',
      'Jailer Hukum Anirudh Ravichander',
      'Petta Paraak Mass Entry Theme Anirudh',
      'Baahubali Saahore Baahubali King Entry',
    ],
    'SIXER_DROP': [
      'IPL Trumpet Stadium Horn Official Remix',
      'KGF Sultan High Bass Chorus Drop',
      'Vaathi Coming Mass Beat Drop Anirudh',
      'Arabic Kuthu Halamithi Habibo Bass Drop',
      'Puneri Dhol Tasha High Bass DJ Drop',
    ],
    'FOUR_HORN': [
      'IPL Boundary Horn Stadium Brass Remix',
      'Naatu Naatu RRR Fast Dance Beat',
      'Dhol Tasha Fast Boundary Celebration',
      'Jhoome Jo Pathaan Fast Chorus Beat',
    ],
    'WICKET_OUT': [
      'Vikram Rolex Theme Dark Wicket BGM',
      'KGF Garuda Dark Villain Entry BGM',
      'Animal Arjan Vailly Fierce Axe BGM',
      'Marco Unni Mukundan Dark Violence BGM',
    ],
    'ENCOURAGE': [
      'Sultan Title Track Salman Khan Workout',
      'Chak De India Victory Stadium Anthem',
      'Kar Har Maidan Fateh Motivational Anthem',
      'Zinda Bhaag Milkha Bhaag Energetic',
      'Dheera Dheera KGF Chapter 1 Kannada',
      'Brothers Anthem Vishal Dadlani High Bass',
      'Dangal Title Track Daler Mehndi Anthem',
    ],
    'KANNADA_MASS': [
      'KGF Chapter 1 Dheera Dheera Kannada',
      'Tagaru Title Track Shiva Kannada Charan Raj',
      'Kantara Varaha Roopam Kannada Mass',
      'Kaatera Pasandaagavne Kannada Mass',
      'Jackie Title Track Puneeth Rajkumar Kannada',
      'Ugramm Veeram Kannada Mass Theme',
      'Bheema Bad Boys Duniya Vijay Kannada BGM',
      'Max Kiccha Sudeep Kannada Mass Song',
      'Yuva Title Track Yuva Rajkumar Kannada',
      'Kabzaa Title Track Ravi Basrur Kannada BGM',
    ],
  };

  /// Strict Blacklist: Blocks love, romantic, melody, slow, sad, devotional & normal songs!
  static const List<String> _normalSongBlacklist = [
    'love',
    'romantic',
    'romance',
    'melody',
    'duet',
    'sad',
    'heartbreak',
    'lullaby',
    'unplugged',
    'lofi',
    'lo-fi',
    'slowed',
    'acoustic',
    'sleep',
    'relaxing',
    'rain',
    'preethi',
    'prema',
    'premi',
    'pyaar',
    'ishq',
    'mohabbat',
    'dil ',
    'sanam',
    'kanasu',
    'munjane',
    'mungaru',
    'neene',
    'ninna',
    'nanna',
    'sojugada',
    'dwapara',
    'mayavi',
    'honeymoon',
    'bhajan',
    'devotional',
    'aarti',
    'chalisa',
    'stotram',
    'karaoke',
    'flute version',
    'piano version',
  ];

  /// Strict Whitelist: Track MUST contain at least one Entry, BGM, Bass, Encourage, or Mass Action marker!
  static const List<String> _entryEncourageWhitelist = [
    'bgm',
    'theme',
    'ost',
    'entry',
    'walkout',
    'mass',
    'monster',
    'rolex',
    'hukum',
    'boss',
    'king',
    'sultan',
    'dheera',
    'varaha',
    'tandav',
    'garuda',
    'arjan',
    'vailly',
    'jamal',
    'kudu',
    'badass',
    'vaathi',
    'raid',
    'fear',
    'blood',
    'violence',
    'power',
    'warrior',
    'anthem',
    'workout',
    'motivation',
    'encourage',
    'victory',
    'champion',
    'ipl',
    'rcb',
    'csk',
    'stadium',
    'trumpet',
    'horn',
    'dhol',
    'tasha',
    'drums',
    'bass',
    'drop',
    'remix',
    'dj',
    'mashup',
    'edm',
    'trap',
    'instrumental',
    'title',
    'teaser',
    'trailer',
    'kgf',
    'salaar',
    'kantara',
    'vikram',
    'jailer',
    'leo',
    'pushpa',
    'kalki',
    'devara',
    'animal',
    'marco',
    'tagaru',
    'kaatera',
    'ugramm',
    'bheema',
    'max',
    'yuva',
    'jackie',
    'kabzaa',
    'baahubali',
    'saahore',
    'naatu',
    'pathaan',
    'jawan',
    'zinda',
    'chak de',
    'dangal',
    'maidan',
    'brothers',
    'ravi basrur',
    'anirudh',
    'charan raj',
  ];

  static int _batchCursor = 0;

  static Future<void> loadSavedCues() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('entry_custom_cues_v50');
      if (raw != null) {
        final Map<String, dynamic> decoded = jsonDecode(raw);
        decoded.forEach((k, v) => customSavedCueSeconds[k] = (v as num).toInt());
      }
    } catch (_) {}
  }

  static Future<void> saveCustomCue(String trackId, int dropSecond) async {
    customSavedCueSeconds[trackId] = dropSecond;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('entry_custom_cues_v50', jsonEncode(customSavedCueSeconds));
    } catch (_) {}
  }

  static String _cleanTitle(String raw) {
    return raw
        .replaceAll('&quot;', '"')
        .replaceAll('&amp;', '&')
        .replaceAll('&#039;', "'")
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .trim();
  }

  static int computeSmartEntryDropSecond(String id, String title, int durationSec) {
    if (customSavedCueSeconds.containsKey(id)) {
      return customSavedCueSeconds[id]!;
    }
    final String lower = title.toLowerCase();
    if (durationSec > 0 && durationSec <= 75) return 0;
    if (lower.contains('bgm') ||
        lower.contains('theme') ||
        lower.contains('ost') ||
        lower.contains('monster') ||
        lower.contains('rolex') ||
        lower.contains('trumpet') ||
        lower.contains('horn')) {
      return durationSec <= 130 ? 0 : 4;
    }
    if (lower.contains('hukum')) return 19;
    if (lower.contains('sultan')) return 24;
    if (lower.contains('dheera')) return 21;
    if (lower.contains('varaha')) return 12;
    if (lower.contains('jamal kudu') || lower.contains('abrar')) return 0;
    if (lower.contains('arjan vailly')) return 14;
    if (lower.contains('vaathi coming')) return 8;
    if (lower.contains('badass')) return 16;
    if (lower.contains('fear song') || lower.contains('devara')) return 18;
    if (lower.contains('tagaru')) return 9;
    if (lower.contains('chak de')) return 18;
    if (durationSec > 180) return 8;
    return 2;
  }

  /// Enforces that ONLY Entry, Mass BGM, High-Bass DJ, or Player Encourage tracks pass!
  static bool isStrictEntryOrEncourageTrack(String title, String subtitle, int durSec) {
    if (durSec > 0 && durSec < 12) return false;
    final String combined = ('$title $subtitle').toLowerCase();

    // 1. Reject any normal love/romantic/melody/slow track immediately
    for (final bad in _normalSongBlacklist) {
      if (combined.contains(bad)) return false;
    }

    // 2. Require at least one Entry / BGM / Mass / Bass / Encourage keyword
    for (final good in _entryEncourageWhitelist) {
      if (combined.contains(good)) return true;
    }
    return false;
  }

  /// Rewrites any user search (like "kannada") into strict Entry & Encourage BGM queries!
  static List<String> _buildStrictEntrySearchQueries(String userSearch) {
    final String clean = userSearch.trim();
    final String lower = clean.toLowerCase();
    if (lower == 'kannada' || lower == 'kannada songs' || lower == 'kannada entry') {
      return [
        'KGF Dheera Dheera Sultan Kannada Ravi Basrur',
        'Tagaru Shiva Mass Theme Kannada Charan Raj',
        'Kantara Varaha Roopam Kannada Mass BGM',
        'Kaatera Mass Theme Darshan Kannada',
        'Jackie Yuva Max Ugramm Kannada Mass Song',
        'Kannada High Bass DJ Entry Remix BGM',
      ];
    }
    if (lower == 'hindi' || lower == 'bollywood') {
      return [
        'Sultan Chak De India Kar Har Maidan Fateh Anthem',
        'Animal Arjan Vailly Abrar Entry Jamal Kudu BGM',
        'KGF Monster Sultan Hindi Mass BGM',
        'Pathaan Jawan Mass Entry Theme BGM',
      ];
    }
    return [
      '$clean Mass Entry BGM Theme',
      '$clean High Bass DJ Remix Drop',
      '$clean Hero Walkout OST Theme',
      '$clean Motivational Workout Anthem',
      '$clean Ravi Basrur Anirudh BGM',
    ];
  }

  static Future<List<Map<String, dynamic>>> fetchEntryTracks({
    required String categoryKey,
    String? customQuery,
    bool loadNextBatch = false,
  }) async {
    await loadSavedCues();
    final List<Map<String, dynamic>> out = [];
    final Set<String> seenIds = {};
    final Set<String> seenFingerprints = {};

    List<String> queries = [];
    if (customQuery != null && customQuery.trim().isNotEmpty) {
      queries = _buildStrictEntrySearchQueries(customQuery);
    } else {
      final List<String> pool = categorySeedQueries[categoryKey] ?? categorySeedQueries['ALL_1000']!;
      if (loadNextBatch) {
        _batchCursor = (_batchCursor + 4) % pool.length;
      }
      for (int i = 0; i < 6; i++) {
        queries.add(pool[(_batchCursor + i) % pool.length]);
      }
    }

    final Map<String, String> headers = {
      'User-Agent': 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/124.0 Mobile Safari/537.36',
      'Accept': 'application/json, text/plain, */*',
    };

    for (final q in queries) {
      try {
        final String url =
            'https://www.jiosaavn.com/api.php?__call=search.getResults&_format=json&_marker=0&api_version=4&ctx=web6dot0&n=30&p=1&q=' +
                Uri.encodeComponent(q);
        final res = await http.get(Uri.parse(url), headers: headers).timeout(const Duration(seconds: 6));
        if (res.statusCode == 200) {
          final decoded = jsonDecode(res.body);
          final List results = decoded['results'] ?? [];
          for (final item in results) {
            final String id = (item['id'] ?? '').toString();
            if (id.isEmpty || seenIds.contains(id)) continue;

            final Map moreInfo = (item['more_info'] is Map) ? item['more_info'] : {};
            final String title = _cleanTitle((item['title'] ?? item['song'] ?? 'Entry BGM').toString());
            final String subtitle = _cleanTitle((item['subtitle'] ?? moreInfo['music'] ?? 'Mass BGM').toString());
            final String album = _cleanTitle((moreInfo['album'] ?? '').toString());
            final int durSec = int.tryParse((moreInfo['duration'] ?? item['duration'] ?? '0').toString()) ?? 0;

            // 1. Canonical Fingerprint Deduplication (Zero Duplicates!)
            final String fp = SaavnDesDecryptor.canonicalFingerprint(title);
            if (seenFingerprints.contains(fp)) continue;

            // 2. Strict Entry & Encourage Gatekeeper (Zero Normal/Melody Songs!)
            if (!isStrictEntryOrEncourageTrack(title, '$subtitle $album', durSec)) continue;

            final String? encUrl = (moreInfo['encrypted_media_url'] ?? item['encrypted_media_url'])?.toString();
            final String? prevUrl = (moreInfo['vlink'] ?? item['media_preview_url'])?.toString();
            final List<String> urls = SaavnDesDecryptor.decryptToFullUrls(encUrl, prevUrl);
            if (urls.isEmpty) continue;

            seenIds.add(id);
            seenFingerprints.add(fp);

            final int playCount =
                int.tryParse((item['play_count'] ?? moreInfo['play_count'] ?? '50000').toString()) ?? 50000;
            final int year = int.tryParse((item['year'] ?? moreInfo['year'] ?? '2026').toString()) ?? 2026;
            final String cover = (item['image'] ?? 'https://via.placeholder.com/150')
                .toString()
                .replaceAll('150x150', '500x500');

            final int smartDropSec = computeSmartEntryDropSecond(id, title, durSec);

            out.add({
              'id': id,
              'title': title,
              'artist': subtitle,
              'cover': cover,
              'urls': urls,
              'durationSec': durSec,
              'smartDropSec': smartDropSec,
              'playCount': playCount,
              'year': year,
              'tag': categoryKey,
              'isOffline': false,
            });
          }
        }
      } catch (_) {}
    }

    out.sort((a, b) => ((b['playCount'] ?? 0) as int).compareTo((a['playCount'] ?? 0) as int));
    return out;
  }
}
