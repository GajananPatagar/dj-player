import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'des_helper.dart';

class MasterVolumeController {
  static final ValueNotifier<double> page1MusicVolume = ValueNotifier<double>(1.0);
  static final ValueNotifier<double> page2VoiceVolume = ValueNotifier<double>(1.0);
  static final ValueNotifier<double> page3SfxVolume = ValueNotifier<double>(0.65);
  static final ValueNotifier<double> page4EntryVolume = ValueNotifier<double>(0.0);
  static final ValueNotifier<String?> autoCricketStingerTrigger = ValueNotifier<String?>(null);
  static bool autoPlayEntryOnCricketBoundaryOrWicket = true;
}

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
    favSongs.value = await _loadList('v51_fav_songs');
    offlineSongs.value = await _loadList('v51_off_songs');
    favEntries.value = await _loadList('v51_fav_entries');
    offlineEntries.value = await _loadList('v51_off_entries');
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
      'smartDropSec': int.tryParse((t['smartDropSec'] ?? '25').toString()) ?? 25,
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

  static Future<bool> toggleFavorite(Map<String, dynamic> track, {required bool isEntry}) async {
    final clean = _sanitizeTrackMap(track);
    final String id = clean['id'].toString();
    final notifier = isEntry ? favEntries : favSongs;
    final String storageKey = isEntry ? 'v51_fav_entries' : 'v51_fav_songs';

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

  static Future<bool> downloadTrack(Map<String, dynamic> track, {required bool isEntry}) async {
    final clean = _sanitizeTrackMap(track);
    final String id = clean['id'].toString();
    final List<String> urls = List<String>.from(clean['urls'] as List);
    if (urls.isEmpty) return false;

    downloadProgressMap.value = {...downloadProgressMap.value, id: 10};

    final Map<String, String> headers = {
      'User-Agent': 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/124.0 Mobile Safari/537.36',
      'Accept': '*/*',
    };

    for (final rawUrl in urls) {
      try {
        downloadProgressMap.value = {...downloadProgressMap.value, id: 35};
        final res = await http.get(Uri.parse(rawUrl), headers: headers).timeout(const Duration(seconds: 40));
        if (res.statusCode == 200 && res.bodyBytes.length > 60000) {
          downloadProgressMap.value = {...downloadProgressMap.value, id: 85};
          final dir = await _safeStorageDir();
          final safeId = id.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
          final String prefix = isEntry ? 'entry_320k_' : 'song_320k_';
          final File outFile = File('${dir.path}/$prefix$safeId.mp4');
          await outFile.writeAsBytes(res.bodyBytes, flush: true);

          clean['localPath'] = outFile.path;
          clean['isOffline'] = true;
          clean['quality'] =
              'OFFLINE 320K (' + (res.bodyBytes.length / (1024 * 1024)).toStringAsFixed(1) + ' MB)';

          final notifier = isEntry ? offlineEntries : offlineSongs;
          final String storageKey = isEntry ? 'v51_off_entries' : 'v51_off_songs';
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
      } catch (_) {}
    }

    final updatedMap = Map<String, int>.from(downloadProgressMap.value);
    updatedMap.remove(id);
    downloadProgressMap.value = updatedMap;
    return false;
  }
}

class EntryMusicHarvester {
  static final Map<String, int> customSavedCueSeconds = {};
  static final Random _rng = Random();

  /// Massive Seed Pools including Brazilian Funk, Phonk, Bass Drops & Mass Entry BGMs
  static final Map<String, List<String>> categorySeedQueries = {
    'FUNK_BASS': [
      'Brazilian Phonk Bass Boosted',
      'Montagem Funk Bass Drop',
      'Masha Ultrafunk Phonk',
      'Tuca Donka Phonk Funk',
      'Automotivo Brazilian Funk',
      'Murder In My Mind Kordhell Phonk',
      'Rave Dxrk Phonk Bass',
      'GigaChad Theme Phonk Bass',
      'Funk Estranho Bass Drop',
      'Bounce Funk Bass Boosted',
      'Slay Eternxlkz Phonk',
      'Passo Bem Solto Funk',
      'Bibi Phonk BR',
      'Neon Blade Phonk',
      'Close Eyes DVRST Phonk',
      'Metamorphosis Interworld Phonk',
      'Sahara Hensonn Phonk Bass',
      'Orquestra Maldita Funk',
      'Montagem Coral Funk',
      'Agudo Magico Funk Bass',
    ],
    'ALL_1000': [
      'Brazilian Phonk Bass Boosted',
      'Masha Ultrafunk Phonk',
      'KGF Monster BGM Ravi Basrur',
      'Hukum Tiger Ka Hukum Jailer Anirudh',
      'Tuca Donka Phonk Funk',
      'Vikram Title Track Anirudh Ravichander',
      'Salaar Sound of Salaar Theme BGM',
      'Montagem Funk Bass Drop',
      'Kantara Varaha Roopam Mass Song',
      'Dheera Dheera KGF Chapter 1',
      'Sultan KGF Chapter 2 Mass Song',
      'Murder In My Mind Kordhell Phonk',
      'Leo Badass Song Anirudh Ravichander',
      'Devara Fear Song Anirudh',
      'Master Vaathi Raid Vaathi Coming Anirudh',
      'Animal Arjan Vailly Mass Song',
      'Animal Abrar Entry Jamal Kudu',
      'Tagaru Shiva Title Track Charan Raj',
      'Marco Blood Theme Ravi Basrur',
      'Close Eyes DVRST Phonk',
    ],
    'KANNADA_MASS': [
      'Dheera Dheera KGF Chapter 1 Kannada',
      'Sulthana KGF Chapter 2 Kannada',
      'Tagaru Shiva Title Track Kannada Charan Raj',
      'Varaha Roopam Kantara Kannada',
      'Ugramm Veeram Title Track Kannada',
      'Kaatera Theme Song Kannada',
      'Kabzaa Title Track Kannada Ravi Basrur',
      'Bheema Bad Boys Kannada Charan Raj',
      'Max Kiccha Sudeep Kannada Mass',
      'UI Troll Song Upendra Kannada',
      'Yuva Title Track Kannada Mass',
      'Bagheera Rudhira Dhara Kannada Mass',
    ],
    'HERO_ENTRY': [
      'KGF Monster Song Ravi Basrur',
      'Hukum Tiger Ka Hukum Anirudh',
      'Masha Ultrafunk Phonk',
      'Vikram Title Track Anirudh',
      'Sound of Salaar Ravi Basrur',
      'GigaChad Theme Phonk',
      'Petta Paraak Anirudh Ravichander',
      'Saahore Baahubali Entry Song',
      'Murder In My Mind Kordhell',
    ],
    'ENCOURAGE': [
      'Sultan Title Track Salman Khan Sukhwinder',
      'Chak De India Title Song Sukhwinder Singh',
      'Kar Har Maidan Fateh Sanju Sukhwinder',
      'Zinda Bhaag Milkha Bhaag',
      'Dangal Title Track Daler Mehndi',
      'Brothers Anthem Vishal Dadlani',
      'Dheera Dheera KGF Chapter 1',
      'Unstoppable Sia High Energy',
      'Believer Imagine Dragons Bass',
    ],
    'SIXER_DROP': [
      'Brazilian Phonk Bass Drop',
      'Montagem Funk Bass',
      'Tuca Donka Funk Drop',
      'Vaathi Coming Master Anirudh',
      'Arabic Kuthu Halamithi Habibo Anirudh',
      'KGF Sulthana High Energy',
      'Puneri Dhol Tasha Nonstop Beat',
      'Martin Garrix Animals Bass Drop',
    ],
    'FOUR_HORN': [
      'IPL Trumpet Horn Stadium Beat',
      'Automotivo Funk Fast Beat',
      'Jhoome Jo Pathaan Fast Beat',
      'Naatu Naatu RRR Dance Beat',
      'Vaathi Raid Master Anirudh',
    ],
    'WICKET_OUT': [
      'Vikram Rolex Theme BGM Anirudh',
      'Close Eyes DVRST Phonk',
      'Sahara Hensonn Phonk',
      'Arjan Vailly Animal Fierce',
      'Marco Blood Theme Ravi Basrur',
      'Fear Song Devara Anirudh',
    ],
  };

  static final RegExp _strictRejectRegex = RegExp(
    r'\b(masstaani|eradu|jadeyannu|love|romantic|romance|melody|duet|sad|lullaby|unplugged|lofi|slowed|acoustic|preethi|prema|pyaar|ishq|mohabbat|sanam|kanasu|munjane|mungaru|sojugada|dwapara|mayavi|bhajan|devotional|aarti|chalisa|karaoke)\b',
    caseSensitive: false,
  );

  static Future<void> loadSavedCues() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('entry_custom_cues_v303');
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
      await prefs.setString('entry_custom_cues_v303', jsonEncode(customSavedCueSeconds));
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

  /// Calculates the EXACT Peak Bass Drop / Climax Hook Second for the 10-Second Cricket Window!
  /// NEVER returns 0:00 on songs with intros so the 10 seconds are 100% pure high-bass energy!
  static int computeSmartEntryDropSecond(String id, String title, int durationSec) {
    if (customSavedCueSeconds.containsKey(id)) {
      return customSavedCueSeconds[id]!;
    }
    final String lower = title.toLowerCase();

    // Known Blockbuster & Funk Exact Peak Bass-Drop Timestamps
    if (lower.contains('hukum')) return 19;
    if (lower.contains('sultan') || lower.contains('sulthana')) return 24;
    if (lower.contains('dheera')) return 21;
    if (lower.contains('varaha')) return 18;
    if (lower.contains('arjan vailly')) return 14;
    if (lower.contains('vaathi coming')) return 22;
    if (lower.contains('badass')) return 16;
    if (lower.contains('fear song')) return 18;
    if (lower.contains('tagaru')) return 15;
    if (lower.contains('chak de')) return 24;
    if (lower.contains('ultrafunk') || lower.contains('masha')) return 16;
    if (lower.contains('tuca donka')) return 14;
    if (lower.contains('murder in my mind')) return 22;
    if (lower.contains('close eyes')) return 15;
    if (lower.contains('sahara')) return 19;
    if (lower.contains('metamorphosis')) return 17;

    // For Phonk / Funk / Short BGMs (35s - 110s): The main bass drop hits at ~28% of the track!
    if (durationSec >= 35 && durationSec <= 110) {
      return (durationSec * 0.28).round().clamp(12, 32);
    }

    // For Full-Length Songs (> 110s): Skip the 24-34 second intro buildup straight to the main chorus drop!
    if (durationSec > 110) {
      final int hashOffset = (id.hashCode.abs() % 12);
      return 24 + hashOffset; // Lands between 0:24 and 0:35 right on the chorus/drop!
    }

    return 8;
  }

  static List<String> _buildStrictEntrySearchQueries(String userSearch) {
    final String clean = userSearch.trim();
    final String lower = clean.toLowerCase();
    if (lower.contains('funk') || lower.contains('phonk') || lower.contains('bass')) {
      return categorySeedQueries['FUNK_BASS']!;
    }
    if (lower.contains('kannada')) {
      return categorySeedQueries['KANNADA_MASS']!;
    }
    if (lower.contains('hindi')) {
      return categorySeedQueries['ENCOURAGE']!;
    }
    return [
      '$clean Phonk Funk Bass',
      '$clean Mass Entry BGM',
      '$clean High Bass Remix',
      '$clean Title Track Anthem',
    ];
  }

  /// Dynamic Daily + Multi-Page Harvester: Pulls from Pages 1..6 and shuffles seeds daily
  /// so Lakhs of Online Funk, Bass & Entry options rotate every single day and on every refresh!
  static Future<List<Map<String, dynamic>>> fetchEntryTracks({
    required String categoryKey,
    String? customQuery,
    bool loadNextBatch = false,
  }) async {
    await loadSavedCues();
    final List<Map<String, dynamic>> out = [];
    final Set<String> seenIds = {};
    final Set<String> seenFingerprints = {};

    final DateTime now = DateTime.now();
    final int dayOfYear = now.difference(DateTime(now.year, 1, 1)).inDays;

    List<String> pool = [];
    if (customQuery != null && customQuery.trim().isNotEmpty) {
      pool = List<String>.from(_buildStrictEntrySearchQueries(customQuery));
    } else {
      pool = List<String>.from(categorySeedQueries[categoryKey] ?? categorySeedQueries['ALL_1000']!);
    }

    // Rotate pool using today's date + random salt on "Load More" so it NEVER shows the same fixed list!
    final int shift = loadNextBatch ? _rng.nextInt(pool.length) : (dayOfYear * 3) % pool.length;
    final List<String> rotatedPool = [
      ...pool.sublist(shift),
      ...pool.sublist(0, shift),
    ];

    final List<String> selectedQueries = rotatedPool.take(7).toList();
    final int apiPage = loadNextBatch ? (1 + _rng.nextInt(5)) : (1 + (dayOfYear % 3));

    final Map<String, String> headers = {
      'User-Agent': 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/124.0 Mobile Safari/537.36',
      'Accept': 'application/json, text/plain, */*',
    };

    for (final q in selectedQueries) {
      try {
        final String url =
            'https://www.jiosaavn.com/api.php?__call=search.getResults&_format=json&_marker=0&api_version=4&ctx=web6dot0&n=25&p=' +
                apiPage.toString() +
                '&q=' +
                Uri.encodeComponent(q);
        final res = await http.get(Uri.parse(url), headers: headers).timeout(const Duration(seconds: 6));
        if (res.statusCode == 200) {
          final decoded = jsonDecode(res.body);
          final List results = decoded['results'] ?? [];
          for (final item in results) {
            final String id = (item['id'] ?? '').toString();
            if (id.isEmpty || seenIds.contains(id)) continue;

            final Map moreInfo = (item['more_info'] is Map) ? item['more_info'] : {};
            final String title = _cleanTitle((item['title'] ?? item['song'] ?? '').toString());
            final String subtitle = _cleanTitle((item['subtitle'] ?? moreInfo['music'] ?? 'Bass Boosted').toString());
            final int durSec = int.tryParse((moreInfo['duration'] ?? item['duration'] ?? '0').toString()) ?? 0;

            // Allow 35s+ tracks so Brazilian Funk / Phonk & Mass BGMs (often 60s-110s) are included!
            if (durSec < 35) continue;
            if (_strictRejectRegex.hasMatch('$title $subtitle')) continue;

            final String fp = SaavnDesDecryptor.canonicalFingerprint(title);
            if (seenFingerprints.contains(fp)) continue;

            final String? encUrl = (moreInfo['encrypted_media_url'] ?? item['encrypted_media_url'])?.toString();
            final bool has320 = (moreInfo['320kbps']?.toString() == 'true');
            final List<String> urls = SaavnDesDecryptor.decryptToFullUrls(encUrl, null, has320: has320);
            if (urls.isEmpty) continue;

            seenIds.add(id);
            seenFingerprints.add(fp);

            final String cover = (item['image'] ?? 'https://via.placeholder.com/150')
                .toString()
                .replaceAll('150x150', '500x500');

            final int smartDropSec = computeSmartEntryDropSecond(id, title, durSec);
            final int m = durSec ~/ 60;
            final int s = durSec % 60;
            final String durFormatted = '$m:${s < 10 ? '0$s' : '$s'}';

            out.add({
              'id': id,
              'title': title,
              'artist': subtitle,
              'cover': cover,
              'urls': urls,
              'durationSec': durSec,
              'durationStr': durFormatted,
              'smartDropSec': smartDropSec,
              'quality': has320 ? '320kbps PURE ($durFormatted)' : '160kbps PURE ($durFormatted)',
              'tag': categoryKey,
              'isOffline': false,
            });
          }
        }
      } catch (_) {}
    }

    // Daily + Session Shuffle so top tracks are fresh every day
    final int dailySeed = dayOfYear * 97 + (loadNextBatch ? _rng.nextInt(9999) : 0);
    out.sort((a, b) {
      final int hA = (a['id'].toString().hashCode ^ dailySeed) & 0x7fffffff;
      final int hB = (b['id'].toString().hashCode ^ dailySeed) & 0x7fffffff;
      return hB.compareTo(hA);
    });
    return out;
  }
}
