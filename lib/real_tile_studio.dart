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
import 'entry_music_data.dart';
import 'main.dart';

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
  static final AudioPlayer realClipPlayer = AudioPlayer();
  static Timer? _trimCutTimer;

  static bool isRealAudioMode = false; // false = AI Mode, true = STRICT Real Audio Mode (0 AI Voice!)
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
      isRealAudioMode = prefs.getBool('v308_is_real_mode') ?? false;
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
    if (val) {
      // Immediately silence any AI TTS when switching to REAL mode!
      await AppSoundEngine.panicMuteAll();
    } else {
      await stopRealPlayback();
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('v308_is_real_mode', val);
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
    await realClipPlayer.stop();
    await realClipPlayer.setVolume(vol);
    await realClipPlayer.play(
      DeviceFileSource(path),
      position: Duration(milliseconds: startMs.clamp(0, 3600000)),
    );

    final int playDurationMs = (endMs - startMs).clamp(300, 300000);
    _trimCutTimer = Timer(Duration(milliseconds: playDurationMs), () {
      realClipPlayer.pause();
    });
  }

  static Future<void> stopRealPlayback() async {
    _trimCutTimer?.cancel();
    await realClipPlayer.stop();
  }

  static String generateExtraTileAiLine(String key, String title, String lang) {
    final Random rng = Random();
    if (key == 'NUDIMUTTU') {
      if (lang == 'KANNADA') {
        const lines = [
          'ನುಡಿಮುತ್ತು! | ಗೆಲುವು ಎಂದಿಗೂ ಶಾಶ್ವತವಲ್ಲ, ಸೋಲು ಎಂದಿಗೂ ಅಂತಿಮವಲ್ಲ! | ಪ್ರಯತ್ನ ನಿರಂತರವಾಗಿರಲಿ, ಯಶಸ್ಸು ನಿಮ್ಮದಾಗುತ್ತದೆ!',
          'ಇಂದಿನ ನುಡಿಮುತ್ತು! | ಕಠಿಣ ಪರಿಶ್ರಮಕ್ಕೆ ಪರ್ಯಾಯವಿಲ್ಲ! | ಬೆವರು ಸುರಿಸಿ ಆಡುವ ಆಟಗಾರನೇ ನಿಜವಾದ ಚಾಂಪಿಯನ್!',
          'ನುಡಿಮುತ್ತು! | ತಾಳ್ಮೆ ಮತ್ತು ಆತ್ಮವಿಶ್ವಾಸ ಇದ್ದರೆ ಎಂತಹ ಕಠಿಣ ಪಂದ್ಯವನ್ನೂ ಗೆಲ್ಲಬಹುದು! | ಕ್ರೀಡಾಸ್ಫೂರ್ತಿ ಸದಾ ಚಿರಾಯುವಾಗಿರಲಿ!'
        ];
        return lines[rng.nextInt(lines.length)];
      } else if (lang == 'HINDI') {
        const lines = [
          'आज का सुविचार! | लहरों से डरकर नौका पार नहीं होती, कोशिश करने वालों की कभी हार नहीं होती!',
          'अनमोल वचन! | जीत और हार खेल का हिस्सा हैं, लेकिन आखिरी गेंद तक लड़ना ही असली चैंपियन की पहचान है!'
        ];
        return lines[rng.nextInt(lines.length)];
      } else {
        const lines = [
          'Words of Wisdom! | Champions keep playing until they get it right! | Never give up on any ball!'
        ];
        return lines[rng.nextInt(lines.length)];
      }
    }
    return '$title! | ಮೈದಾನದಲ್ಲಿ ಅದ್ಭುತವಾದ ರೋಮಾಂಚನ! | ಪ್ರೇಕ್ಷಕರಿಂದ ಭರ್ಜರಿ ಚಪ್ಪಾಳೆ!';
  }

  static Future<String?> pickAndExtractFile({required bool isVideo}) async {
    try {
      return await _nativeChannel.invokeMethod<String>('pickMediaAndExtractAudio', {'isVideo': isVideo});
    } catch (_) {
      return null;
    }
  }

  /// Compute 64-Bar Real Audio Spectrum Waveform from the audio file's byte amplitude peaks
  static Future<List<double>> computeAudioSpectrumBars(String filePath, int barCount) async {
    try {
      final File f = File(filePath);
      if (!await f.exists()) return List<double>.filled(barCount, 0.4);
      final Uint8List bytes = await f.readAsBytes();
      if (bytes.length < 1024) return List<double>.filled(barCount, 0.5);

      // Skip MP4/M4A header container box (~first 5%)
      final int startOffset = (bytes.length * 0.05).toInt();
      final int usableLength = bytes.length - startOffset;
      final int chunkSize = max(1, usableLength ~/ barCount);
      final List<double> bars = [];

      double maxEnergy = 0.01;
      for (int b = 0; b < barCount; b++) {
        final int chunkStart = startOffset + (b * chunkSize);
        final int step = max(1, chunkSize ~/ 80);
        double sumDiff = 0;
        int samples = 0;
        for (int i = chunkStart; i < chunkStart + chunkSize - step && i < bytes.length - step; i += step) {
          sumDiff += (bytes[i] - bytes[i + step]).abs();
          samples++;
        }
        final double avg = samples > 0 ? (sumDiff / samples) : 20.0;
        if (avg > maxEnergy) maxEnergy = avg;
        bars.add(avg);
      }

      return bars.map((e) => (e / maxEnergy).clamp(0.12, 1.0)).toList();
    } catch (_) {
      return List<double>.filled(barCount, 0.5);
    }
  }

  /// EXACT Instagram Reels & YouTube Shorts Audio Extractor (NEVER falls back to random songs!)
  static Future<String?> extractAudioFromReelOrShortUrl(String rawInput) async {
    final String clean = rawInput.trim();
    if (clean.isEmpty) return null;

    // 1. Direct local file or content:// URI shared from gallery/apps
    if (clean.startsWith('/') || clean.startsWith('content://')) {
      try {
        return await _nativeChannel.invokeMethod<String>('extractAudioFromUri', {'uri': clean});
      } catch (_) {}
    }

    final RegExp urlReg = RegExp(r'https?://[^\s]+');
    final match = urlReg.firstMatch(clean);
    final String targetUrl = match != null ? match.group(0)! : clean;

    final dir = await getApplicationDocumentsDirectory();
    final int ts = DateTime.now().millisecondsSinceEpoch;
    final String outAudioPath = '${dir.path}/exact_reel_short_$ts.m4a';
    final String tempVideoPath = '${dir.path}/temp_video_$ts.mp4';

    // =========================================================================
    // PATH A: INSTAGRAM REELS / POSTS (instagram.com/reel/... or /reels/... or /p/...)
    // =========================================================================
    if (targetUrl.contains('instagram.com') || targetUrl.contains('instagr.am')) {
      String? shortcode;
      final RegExp igReg = RegExp(r'(?:reel|reels|p|tv)/([A-Za-z0-9_-]+)');
      final igMatch = igReg.firstMatch(targetUrl);
      if (igMatch != null) shortcode = igMatch.group(1);

      final List<String> candidateVideoUrls = [];

      // Method 1: VXInstagram / DDInstagram JSON & Direct Video Resolver
      if (shortcode != null && shortcode.isNotEmpty) {
        for (final apiHost in ['https://api.vxinstagram.com', 'https://ddinstagram.com']) {
          try {
            final res = await http.get(
              Uri.parse('$apiHost/reel/$shortcode'),
              headers: {'User-Agent': 'TelegramBot (like TwitterBot)', 'Accept': 'application/json, text/html'},
            ).timeout(const Duration(seconds: 7));
            if (res.statusCode == 200) {
              final RegExp mp4Reg = RegExp(r'https?://[^\s"<>\\]+\.mp4[^\s"<>\\]*');
              for (final m in mp4Reg.allMatches(res.body)) {
                final String u = m.group(0)!.replaceAll(r'\/', '/').replaceAll('&amp;', '&');
                if (!candidateVideoUrls.contains(u)) candidateVideoUrls.add(u);
              }
            }
          } catch (_) {}
        }

        // Method 2: Instagram Public /embed/captioned/ Endpoint (Exposes video_url without login!)
        try {
          final embedUrl = 'https://www.instagram.com/p/$shortcode/embed/captioned/';
          final embedRes = await http.get(
            Uri.parse(embedUrl),
            headers: {
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/124.0.0.0 Safari/537.36',
              'Accept': 'text/html,application/xhtml+xml',
            },
          ).timeout(const Duration(seconds: 8));
          if (embedRes.statusCode == 200) {
            final String body = embedRes.body;
            final RegExp vUrlReg = RegExp(r'"video_url"\s*:\s*"([^"]+)"');
            for (final m in vUrlReg.allMatches(body)) {
              final String rawV = m
                  .group(1)!
                  .replaceAll(r'\/', '/')
                  .replaceAll(r'\u0026', '&')
                  .replaceAll('&amp;', '&');
              if (rawV.startsWith('http') && !candidateVideoUrls.contains(rawV)) {
                candidateVideoUrls.add(rawV);
              }
            }
            final RegExp ogVid = RegExp(r'property="og:video(?::secure_url)?"\s+content="([^"]+)"');
            for (final m in ogVid.allMatches(body)) {
              final String rawV = m.group(1)!.replaceAll('&amp;', '&');
              if (rawV.startsWith('http') && !candidateVideoUrls.contains(rawV)) {
                candidateVideoUrls.add(rawV);
              }
            }
          }
        } catch (_) {}
      }

      // Download the extracted Reel .mp4 and strip its exact audio track using Android MediaExtractor
      for (final vidUrl in candidateVideoUrls) {
        try {
          final vRes = await http.get(
            Uri.parse(vidUrl),
            headers: {'User-Agent': 'Mozilla/5.0 (Android 14; Mobile)'},
          ).timeout(const Duration(seconds: 25));
          if (vRes.statusCode == 200 && vRes.bodyBytes.length > 15000) {
            final File vf = File(tempVideoPath);
            await vf.writeAsBytes(vRes.bodyBytes, flush: true);
            final String? strippedAudio = await _nativeChannel.invokeMethod<String>(
              'extractAudioFromUri',
              {'uri': vf.path},
            );
            return strippedAudio ?? vf.path;
          }
        } catch (_) {}
      }
    }

    // =========================================================================
    // PATH B: YOUTUBE SHORTS / VIDEOS (youtube.com/shorts/... or youtu.be/...)
    // =========================================================================
    String? ytVideoId;
    if (targetUrl.contains('shorts/')) {
      ytVideoId = targetUrl.split('shorts/').last.split('?').first.split('/').first;
    } else if (targetUrl.contains('youtu.be/')) {
      ytVideoId = targetUrl.split('youtu.be/').last.split('?').first.split('/').first;
    } else if (targetUrl.contains('v=')) {
      ytVideoId = targetUrl.split('v=').last.split('&').first;
    }

    if (ytVideoId != null && ytVideoId.isNotEmpty) {
      // Method 1: Direct YouTube Innertube Player API (ANDROID_VR / IOS Client returns direct audio/mp4 stream!)
      final List<Map<String, dynamic>> clients = [
        {
          'clientName': 'ANDROID_VR',
          'clientVersion': '1.56.21',
          'androidSdkVersion': 34,
          'userAgent': 'com.google.android.apps.youtube.vr.oculus/1.56.21 (Linux; U; Android 14) gzip',
        },
        {
          'clientName': 'IOS',
          'clientVersion': '19.29.1',
          'deviceMake': 'Apple',
          'deviceModel': 'iPhone16,2',
          'userAgent': 'com.google.ios.youtube/19.29.1 (iPhone16,2; U; CPU iOS 17_5_1 like Mac OS X;)',
        },
      ];

      for (final c in clients) {
        try {
          final res = await http
              .post(
                Uri.parse('https://www.youtube.com/youtubei/v1/player?prettyPrint=false'),
                headers: {
                  'Content-Type': 'application/json',
                  'User-Agent': c['userAgent'].toString(),
                },
                body: jsonEncode({
                  'videoId': ytVideoId,
                  'context': {
                    'client': {
                      'clientName': c['clientName'],
                      'clientVersion': c['clientVersion'],
                      'hl': 'en',
                      'gl': 'IN',
                    }
                  },
                  'contentCheckOk': true,
                  'racyCheckOk': true,
                }),
              )
              .timeout(const Duration(seconds: 8));

          if (res.statusCode == 200) {
            final Map data = jsonDecode(res.body);
            final Map? streamingData = data['streamingData'] as Map?;
            if (streamingData != null) {
              final List adaptive = (streamingData['adaptiveFormats'] as List?) ?? [];
              final List formats = (streamingData['formats'] as List?) ?? [];

              // Prefer m4a audio stream (itag 140) first
              String? bestAudioUrl;
              for (final f in adaptive) {
                final String mime = (f['mimeType'] ?? '').toString();
                final String? u = f['url']?.toString();
                if (u != null && mime.startsWith('audio/mp4')) {
                  bestAudioUrl = u;
                  break;
                }
              }
              bestAudioUrl ??= adaptive
                  .where((f) => (f['mimeType'] ?? '').toString().startsWith('audio/') && f['url'] != null)
                  .map((f) => f['url'].toString())
                  .firstOrNull;
              bestAudioUrl ??= formats
                  .where((f) => f['url'] != null)
                  .map((f) => f['url'].toString())
                  .firstOrNull;

              if (bestAudioUrl != null) {
                final audioRes = await http.get(
                  Uri.parse(bestAudioUrl),
                  headers: {'User-Agent': c['userAgent'].toString()},
                ).timeout(const Duration(seconds: 25));
                if (audioRes.statusCode == 200 && audioRes.bodyBytes.length > 10000) {
                  final File af = File(outAudioPath);
                  await af.writeAsBytes(audioRes.bodyBytes, flush: true);
                  return af.path;
                }
              }
            }
          }
        } catch (_) {}
      }

      // Method 2: Active Piped & Invidious Mirrors
      const mirrors = [
        'https://pipedapi.adminforge.de',
        'https://pipedapi.smnz.de',
        'https://pipedapi.kavin.rocks',
        'https://inv.tux.pizza/api/v1/videos',
      ];
      for (final node in mirrors) {
        try {
          final String apiUrl =
              node.contains('/api/v1/videos') ? '$node/$ytVideoId' : '$node/streams/$ytVideoId';
          final res = await http.get(Uri.parse(apiUrl)).timeout(const Duration(seconds: 6));
          if (res.statusCode == 200) {
            final data = jsonDecode(res.body);
            final List streams = (data['audioStreams'] ?? data['adaptiveFormats'] ?? []) as List;
            for (final s in streams) {
              final String? u = s['url']?.toString();
              if (u != null && u.startsWith('http')) {
                final aRes = await http.get(Uri.parse(u)).timeout(const Duration(seconds: 20));
                if (aRes.statusCode == 200 && aRes.bodyBytes.length > 10000) {
                  final File af = File(outAudioPath);
                  await af.writeAsBytes(aRes.bodyBytes, flush: true);
                  return af.path;
                }
              }
            }
          }
        } catch (_) {}
      }
    }

    return null;
  }

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
                          'No custom Real audios added to this tile yet.\nUse the Trimmer Studio below to Record, Upload Song/Video, or Share Reels/Shorts!',
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

/// Interactive 64-Bar Audio Spectrum Waveform Painter with Live Playhead & Trim Window
class AudioSpectrumPainter extends CustomPainter {
  final List<double> bars;
  final double trimStartSec;
  final double trimEndSec;
  final double currentPlaySec;
  final double totalDurationSec;

  AudioSpectrumPainter({
    required this.bars,
    required this.trimStartSec,
    required this.trimEndSec,
    required this.currentPlaySec,
    required this.totalDurationSec,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double safeTotal = totalDurationSec <= 0.1 ? 30.0 : totalDurationSec;
    final double startRatio = (trimStartSec / safeTotal).clamp(0.0, 1.0);
    final double endRatio = (trimEndSec / safeTotal).clamp(0.0, 1.0);
    final double playRatio = (currentPlaySec / safeTotal).clamp(0.0, 1.0);

    // 1. Highlight Selected Trim Region Background
    final Paint regionPaint = Paint()
      ..color = const Color(0xFF00E676).withOpacity(0.14)
      ..style = PaintingStyle.fill;
    canvas.drawRect(
      Rect.fromLTRB(size.width * startRatio, 0, size.width * endRatio, size.height),
      regionPaint,
    );

    // 2. Draw 64 Audio Spectrum Bars
    final int n = bars.isEmpty ? 1 : bars.length;
    final double barSlotWidth = size.width / n;
    final double barWidth = (barSlotWidth * 0.68).clamp(2.0, 10.0);

    for (int i = 0; i < n; i++) {
      final double barPosRatio = (i + 0.5) / n;
      final bool isInsideTrim = barPosRatio >= startRatio && barPosRatio <= endRatio;
      final bool isPassedByPlayhead = barPosRatio >= startRatio && barPosRatio <= playRatio;

      final Paint barPaint = Paint()
        ..color = isPassedByPlayhead
            ? Colors.amberAccent
            : (isInsideTrim ? const Color(0xFF00E676) : Colors.white24)
        ..strokeCap = StrokeCap.round
        ..strokeWidth = barWidth;

      final double amp = bars[i].clamp(0.12, 1.0);
      final double halfH = (size.height * 0.44) * amp;
      final double centerY = size.height * 0.5;
      final double x = i * barSlotWidth + (barSlotWidth / 2);

      canvas.drawLine(Offset(x, centerY - halfH), Offset(x, centerY + halfH), barPaint);
    }

    // 3. Draw Start & End Trim Handles
    final Paint handlePaint = Paint()
      ..color = Colors.cyanAccent
      ..strokeWidth = 2.5;
    canvas.drawLine(Offset(size.width * startRatio, 0), Offset(size.width * startRatio, size.height), handlePaint);
    canvas.drawLine(Offset(size.width * endRatio, 0), Offset(size.width * endRatio, size.height), handlePaint);

    // 4. Draw Live Moving Playhead Line
    final Paint playheadPaint = Paint()
      ..color = Colors.redAccent
      ..strokeWidth = 2.8;
    final double px = size.width * playRatio;
    canvas.drawLine(Offset(px, 0), Offset(px, size.height), playheadPaint);
    canvas.drawCircle(Offset(px, 6), 5, playheadPaint);
  }

  @override
  bool shouldRepaint(covariant AudioSpectrumPainter oldDelegate) => true;
}
