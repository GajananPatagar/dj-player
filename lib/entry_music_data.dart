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
  static final ValueNotifier<double> page3SfxVolume = ValueNotifier<double>(0.70);
  static final ValueNotifier<double> page4EntryVolume = ValueNotifier<double>(0.0);
  static final ValueNotifier<String?> autoCricketStingerTrigger = ValueNotifier<String?>(null);
  static bool autoPlayEntryOnCricketBoundaryOrWicket = false;
}

class VaultManager {
  static final ValueNotifier<List<Map<String, dynamic>>> favSongs = ValueNotifier([]);
  static final ValueNotifier<List<Map<String, dynamic>>> offlineSongs = ValueNotifier([]);
  static final ValueNotifier<List<Map<String, dynamic>>> favEntries = ValueNotifier([]);
  static final ValueNotifier<List<Map<String, dynamic>>> offlineEntries = ValueNotifier([]);
  static final ValueNotifier<Map<String, int>> downloadProgressMap = ValueNotifier({});

  /// Built-in + User-Created Offline Category Folders
  static const List<String> defaultOfflineCategories = [
    'Marriage',
    'Fashion Show',
    'Devotional',
    'Kannada',
    'Hindi',
    'DJ Bass & Party',
    'Mass Entry',
    'Janapada & Folk',
  ];

  static final ValueNotifier<List<String>> offlineCategories = ValueNotifier<List<String>>([
    ...defaultOfflineCategories,
  ]);

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
    await _loadCustomCategories();
    favSongs.value = await _loadList('v51_fav_songs');
    offlineSongs.value = await _loadList('v51_off_songs');
    favEntries.value = await _loadList('v51_fav_entries');
    offlineEntries.value = await _loadList('v51_off_entries');
  }

  static Future<void> _loadCustomCategories() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<String> saved = prefs.getStringList('v500_offline_categories') ?? [];
      final List<String> merged = [...defaultOfflineCategories];
      for (final c in saved) {
        final clean = c.trim();
        if (clean.isNotEmpty && !merged.any((m) => m.toLowerCase() == clean.toLowerCase())) {
          merged.add(clean);
        }
      }
      offlineCategories.value = merged;
    } catch (_) {}
  }

  static Future<String> addCustomCategory(String rawName) async {
    final String clean = rawName.trim();
    if (clean.isEmpty) return defaultOfflineCategories.first;
    final List<String> current = List<String>.from(offlineCategories.value);
    final int existingIdx = current.indexWhere((c) => c.toLowerCase() == clean.toLowerCase());
    if (existingIdx >= 0) {
      return current[existingIdx];
    }
    current.add(clean);
    offlineCategories.value = current;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('v500_offline_categories', current);
    } catch (_) {}
    return clean;
  }

  static String categoryIcon(String cat) {
    final String lower = cat.toLowerCase();
    if (lower.contains('marriage') || lower.contains('wedding') || lower.contains('haldi')) return '💍';
    if (lower.contains('fashion') || lower.contains('ramp')) return '👗';
    if (lower.contains('devotional') || lower.contains('bhakti') || lower.contains('pooja')) return '🪔';
    if (lower.contains('kannada')) return '👑';
    if (lower.contains('hindi')) return '🇮🇳';
    if (lower.contains('dj') || lower.contains('bass') || lower.contains('party')) return '🔥';
    if (lower.contains('entry') || lower.contains('mass')) return '⚡';
    if (lower.contains('folk') || lower.contains('janapada')) return '🥁';
    return '📂';
  }

  /// Returns ONLY the offline songs inside [category] in their exact custom Song Number sequence!
  static List<Map<String, dynamic>> getOfflineSongsByCategory(String category) {
    if (category == 'ALL_OFFLINE') {
      return offlineSongs.value;
    }
    return offlineSongs.value.where((trk) {
      final String trkCat = (trk['category'] ?? 'Kannada').toString().trim();
      return trkCat.toLowerCase() == category.trim().toLowerCase();
    }).toList();
  }

  /// Changes the Song Number (1-based position) of [trackId] inside [category] and saves permanently!
  static Future<void> changeSongNumberInCategory(
    String category,
    String trackId,
    int targetOneBasedNumber,
  ) async {
    final List<Map<String, dynamic>> all = List<Map<String, dynamic>>.from(offlineSongs.value);
    final List<Map<String, dynamic>> inCat = [];
    final List<int> originalSlotIndices = [];

    for (int i = 0; i < all.length; i++) {
      final String trkCat = (all[i]['category'] ?? 'Kannada').toString().trim();
      if (category == 'ALL_OFFLINE' || trkCat.toLowerCase() == category.trim().toLowerCase()) {
        inCat.add(all[i]);
        originalSlotIndices.add(i);
      }
    }

    if (inCat.length < 2) return;
    final int currentIdx = inCat.indexWhere((e) => e['id'].toString() == trackId);
    if (currentIdx < 0) return;

    final int targetIdx = (targetOneBasedNumber - 1).clamp(0, inCat.length - 1);
    if (currentIdx == targetIdx) return;

    final Map<String, dynamic> moved = inCat.removeAt(currentIdx);
    inCat.insert(targetIdx, moved);

    for (int k = 0; k < originalSlotIndices.length; k++) {
      final Map<String, dynamic> updatedItem = Map<String, dynamic>.from(inCat[k]);
      updatedItem['customOrder'] = k + 1;
      all[originalSlotIndices[k]] = updatedItem;
    }

    offlineSongs.value = all;
    await _saveList('v51_off_songs', all);
  }

  /// Changes Song Number inside Favorites list
  static Future<void> changeSongNumberInFavorites(
    String trackId,
    int targetOneBasedNumber,
  ) async {
    final List<Map<String, dynamic>> favs = List<Map<String, dynamic>>.from(favSongs.value);
    if (favs.length < 2) return;
    final int currentIdx = favs.indexWhere((e) => e['id'].toString() == trackId);
    if (currentIdx < 0) return;
    final int targetIdx = (targetOneBasedNumber - 1).clamp(0, favs.length - 1);
    if (currentIdx == targetIdx) return;

    final Map<String, dynamic> moved = favs.removeAt(currentIdx);
    favs.insert(targetIdx, moved);
    favSongs.value = favs;
    await _saveList('v51_fav_songs', favs);
  }

  /// Saves a Custom Start Cue Second for any song (e.g. skip slow intro on Marriage / Fashion Show track)
  static Future<void> setTrackCustomStartCue(String id, int startSec) async {
    final List<Map<String, dynamic>> current = List<Map<String, dynamic>>.from(offlineSongs.value);
    bool changed = false;
    for (int i = 0; i < current.length; i++) {
      if (current[i]['id'].toString() == id) {
        final updated = Map<String, dynamic>.from(current[i]);
        updated['customStartSec'] = startSec;
        current[i] = updated;
        changed = true;
      }
    }
    if (changed) {
      offlineSongs.value = current;
      await _saveList('v51_off_songs', current);
    }
  }

  static String? getTrackOfflineCategory(String id) {
    for (final e in offlineSongs.value) {
      if (e['id'].toString() == id) {
        return (e['category'] ?? 'Kannada').toString();
      }
    }
    return null;
  }

  static Future<void> assignOfflineCategory(String id, String newCategory) async {
    final List<Map<String, dynamic>> current = List<Map<String, dynamic>>.from(offlineSongs.value);
    bool changed = false;
    for (int i = 0; i < current.length; i++) {
      if (current[i]['id'].toString() == id) {
        final updated = Map<String, dynamic>.from(current[i]);
        updated['category'] = newCategory;
        current[i] = updated;
        changed = true;
      }
    }
    if (changed) {
      offlineSongs.value = current;
      await _saveList('v51_off_songs', current);
    }
  }

  static Future<void> deleteOfflineSong(String id, {bool isEntry = false}) async {
    final notifier = isEntry ? offlineEntries : offlineSongs;
    final String storageKey = isEntry ? 'v51_off_entries' : 'v51_off_songs';
    final List<Map<String, dynamic>> current = List<Map<String, dynamic>>.from(notifier.value);
    current.removeWhere((e) => e['id'].toString() == id);
    notifier.value = current;
    await _saveList(storageKey, current);
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
      'smartDropSec': int.tryParse((t['smartDropSec'] ?? '12').toString()) ?? 12,
      'customStartSec': int.tryParse((t['customStartSec'] ?? '0').toString()) ?? 0,
      'year': int.tryParse((t['year'] ?? '2026').toString()) ?? 2026,
      'quality': (t['quality'] ?? '320kbps MASTER').toString(),
      'localPath': t['localPath']?.toString(),
      'isOffline': t['isOffline'] == true,
      'category': (t['category'] ?? 'Kannada').toString(),
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

  static Future<bool> downloadTrack(
    Map<String, dynamic> track, {
    required bool isEntry,
    String category = 'Kannada',
  }) async {
    final clean = _sanitizeTrackMap(track);
    clean['category'] = category;
    final String id = clean['id'].toString();

    if (clean['localPath'] != null && File(clean['localPath'].toString()).existsSync()) {
      clean['isOffline'] = true;
      final notifier = isEntry ? offlineEntries : offlineSongs;
      final String storageKey = isEntry ? 'v51_off_entries' : 'v51_off_songs';
      final List<Map<String, dynamic>> current = List<Map<String, dynamic>>.from(notifier.value);
      current.removeWhere((e) => e['id'].toString() == id);
      current.add(clean); // Append at end of category so song numbers #1, #2, #3 stay in order!
      notifier.value = current;
      await _saveList(storageKey, current);
      return true;
    }

    final List<String> urls = List<String>.from(clean['urls'] as List);
    if (urls.isEmpty) return false;

    downloadProgressMap.value = {...downloadProgressMap.value, id: 15};

    final Map<String, String> headers = {
      'User-Agent': 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/124.0 Mobile Safari/537.36',
      'Accept': '*/*',
    };

    for (final rawUrl in urls) {
      try {
        downloadProgressMap.value = {...downloadProgressMap.value, id: 45};
        final res = await http.get(Uri.parse(rawUrl), headers: headers).timeout(const Duration(seconds: 40));
        if (res.statusCode == 200 && res.bodyBytes.length > 25000) {
          downloadProgressMap.value = {...downloadProgressMap.value, id: 85};
          final dir = await _safeStorageDir();
          final safeId = id.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
          final String prefix = isEntry ? 'entry_320k_' : 'song_320k_';
          final File outFile = File('${dir.path}/$prefix$safeId.mp4');
          await outFile.writeAsBytes(res.bodyBytes, flush: true);

          clean['localPath'] = outFile.path;
          clean['isOffline'] = true;
          clean['category'] = category;
          clean['quality'] =
              'OFFLINE 320K (${(res.bodyBytes.length / (1024 * 1024)).toStringAsFixed(1)} MB)';

          final notifier = isEntry ? offlineEntries : offlineSongs;
          final String storageKey = isEntry ? 'v51_off_entries' : 'v51_off_songs';
          final List<Map<String, dynamic>> current = List<Map<String, dynamic>>.from(notifier.value);
          current.removeWhere((e) => e['id'].toString() == id);
          current.add(clean);
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

  static const List<String> masterFunkAndMassPool = [
    'Funk Criminal',
    'Funk Criminal Slowed Bass',
    'Masha Ultrafunk',
    'Tuca Donka',
    'Montagem Mysterious Game',
    'Montagem Coral Funk',
    'Automotivo Bibi Fogosa',
    'Passo Bem Solto Funk',
    'Murder In My Mind Kordhell',
    'Rave Dxrk Phonk',
    'Close Eyes DVRST',
    'Metamorphosis Interworld',
    'Sahara Hensonn',
    'GigaChad Theme Phonk',
    'Slay Eternxlkz Funk',
    'Orquestra Maldita Funk',
    'Agudo Magico Funk',
    'Funk Estranho',
    'Bounce Funk Bass Boosted',
    'KGF Monster BGM Ravi Basrur',
    'Vikram Rolex Theme BGM Anirudh',
    'Hukum Tiger Ka Hukum Jailer',
    'Salaar Sound of Salaar BGM',
    'Marco Blood Theme Ravi Basrur',
    'KGF Sulthana Mass Song',
    'KGF Dheera Dheera Mass',
    'Animal Arjan Vailly Mass',
    'Animal Abrar Entry Jamal Kudu',
    'Leo Badass Anirudh',
    'Devara Fear Song Anirudh',
    'Master Vaathi Raid Anirudh',
    'Kantara Varaha Roopam Mass',
    'Tagaru Shiva Theme Charan Raj',
    'IPL Stadium Horn Bass Drop',
  ];

  static final RegExp _rejectSlowOrLoveRegex = RegExp(
    r'\b(masstaani|eradu|jadeyannu|lullaby|unplugged|acoustic|karaoke)\b',
    caseSensitive: false,
  );

  static Future<void> loadSavedCues() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('entry_custom_cues_v304');
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
      await prefs.setString('entry_custom_cues_v304', jsonEncode(customSavedCueSeconds));
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

    if (lower.contains('funk criminal')) return 12;
    if (lower.contains('ultrafunk') || lower.contains('masha')) return 15;
    if (lower.contains('tuca donka')) return 13;
    if (lower.contains('montagem')) return 11;
    if (lower.contains('automotivo') || lower.contains('bibi')) return 14;
    if (lower.contains('passo bem')) return 12;
    if (lower.contains('murder in my mind')) return 21;
    if (lower.contains('close eyes')) return 14;
    if (lower.contains('rave')) return 13;
    if (lower.contains('sahara')) return 18;
    if (lower.contains('metamorphosis')) return 16;
    if (lower.contains('slay') || lower.contains('orquestra') || lower.contains('agudo')) return 11;
    if (lower.contains('monster')) return 8;
    if (lower.contains('rolex')) return 10;
    if (lower.contains('hukum')) return 19;
    if (lower.contains('sultan') || lower.contains('sulthana')) return 24;
    if (lower.contains('dheera')) return 21;
    if (lower.contains('varaha')) return 18;
    if (lower.contains('arjan vailly')) return 14;
    if (lower.contains('jamal kudu') || lower.contains('abrar')) return 6;
    if (lower.contains('badass')) return 16;
    if (lower.contains('fear song')) return 18;
    if (lower.contains('tagaru')) return 15;

    if (durationSec >= 35 && durationSec <= 125) {
      return 12;
    }
    return 22;
  }

  static Future<List<Map<String, dynamic>>> fetchEntryTracks({
    String categoryKey = 'ALL',
    String? customQuery,
    bool loadNextBatch = false,
  }) async {
    await loadSavedCues();
    final List<Map<String, dynamic>> out = [];
    final Set<String> seenIds = {};
    final Set<String> seenFingerprints = {};

    final DateTime now = DateTime.now();
    final int daySeed = now.year * 400 + now.month * 32 + now.day;

    List<String> selectedQueries = [];
    if (customQuery != null && customQuery.trim().isNotEmpty) {
      final String q = customQuery.trim();
      selectedQueries = [
        q,
        '$q Funk Bass',
        '$q Phonk Remix',
        '$q Mass Entry BGM',
        '$q High Bass Drop',
      ];
    } else {
      final List<String> pool = List<String>.from(masterFunkAndMassPool);
      if (loadNextBatch) {
        pool.shuffle(_rng);
        selectedQueries = pool.take(12).toList();
      } else {
        final int offset = daySeed % (pool.length - 6);
        selectedQueries = [
          'Funk Criminal',
          'Masha Ultrafunk',
          'Tuca Donka',
          'Montagem Mysterious Game',
          'Automotivo Bibi Fogosa',
          'Murder In My Mind Kordhell',
          'KGF Monster BGM',
          'Vikram Rolex Theme BGM',
          'Hukum Tiger Ka Hukum',
          ...pool.sublist(offset, (offset + 5).clamp(0, pool.length)),
        ];
      }
    }

    final Map<String, String> headers = {
      'User-Agent': 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/124.0 Mobile Safari/537.36',
      'Accept': 'application/json, text/plain, */*',
    };

    final int pageNum = loadNextBatch ? (1 + _rng.nextInt(3)) : 1;

    final List<Future<http.Response?>> futures = selectedQueries.map((q) async {
      try {
        final String url =
            'https://www.jiosaavn.com/api.php?__call=search.getResults&_format=json&_marker=0&api_version=4&ctx=web6dot0&n=16&p=$pageNum&q=${Uri.encodeComponent(q)}';
        return await http.get(Uri.parse(url), headers: headers).timeout(const Duration(seconds: 6));
      } catch (_) {
        return null;
      }
    }).toList();

    final List<http.Response?> responses = await Future.wait(futures);

    for (final res in responses) {
      if (res == null || res.statusCode != 200) continue;
      try {
        final decoded = jsonDecode(res.body);
        final List results = decoded['results'] ?? [];
        for (final item in results) {
          final String id = (item['id'] ?? '').toString();
          if (id.isEmpty || seenIds.contains(id)) continue;

          final Map moreInfo = (item['more_info'] is Map) ? item['more_info'] : {};
          final String title = _cleanTitle((item['title'] ?? item['song'] ?? '').toString());
          final String subtitle = _cleanTitle((item['subtitle'] ?? moreInfo['music'] ?? 'Heavy Bass').toString());
          final int durSec = int.tryParse((moreInfo['duration'] ?? item['duration'] ?? '0').toString()) ?? 0;

          if (durSec < 25) continue;
          if (_rejectSlowOrLoveRegex.hasMatch('$title $subtitle')) continue;

          final String fp = SaavnDesDecryptor.canonicalFingerprint(title, subtitle);
          if (seenFingerprints.contains(fp)) continue;

          final String? encUrl = (moreInfo['encrypted_media_url'] ?? item['encrypted_media_url'])?.toString();
          final String? prevUrl = (moreInfo['vlink'] ?? item['media_preview_url'])?.toString();
          final bool has320 = (moreInfo['320kbps']?.toString() != 'false');
          final List<String> urls = SaavnDesDecryptor.decryptToFullUrls(encUrl, prevUrl, has320: has320);
          if (urls.isEmpty) continue;

          seenIds.add(id);
          seenFingerprints.add(fp);

          final String cover = (item['image'] ?? 'https://via.placeholder.com/300')
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
            'quality': has320 ? '320kbps HEAVY BASS' : '160kbps HEAVY BASS',
            'isOffline': false,
            'category': 'Mass Entry',
          });
        }
      } catch (_) {}
    }

    return out;
  }
}
