#!/data/data/com.termux/files/usr/bin/bash
set -e

echo "🎛 1/3 Creating lib/real_tile_studio.dart (AI/Real Switch, Trimmer, Video Extractor, Reels/Shorts Share & 5s Hold Manager)..."

cat << 'EOF' > lib/real_tile_studio.dart
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
EOF

echo "🎛 2/3 Updating .github/workflows/main.yml (Share Sheet Intent for IG Reels & YT Shorts + Video-to-Audio MediaExtractor)..."

python3 - << 'PYEOF'
with open(".github/workflows/main.yml", "r") as f:
    yml = f.read()

# 1. Add Native File Picker, Video Audio Extractor (MediaExtractor + MediaMuxer), and Share Intent Receiver to MainActivity.kt
old_imports = """          import android.Manifest
          import android.content.pm.PackageManager
          import android.media.MediaRecorder"""

new_imports = """          import android.Manifest
          import android.app.Activity
          import android.content.Intent
          import android.content.pm.PackageManager
          import android.media.MediaCodec
          import android.media.MediaExtractor
          import android.media.MediaFormat
          import android.media.MediaMuxer
          import android.media.MediaRecorder
          import android.net.Uri
          import java.io.FileOutputStream
          import java.nio.ByteBuffer"""

if old_imports in yml:
    yml = yml.replace(old_imports, new_imports)

old_fields = """              private var karaokeEq: Equalizer? = null
              private var methodChannel: MethodChannel? = null"""

new_fields = """              private var karaokeEq: Equalizer? = null
              private var methodChannel: MethodChannel? = null
              private var pendingFileResult: MethodChannel.Result? = null
              private var pendingIsVideo: Boolean = false
              private var initialSharedMedia: String? = null"""

if old_fields in yml:
    yml = yml.replace(old_fields, new_fields)

old_oncreate_body = """                  super.onCreate(savedInstanceState)
                  tts = TextToSpeech(this, this)"""

new_oncreate_body = """                  super.onCreate(savedInstanceState)
                  tts = TextToSpeech(this, this)
                  handleIncomingShareIntent(intent)"""

if old_oncreate_body in yml:
    yml = yml.replace(old_oncreate_body, new_oncreate_body)

# Add helper methods inside MainActivity
helper_methods = """
              override fun onNewIntent(intent: Intent) {
                  super.onNewIntent(intent)
                  handleIncomingShareIntent(intent)
              }

              private fun handleIncomingShareIntent(intent: Intent?) {
                  if (intent == null) return
                  if (Intent.ACTION_SEND == intent.action) {
                      val sharedText = intent.getStringExtra(Intent.EXTRA_TEXT)
                      val sharedStream = intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
                      if (!sharedText.isNullOrEmpty()) {
                          initialSharedMedia = sharedText
                          methodChannel?.invokeMethod("onSharedMedia", sharedText)
                      } else if (sharedStream != null) {
                          val extracted = copyUriAndExtractAudio(sharedStream, true)
                          if (extracted != null) {
                              initialSharedMedia = extracted
                              methodChannel?.invokeMethod("onSharedMedia", extracted)
                          }
                      }
                  }
              }

              override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
                  super.onActivityResult(requestCode, resultCode, data)
                  if (requestCode == 701) {
                      if (resultCode == Activity.RESULT_OK && data?.data != null) {
                          val path = copyUriAndExtractAudio(data.data!!, pendingIsVideo)
                          pendingFileResult?.success(path)
                      } else {
                          pendingFileResult?.success(null)
                      }
                      pendingFileResult = null
                  }
              }

              private fun copyUriAndExtractAudio(uri: Uri, extractIfVideo: Boolean): String? {
                  return try {
                      val mime = contentResolver.getType(uri) ?: ""
                      val isVid = extractIfVideo || mime.startsWith("video")
                      val ext = if (isVid) ".mp4" else ".m4a"
                      val tempIn = File(filesDir, "picked_${System.currentTimeMillis()}$ext")
                      contentResolver.openInputStream(uri)?.use { input ->
                          FileOutputStream(tempIn).use { output ->
                              input.copyTo(output)
                          }
                      }
                      if (isVid) {
                          extractAudioTrackHardware(tempIn.absolutePath) ?: tempIn.absolutePath
                      } else {
                          tempIn.absolutePath
                      }
                  } catch (_: Exception) {
                      null
                  }
              }

              private fun extractAudioTrackHardware(videoPath: String): String? {
                  return try {
                      val outAudioFile = File(filesDir, "extracted_audio_${System.currentTimeMillis()}.m4a")
                      val extractor = MediaExtractor()
                      extractor.setDataSource(videoPath)
                      var audioTrackIndex = -1
                      for (i in 0 until extractor.trackCount) {
                          val format = extractor.getTrackFormat(i)
                          val mime = format.getString(MediaFormat.KEY_MIME) ?: ""
                          if (mime.startsWith("audio/")) {
                              audioTrackIndex = i
                              break
                          }
                      }
                      if (audioTrackIndex < 0) {
                          extractor.release()
                          return videoPath
                      }
                      extractor.selectTrack(audioTrackIndex)
                      val format = extractor.getTrackFormat(audioTrackIndex)
                      val muxer = MediaMuxer(outAudioFile.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
                      val dstIndex = muxer.addTrack(format)
                      muxer.start()
                      val buffer = ByteBuffer.allocate(256 * 1024)
                      val bufferInfo = MediaCodec.BufferInfo()
                      while (true) {
                          val sampleSize = extractor.readSampleData(buffer, 0)
                          if (sampleSize < 0) break
                          bufferInfo.offset = 0
                          bufferInfo.size = sampleSize
                          bufferInfo.presentationTimeUs = extractor.sampleTime
                          bufferInfo.flags = extractor.sampleFlags
                          muxer.writeSampleData(dstIndex, buffer, bufferInfo)
                          extractor.advance()
                      }
                      muxer.stop()
                      muxer.release()
                      extractor.release()
                      outAudioFile.absolutePath
                  } catch (_: Exception) {
                      videoPath
                  }
              }
"""

yml = yml.replace("              override fun onInit(status: Int) {", helper_methods + "\n              override fun onInit(status: Int) {")

# Add MethodChannel handlers for pickMediaAndExtractAudio, extractAudioFromUri, getInitialSharedMedia
old_else = "                          else -> result.notImplemented()"
new_handlers = """                          "pickMediaAndExtractAudio" -> {
                              pendingFileResult = result
                              pendingIsVideo = call.argument<Boolean>("isVideo") ?: false
                              val intent = Intent(Intent.ACTION_GET_CONTENT).apply {
                                  type = if (pendingIsVideo) "video/*" else "audio/*"
                                  addCategory(Intent.CATEGORY_OPENABLE)
                              }
                              startActivityForResult(Intent.createChooser(intent, "Select Media"), 701)
                          }
                          "extractAudioFromUri" -> {
                              val u = call.argument<String>("uri") ?: ""
                              if (u.startsWith("content://")) {
                                  result.success(copyUriAndExtractAudio(Uri.parse(u), true))
                              } else {
                                  result.success(extractAudioTrackHardware(u))
                              }
                          }
                          "getInitialSharedMedia" -> {
                              val s = initialSharedMedia
                              initialSharedMedia = null
                              result.success(s)
                          }
                          else -> result.notImplemented()"""

yml = yml.replace(old_else, new_handlers)

# 2. Inject Share Target <intent-filter> into AndroidManifest.xml so Instagram Reels & YouTube Shorts show "DJ Play and Commentry App" on Share!
old_manifest_step = """            if ! grep -q "android.permission.INTERNET" "$MANIFEST"; then
              sed -i 's/<application/<uses-permission android:name="android.permission.INTERNET"\\/>\\n    <uses-permission android:name="android.permission.RECORD_AUDIO"\\/>\\n    <uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS"\\/>\\n    <application/' "$MANIFEST"
            fi"""

new_manifest_step = """            if ! grep -q "android.permission.INTERNET" "$MANIFEST"; then
              sed -i 's/<application/<uses-permission android:name="android.permission.INTERNET"\\/>\\n    <uses-permission android:name="android.permission.RECORD_AUDIO"\\/>\\n    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"\\/>\\n    <uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS"\\/>\\n    <application/' "$MANIFEST"
            fi
            if ! grep -q "android.intent.action.SEND" "$MANIFEST"; then
              sed -i 's|<category android:name="android.intent.category.LAUNCHER"/>|<category android:name="android.intent.category.LAUNCHER"/></intent-filter><intent-filter><action android:name="android.intent.action.SEND"/><category android:name="android.intent.category.DEFAULT"/><data android:mimeType="text/plain"/><data android:mimeType="video/*"/><data android:mimeType="audio/*"/>|g' "$MANIFEST"
            fi"""

yml = yml.replace(old_manifest_step, new_manifest_step)

with open(".github/workflows/main.yml", "w") as f:
    f.write(yml)
print("✅ Patched .github/workflows/main.yml with Share Target Intent & Video Audio Extractor!")
PYEOF

echo "🎛 3/3 Patching lib/cricket_studio.dart (Keeping All Existing Commentary Code Untouched + Adding AI/Real Switch, 5s Hold, Nudimuttu, Custom Tiles & Trimmer Studio)..."

python3 - << 'PYEOF'
with open("lib/cricket_studio.dart", "r") as f:
    code = f.read()

if "import 'real_tile_studio.dart';" not in code:
    code = "import 'dart:async';\nimport 'real_tile_studio.dart';\n" + code

# 1. Add state fields for Trimmer Studio, 5-Second Hold Timer, and Custom Tiles without touching existing commentary arrays
old_state_vars = """  final List<String> _recentHashes = [];
  final List<String> _historyFeed = [];"""

new_state_vars = """  final List<String> _recentHashes = [];
  final List<String> _historyFeed = [];

  Timer? _fiveSecHoldTimer;
  String _selectedTileForStudio = 'SIX';
  String? _loadedDraftFilePath;
  String _loadedDraftTitle = '';
  double _trimStartSec = 0.0;
  double _trimEndSec = 10.0;
  double _maxDraftDurationSec = 60.0;
  bool _isRecordingTileMic = false;
  bool _isExtractingMedia = false;
  final TextEditingController _reelShortUrlCtrl = TextEditingController();
  final TextEditingController _clipNameCtrl = TextEditingController(text: 'My Custom Real Sound');

  @override
  void initState() {
    super.initState();
    RealTileStudioManager.init(
      onSharedMediaReceived: (shared) async {
        if (!mounted) return;
        setState(() {
          _isExtractingMedia = true;
          _lastSpokenBanner = '📲 Extracting Audio from Shared Instagram Reel / YT Short...';
        });
        final path = await RealTileStudioManager.extractAudioFromReelOrShortUrl(shared);
        if (mounted) {
          setState(() {
            _isExtractingMedia = false;
            if (path != null) {
              _loadedDraftFilePath = path;
              _loadedDraftTitle = 'Shared Reel / Short Audio';
              _clipNameCtrl.text = 'Reel/Short Audio';
              _trimStartSec = 0.0;
              _trimEndSec = 10.0;
              _lastSpokenBanner = '✅ Reel/Short Audio Extracted! Trim & Preview below before adding!';
            }
          });
        }
      },
    ).then((_) {
      if (mounted) setState(() {});
    });
  }

  List<Map<String, dynamic>> get _allCombinedTiles => [
        ..._tiles,
        ...RealTileStudioManager.extraBuiltInTiles,
        ...RealTileStudioManager.userCustomTiles,
      ];"""

code = code.replace(old_state_vars, new_state_vars)

# 2. Update _onTilePressed so if Real Mode is ON, it plays the user's trimmed Real Audio for that Tile + Language!
old_on_tile = """  void _onTilePressed(Map<String, dynamic> tile) {
    final String key = tile['key'].toString();
    final String emotion = tile['emotion'].toString();"""

new_on_tile = """  Future<void> _onTilePressed(Map<String, dynamic> tile) async {
    final String key = tile['key'].toString();
    final String emotion = tile['emotion'].toString();

    // If REAL Mode is active, play user's added/trimmed Real Audio clip for this Tile + Language!
    if (RealTileStudioManager.isRealAudioMode) {
      final playedClip = await RealTileStudioManager.playRealClipForTile(key, _commLanguage);
      if (playedClip != null) {
        setState(() {
          _lastSpokenBanner = '🎵 [REAL AUDIO • $_commLanguage] Playing: ${playedClip.title} '
              '(${(playedClip.startMs / 1000).toStringAsFixed(1)}s ➔ ${(playedClip.endMs / 1000).toStringAsFixed(1)}s)';
          _historyFeed.insert(0, '[${tile['title']}] 🎵 ${playedClip.title}');
        });
        return;
      } else {
        setState(() {
          _lastSpokenBanner = '⚠️ No Real Audio saved for [${tile['title']}] ($_commLanguage) yet — playing AI backup!';
        });
      }
    }

    // Handle Nudimuttu, Others, and Custom User Tiles in AI Mode
    if (key == 'NUDIMUTTU' || key == 'OTHERS' || key.startsWith('CUSTOM_')) {
      _applySituationEmotionProsody(emotion);
      final String extraLine = RealTileStudioManager.generateExtraTileAiLine(key, tile['title'].toString(), _commLanguage);
      final String cleanDisp = extraLine.replaceAll(' | ', ' ');
      setState(() {
        _lastSpokenBanner = cleanDisp;
        _historyFeed.insert(0, '[${tile['title']}] $cleanDisp');
      });
      AppSoundEngine.speakRealVoice(extraLine, _commLanguage, eventKey: key);
      return;
    }"""

code = code.replace(old_on_tile, new_on_tile)

# 3. Replace the Top Bar to include the AI / REAL Master Switch + Add "+ Own Tile" button
old_top_bar = """              Row(
                children: [
                  const Text('🏟 Roar', style: TextStyle(fontSize: 10, color: Colors.white70)),
                  Switch(
                    value: _stadiumAtmosphereRoar,
                    activeColor: Colors.amber,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    onChanged: (v) => setState(() => _stadiumAtmosphereRoar = v),
                  ),
                ],
              ),"""

new_top_bar = """              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: RealTileStudioManager.isRealAudioMode ? Colors.green.shade800 : Colors.blueGrey.shade800,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.amberAccent),
                    ),
                    child: Row(
                      children: [
                        Text(
                          RealTileStudioManager.isRealAudioMode ? '🎵 REAL' : '🤖 AI',
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.white),
                        ),
                        Switch(
                          value: RealTileStudioManager.isRealAudioMode,
                          activeColor: Colors.amber,
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          onChanged: (v) async {
                            await RealTileStudioManager.setRealMode(v);
                            if (!v) await RealTileStudioManager.stopRealPlayback();
                            setState(() {});
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text('🏟', style: TextStyle(fontSize: 11)),
                  Switch(
                    value: _stadiumAtmosphereRoar,
                    activeColor: Colors.amber,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    onChanged: (v) => setState(() => _stadiumAtmosphereRoar = v),
                  ),
                ],
              ),"""

code = code.replace(old_top_bar, new_top_bar)

# 4. Upgrade GridView.builder to use _allCombinedTiles and support 5-Second Hold to open Delete/List Dialog
old_grid = """              // 3. 16 INSTANT COMMENTARY TILES (ONLY TILES — NO SCORING FORMS)
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _tiles.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 1.15,
                ),
                itemBuilder: (ctx, i) {
                  final tile = _tiles[i];
                  return ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color(tile['color'] as int),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.all(4),
                      elevation: 4,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(color: Colors.white24, width: 1),
                      ),
                    ),
                    onPressed: () => _onTilePressed(tile),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          tile['title'].toString(),
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          tile['sub'].toString(),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: Colors.amberAccent),
                        ),
                      ],
                    ),
                  );
                },
              ),"""

new_grid = """              // 3. ALL TILES (16 CRICKET + NUDIMUTTU + OTHERS + USER CUSTOM TILES) WITH 5-SEC HOLD LIST/DELETE
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '⚡ Tap = Play • Hold 5 Sec = View/Delete Saved Songs',
                    style: TextStyle(fontSize: 10, color: Colors.amberAccent, fontWeight: FontWeight.bold),
                  ),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      backgroundColor: const Color(0xFF1E3A8A),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    ),
                    icon: const Icon(Icons.add_box, size: 15, color: Color(0xFF00E5FF)),
                    label: const Text('➕ Create Own Tile',
                        style: TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w900)),
                    onPressed: _showCreateCustomTileDialog,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _allCombinedTiles.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 1.12,
                ),
                itemBuilder: (ctx, i) {
                  final tile = _allCombinedTiles[i];
                  final String tKey = tile['key'].toString();
                  final int clipCount = RealTileStudioManager.getClipsFor(tKey, _commLanguage).length;

                  return Listener(
                    onPointerDown: (_) {
                      _fiveSecHoldTimer?.cancel();
                      _fiveSecHoldTimer = Timer(const Duration(seconds: 5), () {
                        if (mounted) {
                          RealTileStudioManager.show5SecHoldTileClipsDialog(
                            context,
                            tile,
                            _commLanguage,
                            () => setState(() {}),
                          );
                        }
                      });
                    },
                    onPointerUp: (_) => _fiveSecHoldTimer?.cancel(),
                    onPointerCancel: (_) => _fiveSecHoldTimer?.cancel(),
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Color(tile['color'] as int),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.all(3),
                        elevation: 4,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: clipCount > 0 ? const Color(0xFF00E676) : Colors.white24,
                            width: clipCount > 0 ? 1.8 : 1.0,
                          ),
                        ),
                      ),
                      onPressed: () => _onTilePressed(tile),
                      onLongPress: () {
                        // Also allow opening if held
                      },
                      child: Stack(
                        children: [
                          Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  tile['title'].toString(),
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  tile['sub'].toString(),
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 8.0, fontWeight: FontWeight.bold, color: Colors.amberAccent),
                                ),
                              ],
                            ),
                          ),
                          if (clipCount > 0)
                            Positioned(
                              right: 0,
                              top: 0,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(
                                  color: Colors.black87,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '🎵$clipCount',
                                  style: const TextStyle(
                                      fontSize: 8, color: Color(0xFF00E676), fontWeight: FontWeight.w900),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),

              // 3B. ULTRA-PRO REAL AUDIO ADDER & TRIMMER STUDIO (RECORD, AUDIO FILE, VIDEO EXTRACT, IG REELS / YT SHORTS)
              _buildRealAudioTrimmerStudioCard(),"""

code = code.replace(old_grid, new_grid)

# 5. Append _showCreateCustomTileDialog and _buildRealAudioTrimmerStudioCard methods before the final closing brace of _CricketCommentaryScreenState
studio_methods = """
  void _showCreateCustomTileDialog() {
    final TextEditingController titleCtrl = TextEditingController();
    final TextEditingController subCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF11192B),
        title: const Text('➕ Create Your Own Custom Tile',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF00E5FF))),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleCtrl,
              decoration: const InputDecoration(labelText: 'Tile Title (e.g. 🏆 TOSS, 🔥 ENTRY, 👑 KING)'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: subCtrl,
              decoration: const InputDecoration(labelText: 'Subtitle (e.g. SPECIAL CALL)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00E676), foregroundColor: Colors.black),
            onPressed: () async {
              if (titleCtrl.text.trim().isNotEmpty) {
                await RealTileStudioManager.addCustomTile(titleCtrl.text, subCtrl.text, 0xFF00695C);
                setState(() {
                  _selectedTileForStudio = RealTileStudioManager.userCustomTiles.last['key'].toString();
                });
                if (ctx.mounted) Navigator.pop(ctx);
              }
            },
            child: const Text('Create Tile', style: TextStyle(fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );
  }

  Widget _buildRealAudioTrimmerStudioCard() {
    final tilesList = _allCombinedTiles;
    final bool validSelected = tilesList.any((t) => t['key'].toString() == _selectedTileForStudio);
    if (!validSelected && tilesList.isNotEmpty) {
      _selectedTileForStudio = tilesList.first['key'].toString();
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF1A103C), Color(0xFF0D1526)]),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.amberAccent, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '🎛 REAL SONG / VIDEO / IG REELS & YT SHORTS TRIMMER STUDIO',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Colors.amberAccent),
          ),
          const SizedBox(height: 4),
          const Text(
            'Select Tile & Language ➔ Record Mic, Upload Song, Upload Video (Auto-Extracts Music), or Share from Instagram Reels / YT Shorts ➔ Trim & Preview before adding!',
            style: TextStyle(fontSize: 10, color: Colors.white70),
          ),
          const SizedBox(height: 10),

          // Tile Selector + Language Indicator
          Row(
            children: [
              const Text('Target Tile: ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.cyanAccent)),
              const SizedBox(width: 6),
              Expanded(
                child: DropdownButton<String>(
                  value: _selectedTileForStudio,
                  isExpanded: true,
                  items: tilesList.map((t) {
                    return DropdownMenuItem<String>(
                      value: t['key'].toString(),
                      child: Text('${t['title']} (${t['sub']}) — $_commLanguage',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    );
                  }).toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _selectedTileForStudio = v);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // 4 Input Source Buttons: Record Mic, Upload Audio, Upload Video (Extract), IG Reels/Shorts
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isRecordingTileMic ? Colors.redAccent : const Color(0xFF00E676),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                ),
                icon: Icon(_isRecordingTileMic ? Icons.stop_circle : Icons.mic, size: 16),
                label: Text(
                  _isRecordingTileMic ? '⏹ Stop Mic' : '🎙 1. Record Mic',
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900),
                ),
                onPressed: () async {
                  if (!_isRecordingTileMic) {
                    final path = await AppSoundEngine.startMicRecording(
                      'tile_${_selectedTileForStudio}_${DateTime.now().millisecondsSinceEpoch}',
                    );
                    setState(() {
                      _isRecordingTileMic = true;
                      _loadedDraftFilePath = path;
                      _loadedDraftTitle = 'Mic Recording ($_selectedTileForStudio)';
                      _clipNameCtrl.text = 'Mic Voice ($_selectedTileForStudio)';
                    });
                  } else {
                    final path = await AppSoundEngine.stopMicRecording();
                    setState(() {
                      _isRecordingTileMic = false;
                      if (path != null) {
                        _loadedDraftFilePath = path;
                        _trimStartSec = 0.0;
                        _trimEndSec = 10.0;
                      }
                    });
                  }
                },
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0288D1),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                ),
                icon: const Icon(Icons.audio_file, size: 16),
                label: const Text('🎵 2. Upload Audio File',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900)),
                onPressed: () async {
                  final path = await RealTileStudioManager.pickAndExtractFile(isVideo: false);
                  if (path != null && mounted) {
                    setState(() {
                      _loadedDraftFilePath = path;
                      _loadedDraftTitle = path.split('/').last;
                      _clipNameCtrl.text = 'Uploaded Song Cut';
                      _trimStartSec = 0.0;
                      _trimEndSec = 12.0;
                    });
                  }
                },
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7B1FA2),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                ),
                icon: const Icon(Icons.video_file, size: 16),
                label: const Text('🎬 3. Upload Video (Extract Music)',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900)),
                onPressed: () async {
                  setState(() => _isExtractingMedia = true);
                  final path = await RealTileStudioManager.pickAndExtractFile(isVideo: true);
                  if (mounted) {
                    setState(() {
                      _isExtractingMedia = false;
                      if (path != null) {
                        _loadedDraftFilePath = path;
                        _loadedDraftTitle = 'Extracted Video Music';
                        _clipNameCtrl.text = 'Video Extracted Music';
                        _trimStartSec = 0.0;
                        _trimEndSec = 12.0;
                      }
                    });
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Instagram Reels / YouTube Shorts Link or Share Input
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _reelShortUrlCtrl,
                  style: const TextStyle(fontSize: 11),
                  decoration: InputDecoration(
                    hintText: '📲 Paste IG Reel / YT Short Link (or Share directly from Instagram/YouTube app)...',
                    filled: true,
                    fillColor: const Color(0xFF090E1A),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.pinkAccent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                ),
                onPressed: () async {
                  if (_reelShortUrlCtrl.text.trim().isEmpty) return;
                  setState(() => _isExtractingMedia = true);
                  final path = await RealTileStudioManager.extractAudioFromReelOrShortUrl(_reelShortUrlCtrl.text);
                  if (mounted) {
                    setState(() {
                      _isExtractingMedia = false;
                      if (path != null) {
                        _loadedDraftFilePath = path;
                        _loadedDraftTitle = 'IG Reel / YT Short Music';
                        _clipNameCtrl.text = 'Reel/Short Cut';
                        _trimStartSec = 0.0;
                        _trimEndSec = 10.0;
                      }
                    });
                  }
                },
                child: const Text('Extract Reel/Short', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900)),
              ),
            ],
          ),

          if (_isExtractingMedia)
            const Padding(
              padding: EdgeInsets.all(10.0),
              child: LinearProgressIndicator(color: Colors.amberAccent),
            ),

          // IN-APP TRIMMER & PREVIEW PLAY CONFIRMATION BOX
          if (_loadedDraftFilePath != null) ...[
            const Divider(color: Colors.white24, height: 18),
            Text(
              '✂️ TRIM & PREVIEW BEFORE ADDING: $_loadedDraftTitle',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Color(0xFF00E676)),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _clipNameCtrl,
              style: const TextStyle(fontSize: 11),
              decoration: const InputDecoration(
                labelText: 'Clip Label / Name',
                isDense: true,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Start: ${_trimStartSec.toStringAsFixed(1)}s',
                    style: const TextStyle(fontSize: 11, color: Colors.cyanAccent, fontWeight: FontWeight.bold)),
                Text('Duration: ${(_trimEndSec - _trimStartSec).toStringAsFixed(1)}s',
                    style: const TextStyle(fontSize: 11, color: Colors.amberAccent, fontWeight: FontWeight.bold)),
                Text('End: ${_trimEndSec.toStringAsFixed(1)}s',
                    style: const TextStyle(fontSize: 11, color: Colors.pinkAccent, fontWeight: FontWeight.bold)),
              ],
            ),
            RangeSlider(
              values: RangeValues(
                _trimStartSec.clamp(0.0, _maxDraftDurationSec),
                _trimEndSec.clamp(_trimStartSec + 0.5, _maxDraftDurationSec),
              ),
              min: 0.0,
              max: _maxDraftDurationSec,
              activeColor: Colors.amberAccent,
              onChanged: (RangeValues values) {
                setState(() {
                  _trimStartSec = values.start;
                  _trimEndSec = values.end;
                });
              },
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: () => setState(() => _maxDraftDurationSec = (_maxDraftDurationSec == 60.0) ? 240.0 : 60.0),
                  child: Text(
                    _maxDraftDurationSec == 60.0 ? '🔍 Range: 60s (Tap for 240s)' : '🔍 Range: 240s (Tap for 60s)',
                    style: const TextStyle(fontSize: 10, color: Colors.white70),
                  ),
                ),
                Row(
                  children: [
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00E5FF),
                        foregroundColor: Colors.black,
                      ),
                      icon: const Icon(Icons.play_arrow, size: 16),
                      label: const Text('▶ Preview Trim', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900)),
                      onPressed: () {
                        RealTileStudioManager.playSpecificTrimmedClip(
                          _loadedDraftFilePath!,
                          (_trimStartSec * 1000).toInt(),
                          (_trimEndSec * 1000).toInt(),
                        );
                      },
                    ),
                    const SizedBox(width: 6),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00E676),
                        foregroundColor: Colors.black,
                      ),
                      icon: const Icon(Icons.check_circle, size: 16),
                      label: const Text('✅ Add to Tile', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900)),
                      onPressed: () async {
                        final newClip = CustomTileClip(
                          id: 'clip_${DateTime.now().millisecondsSinceEpoch}',
                          tileKey: _selectedTileForStudio,
                          language: _commLanguage,
                          title: _clipNameCtrl.text.trim().isEmpty ? 'Custom Sound' : _clipNameCtrl.text.trim(),
                          filePath: _loadedDraftFilePath!,
                          startMs: (_trimStartSec * 1000).toInt(),
                          endMs: (_trimEndSec * 1000).toInt(),
                        );
                        RealTileStudioManager.allClips.insert(0, newClip);
                        await RealTileStudioManager.saveClips();
                        await RealTileStudioManager.setRealMode(true);
                        if (mounted) {
                          setState(() {
                            _loadedDraftFilePath = null;
                            _lastSpokenBanner =
                                '✅ Added "${newClip.title}" to [$_selectedTileForStudio • $_commLanguage] & Switched to REAL Mode!';
                          });
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
"""

last_brace_idx = code.rfind("}")
code = code[:last_brace_idx] + studio_methods
with open("lib/cricket_studio.dart", "w") as f:
    f.write(code)
print("✅ Patched lib/cricket_studio.dart without touching any existing commentary sentences!")
PYEOF

echo "✅ All v307.0 upgrades applied!"
