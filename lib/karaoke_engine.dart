import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'des_helper.dart';

class LyricLine {
  final int timeMs;
  final String text;
  LyricLine({required this.timeMs, required this.text});
}

class KaraokeTake {
  final String id;
  final String songTitle;
  final String songArtist;
  final String coverUrl;
  final String backingStreamUrl;
  final String vocalFilePath;
  final String presetName;
  final double vocalPitch;
  final bool doubleChoirEnabled;
  final int syncOffsetMs;

  KaraokeTake({
    required this.id,
    required this.songTitle,
    required this.songArtist,
    required this.coverUrl,
    required this.backingStreamUrl,
    required this.vocalFilePath,
    required this.presetName,
    required this.vocalPitch,
    required this.doubleChoirEnabled,
    required this.syncOffsetMs,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'songTitle': songTitle,
        'songArtist': songArtist,
        'coverUrl': coverUrl,
        'backingStreamUrl': backingStreamUrl,
        'vocalFilePath': vocalFilePath,
        'presetName': presetName,
        'vocalPitch': vocalPitch,
        'doubleChoirEnabled': doubleChoirEnabled,
        'syncOffsetMs': syncOffsetMs,
      };

  factory KaraokeTake.fromJson(Map<String, dynamic> m) => KaraokeTake(
        id: (m['id'] ?? '').toString(),
        songTitle: (m['songTitle'] ?? 'Recorded Song').toString(),
        songArtist: (m['songArtist'] ?? 'Artist').toString(),
        coverUrl: (m['coverUrl'] ?? '').toString(),
        backingStreamUrl: (m['backingStreamUrl'] ?? '').toString(),
        vocalFilePath: (m['vocalFilePath'] ?? '').toString(),
        presetName: (m['presetName'] ?? 'Auto-Tune Pro').toString(),
        vocalPitch: double.tryParse((m['vocalPitch'] ?? '1.0').toString()) ?? 1.0,
        doubleChoirEnabled: m['doubleChoirEnabled'] == true,
        syncOffsetMs: int.tryParse((m['syncOffsetMs'] ?? '-60').toString()) ?? -60,
      );
}

class KaraokeEngine {
  static List<KaraokeTake> savedTakes = [];

  static Future<void> loadSavedTakes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList('v300_karaoke_takes') ?? [];
      savedTakes = raw
          .map((s) => KaraokeTake.fromJson(Map<String, dynamic>.from(jsonDecode(s))))
          .where((t) => File(t.vocalFilePath).existsSync())
          .toList();
    } catch (_) {}
  }

  static Future<void> saveTake(KaraokeTake take) async {
    savedTakes.removeWhere((t) => t.id == take.id);
    savedTakes.insert(0, take);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        'v300_karaoke_takes',
        savedTakes.map((t) => jsonEncode(t.toJson())).toList(),
      );
    } catch (_) {}
  }

  static Future<void> deleteTake(String id) async {
    savedTakes.removeWhere((t) => t.id == id);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        'v300_karaoke_takes',
        savedTakes.map((t) => jsonEncode(t.toJson())).toList(),
      );
    } catch (_) {}
  }

  static String _cleanStr(String s) {
    return s
        .replaceAll('&quot;', '"')
        .replaceAll('&amp;', '&')
        .replaceAll('&#039;', "'")
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .trim();
  }

  static bool _detectInstrumentalOrKaraoke(String title, String artist) {
    final String combined = '$title $artist'.toLowerCase();
    return combined.contains('karaoke') ||
        combined.contains('instrumental') ||
        combined.contains('backing track') ||
        combined.contains('minus one') ||
        combined.contains('without vocal') ||
        combined.contains('no vocal') ||
        combined.contains('sing along');
  }

  /// Strips "Karaoke", "Instrumental", "Backing Track", etc. so LRCLIB & JioSaavn find the exact original song lyrics!
  static String cleanSongTitleForLyricsLookup(String rawTitle) {
    String s = rawTitle;
    s = s.replaceAll(RegExp(r'\(.*?\)|\[.*?\]'), ' ');
    s = s.replaceAll(
      RegExp(
        r'\b(karaoke|instrumental|backing\s*track|without\s*vocals?|minus\s*one|sing\s*along|version|cover|with\s*lyrics|originally\s*performed\s*by|tribute\s*to)\b',
        caseSensitive: false,
      ),
      ' ',
    );
    if (s.contains(' - ')) {
      s = s.split(' - ').first;
    }
    return s.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Multi-Engine Karaoke & Instrumental Harvester:
  /// Fetches Dedicated Pure Karaoke / Instrumental Backing Tracks FIRST + Original Tracks with AI Vocal-Cut Support,
  /// and automatically pairs every song with a matched Pure Instrumental URL if one exists in the search pool!
  static Future<List<Map<String, dynamic>>> searchSongsForKaraoke(String query) async {
    final String cleanQ = query.trim().isEmpty ? 'Kannada Hindi Superhit Songs' : query.trim();
    final List<Map<String, dynamic>> pureInstrumentals = [];
    final List<Map<String, dynamic>> aiVocalCutSongs = [];
    final Set<String> seenIds = {};
    final Set<String> seenFp = {};

    final Map<String, String> headers = {
      'User-Agent': 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/124.0 Mobile Safari/537.36',
      'Accept': 'application/json, text/plain, */*',
    };

    final List<String> subQueries = [
      '$cleanQ Karaoke',
      '$cleanQ Instrumental',
      '$cleanQ Karaoke Backing Track',
      cleanQ,
    ];

    // Run all queries in parallel for < 1.2s speed!
    final List<Future<http.Response?>> futures = subQueries.map((q) {
      final String url =
          'https://www.jiosaavn.com/api.php?__call=search.getResults&_format=json&_marker=0&api_version=4&ctx=web6dot0&n=35&p=1&q=${Uri.encodeComponent(q)}';
      return http
          .get(Uri.parse(url), headers: headers)
          .timeout(const Duration(seconds: 6))
          .then<http.Response?>((v) => v)
          .catchError((_) => null);
    }).toList();

    // Also query iTunes Global Karaoke Catalog in parallel (huge library of true Karaoke minus-one tracks!)
    final String itunesKaraokeUrl =
        'https://itunes.apple.com/search?media=music&entity=song&limit=25&term=${Uri.encodeComponent('$cleanQ karaoke')}';
    futures.add(
      http
          .get(Uri.parse(itunesKaraokeUrl))
          .timeout(const Duration(seconds: 5))
          .then<http.Response?>((v) => v)
          .catchError((_) => null),
    );

    final List<http.Response?> responses = await Future.wait(futures);

    // Map from base song title -> pure instrumental stream URLs so even normal songs can auto-swap to pure instrumental audio!
    final Map<String, List<String>> baseTitleToInstrumentalUrls = {};

    for (final res in responses) {
      if (res == null || res.statusCode != 200) continue;
      try {
        final dynamic decoded = jsonDecode(res.body);
        if (decoded is! Map) continue;

        final List results = (decoded['results'] as List?) ?? [];
        for (final item in results) {
          if (item is! Map) continue;

          // Check if iTunes Karaoke result
          if (item.containsKey('trackId') && item.containsKey('previewUrl')) {
            final String id = 'it_kar_${item['trackId']}';
            final String? prev = item['previewUrl']?.toString();
            if (prev == null || !prev.startsWith('http') || seenIds.contains(id)) continue;
            seenIds.add(id);

            final String title = _cleanStr((item['trackName'] ?? 'Karaoke Track').toString());
            final String artist = _cleanStr((item['artistName'] ?? 'Karaoke Backing Band').toString());
            final int durSec = ((item['trackTimeMillis'] ?? 180000) as num).toInt() ~/ 1000;
            final String cover = (item['artworkUrl100'] ?? '')
                .toString()
                .replaceAll('100x100bb', '500x500bb');

            final String baseClean = cleanSongTitleForLyricsLookup(title).toLowerCase();
            if (baseClean.length >= 3) {
              baseTitleToInstrumentalUrls[baseClean] = [prev];
            }

            pureInstrumentals.add({
              'id': id,
              'title': title,
              'cleanLyricsTitle': cleanSongTitleForLyricsLookup(title),
              'artist': artist,
              'cover': cover,
              'urls': [prev],
              'instrumentalUrls': [prev],
              'durationSec': durSec,
              'isPureInstrumental': true,
            });
            continue;
          }

          // JioSaavn result
          final String id = (item['id'] ?? '').toString();
          if (id.isEmpty || seenIds.contains(id)) continue;

          final Map moreInfo = (item['more_info'] is Map) ? item['more_info'] : {};
          final String title = _cleanStr((item['title'] ?? item['song'] ?? 'Song').toString());
          final String subtitle = _cleanStr((item['subtitle'] ?? moreInfo['music'] ?? 'Artist').toString());
          final int durSec = int.tryParse((moreInfo['duration'] ?? item['duration'] ?? '180').toString()) ?? 180;
          if (durSec < 35) continue;

          final bool isInstrumental = _detectInstrumentalOrKaraoke(title, subtitle);
          final String fp = SaavnDesDecryptor.canonicalFingerprint(title, subtitle);
          final String dedupKey = isInstrumental ? '${fp}_inst' : fp;
          if (seenFp.contains(dedupKey)) continue;

          final String? encUrl = (moreInfo['encrypted_media_url'] ?? item['encrypted_media_url'])?.toString();
          final String? prevUrl = (moreInfo['vlink'] ?? item['media_preview_url'])?.toString();
          final bool has320 = (moreInfo['320kbps']?.toString() != 'false');
          final List<String> urls = SaavnDesDecryptor.decryptToFullUrls(encUrl, prevUrl, has320: has320);
          if (urls.isEmpty) continue;

          seenIds.add(id);
          seenFp.add(dedupKey);

          final String cover = (item['image'] ?? 'https://via.placeholder.com/300')
              .toString()
              .replaceAll('150x150', '500x500');
          final String cleanForLrc = cleanSongTitleForLyricsLookup(title);

          if (isInstrumental && cleanForLrc.length >= 3) {
            baseTitleToInstrumentalUrls[cleanForLrc.toLowerCase()] = urls;
          }

          final Map<String, dynamic> songMap = {
            'id': id,
            'title': title,
            'cleanLyricsTitle': cleanForLrc,
            'artist': subtitle,
            'cover': cover,
            'urls': urls,
            'instrumentalUrls': isInstrumental ? urls : <String>[],
            'durationSec': durSec,
            'isPureInstrumental': isInstrumental,
          };

          if (isInstrumental) {
            pureInstrumentals.add(songMap);
          } else {
            aiVocalCutSongs.add(songMap);
          }
        }
      } catch (_) {}
    }

    // Link any matching pure instrumental stream onto normal songs so AI Vocal-Cut can use pure instrumental backing automatically!
    for (final s in aiVocalCutSongs) {
      final String key = (s['cleanLyricsTitle'] ?? '').toString().toLowerCase();
      if (baseTitleToInstrumentalUrls.containsKey(key)) {
        s['instrumentalUrls'] = baseTitleToInstrumentalUrls[key]!;
        s['hasMatchedInstrumental'] = true;
      }
    }

    // Always place Pure Karaoke / Instrumental tracks first, followed by AI Vocal-Cut songs!
    return [...pureInstrumentals, ...aiVocalCutSongs];
  }

  /// Fetches time-synced LRC lyrics using cleaned base song title (strips "Karaoke"/"Instrumental" so lyrics always match!)
  static Future<List<LyricLine>> fetchSyncedLyrics(
    String songId,
    String title,
    String artist,
    int durationSec,
  ) async {
    final String cleanTitle = cleanSongTitleForLyricsLookup(title);
    final String firstArtist = cleanSongTitleForLyricsLookup(artist.split(',').first.trim());
    String movieName = '';
    final RegExp movieReg = RegExp(r'"([^"]+)"');
    final mMatch = movieReg.firstMatch(title);
    if (mMatch != null) movieName = mMatch.group(1) ?? '';

    final List<String> searchQueries = [
      if (cleanTitle.isNotEmpty) cleanTitle,
      if (movieName.isNotEmpty && cleanTitle.isNotEmpty) '$cleanTitle $movieName',
      if (cleanTitle.isNotEmpty && firstArtist.isNotEmpty) '$cleanTitle $firstArtist',
      if (cleanTitle.split(' ').length >= 2) cleanTitle.split(' ').take(2).join(' '),
    ];

    // 1. Try LRCLIB Time-Synced LRC API
    for (final sq in searchQueries) {
      try {
        final uri = Uri.parse('https://lrclib.net/api/search?q=${Uri.encodeComponent(sq)}');
        final res = await http.get(uri).timeout(const Duration(seconds: 5));
        if (res.statusCode == 200) {
          final List list = jsonDecode(res.body);
          for (final item in list) {
            final String? synced = item['syncedLyrics']?.toString();
            if (synced != null && synced.trim().isNotEmpty) {
              final parsed = _parseLrcString(synced);
              if (parsed.length >= 4) return parsed;
            }
          }
          for (final item in list) {
            final String? plain = item['plainLyrics']?.toString();
            if (plain != null && plain.trim().isNotEmpty) {
              return _distributePlainLyricsOverTime(plain, durationSec);
            }
          }
        }
      } catch (_) {}
    }

    // 2A. Try Saavn.dev Lyrics Mirror
    if (!songId.startsWith('it_')) {
      try {
        final resMirror = await http
            .get(Uri.parse('https://saavn.dev/api/songs/$songId/lyrics'))
            .timeout(const Duration(seconds: 4));
        if (resMirror.statusCode == 200) {
          final Map b = jsonDecode(resMirror.body);
          final String? lyr = b['data']?['lyrics']?.toString();
          if (lyr != null && lyr.trim().length > 20) {
            final String cleaned = lyr
                .replaceAll('<br>', '\n')
                .replaceAll('<br/>', '\n')
                .replaceAll(RegExp(r'<[^>]*>'), '');
            return _distributePlainLyricsOverTime(cleaned, durationSec);
          }
        }
      } catch (_) {}

      // 2B. Try Official JioSaavn Lyrics Endpoint
      try {
        final String sUrl =
            'https://www.jiosaavn.com/api.php?__call=lyrics.getLyrics&ctx=web6dot0&api_version=4&_format=json&_marker=0&lyrics_id=${Uri.encodeComponent(songId)}';
        final sRes = await http.get(Uri.parse(sUrl)).timeout(const Duration(seconds: 4));
        if (sRes.statusCode == 200) {
          final Map data = jsonDecode(sRes.body);
          final String? rawLyrics = data['lyrics']?.toString();
          if (rawLyrics != null && rawLyrics.trim().isNotEmpty) {
            final String cleanPlain = rawLyrics
                .replaceAll('<br>', '\n')
                .replaceAll('<br/>', '\n')
                .replaceAll(RegExp(r'<[^>]*>'), '');
            return _distributePlainLyricsOverTime(cleanPlain, durationSec);
          }
        }
      } catch (_) {}
    }

    // 2C. If the user selected a Pure Instrumental track whose ID didn't have lyrics attached,
    // search JioSaavn for the original song's ID by cleanTitle and fetch its lyrics!
    if (cleanTitle.isNotEmpty) {
      try {
        final String lookupUrl =
            'https://www.jiosaavn.com/api.php?__call=search.getResults&_format=json&_marker=0&api_version=4&ctx=web6dot0&n=5&p=1&q=${Uri.encodeComponent(cleanTitle)}';
        final lRes = await http.get(Uri.parse(lookupUrl)).timeout(const Duration(seconds: 4));
        if (lRes.statusCode == 200) {
          final Map lData = jsonDecode(lRes.body);
          final List results = (lData['results'] as List?) ?? [];
          for (final item in results) {
            final String candId = (item['id'] ?? '').toString();
            if (candId.isEmpty) continue;
            final String sUrl =
                'https://www.jiosaavn.com/api.php?__call=lyrics.getLyrics&ctx=web6dot0&api_version=4&_format=json&_marker=0&lyrics_id=${Uri.encodeComponent(candId)}';
            final sRes = await http.get(Uri.parse(sUrl)).timeout(const Duration(seconds: 3));
            if (sRes.statusCode == 200) {
              final Map data = jsonDecode(sRes.body);
              final String? rawLyrics = data['lyrics']?.toString();
              if (rawLyrics != null && rawLyrics.trim().length > 20) {
                final String cleanPlain = rawLyrics
                    .replaceAll('<br>', '\n')
                    .replaceAll('<br/>', '\n')
                    .replaceAll(RegExp(r'<[^>]*>'), '');
                return _distributePlainLyricsOverTime(cleanPlain, durationSec);
              }
            }
          }
        }
      } catch (_) {}
    }

    // 3. Smart Beat-Synced Stage Teleprompter Fallback
    return _buildSmartStagePrompter(cleanTitle.isEmpty ? title : cleanTitle, firstArtist, durationSec);
  }

  static List<LyricLine> _parseLrcString(String lrc) {
    final List<LyricLine> lines = [];
    final RegExp reg = RegExp(r'\[(\d+):(\d+(?:\.\d+)?)\](.*)');
    for (final rawLine in lrc.split('\n')) {
      final match = reg.firstMatch(rawLine);
      if (match != null) {
        final int mins = int.tryParse(match.group(1) ?? '0') ?? 0;
        final double secs = double.tryParse(match.group(2) ?? '0') ?? 0.0;
        final String txt = (match.group(3) ?? '').trim();
        if (txt.isNotEmpty) {
          lines.add(LyricLine(timeMs: (mins * 60000) + (secs * 1000).toInt(), text: txt));
        }
      }
    }
    return lines;
  }

  static List<LyricLine> _distributePlainLyricsOverTime(String plain, int durationSec) {
    final List<String> rawLines = plain
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (rawLines.isEmpty) return [];
    final int totalMs = (durationSec > 30 ? durationSec - 10 : 150) * 1000;
    final int stepMs = (totalMs ~/ rawLines.length).clamp(2500, 6500);
    final List<LyricLine> out = [
      LyricLine(timeMs: 0, text: '🎵 [Karaoke Instrumental Intro — Get Ready to Sing!] 🎵'),
    ];
    for (int i = 0; i < rawLines.length; i++) {
      out.add(LyricLine(timeMs: 3500 + (i * stepMs), text: rawLines[i]));
    }
    return out;
  }

  static List<LyricLine> _buildSmartStagePrompter(String title, String artist, int durationSec) {
    final List<LyricLine> out = [
      LyricLine(timeMs: 0, text: '🎧 Karaoke Stage Ready: $title'),
      LyricLine(timeMs: 3500, text: '🎤 Style: $artist — Feel the Rhythm & Sing on Cue!'),
    ];
    final int totalSec = durationSec > 40 ? durationSec : 180;
    for (int s = 8; s < totalSec; s += 8) {
      out.add(LyricLine(
        timeMs: s * 1000,
        text: '🎶 $title — Lead Vocal Cue (${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}) 🎶',
      ));
    }
    return out;
  }

  static String formatLineForLanguageMode(String line, String scriptMode) {
    if (scriptMode == 'KANGLISH (ಕನ್ನಡ-Eng)') {
      return _transliterateNativeToRoman(line);
    } else if (scriptMode == 'HINGLISH (हिन्दी-Eng)') {
      return _transliterateNativeToRoman(line);
    } else if (scriptMode == 'KANNADA (ಕನ್ನಡ)') {
      return _romanPhoneticToKannadaHint(line);
    } else if (scriptMode == 'HINDI (हिन्दी)') {
      return _romanPhoneticToHindiHint(line);
    }
    return line;
  }

  static String _transliterateNativeToRoman(String input) {
    const Map<String, String> knToRom = {
      'ಅ': 'a', 'ಆ': 'aa', 'ಇ': 'i', 'ಈ': 'ee', 'ಉ': 'u', 'ಊ': 'oo', 'ಎ': 'e', 'ಏ': 'e', 'ಐ': 'ai',
      'ಒ': 'o', 'ಓ': 'o', 'ಔ': 'au', 'ಕ': 'ka', 'ಖ': 'kha', 'ಗ': 'ga', 'ಘ': 'gha', 'ಚ': 'cha',
      'ಛ': 'chha', 'ಜ': 'ja', 'ಟ': 'ta', 'ಡ': 'da', 'ಣ': 'na', 'ತ': 'tha', 'ದ': 'da', 'ಧ': 'dha',
      'ನ': 'na', 'ಪ': 'pa', 'ಫ': 'pha', 'ಬ': 'ba', 'ಭ': 'bha', 'ಮ': 'ma', 'ಯ': 'ya', 'ರ': 'ra',
      'ಲ': 'la', 'ವ': 'va', 'ಶ': 'sha', 'ಷ': 'sha', 'ಸ': 'sa', 'ಹ': 'ha', 'ಳ': 'la',
      'ಾ': 'aa', 'ಿ': 'i', 'ೀ': 'ee', 'ು': 'u', 'ೂ': 'oo', 'ೆ': 'e', 'ೇ': 'e', 'ೈ': 'ai',
      'ೊ': 'o', 'ೋ': 'o', 'ೌ': 'au', '್': '', 'ಂ': 'm', 'ಃ': 'h',
      'अ': 'a', 'आ': 'aa', 'इ': 'i', 'ई': 'ee', 'उ': 'u', 'ऊ': 'oo', 'ए': 'e', 'ऐ': 'ai', 'ओ': 'o',
      'क': 'ka', 'ख': 'kha', 'ग': 'ga', 'घ': 'gha', 'च': 'cha', 'ज': 'ja', 'ट': 'ta', 'ड': 'da',
      'त': 'ta', 'थ': 'tha', 'द': 'da', 'ध': 'dha', 'न': 'na', 'प': 'pa', 'फ': 'pha', 'ब': 'ba',
      'भ': 'bha', 'म': 'ma', 'य': 'ya', 'र': 'ra', 'ल': 'la', 'व': 'va', 'श': 'sha', 'स': 'sa',
      'ह': 'ha', 'ा': 'aa', 'ि': 'i', 'ी': 'ee', 'ु': 'u', 'ू': 'oo', 'े': 'e', 'ै': 'ai',
      'ो': 'o', 'ौ': 'au', '्': '', 'ं': 'n',
    };
    final StringBuffer sb = StringBuffer();
    for (int i = 0; i < input.length; i++) {
      final String ch = input[i];
      sb.write(knToRom[ch] ?? ch);
    }
    return sb.toString();
  }

  static String _romanPhoneticToKannadaHint(String input) {
    String out = input;
    const Map<String, String> commonWords = {
      'ninna': 'ನಿನ್ನ', 'nanna': 'ನನ್ನ', 'preethi': 'ಪ್ರೀತಿ', 'manasu': 'ಮನಸು',
      'kanasu': 'ಕನಸು', 'jeeva': 'ಜೀವ', 'hrudaya': 'ಹೃದಯ', 'baare': 'ಬಾರೆ',
      'geleya': 'ಗೆಳೆಯ', 'kannada': 'ಕನ್ನಡ', 'raaja': 'ರಾಜ', 'rani': 'ರಾಣಿ',
    };
    commonWords.forEach((en, kn) {
      out = out.replaceAll(RegExp('\\b$en\\b', caseSensitive: false), '$en ($kn)');
    });
    return out;
  }

  static String _romanPhoneticToHindiHint(String input) {
    String out = input;
    const Map<String, String> commonWords = {
      'dil': 'दिल', 'pyaar': 'प्यार', 'ishq': 'इश्क़', 'zindagi': 'ज़िंदगी',
      'tera': 'तेरा', 'mera': 'मेरा', 'sanam': 'सनम', 'duniya': 'दुनिया',
    };
    commonWords.forEach((en, hi) {
      out = out.replaceAll(RegExp('\\b$en\\b', caseSensitive: false), '$en ($hi)');
    });
    return out;
  }
}
