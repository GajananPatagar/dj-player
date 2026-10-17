import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'des_helper.dart';

/// Global Master Volume Controller shared across all 4 pages
class MasterVolumeController {
  static final ValueNotifier<double> page1MusicVolume = ValueNotifier<double>(1.0);
  static final ValueNotifier<double> page2VoiceVolume = ValueNotifier<double>(1.0);
  static final ValueNotifier<double> page3SfxVolume = ValueNotifier<double>(0.55);
  static final ValueNotifier<double> page4EntryVolume = ValueNotifier<double>(0.0);
}

/// Auto-Extracts 1000+ High-Bass Entry, Walkout, Sixer, Four, Out & Encourage Tracks Online
class EntryMusicHarvester {
  static final Map<String, List<String>> categorySeedQueries = {
    'ALL_1000': [
      'KGF Chapter 2 Monster BGM Theme',
      'Salaar Cease Fire Bgm Ost',
      'Vikram Rolex Entry BGM Anirudh',
      'Jailer Hukum Tiger Ka Hukum BGM',
      'Kantara Varaha Roopam Mass BGM',
      'Animal Abrars Entry Jamal Kudu BGM',
      'IPL Stadium Trumpet Horn Remix',
      'Pushpa The Rule Mass Entry BGM',
      'Kalki 2898 AD Theme BGM',
      'Leo Badass Mass Entry BGM',
      'BaahubaliWKKB King Entry Theme',
      'Devara Fear Song Mass BGM',
      'Marco Blood Theme High Bass BGM',
      'UI Movie Troll Song Kannada BGM',
      'Max Kiccha Sudeep Mass BGM',
      'Bagheera Kannada Mass Entry Theme',
    ],
    'HERO_ENTRY': [
      'KGF Rocky Bhai Entry Theme BGM',
      'Salaar Prabhas Walkout Theme BGM',
      'Vikram Once Upon A Time BGM',
      'Master Vaathi Raid Mass BGM',
      'KGF Garbha Dheera Dheera BGM',
      'Petta Paraak Mass Entry Theme',
    ],
    'SIXER_DROP': [
      'IPL Sixer Horn Stadium Bass Boosted Remix',
      'Monster Bass Drop EDM Festival Remix',
      'T20 Cricket Boundary Sixer Celebration DJ',
      'Dhol Tasha Bass Drop DJ Remix',
    ],
    'FOUR_HORN': [
      'Cricket Boundary Trumpet Fanfare Remix',
      'Stadium Brass Horn Celebration Beat',
      'IPL Four Boundary Sound Effect Remix',
      'Fast Puneri Dhol Stadium Beat',
    ],
    'WICKET_OUT': [
      'Vikram Rolex Danger Wicket BGM',
      'Coffin Dance Astronomia Bass Remix',
      'KGF Villain Garuda Entry Dark BGM',
      'Animal Ranvijay Fierce Theme BGM',
    ],
    'ENCOURAGE': [
      'Sultan Title Track Workout Mass Song',
      'Chak De India Victory Stadium Anthem',
      'Kar Har Maidan Fateh Sanju Anthem',
      'Brothers Anthem Vishal Dadlani High Bass',
      'Dheera Dheera KGF Motivational Song',
      'Zinda Bhaag Milkha Bhaag Energetic',
    ],
    'KANNADA_MASS': [
      'Tagaru Shiva Mass Kannada BGM Charan Raj',
      'Kaatera Darshan Mass Entry Theme Song',
      'KGF Kannada Dheera Dheera Full Song',
      'Kantara Kannada Singara Siriye Varaha',
      'Bheema Duniya Vijay Bad Boys Kannada BGM',
      'Jackie Puneeth Rajkumar Mass Kannada Song',
      'Yuva Rajkumar Title Track Kannada Mass',
      'Ugramm Veeram Kannada Mass Theme BGM',
    ],
  };

  static int _batchCursor = 0;

  static String _cleanTitle(String raw) {
    return raw
        .replaceAll('&quot;', '"')
        .replaceAll('&amp;', '&')
        .replaceAll('&#039;', "'")
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .trim();
  }

  /// Harvests high-bass entry tracks from official endpoints + daily trending seed
  static Future<List<Map<String, dynamic>>> fetchEntryTracks({
    required String categoryKey,
    String? customQuery,
    bool loadNextBatch = false,
  }) async {
    final List<Map<String, dynamic>> out = [];
    final Set<String> seenIds = {};

    final DateTime now = DateTime.now();
    final String dailySeed = '2026';

    List<String> queries = [];
    if (customQuery != null && customQuery.trim().isNotEmpty) {
      queries = [
        customQuery.trim() + ' BGM Theme',
        customQuery.trim() + ' High Bass Remix',
        customQuery.trim() + ' Entry Song',
      ];
    } else {
      final List<String> pool = categorySeedQueries[categoryKey] ?? categorySeedQueries['ALL_1000']!;
      if (loadNextBatch) {
        _batchCursor = (_batchCursor + 3) % pool.length;
      } else {
        _batchCursor = (now.day + now.hour) % pool.length;
      }
      for (int i = 0; i < 4; i++) {
        queries.add(pool[(_batchCursor + i) % pool.length]);
      }
      queries.add('Trending Mass Entry BGM ' + dailySeed);
    }

    final Map<String, String> headers = {
      'User-Agent': 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/124.0 Mobile Safari/537.36',
      'Accept': 'application/json, text/plain, */*',
    };

    for (final q in queries) {
      try {
        final String url =
            'https://www.jiosaavn.com/api.php?__call=search.getResults&_format=json&_marker=0&api_version=4&ctx=web6dot0&n=35&p=1&q=' +
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

            final List<String> urls = SaavnDesDecryptor.decryptToFullUrls(encUrl, prevUrl);
            if (urls.isEmpty) continue;

            seenIds.add(id);
            final String title = _cleanTitle((item['title'] ?? item['song'] ?? 'Entry BGM').toString());
            final String artist = _cleanTitle((item['subtitle'] ?? moreInfo['music'] ?? 'Bass Boosted BGM').toString());
            final String cover = (item['image'] ?? 'https://via.placeholder.com/150')
                .toString()
                .replaceAll('150x150', '500x500');

            out.add({
              'id': id,
              'title': title,
              'artist': artist,
              'cover': cover,
              'urls': urls,
              'durationSec': durSec,
              'tag': categoryKey,
            });
          }
        }
      } catch (_) {}
    }
    return out;
  }
}
