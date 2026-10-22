import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
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
        syncOffsetMs: int.tryParse((m['syncOffsetMs'] ?? '0').toString()) ?? 0,
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

  /// Searches any song worldwide + fetches both Original Track (for AI Vocal-Cut) and Instrumental if available
  static Future<List<Map<String, dynamic>>> searchSongsForKaraoke(String query) async {
    final String cleanQ = query.trim().isEmpty ? 'Kannada Hindi Latest Hit Songs' : query.trim();
    final List<Map<String, dynamic>> out = [];
    final Set<String> seenFp = {};

    final Map<String, String> headers = {
      'User-Agent': 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/124.0 Mobile Safari/537.36',
      'Accept': 'application/json, text/plain, */*',
    };

    final List<String> subQueries = [
      cleanQ,
      '$cleanQ Karaoke Instrumental',
    ];

    for (final q in subQueries) {
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
            if (id.isEmpty) continue;

            final Map moreInfo = (item['more_info'] is Map) ? item['more_info'] : {};
            final String title = _cleanStr((item['title'] ?? item['song'] ?? 'Song').toString());
            final String subtitle = _cleanStr((item['subtitle'] ?? moreInfo['music'] ?? 'Artist').toString());
            final int durSec = int.tryParse((moreInfo['duration'] ?? item['duration'] ?? '0').toString()) ?? 0;
            if (durSec < 45) continue;

            final String fp = SaavnDesDecryptor.canonicalFingerprint(title);
            final bool isInstrumental = title.toLowerCase().contains('karaoke') ||
                title.toLowerCase().contains('instrumental');
            final String dedupKey = isInstrumental ? '${fp}_inst' : fp;
            if (seenFp.contains(dedupKey)) continue;

            final String? encUrl = (moreInfo['encrypted_media_url'] ?? item['encrypted_media_url'])?.toString();
            final bool has320 = (moreInfo['320kbps']?.toString() == 'true');
            final List<String> urls = SaavnDesDecryptor.decryptToFullUrls(encUrl, null, has320: has320);
            if (urls.isEmpty) continue;

            seenFp.add(dedupKey);
            final String cover = (item['image'] ?? 'https://via.placeholder.com/150')
                .toString()
                .replaceAll('150x150', '500x500');

            out.add({
              'id': id,
              'title': title,
              'artist': subtitle,
              'cover': cover,
              'urls': urls,
              'durationSec': durSec,
              'isPureInstrumental': isInstrumental,
            });
          }
        }
      } catch (_) {}
    }
    return out;
  }

  /// Fetches time-synced LRC lyrics from LRCLIB + JioSaavn Lyrics API fallback
  static Future<List<LyricLine>> fetchSyncedLyrics(
    String songId,
    String title,
    String artist,
    int durationSec,
  ) async {
    final String cleanTitle = title.replaceAll(RegExp(r'\(.*?\)|\[.*?\]'), '').trim();
    final String firstArtist = artist.split(',').first.trim();

    // 1. Try LRCLIB Time-Synced LRC API
    final List<String> searchQueries = [
      '$cleanTitle $firstArtist',
      cleanTitle,
    ];

    for (final sq in searchQueries) {
      try {
        final uri = Uri.parse('https://lrclib.net/api/search?q=' + Uri.encodeComponent(sq));
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

    // 2. Try Official JioSaavn Lyrics Endpoint
    try {
      final String sUrl =
          'https://www.jiosaavn.com/api.php?__call=lyrics.getLyrics&ctx=web6dot0&api_version=4&_format=json&_marker=0&lyrics_id=' +
              Uri.encodeComponent(songId);
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

    // 3. Smart Beat-Synced Stage Teleprompter Fallback (Guarantees 0 Empty Lyrics Screens!)
    return _buildSmartStagePrompter(cleanTitle, firstArtist, durationSec);
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
    final int stepMs = (totalMs ~/ rawLines.length).clamp(2500, 7000);
    final List<LyricLine> out = [
      LyricLine(timeMs: 0, text: '🎵 [Instrumental Intro — Get Ready to Sing!] 🎵'),
    ];
    for (int i = 0; i < rawLines.length; i++) {
      out.add(LyricLine(timeMs: 4000 + (i * stepMs), text: rawLines[i]));
    }
    return out;
  }

  static List<LyricLine> _buildSmartStagePrompter(String title, String artist, int durationSec) {
    final List<LyricLine> out = [
      LyricLine(timeMs: 0, text: '🎧 Karaoke Stage Ready: $title'),
      LyricLine(timeMs: 4000, text: '🎤 Original Style: $artist — Sing on the Beat!'),
    ];
    final int totalSec = durationSec > 40 ? durationSec : 180;
    for (int s = 8; s < totalSec; s += 8) {
      out.add(LyricLine(
        timeMs: s * 1000,
        text: '🎶 $title — Sing Verse / Chorus Hook (${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}) 🎶',
      ));
    }
    return out;
  }

  /// Converts lyrics line into English/Kanglish/Hinglish/Kannada/Hindi script for easy reading
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

  /// Converts Kannada or Devanagari Unicode characters into readable Kanglish/Hinglish Roman script
  static String _transliterateNativeToRoman(String input) {
    const Map<String, String> knToRom = {
      'ಅ': 'a', 'ಆ': 'aa', 'ಇ': 'i', 'ಈ': 'ee', 'ಉ': 'u', 'ಊ': 'oo', 'ಎ': 'e', 'ಏ': 'e', 'ಐ': 'ai',
      'ಒ': 'o', 'ಓ': 'o', 'ಔ': 'au', 'ಕ': 'ka', 'ಖ': 'kha', 'ಗ': 'ga', 'ಘ': 'gha', 'ಚ': 'cha',
      'ಛ': 'chha', 'ಜ': 'ja', 'ಟ': 'ta', 'ಡ': 'da', 'ಣ': 'na', 'ತ': 'tha', 'ದ': 'da', 'ಧ': 'dha',
      'ನ': 'na', 'ಪ': 'pa', 'ಫ': 'pha', 'ಬ': 'ba', 'ಭ': 'bha', 'ಮ': 'ma', 'ಯ': 'ya', 'ರ': 'ra',
      'ಲ': 'la', 'ವ': 'va', 'ಶ': 'sha', 'ಷ': 'sha', 'ಸ': 'sa', 'ಹ': 'ha', 'ಳ': 'la',
      'ಾ': 'aa', 'ಿ': 'i', 'ೀ': 'ee', 'ು': 'u', 'ೂ': 'oo', 'ೆ': 'e', 'ೇ': 'e', 'ೈ': 'ai',
      'ೊ': 'o', 'ೋ': 'o', 'ೌ': 'au', '್': '', 'ಂ': 'm', 'ಃ': 'h',
      // Devanagari to Hinglish
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
