import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'des_helper.dart';

/// Global Master Volume Controller shared across all 4 pages
class MasterVolumeController {
  static final ValueNotifier<double> page1MusicVolume = ValueNotifier<double>(1.0);
  static final ValueNotifier<double> page2VoiceVolume = ValueNotifier<double>(1.0);
  static final ValueNotifier<double> page3SfxVolume = ValueNotifier<double>(0.55);
  static final ValueNotifier<double> page4EntryVolume = ValueNotifier<double>(0.0);
}

/// Famous-Only High-Bass Entry Music Harvester & Smart Dynamic Entry Cut Calculator
class EntryMusicHarvester {
  static final Map<String, int> customSavedCueSeconds = {};

  /// Curated High-Popularity Famous Entry BGMs & Stadium Anthems
  static final Map<String, List<String>> categorySeedQueries = {
    'ALL_1000': [
      'KGF Chapter 2 Monster BGM Ravi Basrur',
      'Vikram Rolex Entry Theme BGM Anirudh',
      'Jailer Hukum Tiger Ka Hukum Anirudh',
      'Salaar Cease Fire Sound of Salaar Ravi Basrur',
      'Kantara Varaha Roopam Daiva Mass BGM',
      'Animal Abrars Entry Jamal Kudu BGM',
      'Pushpa The Rule Pushpa Pushpa Mass Song',
      'Leo Badass Mass Entry Anirudh Ravichander',
      'Devara Fear Song Anirudh High Bass',
      'Kalki 2898 AD Theme of Kalki BGM',
      'Master Vaathi Coming Vaathi Raid Anirudh',
      'KGF Dheera Dheera Sultan Mass Song',
      'Baahubali The Conclusion Saahore Baahubali',
      'Marco Blood Theme Ravi Basrur BGM',
      'Tagaru Shiva Theme Charan Raj Kannada',
      'Kaatera Mass Theme Song Darshan',
    ],
    'HERO_ENTRY': [
      'KGF Rocky Bhai Walkout Theme BGM',
      'Salaar Prabhas Entry Theme Ravi Basrur',
      'Vikram Title Track Nayagan Meendum Mass',
      'Jailer Hukum Anirudh Ravichander',
      'Petta Paraak Mass Entry Theme Anirudh',
      'Donjon John Cena Roman Reigns Entry Theme',
    ],
    'SIXER_DROP': [
      'IPL Trumpet Stadium Horn Official Remix',
      'Vaathi Coming Otha Sollaala Mass Drop',
      'KGF Sultan High Bass Chorus Drop',
      'Arabic Kuthu Halamithi Habibo Bass Drop',
      'Kurchi Madathapetti High Energy Beat',
    ],
    'FOUR_HORN': [
      'IPL Boundary Horn Puneri Dhol Tasha Beat',
      'Naatu Naatu RRR High Speed Dance Beat',
      'Jhoome Jo Pathaan Fast Chorus Beat',
      'Gallan Goodiyaan Fast Dhol Celebration',
    ],
    'WICKET_OUT': [
      'Vikram Rolex Theme Dark Wicket BGM',
      'KGF Garuda Theme Dark Villain BGM',
      'Animal Arjan Vailly Fierce Axe BGM',
      'Marco Unni Mukundan Violence BGM',
    ],
    'ENCOURAGE': [
      'Sultan Title Track Salman Khan Sukhwinder',
      'Chak De India Title Song Sukhwinder Singh',
      'Kar Har Maidan Fateh Sukhwinder Singh',
      'Zinda Bhaag Milkha Bhaag Siddharth Mahadevan',
      'Dheera Dheera KGF Chapter 1 Kannada',
      'Brothers Anthem Vishal Dadlani',
    ],
    'KANNADA_MASS': [
      'KGF Chapter 1 Dheera Dheera Kannada',
      'Tagaru Title Track Shiva Kannada Charan Raj',
      'Kantara Varaha Roopam Kannada Original',
      'Kaatera Pasandaagavne Kannada Mass Song',
      'Jackie Title Track Puneeth Rajkumar Kannada',
      'Raajakumara Appu Dance Kannada Song',
      'Ugramm Veeram Kannada Mass Song',
      'Max Kiccha Sudeep Maximum Mass Song',
    ],
  };

  /// Words that indicate slow, silent, karaoke, or non-entry tracks—automatically rejected!
  static const List<String> _rejectedWords = [
    'karaoke',
    'lullaby',
    'sad',
    'unplugged',
    'acoustic',
    'lofi',
    'lo-fi',
    'slowed',
    'sleep',
    'relaxing',
    'meditation',
    'piano version',
    'flute version',
    'dialogue only',
    'interview',
    'making of',
    'teaser review',
  ];

  static int _batchCursor = 0;

  static Future<void> loadSavedCues() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('entry_custom_cues_v24');
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
      await prefs.setString('entry_custom_cues_v24', jsonEncode(customSavedCueSeconds));
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

  /// Smart Dynamic Entry Beat/Drop Calculator (Replaces the bad fixed 15s cut!)
  /// Calculates exact start second for each track based on whether it is a pure BGM,
  /// an OST theme, or a full song with a known chorus drop.
  static int computeSmartEntryDropSecond(String id, String title, int durationSec) {
    // 1. User-locked custom cue point always wins
    if (customSavedCueSeconds.containsKey(id)) {
      return customSavedCueSeconds[id]!;
    }

    final String lower = title.toLowerCase();

    // 2. Pure BGM / Theme / Ringtone / Horn / OST (< 75 seconds) -> Start right at the impact!
    if (durationSec > 0 && durationSec <= 75) {
      return 0;
    }
    if (lower.contains('bgm') ||
        lower.contains('theme') ||
        lower.contains('ost') ||
        lower.contains('monster') ||
        lower.contains('rolex') ||
        lower.contains('trumpet') ||
        lower.contains('horn') ||
        lower.contains('walkout') ||
        lower.contains('intro')) {
      if (durationSec <= 130) return 2;
      return 5;
    }

    // 3. Famous Blockbuster Song Signature Cue Map (Starts right on the mass beat drop!)
    if (lower.contains('hukum')) return 19;
    if (lower.contains('sultan')) return 24;
    if (lower.contains('dheera')) return 21;
    if (lower.contains('varaha')) return 12;
    if (lower.contains('jamal kudu') || lower.contains('abrar')) return 0;
    if (lower.contains('arjan vailly')) return 14;
    if (lower.contains('vaathi coming')) return 8;
    if (lower.contains('vaathi raid')) return 4;
    if (lower.contains('badass')) return 16;
    if (lower.contains('fear song') || lower.contains('devara')) return 18;
    if (lower.contains('tagaru')) return 9;
    if (lower.contains('chak de')) return 18;
    if (lower.contains('saahore')) return 22;

    // 4. Smart Proportional Intro Trim for Full Movie Songs (> 130s)
    // Skips quiet 6-8s ambient studio logos without cutting into the main hook
    if (durationSec > 180) {
      return 8;
    }
    return 3;
  }

  static bool _isFamousAndHighEnergy(String title, String subtitle, int durSec, int playCount) {
    if (durSec > 0 && durSec < 15) return false; // Reject tiny broken clips
    final String combined = (title + ' ' + subtitle).toLowerCase();
    for (final bad in _rejectedWords) {
      if (combined.contains(bad)) return false;
    }
    // Reject obscure/unfamous uploads unless it's an explicit BGM/Theme track
    final bool isExplicitBgm = combined.contains('bgm') ||
        combined.contains('theme') ||
        combined.contains('ost') ||
        combined.contains('remix') ||
        combined.contains('kgf') ||
        combined.contains('salaar') ||
        combined.contains('vikram') ||
        combined.contains('hukum') ||
        combined.contains('kantara');
    if (!isExplicitBgm && playCount > 0 && playCount < 5000) {
      return false;
    }
    return true;
  }

  static Future<List<Map<String, dynamic>>> fetchEntryTracks({
    required String categoryKey,
    String? customQuery,
    bool loadNextBatch = false,
  }) async {
    await loadSavedCues();
    final List<Map<String, dynamic>> out = [];
    final Set<String> seenIds = {};

    List<String> queries = [];
    if (customQuery != null && customQuery.trim().isNotEmpty) {
      queries = [
        customQuery.trim() + ' BGM Theme',
        customQuery.trim() + ' Mass Song',
        customQuery.trim(),
      ];
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
            'https://www.jiosaavn.com/api.php?__call=search.getResults&_format=json&_marker=0&api_version=4&ctx=web6dot0&n=25&p=1&q=' +
                Uri.encodeComponent(q);
        final res = await http.get(Uri.parse(url), headers: headers).timeout(const Duration(seconds: 6));
        if (res.statusCode == 200) {
          final decoded = jsonDecode(res.body);
          final List results = decoded['results'] ?? [];
          for (final item in results) {
            final String id = (item['id'] ?? '').toString();
            if (id.isEmpty || seenIds.contains(id)) continue;

            final Map moreInfo = (item['more_info'] is Map) ? item['more_info'] : {};
            final String? encUrl = (moreInfo['encrypted_media_url'] ?? item['encrypted_media_url'])?.toString();
            final String? prevUrl = (moreInfo['vlink'] ?? item['media_preview_url'])?.toString();
            final int durSec = int.tryParse((moreInfo['duration'] ?? item['duration'] ?? '0').toString()) ?? 0;
            final int playCount =
                int.tryParse((item['play_count'] ?? moreInfo['play_count'] ?? '50000').toString()) ?? 50000;

            final String title = _cleanTitle((item['title'] ?? item['song'] ?? 'Entry BGM').toString());
            final String artist = _cleanTitle((item['subtitle'] ?? moreInfo['music'] ?? 'Mass BGM').toString());

            if (!_isFamousAndHighEnergy(title, artist, durSec, playCount)) continue;

            final List<String> urls = SaavnDesDecryptor.decryptToFullUrls(encUrl, prevUrl);
            if (urls.isEmpty) continue;

            seenIds.add(id);
            final String cover = (item['image'] ?? 'https://via.placeholder.com/150')
                .toString()
                .replaceAll('150x150', '500x500');

            final int smartDropSec = computeSmartEntryDropSecond(id, title, durSec);

            out.add({
              'id': id,
              'title': title,
              'artist': artist,
              'cover': cover,
              'urls': urls,
              'durationSec': durSec,
              'smartDropSec': smartDropSec,
              'playCount': playCount,
              'tag': categoryKey,
              'isOffline': false,
            });
          }
        }
      } catch (_) {}
    }

    // Sort by playCount descending so famous originals are always at the top
    out.sort((a, b) => ((b['playCount'] ?? 0) as int).compareTo((a['playCount'] ?? 0) as int));
    return out;
  }
}
