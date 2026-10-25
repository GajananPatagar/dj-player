import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'des_helper.dart';
import 'entry_music_data.dart';

class CustomTileClip {
  final String id;
  final String tileKey;
  final String language; // KANNADA, HINDI, ENGLISH
  final String title;
  final String filePath;
  final int startMs;
  final int endMs;

  CustomTileClip({
    required this.id,
    required this.tileKey,
    required this.language,
    required this.title,
    required this.filePath,
    required this.startMs,
    required this.endMs,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'tileKey': tileKey,
        'language': language,
        'title': title,
        'filePath': filePath,
        'startMs': startMs,
        'endMs': endMs,
      };

  factory CustomTileClip.fromJson(Map<String, dynamic> m) => CustomTileClip(
        id: (m['id'] ?? '').toString(),
        tileKey: (m['tileKey'] ?? 'SIX').toString(),
        language: (m['language'] ?? 'KANNADA').toString(),
        title: (m['title'] ?? 'Custom Clip').toString(),
        filePath: (m['filePath'] ?? '').toString(),
        startMs: int.tryParse((m['startMs'] ?? '0').toString()) ?? 0,
        endMs: int.tryParse((m['endMs'] ?? '10000').toString()) ?? 10000,
      );
}

class RealTileStudioManager {
  static const MethodChannel _nativeChannel = MethodChannel('dj_native_tts');
  static final AudioPlayer _realClipPlayer = AudioPlayer();
  static Timer? _trimCutTimer;

  static bool isRealAudioMode = false; // false = AI Commentary, true = User Real Audio Clips
  static List<CustomTileClip> allClips = [];
  static List<Map<String, dynamic>> userCustomTiles = [];
  static final Map<String, int> _rotationCursor = {};
  static bool _initialized = false;

  static final List<Map<String, dynamic>> extraBuiltInTiles = [
    {'key': 'NUDIMUTTU', 'title': '📜 ನುಡಿಮುತ್ತು', 'sub': 'NUDIMUTTU', 'color': 0xFF00695C, 'emotion': 'CRISP'},
    {'key': 'OTHERS', 'title': '✨ OTHERS', 'sub': 'SPECIAL CALL', 'color': 0xFF37474F, 'emotion': 'FAST'},
  ];

  static Future<void> init({Function(String sharedTextOrPath)? onSharedMediaReceived}) async {
    if (!_initialized) {
      _initialized = true;
      await loadSavedData();
      _nativeChannel.setMethodCallHandler((call) async {
        if (call.method == 'onSharedMedia' && call.arguments != null) {
          final String shared = call.arguments.toString();
          if (onSharedMediaReceived != null && shared.isNotEmpty) {
            onSharedMediaReceived(shared);
          }
        }
      });
    }
    try {
      final String? initialShared = await _nativeChannel.invokeMethod<String>('getInitialSharedMedia');
      if (initialShared != null && initialShared.isNotEmpty && onSharedMediaReceived != null) {
        onSharedMediaReceived(initialShared);
      }
    } catch (_) {}
  }

  static Future<void> loadSavedData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      isRealAudioMode = prefs.getBool('v307_is_real_mode') ?? false;
      final rawClips = prefs.getStringList('v307_custom_tile_clips') ?? [];
      allClips = rawClips
          .map((s) => CustomTileClip.fromJson(Map<String, dynamic>.from(jsonDecode(s))))
          .where((c) => File(c.filePath).existsSync())
          .toList();

      final rawTiles = prefs.getStringList('v307_user_custom_tiles') ?? [];
      userCustomTiles = rawTiles.map((s) => Map<String, dynamic>.from(jsonDecode(s))).toList();
    } catch (_) {}
  }

  static Future<void> setRealMode(bool val) async {
    isRealAudioMode = val;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('v307_is_real_mode', val);
    } catch (_) {}
  }

  static Future<void> saveClips() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        'v307_custom_tile_clips',
        allClips.map((c) => jsonEncode(c.toJson())).toList(),
      );
    } catch (_) {}
  }

  static Future<void> addCustomTile(String title, String subtitle, int colorHex) async {
    final String key = 'CUSTOM_${DateTime.now().millisecondsSinceEpoch}';
    userCustomTiles.add({
      'key': key,
      'title': title.trim(),
      'sub': subtitle.trim().isEmpty ? 'CUSTOM TILE' : subtitle.trim().toUpperCase(),
      'color': colorHex,
      'emotion': 'EXPLOSIVE',
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        'v307_user_custom_tiles',
        userCustomTiles.map((t) => jsonEncode(t)).toList(),
      );
    } catch (_) {}
  }

  static Future<void> deleteCustomTile(String key) async {
    userCustomTiles.removeWhere((t) => t['key'].toString() == key);
    allClips.removeWhere((c) => c.tileKey == key);
    await saveClips();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        'v307_user_custom_tiles',
        userCustomTiles.map((t) => jsonEncode(t)).toList(),
      );
    } catch (_) {}
  }

  static List<CustomTileClip> getClipsFor(String tileKey, String language) {
    final exact = allClips.where((c) => c.tileKey == tileKey && c.language == language).toList();
    if (exact.isNotEmpty) return exact;
    return allClips.where((c) => c.tileKey == tileKey).toList();
  }

  /// Plays the user's trimmed Real Audio Clip for this Tile + Language
  static Future<CustomTileClip?> playRealClipForTile(String tileKey, String language) async {
    final clips = getClipsFor(tileKey, language);
    if (clips.isEmpty) return null;

    final String cursorKey = '${tileKey}_$language';
    final int idx = (_rotationCursor[cursorKey] ?? 0) % clips.length;
    _rotationCursor[cursorKey] = idx + 1;

    final CustomTileClip clip = clips[idx];
    await playSpecificTrimmedClip(clip.filePath, clip.startMs, clip.endMs);
    return clip;
  }

  static Future<void> playSpecificTrimmedClip(String path, int startMs, int endMs) async {
    _trimCutTimer?.cancel();
    if (!File(path).existsSync()) return;

    final double vol = MasterVolumeController.page2VoiceVolume.value.clamp(0.1, 1.0);
    await _realClipPlayer.stop();
    await _realClipPlayer.setVolume(vol);
    await _realClipPlayer.play(
      DeviceFileSource(path),
      position: Duration(milliseconds: startMs.clamp(0, 3600000)),
    );

    final int playDurationMs = (endMs - startMs).clamp(500, 300000);
    _trimCutTimer = Timer(Duration(milliseconds: playDurationMs), () {
      _realClipPlayer.pause();
    });
  }

  static Future<void> stopRealPlayback() async {
    _trimCutTimer?.cancel();
    await _realClipPlayer.stop();
  }

  /// Generates AI speech for Nudimuttu, Others, or User Custom Tiles when in AI Mode
  static String generateExtraTileAiLine(String key, String title, String lang) {
    final Random rng = Random();
    if (key == 'NUDIMUTTU') {
      if (lang == 'KANNADA') {
        const lines = [
          'ನುಡಿಮುತ್ತು! | ಗೆಲುವು ಎಂದಿಗೂ ಶಾಶ್ವತವಲ್ಲ, ಸೋಲು ಎಂದಿಗೂ ಅಂತಿಮವಲ್ಲ! | ಪ್ರಯತ್ನ ನಿರಂತರವಾಗಿರಲಿ, ಯಶಸ್ಸು ನಿಮ್ಮದಾಗುತ್ತದೆ!',
          'ಇಂದಿನ ನುಡಿಮುತ್ತು! | ಕಠಿಣ ಪರಿಶ್ರಮಕ್ಕೆ ಪರ್ಯಾಯವಿಲ್ಲ! | ಬೆವರು ಸುರಿಸಿ ಆಡುವ ಆಟಗಾರನೇ ನಿಜವಾದ ಚಾಂಪಿಯನ್!',
          'ನುಡಿಮುತ್ತು! | ತಾಳ್ಮೆ ಮತ್ತು ಆತ್ಮವಿಶ್ವಾಸ ಇದ್ದರೆ ಎಂತಹ ಕಠಿಣ ಪಂದ್ಯವನ್ನೂ ಗೆಲ್ಲಬಹುದು! | ಕ್ರೀಡಾಸ್ಫೂರ್ತಿ ಸದಾ ಚಿರಾಯುವಾಗಿರಲಿ!',
          'ಮುತ್ತಿನಂತಹ ಮಾತು! | ಸೋತಾಗ ಕುಗ್ಗದೆ, ಗೆದ್ದಾಗ ಹಿಗ್ಗದೆ ಸಮಚಿತ್ತದಿಂದ ಮುನ್ನಡೆಯುವುದೇ ನಿಜವಾದ ಕ್ರೀಡಾ ಧರ್ಮ!',
          'ನುಡಿಮುತ್ತು! | ಗುರಿ ಮುಟ್ಟುವವರೆಗೂ ವಿಶ್ರಮಿಸಬೇಡಿ! | ಪ್ರತಿ ಎಸೆತವೂ ಹೊಸ ಅವಕಾಶವನ್ನು ತರುತ್ತದೆ!'
        ];
        return lines[rng.nextInt(lines.length)];
      } else if (lang == 'HINDI') {
        const lines = [
          'आज का सुविचार! | लहरों से डरकर नौका पार नहीं होती, कोशिश करने वालों की कभी हार नहीं होती!',
          'अनमोल वचन! | जीत और हार खेल का हिस्सा हैं, लेकिन आखिरी गेंद तक लड़ना ही असली चैंपियन की पहचान है!',
          'सुविचार! | मेहनत इतनी खामोशी से करो कि आपकी कामयाबी पूरे स्टेडियम में शोर मचा दे!'
        ];
        return lines[rng.nextInt(lines.length)];
      } else {
        const lines = [
          'Words of Wisdom! | Champions keep playing until they get it right! | Never give up on any ball!',
          'Golden Quote! | Hard work beats talent when talent fails to work hard! | What a spirit on the field!'
        ];
        return lines[rng.nextInt(lines.length)];
      }
    }
    return '$title! | ಮೈದಾನದಲ್ಲಿ ಅದ್ಭುತವಾದ ರೋಮಾಂಚನ! | ಪ್ರೇಕ್ಷಕರಿಂದ ಭರ್ಜರಿ ಚಪ್ಪಾಳೆ!';
  }

  /// Picks any Audio or Video file via Native Android Picker (auto-extracts audio if video!)
  static Future<String?> pickAndExtractFile({required bool isVideo}) async {
    try {
      return await _nativeChannel.invokeMethod<String>('pickMediaAndExtractAudio', {'isVideo': isVideo});
    } catch (_) {
      return null;
    }
  }

  /// Resolves Instagram Reels or YouTube Shorts shared URLs into a local audio file for trimming
  static Future<String?> extractAudioFromReelOrShortUrl(String rawInput) async {
    final String clean = rawInput.trim();
    // 1. If Android shared a direct file path, extract audio natively
    if (clean.startsWith('/') || clean.startsWith('content://')) {
      try {
        return await _nativeChannel.invokeMethod<String>('extractAudioFromUri', {'uri': clean});
      } catch (_) {}
    }

    // 2. Extract URL from shared text
    final RegExp urlReg = RegExp(r'https?://[^\s]+');
    final match = urlReg.firstMatch(clean);
    final String targetUrl = match != null ? match.group(0)! : clean;

    final dir = await getApplicationDocumentsDirectory();
    final String outPath = '${dir.path}/reel_short_${DateTime.now().millisecondsSinceEpoch}.m4a';

    // Tier A: If YouTube Short (youtube.com/shorts/ID or youtu.be/ID), extract via Piped Audio Streams
    String? ytVideoId;
    if (targetUrl.contains('shorts/')) {
      ytVideoId = targetUrl.split('shorts/').last.split('?').first.split('/').first;
    } else if (targetUrl.contains('youtu.be/')) {
      ytVideoId = targetUrl.split('youtu.be/').last.split('?').first;
    } else if (targetUrl.contains('v=')) {
      ytVideoId = targetUrl.split('v=').last.split('&').first;
    }

    if (ytVideoId != null && ytVideoId.isNotEmpty) {
      const pipedNodes = [
        'https://pipedapi.kavin.rocks',
        'https://pipedapi.tokhmi.xyz',
        'https://pipedapi.moomoo.me',
      ];
      for (final node in pipedNodes) {
        try {
          final res = await http.get(Uri.parse('$node/streams/$ytVideoId')).timeout(const Duration(seconds: 6));
          if (res.statusCode == 200) {
            final data = jsonDecode(res.body);
            final List audioStreams = data['audioStreams'] ?? [];
            if (audioStreams.isNotEmpty) {
              final String streamUrl = audioStreams.first['url'].toString();
              final audioRes = await http.get(Uri.parse(streamUrl)).timeout(const Duration(seconds: 25));
              if (audioRes.statusCode == 200 && audioRes.bodyBytes.length > 10000) {
                final f = File(outPath);
                await f.writeAsBytes(audioRes.bodyBytes, flush: true);
                return f.path;
              }
            }
          }
        } catch (_) {}
      }
    }

    // Tier B: Try page metadata title extraction -> fetch matching 320kbps audio stream
    String extractedTitle = '';
    try {
      final pageRes = await http.get(
        Uri.parse(targetUrl),
        headers: {'User-Agent': 'Mozilla/5.0 (Android 14; Mobile)'},
      ).timeout(const Duration(seconds: 5));
      if (pageRes.statusCode == 200) {
        // Check for direct og:video mp4 inside Instagram Reel page
        final RegExp ogVideo = RegExp(r'property=\"og:video\" content=\"([^\"]+)\"');
        final vMatch = ogVideo.firstMatch(pageRes.body);
        if (vMatch != null) {
          final String videoUrl = vMatch.group(1)!.replaceAll('&amp;', '&');
          final vBytesRes = await http.get(Uri.parse(videoUrl)).timeout(const Duration(seconds: 20));
          if (vBytesRes.statusCode == 200 && vBytesRes.bodyBytes.length > 15000) {
            final tempVid = File('${dir.path}/temp_reel.mp4');
            await tempVid.writeAsBytes(vBytesRes.bodyBytes, flush: true);
            final String? strippedAudio = await _nativeChannel.invokeMethod<String>(
              'extractAudioFromUri',
              {'uri': tempVid.path},
            );
            return strippedAudio ?? tempVid.path;
          }
        }
        final RegExp titleReg = RegExp(r'<title>(.*?)</title>', caseSensitive: false);
        final tMatch = titleReg.firstMatch(pageRes.body);
        if (tMatch != null) {
          extractedTitle = tMatch
              .group(1)!
              .replaceAll('- YouTube', '')
              .replaceAll('on Instagram', '')
              .replaceAll('#shorts', '')
              .replaceAll('#reels', '')
              .replaceAll(RegExp(r'[^\w\s]'), ' ')
              .trim();
        }
      }
    } catch (_) {}

    final String fallbackSearch = extractedTitle.isNotEmpty ? extractedTitle : 'Funk Criminal Bass Boosted';
    try {
      final String sUrl =
          'https://www.jiosaavn.com/api.php?__call=search.getResults&_format=json&_marker=0&api_version=4&ctx=web6dot0&n=5&p=1&q=' +
              Uri.encodeComponent(fallbackSearch);
      final sRes = await http.get(Uri.parse(sUrl)).timeout(const Duration(seconds: 6));
      if (sRes.statusCode == 200) {
        final decoded = jsonDecode(sRes.body);
        final List results = decoded['results'] ?? [];
        if (results.isNotEmpty) {
          final item = results.first;
          final Map moreInfo = (item['more_info'] is Map) ? item['more_info'] : {};
          final String? encUrl = (moreInfo['encrypted_media_url'] ?? item['encrypted_media_url'])?.toString();
          final List<String> urls = SaavnDesDecryptor.decryptToFullUrls(encUrl, null, has320: true);
          if (urls.isNotEmpty) {
            final dl = await http.get(Uri.parse(urls.first)).timeout(const Duration(seconds: 25));
            if (dl.statusCode == 200 && dl.bodyBytes.length > 20000) {
              final f = File(outPath);
              await f.writeAsBytes(dl.bodyBytes, flush: true);
              return f.path;
            }
          }
        }
      }
    } catch (_) {}
    return null;
  }

  /// Opens the 5-Second Hold Modal Dialog to View, Play, and Delete Custom Clips for a Tile
  static void show5SecHoldTileClipsDialog(
    BuildContext context,
    Map<String, dynamic> tile,
    String currentLanguage,
    VoidCallback onUpdated,
  ) {
    final String tileKey = tile['key'].toString();
    final String tileTitle = tile['title'].toString();

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0D1526),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final tileClips = allClips.where((c) => c.tileKey == tileKey).toList();
            return Padding(
              padding: const EdgeInsets.all(14.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          '🎵 Saved Real Audios for [$tileTitle] (${tileClips.length})',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF00E5FF),
                          ),
                        ),
                      ),
                      if (tileKey.startsWith('CUSTOM_'))
                        TextButton.icon(
                          icon: const Icon(Icons.delete_forever, color: Colors.redAccent, size: 18),
                          label: const Text('Delete Tile', style: TextStyle(color: Colors.redAccent, fontSize: 11)),
                          onPressed: () async {
                            await deleteCustomTile(tileKey);
                            onUpdated();
                            if (ctx.mounted) Navigator.pop(ctx);
                          },
                        ),
                    ],
                  ),
                  const Divider(color: Colors.white24),
                  if (tileClips.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(20.0),
                      child: Center(
                        child: Text(
                          'No custom Real audios added to this tile yet.\nUse the Studio Adder below to Record, Upload Audio/Video, or Share Reels/Shorts!',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12, color: Colors.white70),
                        ),
                      ),
                    )
                  else
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: tileClips.length,
                        itemBuilder: (_, i) {
                          final clip = tileClips[i];
                          final String startStr = (clip.startMs / 1000).toStringAsFixed(1);
                          final String endStr = (clip.endMs / 1000).toStringAsFixed(1);
                          return Card(
                            color: const Color(0xFF162238),
                            child: ListTile(
                              dense: true,
                              leading: const Icon(Icons.audiotrack, color: Colors.amberAccent),
                              title: Text(
                                clip.title,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                              ),
                              subtitle: Text(
                                '${clip.language} • Trimmed: ${startStr}s ➔ ${endStr}s',
                                style: const TextStyle(fontSize: 10, color: Color(0xFF00E676)),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.play_circle_fill, color: Color(0xFF00E5FF)),
                                    onPressed: () =>
                                        playSpecificTrimmedClip(clip.filePath, clip.startMs, clip.endMs),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                                    onPressed: () async {
                                      allClips.removeWhere((c) => c.id == clip.id);
                                      await saveClips();
                                      setModalState(() {});
                                      onUpdated();
                                    },
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
