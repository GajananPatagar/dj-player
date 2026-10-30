import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:audioplayers/audioplayers.dart';
import 'des_helper.dart';
import 'glass_widgets.dart';
import 'karaoke_engine.dart';
import 'main.dart';

class KaraokeStudioScreen extends StatefulWidget {
  const KaraokeStudioScreen({super.key});

  @override
  State<KaraokeStudioScreen> createState() => _KaraokeStudioScreenState();
}

class _KaraokeStudioScreenState extends State<KaraokeStudioScreen> {
  static const MethodChannel _nativeDsp = MethodChannel('dj_native_tts');

  // 3 Independent Studio Players:
  // 1) _karaokeBackingPlayer -> Plays Pure Instrumental or Hardware Vocal-Cut Karaoke Track
  // 2) _userVocalStemPlayer  -> Plays User's Isolated Recorded Voice
  // 3) _choirHarmonyPlayer   -> Plays 35ms Delayed AI Double-Track Harmony Choir
  final AudioPlayer _karaokeBackingPlayer = AudioPlayer();
  final AudioPlayer _userVocalStemPlayer = AudioPlayer();
  final AudioPlayer _choirHarmonyPlayer = AudioPlayer();

  final TextEditingController _searchCtrl = TextEditingController();
  final ScrollController _pageScrollCtrl = ScrollController();
  final ScrollController _lyricsScrollCtrl = ScrollController();

  final List<Map<String, String>> _karaokeCategories = const [
    {'label': '👑 Kannada Karaoke', 'query': 'Kannada Hit Songs Karaoke Instrumental'},
    {'label': '🇮🇳 Hindi Karaoke', 'query': 'Hindi Bollywood Karaoke Instrumental'},
    {'label': '💍 Marriage Karaoke', 'query': 'Wedding Marriage Songs Karaoke Instrumental'},
    {'label': '🪔 Devotional', 'query': 'Kannada Hindi Devotional Bhakti Karaoke'},
    {'label': '💖 Melody Hits', 'query': 'Kannada Hindi Romantic Melody Karaoke'},
    {'label': '🔥 Folk & Mass', 'query': 'Kannada Janapada Mass Songs Karaoke'},
  ];

  String _selectedCatLabel = '👑 Kannada Karaoke';
  String _filterTab = 'ALL'; // ALL, PURE_INST, SAVED_TAKES

  List<Map<String, dynamic>> _songs = [];
  Map<String, dynamic>? _selectedSong;
  String? _pureKaraokeStreamUrl;
  String? _originalGuideStreamUrl;
  bool _usingPureMatchedInstrumental = false;

  List<LyricLine> _lyrics = [];
  int _activeLyricIndex = 0;
  String _selectedLyricScript = 'KANGLISH (ಕನ್ನಡ-Eng)';
  double _lyricFontSize = 15.5;

  final List<String> _scriptModes = const [
    'KANGLISH (ಕನ್ನಡ-Eng)',
    'HINGLISH (हिन्दी-Eng)',
    'ENGLISH / ORIGINAL',
    'KANNADA (ಕನ್ನಡ)',
    'HINDI (हिन्दी)',
  ];

  // 6 Professional Studio Vocal Presets
  String _vocalPreset = '✨ Smule Auto-Tune Pro Polish';
  final List<String> _vocalPresets = const [
    '✨ Smule Auto-Tune Pro Polish',
    '🎤 Double-Track Choir (Thick Studio Voice)',
    '🏟 Royal Concert Hall Reverb + Warmth',
    '🔥 Mass Hero Baritone Boost',
    '💎 Crystal High-Clarity Pop Vocal',
    '🎙 Raw Unprocessed Studio Mic',
  ];

  bool _isLoading = false;
  bool _isPreparingStage = false;
  bool _isPlayingBacking = false;
  bool _isKaraokeVocalCutActive = true; // Default ON: Removes lead vocals!
  double _vocalCutStrength = 1.0; // 1.0 = 100% Pure Karaoke (0% Singer), 0.0 = Original Guide Singer
  bool _isRecordingSinging = false;
  bool _isPlayingMasterMix = false;
  bool _doubleChoirEnabled = true;
  int _countdownSec = 0;
  int _semitonePitchShift = 0; // -4 to +4 semitones

  double _karaokeMusicVol = 0.80;
  double _userVocalVol = 1.0;
  double _vocalPitchPolish = 1.02;
  int _vocalSyncOffsetMs = -60;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  String _statusBanner = '🎤 Pro Karaoke Studio Ready • 100% Vocal-Cut & Synced Teleprompter Active!';

  @override
  void initState() {
    super.initState();
    _configureMultiTrackAudioFocus();
    KaraokeEngine.loadSavedTakes().then((_) {
      if (mounted) setState(() {});
    });
    _setupListeners();
    _runSongSearch('Kannada Hit Songs Karaoke Instrumental');
  }

  Future<void> _configureMultiTrackAudioFocus() async {
    try {
      final ctx = AudioContext(
        android: const AudioContextAndroid(
          isSpeakerphoneOn: false,
          stayAwake: true,
          contentType: AndroidContentType.music,
          usageType: AndroidUsageType.media,
          audioFocus: AndroidAudioFocus.none,
        ),
      );
      await _karaokeBackingPlayer.setAudioContext(ctx);
      await _userVocalStemPlayer.setAudioContext(ctx);
      await _choirHarmonyPlayer.setAudioContext(ctx);
    } catch (_) {}
  }

  void _setupListeners() {
    _karaokeBackingPlayer.onPositionChanged.listen((pos) {
      if (!mounted) return;
      final int ms = pos.inMilliseconds;
      int newIdx = _activeLyricIndex;
      for (int i = 0; i < _lyrics.length; i++) {
        if (ms >= _lyrics[i].timeMs) {
          newIdx = i;
        } else {
          break;
        }
      }
      if (newIdx != _activeLyricIndex) {
        _activeLyricIndex = newIdx;
        _scrollToActiveLyric();
      }
      setState(() => _position = pos);
    });

    _karaokeBackingPlayer.onDurationChanged.listen((dur) {
      if (mounted) setState(() => _duration = dur);
    });

    _karaokeBackingPlayer.onPlayerStateChanged.listen((st) {
      if (mounted) {
        setState(() => _isPlayingBacking = (st == PlayerState.playing));
      }
    });

    _karaokeBackingPlayer.onPlayerComplete.listen((_) {
      if (_isRecordingSinging) {
        _stopSingingRecordingAndSaveMaster();
      } else if (_isPlayingMasterMix) {
        _stopAllPlayback();
      } else {
        if (mounted) setState(() => _isPlayingBacking = false);
      }
    });
  }

  void _scrollToActiveLyric() {
    if (!_lyricsScrollCtrl.hasClients) return;
    final double targetOffset = (_activeLyricIndex * 46.0 - 65.0).clamp(
      0.0,
      _lyricsScrollCtrl.position.maxScrollExtent,
    );
    _lyricsScrollCtrl.animateTo(
      targetOffset,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
    );
  }

  void _scrollToTopStage() {
    if (!_pageScrollCtrl.hasClients) return;
    _pageScrollCtrl.animateTo(
      0.0,
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _runSongSearch(String q) async {
    setState(() {
      _isLoading = true;
      _statusBanner = '🔄 Searching Pure Karaoke Instrumentals & AI Vocal-Cut Tracks...';
    });
    final res = await KaraokeEngine.searchSongsForKaraoke(q);
    if (mounted) {
      final int instCount = res.where((e) => e['isPureInstrumental'] == true).length;
      setState(() {
        _songs = res;
        _isLoading = false;
        _statusBanner =
            '🟢 Loaded ${res.length} Tracks ($instCount Pure Instrumentals + AI Vocal-Cut Ready)';
      });
      if (_selectedSong == null && res.isNotEmpty) {
        // Load #1 onto the stage silently (do NOT auto-play until user taps Play Karaoke or Sing!)
        _loadSongOntoKaraokeStage(
          res.first,
          startKaraokePlayback: false,
          startRecordingImmediately: false,
        );
      }
    }
  }

  /// Automatically resolves a TRUE Instrumental / Karaoke stream for ANY song if one exists online,
  /// AND activates Hardware Center-Vocal Notch DSP so tapping a song NEVER just plays a normal vocal track!
  Future<void> _loadSongOntoKaraokeStage(
    Map<String, dynamic> song, {
    required bool startKaraokePlayback,
    required bool startRecordingImmediately,
  }) async {
    await _stopAllPlayback();
    if (startKaraokePlayback || startRecordingImmediately) {
      _scrollToTopStage();
    }

    final String id = song['id'].toString();
    final String title = song['title'].toString();
    final String cleanTitle =
        (song['cleanLyricsTitle'] ?? KaraokeEngine.cleanSongTitleForLyricsLookup(title)).toString();
    final String artist = song['artist'].toString();
    final int durSec = (song['durationSec'] as int?) ?? 180;
    final bool isAlreadyPureInst = song['isPureInstrumental'] == true;

    setState(() {
      _selectedSong = song;
      _activeLyricIndex = 0;
      _position = Duration.zero;
      _isPreparingStage = true;
      _isKaraokeVocalCutActive = true;
      _vocalCutStrength = 1.0;
      _statusBanner = '🎛 Preparing True Karaoke Backing & Synced Lyrics for "$cleanTitle"...';
    });

    // 1. Fetch Time-Synced Lyrics & Resolve Streams in parallel
    final Future<List<LyricLine>> lyricsFuture =
        KaraokeEngine.fetchSyncedLyrics(id, title, artist, durSec);

    final List origUrls = (song['urls'] as List?) ?? [];
    final String? origLiveUrl = await SaavnDesDecryptor.resolvePlayableStreamUrl(origUrls);

    String? bestInstrumentalUrl;
    bool foundPureInst = isAlreadyPureInst;

    // 2. If song is already Pure Instrumental or has matched instrumentalUrls, resolve it directly
    final List matchedInstUrls = (song['instrumentalUrls'] as List?) ?? [];
    if (matchedInstUrls.isNotEmpty) {
      bestInstrumentalUrl = await SaavnDesDecryptor.resolvePlayableStreamUrl(matchedInstUrls);
      if (bestInstrumentalUrl != null) {
        foundPureInst = true;
      }
    }

    // 3. If user tapped a normal song that didn't have a pre-matched instrumental URL yet,
    // automatically hunt for a dedicated Karaoke / Instrumental version of this exact song!
    if (bestInstrumentalUrl == null && cleanTitle.length >= 3) {
      bestInstrumentalUrl = await _huntDedicatedInstrumentalStream(cleanTitle);
      if (bestInstrumentalUrl != null) {
        foundPureInst = true;
      }
    }

    final List<LyricLine> fetchedLyrics = await lyricsFuture;

    if (!mounted) return;
    setState(() {
      _lyrics = fetchedLyrics;
      _originalGuideStreamUrl = origLiveUrl;
      _pureKaraokeStreamUrl = bestInstrumentalUrl ?? origLiveUrl;
      _usingPureMatchedInstrumental = foundPureInst;
      _isPreparingStage = false;
      _statusBanner = foundPureInst
          ? '🎹 Pure Instrumental Karaoke Loaded: $cleanTitle (${_lyrics.length} Synced Lines)'
          : '🎛 AI Center-Vocal Remover Armed (-15dB Vocal Cut): $cleanTitle';
    });

    // 4. ONLY engage Hardware Vocal-Cut DSP when actively playing or recording in Karaoke Tab!
    if (startRecordingImmediately) {
      await _applyNativeKaraokeVocalCutDsp();
      await _startSingingRecording();
    } else if (startKaraokePlayback) {
      await _applyNativeKaraokeVocalCutDsp();
      await _startKaraokePracticePlayback();
    }
  }

  /// Hunts JioSaavn & iTunes specifically for a Pure Karaoke / Instrumental stream matching [cleanSongTitle]
  Future<String?> _huntDedicatedInstrumentalStream(String cleanSongTitle) async {
    final Map<String, String> headers = {
      'User-Agent': 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/124.0 Mobile Safari/537.36',
    };
    final List<String> huntQueries = [
      '$cleanSongTitle Karaoke',
      '$cleanSongTitle Instrumental',
    ];

    for (final hq in huntQueries) {
      try {
        final String url =
            'https://www.jiosaavn.com/api.php?__call=search.getResults&_format=json&_marker=0&api_version=4&ctx=web6dot0&n=10&p=1&q=${Uri.encodeComponent(hq)}';
        final res = await http.get(Uri.parse(url), headers: headers).timeout(const Duration(seconds: 3));
        if (res.statusCode == 200) {
          final Map decoded = jsonDecode(res.body);
          final List results = (decoded['results'] as List?) ?? [];
          for (final item in results) {
            final String t = (item['title'] ?? item['song'] ?? '').toString().toLowerCase();
            final String sub = (item['subtitle'] ?? '').toString().toLowerCase();
            if (t.contains('karaoke') ||
                t.contains('instrumental') ||
                sub.contains('karaoke') ||
                sub.contains('instrumental')) {
              final Map moreInfo = (item['more_info'] is Map) ? item['more_info'] : {};
              final String? encUrl =
                  (moreInfo['encrypted_media_url'] ?? item['encrypted_media_url'])?.toString();
              final String? prevUrl = (moreInfo['vlink'] ?? item['media_preview_url'])?.toString();
              final List<String> urls = SaavnDesDecryptor.decryptToFullUrls(encUrl, prevUrl);
              if (urls.isNotEmpty) {
                return urls.first;
              }
            }
          }
        }
      } catch (_) {}
    }
    return null;
  }

  /// Sends the real-time Vocal-Cut DSP curve to MainActivity.kt:
  /// When _isKaraokeVocalCutActive is true, cuts center vocal bands (230Hz, 910Hz, 3.6kHz) by up to -1500mB (-15dB)
  /// while boosting 60Hz Sub-Bass (+800mB) and 14kHz Stereo Air (+750mB) + 1000 Virtualizer Stereo Width!
  Future<void> _applyNativeKaraokeVocalCutDsp() async {
    try {
      await _nativeDsp.invokeMethod('setKaraokeVocalCut', {
        'enabled': _isKaraokeVocalCutActive,
        'strength': _vocalCutStrength,
      });
    } catch (_) {}
  }

  /// Starts playing the Karaoke Backing Track (with Vocal-Cut DSP or Pure Instrumental stream!)
  Future<void> _startKaraokePracticePlayback() async {
    final String? targetUrl = (_isKaraokeVocalCutActive && _pureKaraokeStreamUrl != null)
        ? _pureKaraokeStreamUrl
        : (_originalGuideStreamUrl ?? _pureKaraokeStreamUrl);

    if (targetUrl == null) return;

    await _applyNativeKaraokeVocalCutDsp();
    await _karaokeBackingPlayer.stop();
    await _karaokeBackingPlayer.setVolume(_karaokeMusicVol);

    final double semitoneFactor = 1.0 + (_semitonePitchShift * 0.05946);
    await _karaokeBackingPlayer.setPlaybackRate(semitoneFactor.clamp(0.75, 1.30));

    if (targetUrl.startsWith('http')) {
      await _karaokeBackingPlayer.play(UrlSource(targetUrl));
    } else {
      await _karaokeBackingPlayer.play(DeviceFileSource(targetUrl));
    }

    if (mounted) {
      setState(() {
        _isPlayingBacking = true;
        _statusBanner = _usingPureMatchedInstrumental && _isKaraokeVocalCutActive
            ? '🎹 Playing Pure Instrumental Karaoke — Sing Along to the Teleprompter!'
            : (_isKaraokeVocalCutActive
                ? '🎛 Playing AI Vocal-Cut Karaoke Backing (-15dB Center Vocal Cut Active)!'
                : '🗣 Playing Guide Singer Mode — Learn the Melody!');
      });
    }
  }

  Future<void> _stopAllPlayback() async {
    try {
      await _karaokeBackingPlayer.stop();
      await _userVocalStemPlayer.stop();
      await _choirHarmonyPlayer.stop();
      await AppSoundEngine.resetHardwareAudioToNormalFlat();
    } catch (_) {}
    if (mounted) {
      setState(() {
        _isPlayingBacking = false;
        _isPlayingMasterMix = false;
      });
    }
  }

  /// Pick any song from Phone Storage and immediately convert it into Karaoke!
  Future<void> _pickPhoneSongForKaraoke() async {
    try {
      final String? pickedPath = await _nativeDsp.invokeMethod<String>(
        'pickMediaAndExtractAudio',
        {'isVideo': false},
      );
      if (pickedPath == null || pickedPath.isEmpty) return;
      final String fileName = pickedPath.split('/').last.replaceAll(RegExp(r'\.[a-zA-Z0-9]+$'), '');
      final Map<String, dynamic> customSong = {
        'id': 'local_kar_${DateTime.now().millisecondsSinceEpoch}',
        'title': fileName,
        'cleanLyricsTitle': KaraokeEngine.cleanSongTitleForLyricsLookup(fileName),
        'artist': 'Phone Audio -> AI Vocal-Cut Karaoke',
        'cover': '',
        'urls': [pickedPath],
        'instrumentalUrls': <String>[],
        'durationSec': 210,
        'isPureInstrumental': false,
      };
      await _loadSongOntoKaraokeStage(
        customSong,
        startKaraokePlayback: true,
        startRecordingImmediately: false,
      );
    } catch (_) {}
  }

  /// Starts 3-2-1 Countdown -> Plays Pure Karaoke Backing from 0:00 -> Records Clean Isolated User Voice
  Future<void> _startSingingRecording() async {
    final String? backingUrl = _pureKaraokeStreamUrl ?? _originalGuideStreamUrl;
    if (_selectedSong == null || backingUrl == null) return;
    await _stopAllPlayback();
    _scrollToTopStage();

    setState(() {
      _isKaraokeVocalCutActive = true;
      _vocalCutStrength = 1.0;
    });
    await _applyNativeKaraokeVocalCutDsp();

    for (int c = 3; c >= 1; c--) {
      if (!mounted) return;
      setState(() {
        _countdownSec = c;
        _statusBanner = '🎙 Stage Countdown: $c... (Echo-Canceled Studio Mic Armed!)';
      });
      await Future.delayed(const Duration(seconds: 1));
    }

    if (!mounted) return;
    setState(() {
      _countdownSec = 0;
      _isRecordingSinging = true;
      _activeLyricIndex = 0;
      _statusBanner = '🔴 LIVE RECORDING — Sing Along to the Gold Teleprompter Lyrics!';
    });

    final String takeId = 'take_${DateTime.now().millisecondsSinceEpoch}';
    try {
      await _nativeDsp.invokeMethod('startCleanVocalRecord', {'name': takeId});
    } catch (_) {
      await AppSoundEngine.startMicRecording(takeId);
    }

    final double recBackVol = _usingPureMatchedInstrumental
        ? _karaokeMusicVol
        : (_karaokeMusicVol * 0.55).clamp(0.25, 0.80);
    await _karaokeBackingPlayer.setVolume(recBackVol);
    if (backingUrl.startsWith('http')) {
      await _karaokeBackingPlayer.play(UrlSource(backingUrl));
    } else {
      await _karaokeBackingPlayer.play(DeviceFileSource(backingUrl));
    }
  }

  Future<void> _stopSingingRecordingAndSaveMaster() async {
    if (!_isRecordingSinging) return;
    await _karaokeBackingPlayer.stop();

    String? vocalPath;
    try {
      vocalPath = await _nativeDsp.invokeMethod<String>('stopCleanVocalRecord');
    } catch (_) {
      vocalPath = await AppSoundEngine.stopMicRecording();
    }

    if (!mounted) return;
    setState(() {
      _isRecordingSinging = false;
      _isPlayingBacking = false;
    });

    final String? backingUrl = _pureKaraokeStreamUrl ?? _originalGuideStreamUrl;
    if (vocalPath != null && _selectedSong != null && backingUrl != null) {
      final take = KaraokeTake(
        id: 'take_${DateTime.now().millisecondsSinceEpoch}',
        songTitle: _selectedSong!['title'].toString(),
        songArtist: _selectedSong!['artist'].toString(),
        coverUrl: _selectedSong!['cover'].toString(),
        backingStreamUrl: backingUrl,
        vocalFilePath: vocalPath,
        presetName: _vocalPreset,
        vocalPitch: _vocalPitchPolish,
        doubleChoirEnabled: _doubleChoirEnabled,
        syncOffsetMs: _vocalSyncOffsetMs,
      );
      await KaraokeEngine.saveTake(take);
      setState(() {
        _statusBanner = '✅ Studio Master Saved to /Download/DJ_Karaoke_*.m4a! Playing Mix...';
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.green.shade800,
            content: const Text(
              '🎤 Saved Karaoke Master to Phone Downloads & Studio Vault! Playing Mix Now...',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        );
      }
      await _playDualStemStudioMaster(take);
    }
  }

  Future<void> _playDualStemStudioMaster(KaraokeTake take) async {
    await _stopAllPlayback();
    if (!File(take.vocalFilePath).existsSync()) return;

    setState(() {
      _isPlayingMasterMix = true;
      _statusBanner = '🔊 Playing Studio Master: Karaoke Backing + Your Voice (${take.presetName})';
    });

    await _applyNativeKaraokeVocalCutDsp();

    double pitchRate = take.vocalPitch;
    if (_vocalPreset.contains('Auto-Tune')) {
      pitchRate = 1.02;
    } else if (_vocalPreset.contains('Hero')) {
      pitchRate = 0.97;
    } else if (_vocalPreset.contains('Crystal')) {
      pitchRate = 1.03;
    }

    await _karaokeBackingPlayer.setVolume((_karaokeMusicVol * 0.52).clamp(0.20, 0.90));
    await _userVocalStemPlayer.setVolume(1.0);
    await _userVocalStemPlayer.setPlaybackRate(pitchRate.clamp(0.85, 1.18));

    final Source backSrc = take.backingStreamUrl.startsWith('http')
        ? UrlSource(take.backingStreamUrl)
        : DeviceFileSource(take.backingStreamUrl);

    if (_vocalSyncOffsetMs < 0) {
      await _userVocalStemPlayer.play(DeviceFileSource(take.vocalFilePath));
      await Future.delayed(Duration(milliseconds: _vocalSyncOffsetMs.abs()));
      await _karaokeBackingPlayer.play(backSrc);
    } else {
      await _karaokeBackingPlayer.play(backSrc);
      if (_vocalSyncOffsetMs > 0) {
        await Future.delayed(Duration(milliseconds: _vocalSyncOffsetMs));
      }
      await _userVocalStemPlayer.play(DeviceFileSource(take.vocalFilePath));
    }

    if (_doubleChoirEnabled) {
      await Future.delayed(const Duration(milliseconds: 35));
      await _choirHarmonyPlayer.setVolume((_userVocalVol * 0.40).clamp(0.0, 1.0));
      await _choirHarmonyPlayer.setPlaybackRate((pitchRate * 1.008).clamp(0.85, 1.2));
      await _choirHarmonyPlayer.play(DeviceFileSource(take.vocalFilePath));
    }
  }

  void _applyPresetSelection(String preset) {
    setState(() {
      _vocalPreset = preset;
      if (preset.contains('Auto-Tune')) {
        _vocalPitchPolish = 1.02;
        _doubleChoirEnabled = true;
      } else if (preset.contains('Double-Track')) {
        _vocalPitchPolish = 1.00;
        _doubleChoirEnabled = true;
      } else if (preset.contains('Concert')) {
        _vocalPitchPolish = 1.01;
        _doubleChoirEnabled = true;
      } else if (preset.contains('Crystal')) {
        _vocalPitchPolish = 1.03;
        _doubleChoirEnabled = true;
      } else if (preset.contains('Hero')) {
        _vocalPitchPolish = 0.97;
        _doubleChoirEnabled = false;
      } else {
        _vocalPitchPolish = 1.00;
        _doubleChoirEnabled = false;
      }
    });
  }

  /// Opens a Full-Screen Smule-Style Stage Teleprompter Modal so the singer can read lyrics effortlessly!
  void _openFullScreenStagePrompter() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Container(
              height: MediaQuery.of(ctx).size.height * 0.90,
              padding: const EdgeInsets.all(10),
              child: GlassBox(
                padding: const EdgeInsets.all(16),
                borderRadius: 26,
                blur: 24,
                tintColor: const Color(0xFF0A0F24),
                borderColor: _isRecordingSinging ? Colors.redAccent : const Color(0xFF00E5FF),
                borderWidth: 1.8,
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 28, color: Colors.white),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                        Expanded(
                          child: Column(
                            children: [
                              Text(
                                _selectedSong?['title']?.toString() ?? 'Karaoke Stage',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Colors.white),
                              ),
                              Text(
                                _isRecordingSinging
                                    ? '🔴 RECORDING LIVE VOCALS'
                                    : '🎹 FULL-SCREEN KARAOKE TELEPROMPTER',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.bold,
                                  color: _isRecordingSinging ? Colors.redAccent : const Color(0xFF00E676),
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.text_increase_rounded, color: Colors.amberAccent),
                          onPressed: () {
                            setState(() => _lyricFontSize = (_lyricFontSize + 1.5).clamp(13.0, 24.0));
                            setModalState(() {});
                          },
                        ),
                      ],
                    ),
                    const Divider(color: Colors.white24),
                    Expanded(
                      child: ListView.builder(
                        itemCount: _lyrics.length,
                        itemBuilder: (ctx, idx) {
                          final bool isCurrent = (idx == _activeLyricIndex);
                          final String formatted = KaraokeEngine.formatLineForLanguageMode(
                            _lyrics[idx].text,
                            _selectedLyricScript,
                          );
                          return GestureDetector(
                            onTap: () {
                              _karaokeBackingPlayer.seek(Duration(milliseconds: _lyrics[idx].timeMs));
                              setModalState(() {});
                            },
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                              decoration: BoxDecoration(
                                color: isCurrent ? Colors.amber.withOpacity(0.20) : Colors.transparent,
                                borderRadius: BorderRadius.circular(12),
                                border: isCurrent ? Border.all(color: Colors.amberAccent) : null,
                              ),
                              child: Text(
                                formatted,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: isCurrent ? (_lyricFontSize + 3) : _lyricFontSize,
                                  fontWeight: isCurrent ? FontWeight.w900 : FontWeight.w500,
                                  color: isCurrent ? Colors.amberAccent : Colors.white70,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _isRecordingSinging ? Colors.redAccent : const Color(0xFF00E676),
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(vertical: 13),
                            ),
                            icon: Icon(_isRecordingSinging ? Icons.stop_circle : Icons.fiber_manual_record),
                            label: Text(
                              _isRecordingSinging ? '⏹ STOP & SAVE MASTER' : '🔴 START SINGING & RECORD',
                              style: const TextStyle(fontWeight: FontWeight.w900),
                            ),
                            onPressed: () async {
                              if (_isRecordingSinging) {
                                await _stopSingingRecordingAndSaveMaster();
                              } else {
                                await _startSingingRecording();
                              }
                              if (ctx.mounted) setModalState(() {});
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  List<Map<String, dynamic>> _filteredSongsList() {
    if (_filterTab == 'PURE_INST') {
      return _songs
          .where((s) => s['isPureInstrumental'] == true || s['hasMatchedInstrumental'] == true)
          .toList();
    }
    return _songs;
  }

  String _fmtDuration(Duration d) {
    final int m = d.inMinutes;
    final int s = d.inSeconds % 60;
    return '$m:${s < 10 ? '0$s' : '$s'}';
  }

  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>> visibleSongs = _filteredSongsList();

    return Column(
      children: [
        // 1. Top Live Studio Status Strip
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [Color(0xFF0B1329), Color(0xFF1A103C)]),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _statusBanner,
                  style: const TextStyle(fontSize: 10.8, color: Color(0xFF00E676), fontWeight: FontWeight.w900),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              GestureDetector(
                onTap: _pickPhoneSongForKaraoke,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00E5FF).withOpacity(0.18),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFF00E5FF)),
                  ),
                  child: const Text(
                    '📱 Phone Song ➔ Karaoke',
                    style: TextStyle(fontSize: 9.5, color: Color(0xFF00E5FF), fontWeight: FontWeight.w900),
                  ),
                ),
              ),
            ],
          ),
        ),

        Expanded(
          child: ListView(
            controller: _pageScrollCtrl,
            padding: const EdgeInsets.all(10),
            children: [
              // ==================== 1. SEARCH BAR & QUICK KARAOKE CATEGORY PILLS ====================
              Row(
                children: [
                  Expanded(
                    child: GlassBox(
                      borderRadius: 12,
                      blur: 10,
                      padding: EdgeInsets.zero,
                      tintColor: const Color(0xFF101B33),
                      borderColor: const Color(0x5500E5FF),
                      child: TextField(
                        controller: _searchCtrl,
                        style: const TextStyle(fontSize: 12.5, color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'Search any song, movie, artist for Karaoke + Synced Lyrics...',
                          hintStyle: const TextStyle(fontSize: 11, color: Colors.white54),
                          prefixIcon: const Icon(Icons.mic_external_on_rounded, color: Color(0xFF00E5FF), size: 19),
                          suffixIcon: _searchCtrl.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear_rounded, size: 18),
                                  onPressed: () {
                                    _searchCtrl.clear();
                                    _runSongSearch('Kannada Hindi Karaoke Instrumental');
                                  },
                                )
                              : null,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          border: InputBorder.none,
                        ),
                        onSubmitted: _runSongSearch,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00E5FF),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () => _runSongSearch(_searchCtrl.text),
                    child: const Text('Search', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
                  ),
                ],
              ),
              const SizedBox(height: 7),

              // Quick Karaoke Category Chips
              SizedBox(
                height: 34,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _karaokeCategories.length,
                  itemBuilder: (ctx, i) {
                    final cat = _karaokeCategories[i];
                    final bool sel = (_selectedCatLabel == cat['label']);
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(
                          cat['label']!,
                          style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900),
                        ),
                        selected: sel,
                        selectedColor: Colors.amberAccent,
                        backgroundColor: const Color(0xFF111C33),
                        labelStyle: TextStyle(color: sel ? Colors.black : Colors.white),
                        onSelected: (_) {
                          setState(() => _selectedCatLabel = cat['label']!);
                          _runSongSearch(cat['query']!);
                        },
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),

              // ==================== 2. GLASSMORPHIC STAGE TELEPROMPTER & VOCAL-CUT DECK ====================
              GlassBox(
                padding: const EdgeInsets.all(12),
                borderRadius: 20,
                blur: 18,
                tintColor: const Color(0xFF141036),
                borderColor: _isRecordingSinging
                    ? Colors.redAccent
                    : (_isPlayingBacking ? const Color(0xFF00E676) : const Color(0xFF00E5FF)),
                borderWidth: 1.6,
                child: Column(
                  children: [
                    // Stage Header: Active Song + Vocal-Cut Badge + Full-Screen Button
                    if (_selectedSong != null)
                      Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: _selectedSong!['cover'].toString().startsWith('http')
                                ? Image.network(
                                    _selectedSong!['cover'].toString(),
                                    width: 48,
                                    height: 48,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => _stageFallbackIcon(),
                                  )
                                : _stageFallbackIcon(),
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _selectedSong!['title'].toString(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 13.5,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                      decoration: BoxDecoration(
                                        color: _usingPureMatchedInstrumental
                                            ? const Color(0xFF00E676).withOpacity(0.20)
                                            : const Color(0xFF00E5FF).withOpacity(0.20),
                                        borderRadius: BorderRadius.circular(5),
                                        border: Border.all(
                                          color: _usingPureMatchedInstrumental
                                              ? const Color(0xFF00E676)
                                              : const Color(0xFF00E5FF),
                                        ),
                                      ),
                                      child: Text(
                                        _usingPureMatchedInstrumental
                                            ? '🎹 100% PURE INSTRUMENTAL'
                                            : '🎛 AI VOCAL-REMOVER (-15dB)',
                                        style: TextStyle(
                                          fontSize: 8.5,
                                          fontWeight: FontWeight.w900,
                                          color: _usingPureMatchedInstrumental
                                              ? const Color(0xFF00E676)
                                              : const Color(0xFF00E5FF),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    AnimatedEqualizerBars(
                                      isPlaying: _isPlayingBacking || _isRecordingSinging,
                                      color: _isRecordingSinging ? Colors.redAccent : const Color(0xFF00E676),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            tooltip: 'Font Size +',
                            icon: const Icon(Icons.text_increase_rounded, color: Colors.amberAccent, size: 20),
                            onPressed: () {
                              setState(() {
                                _lyricFontSize = (_lyricFontSize >= 21.0) ? 14.5 : (_lyricFontSize + 2.0);
                              });
                            },
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            tooltip: 'Full-Screen Stage Teleprompter',
                            icon: const Icon(Icons.fullscreen_rounded, color: Color(0xFF00E5FF), size: 24),
                            onPressed: _openFullScreenStagePrompter,
                          ),
                        ],
                      ),
                    const SizedBox(height: 8),

                    // Script Mode Selector (Kanglish, Hinglish, Original, Kannada, Hindi)
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: _scriptModes.map((mode) {
                          final bool active = (_selectedLyricScript == mode);
                          return Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ChoiceChip(
                              label: Text(mode, style: const TextStyle(fontSize: 9.8, fontWeight: FontWeight.bold)),
                              selected: active,
                              selectedColor: const Color(0xFF00E5FF),
                              backgroundColor: const Color(0xFF141D38),
                              labelStyle: TextStyle(color: active ? Colors.black : Colors.white),
                              onSelected: (_) => setState(() => _selectedLyricScript = mode),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Synchronized Scrolling Teleprompter Stage Box
                    Container(
                      height: 185,
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.46),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: _isPreparingStage
                          ? const Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  CircularProgressIndicator(color: Color(0xFF00E5FF)),
                                  SizedBox(height: 8),
                                  Text(
                                    'Preparing Vocal-Removed Karaoke & Synced Lyrics...',
                                    style: TextStyle(fontSize: 11.5, color: Colors.amberAccent),
                                  ),
                                ],
                              ),
                            )
                          : _lyrics.isEmpty
                              ? const Center(
                                  child: Text(
                                    'Tap any song below to load Karaoke Music & Time-Synced Lyrics!',
                                    style: TextStyle(color: Colors.white60, fontSize: 12),
                                  ),
                                )
                              : ListView.builder(
                                  controller: _lyricsScrollCtrl,
                                  itemCount: _lyrics.length,
                                  itemBuilder: (ctx, idx) {
                                    final bool isCurrent = (idx == _activeLyricIndex);
                                    final bool isNext = (idx == _activeLyricIndex + 1);
                                    final String formattedLine = KaraokeEngine.formatLineForLanguageMode(
                                      _lyrics[idx].text,
                                      _selectedLyricScript,
                                    );
                                    return GestureDetector(
                                      onTap: () {
                                        _karaokeBackingPlayer.seek(Duration(milliseconds: _lyrics[idx].timeMs));
                                      },
                                      child: AnimatedContainer(
                                        duration: const Duration(milliseconds: 220),
                                        margin: const EdgeInsets.symmetric(vertical: 2.5),
                                        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 10),
                                        decoration: BoxDecoration(
                                          gradient: isCurrent
                                              ? LinearGradient(
                                                  colors: [
                                                    Colors.amber.withOpacity(0.26),
                                                    const Color(0xFF00E5FF).withOpacity(0.18),
                                                  ],
                                                )
                                              : null,
                                          borderRadius: BorderRadius.circular(10),
                                          border: isCurrent
                                              ? Border.all(color: Colors.amberAccent, width: 1.1)
                                              : null,
                                        ),
                                        child: Text(
                                          isCurrent ? '🎤 $formattedLine' : formattedLine,
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontSize: isCurrent ? (_lyricFontSize + 1.5) : _lyricFontSize,
                                            fontWeight: isCurrent
                                                ? FontWeight.w900
                                                : (isNext ? FontWeight.w700 : FontWeight.w500),
                                            color: isCurrent
                                                ? Colors.amberAccent
                                                : (isNext ? const Color(0xFF00E5FF) : Colors.white54),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                    ),
                    const SizedBox(height: 6),

                    // Progress Scrubbing Bar + Pitch Key Shifter (-4 to +4 Semitones)
                    Row(
                      children: [
                        Text(_fmtDuration(_position), style: const TextStyle(fontSize: 10, color: Colors.white70)),
                        Expanded(
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 2.5,
                              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                            ),
                            child: Slider(
                              value: _position.inSeconds
                                  .toDouble()
                                  .clamp(0, (_duration.inSeconds > 0 ? _duration.inSeconds : 1).toDouble()),
                              max: (_duration.inSeconds > 0 ? _duration.inSeconds : 1).toDouble(),
                              activeColor: const Color(0xFF00E5FF),
                              onChanged: (v) => _karaokeBackingPlayer.seek(Duration(seconds: v.toInt())),
                            ),
                          ),
                        ),
                        Text(_fmtDuration(_duration), style: const TextStyle(fontSize: 10, color: Colors.white70)),
                      ],
                    ),

                    // Vocal Remover Mode Switcher (Pure Karaoke Music vs Guide Singer Assist) + Key Pitch Shift
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            ChoiceChip(
                              label: const Text(
                                '🎹 Pure Karaoke (Vocal Cut)',
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900),
                              ),
                              selected: _isKaraokeVocalCutActive,
                              selectedColor: const Color(0xFF00E676),
                              labelStyle: TextStyle(color: _isKaraokeVocalCutActive ? Colors.black : Colors.white),
                              onSelected: (_) async {
                                setState(() {
                                  _isKaraokeVocalCutActive = true;
                                  _vocalCutStrength = 1.0;
                                });
                                await _applyNativeKaraokeVocalCutDsp();
                                if (_isPlayingBacking) {
                                  final Duration curPos = _position;
                                  await _startKaraokePracticePlayback();
                                  await _karaokeBackingPlayer.seek(curPos);
                                }
                              },
                            ),
                            const SizedBox(width: 6),
                            ChoiceChip(
                              label: const Text(
                                '🗣 Guide Singer',
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                              ),
                              selected: !_isKaraokeVocalCutActive,
                              selectedColor: Colors.amberAccent,
                              labelStyle: TextStyle(color: !_isKaraokeVocalCutActive ? Colors.black : Colors.white),
                              onSelected: (_) async {
                                setState(() {
                                  _isKaraokeVocalCutActive = false;
                                  _vocalCutStrength = 0.0;
                                });
                                await _applyNativeKaraokeVocalCutDsp();
                                if (_isPlayingBacking) {
                                  final Duration curPos = _position;
                                  await _startKaraokePracticePlayback();
                                  await _karaokeBackingPlayer.seek(curPos);
                                }
                              },
                            ),
                          ],
                        ),
                        // Key / Scale Pitch Shifter (- / + Semitones)
                        Row(
                          children: [
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                              icon: const Icon(Icons.remove_circle_outline, color: Colors.amberAccent, size: 18),
                              onPressed: () {
                                setState(() => _semitonePitchShift = (_semitonePitchShift - 1).clamp(-4, 4));
                                final double factor = 1.0 + (_semitonePitchShift * 0.05946);
                                _karaokeBackingPlayer.setPlaybackRate(factor.clamp(0.75, 1.30));
                              },
                            ),
                            Text(
                              'Key ${_semitonePitchShift >= 0 ? '+$_semitonePitchShift' : '$_semitonePitchShift'}',
                              style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900, color: Colors.white),
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                              icon: const Icon(Icons.add_circle_outline, color: Colors.amberAccent, size: 18),
                              onPressed: () {
                                setState(() => _semitonePitchShift = (_semitonePitchShift + 1).clamp(-4, 4));
                                final double factor = 1.0 + (_semitonePitchShift * 0.05946);
                                _karaokeBackingPlayer.setPlaybackRate(factor.clamp(0.75, 1.30));
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // 3 Main Stage Transport Buttons:
                    // [1. Play/Pause Karaoke Music]   [2. Record Singing (3-2-1)]   [3. Stop]
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _isPlayingBacking && !_isRecordingSinging
                                  ? Colors.amberAccent
                                  : const Color(0xFF00E5FF),
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            icon: Icon(
                              (_isPlayingBacking && !_isRecordingSinging)
                                  ? Icons.pause_circle_filled_rounded
                                  : Icons.play_circle_fill_rounded,
                              size: 20,
                            ),
                            label: Text(
                              (_isPlayingBacking && !_isRecordingSinging)
                                  ? '⏸ Pause Karaoke'
                                  : '🎹 Play Karaoke Only',
                              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 11),
                            ),
                            onPressed: () async {
                              if (_isPlayingBacking && !_isRecordingSinging) {
                                await _karaokeBackingPlayer.pause();
                              } else {
                                await _startKaraokePracticePlayback();
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _isRecordingSinging ? Colors.redAccent : const Color(0xFF00E676),
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            icon: Icon(
                              _isRecordingSinging ? Icons.stop_circle_rounded : Icons.fiber_manual_record_rounded,
                              size: 20,
                            ),
                            label: Text(
                              _countdownSec > 0
                                  ? 'Countdown $_countdownSec...'
                                  : (_isRecordingSinging ? '⏹ Stop & Save Mix' : '🔴 Sing & Record'),
                              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 11),
                            ),
                            onPressed: _countdownSec > 0
                                ? null
                                : (_isRecordingSinging ? _stopSingingRecordingAndSaveMaster : _startSingingRecording),
                          ),
                        ),
                        const SizedBox(width: 6),
                        IconButton(
                          style: IconButton.styleFrom(
                            backgroundColor: const Color(0xFF1E293B),
                          ),
                          tooltip: 'Stop All',
                          icon: const Icon(Icons.stop_rounded, color: Colors.redAccent),
                          onPressed: _stopAllPlayback,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),

                    // Expandable Pro Vocal FX & Studio Mixer Rack
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: const Text(
                        '🎛 STUDIO VOCAL FX, AUTO-TUNE & MIXER RACK',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Colors.amberAccent),
                      ),
                      children: [
                        DropdownButton<String>(
                          value: _vocalPreset,
                          isExpanded: true,
                          items: _vocalPresets
                              .map((p) => DropdownMenuItem(
                                    value: p,
                                    child: Text(p, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                                  ))
                              .toList(),
                          onChanged: (v) {
                            if (v != null) _applyPresetSelection(v);
                          },
                        ),
                        Text(
                          '🎛 AI Center-Vocal Cut Depth: ${(_vocalCutStrength * 100).toInt()}% (Removes Original Singer)',
                          style: const TextStyle(fontSize: 10.5, color: Color(0xFF00E676), fontWeight: FontWeight.bold),
                        ),
                        Slider(
                          value: _vocalCutStrength,
                          activeColor: const Color(0xFF00E676),
                          onChanged: (v) {
                            setState(() {
                              _vocalCutStrength = v;
                              _isKaraokeVocalCutActive = (v > 0.05);
                            });
                            _applyNativeKaraokeVocalCutDsp();
                          },
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          title: const Text(
                            '🎤 AI Double-Track Harmony Choir (Thickens Singing Voice)',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.amberAccent),
                          ),
                          value: _doubleChoirEnabled,
                          onChanged: (v) => setState(() => _doubleChoirEnabled = v),
                        ),
                        Text(
                          '🎹 Karaoke Music Volume: ${(_karaokeMusicVol * 100).toInt()}%',
                          style: const TextStyle(fontSize: 10.5, color: Color(0xFF00E5FF)),
                        ),
                        Slider(
                          value: _karaokeMusicVol,
                          activeColor: const Color(0xFF00E5FF),
                          onChanged: (v) {
                            setState(() => _karaokeMusicVol = v);
                            _karaokeBackingPlayer.setVolume(v);
                          },
                        ),
                        Text(
                          '🎤 Your Recorded Singing Volume: ${(_userVocalVol * 100).toInt()}%',
                          style: const TextStyle(fontSize: 10.5, color: Color(0xFF00E676)),
                        ),
                        Slider(
                          value: _userVocalVol,
                          activeColor: const Color(0xFF00E676),
                          onChanged: (v) {
                            setState(() => _userVocalVol = v);
                            _userVocalStemPlayer.setVolume(v);
                          },
                        ),
                        Text(
                          '⏱ Vocal Beat-Sync Alignment: $_vocalSyncOffsetMs ms',
                          style: const TextStyle(fontSize: 10.5, color: Colors.amberAccent),
                        ),
                        Slider(
                          value: _vocalSyncOffsetMs.toDouble(),
                          min: -300,
                          max: 300,
                          activeColor: Colors.amberAccent,
                          onChanged: (v) => setState(() => _vocalSyncOffsetMs = v.toInt()),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // ==================== 3. FILTER TABS (All Karaoke / Pure Instrumentals / My Recordings) ====================
              Row(
                children: [
                  Expanded(
                    child: _filterTabBtn('🎵 All Karaoke (${_songs.length})', 'ALL'),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _filterTabBtn(
                      '🎹 Pure Inst (${_songs.where((s) => s['isPureInstrumental'] == true || s['hasMatchedInstrumental'] == true).length})',
                      'PURE_INST',
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _filterTabBtn('🏆 My Recordings (${KaraokeEngine.savedTakes.length})', 'SAVED_TAKES'),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // ==================== 4. SAVED STUDIO KARAOKE RECORDINGS OR KARAOKE SONG CATALOG ====================
              if (_filterTab == 'SAVED_TAKES' || KaraokeEngine.savedTakes.isNotEmpty) ...[
                if (KaraokeEngine.savedTakes.isNotEmpty) ...[
                  const Text(
                    '🏆 Your Recorded Studio Karaoke Masters (Saved in /Download/DJ_Karaoke_*.m4a)',
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900, color: Colors.amberAccent),
                  ),
                  const SizedBox(height: 6),
                  ...KaraokeEngine.savedTakes.map((take) {
                    return GlassBox(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      borderRadius: 14,
                      tintColor: const Color(0xFF162442),
                      borderColor: const Color(0xFF00E676),
                      child: Row(
                        children: [
                          const Icon(Icons.mic_external_on_rounded, color: Color(0xFF00E676), size: 28),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  take.songTitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12.5),
                                ),
                                Text(
                                  '${take.presetName} • Studio Dual-Stem Master',
                                  style: const TextStyle(fontSize: 10, color: Colors.cyanAccent),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                            onPressed: () async {
                              await KaraokeEngine.deleteTake(take.id);
                              setState(() {});
                            },
                          ),
                          OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                              side: const BorderSide(color: Colors.cyanAccent),
                              visualDensity: VisualDensity.compact,
                            ),
                            onPressed: () async {
                              await _stopAllPlayback();
                              await _userVocalStemPlayer.setVolume(1.0);
                              await _userVocalStemPlayer.play(DeviceFileSource(take.vocalFilePath));
                              setState(() => _statusBanner = '🎤 Playing Your Isolated Recorded Voice Only!');
                            },
                            child: const Text('🎤 Voice', style: TextStyle(fontSize: 10, color: Colors.cyanAccent)),
                          ),
                          const SizedBox(width: 5),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.amberAccent,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              visualDensity: VisualDensity.compact,
                            ),
                            icon: const Icon(Icons.play_arrow_rounded, size: 16),
                            label: const Text('Play Mix', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900)),
                            onPressed: () => _playDualStemStudioMaster(take),
                          ),
                        ],
                      ),
                    );
                  }),
                  const SizedBox(height: 10),
                ],
              ],

              // ==================== 5. KARAOKE SONG CARDS (With [🎹 Karaoke] & [🔴 Record] Buttons) ====================
              if (_filterTab != 'SAVED_TAKES') ...[
                const Text(
                  '🎵 Tap [🎹 Karaoke] to Play Music Without Singer or [🔴 Sing] to Record',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900, color: Color(0xFF00E5FF)),
                ),
                const SizedBox(height: 6),
                if (_isLoading)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator(color: Color(0xFF00E5FF))),
                  )
                else
                  ...List.generate(visibleSongs.length, (idx) {
                    final Map<String, dynamic> s = visibleSongs[idx];
                    final bool isSelected = (_selectedSong != null && _selectedSong!['id'] == s['id']);
                    final bool isPureInst =
                        (s['isPureInstrumental'] == true || s['hasMatchedInstrumental'] == true);

                    return GlassBox(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      borderRadius: 15,
                      tintColor: isSelected ? const Color(0xFF193266) : const Color(0xFF0E172A),
                      borderColor: isSelected
                          ? Colors.amberAccent
                          : (isPureInst ? const Color(0x7700E676) : const Color(0x3300E5FF)),
                      borderWidth: isSelected ? 1.5 : 1.0,
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              s['cover'].toString(),
                              width: 46,
                              height: 46,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => _stageFallbackIcon(),
                            ),
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '#${idx + 1} • ${s['title']}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 12.5,
                                    color: isSelected ? Colors.amberAccent : Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  s['artist'].toString(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 10.5, color: Colors.white70),
                                ),
                                const SizedBox(height: 3),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                  decoration: BoxDecoration(
                                    color: isPureInst
                                        ? const Color(0xFF00E676).withOpacity(0.16)
                                        : const Color(0xFF00E5FF).withOpacity(0.16),
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                  child: Text(
                                    isPureInst
                                        ? '🎹 PURE INSTRUMENTAL KARAOKE (0% SINGER)'
                                        : '🎛 AI VOCAL-CUT KARAOKE + SYNCED LYRICS',
                                    style: TextStyle(
                                      fontSize: 8.2,
                                      fontWeight: FontWeight.w900,
                                      color: isPureInst ? const Color(0xFF00E676) : const Color(0xFF00E5FF),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 4),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF00E5FF),
                                  foregroundColor: Colors.black,
                                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                                  minimumSize: const Size(76, 28),
                                  visualDensity: VisualDensity.compact,
                                ),
                                onPressed: () => _loadSongOntoKaraokeStage(
                                  s,
                                  startKaraokePlayback: true,
                                  startRecordingImmediately: false,
                                ),
                                child: const Text(
                                  '🎹 Karaoke',
                                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900),
                                ),
                              ),
                              const SizedBox(height: 4),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF00E676),
                                  foregroundColor: Colors.black,
                                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                                  minimumSize: const Size(76, 28),
                                  visualDensity: VisualDensity.compact,
                                ),
                                onPressed: () => _loadSongOntoKaraokeStage(
                                  s,
                                  startKaraokePlayback: false,
                                  startRecordingImmediately: true,
                                ),
                                child: const Text(
                                  '🔴 Record',
                                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  }),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _filterTabBtn(String label, String tabKey) {
    final bool active = (_filterTab == tabKey);
    return GestureDetector(
      onTap: () => setState(() => _filterTab = tabKey),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 7),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: active
                ? [const Color(0xFF00E5FF), const Color(0xFF1E40AF)]
                : [const Color(0xFF0E1729), const Color(0xFF0A101D)],
          ),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: active ? Colors.amberAccent : Colors.white24,
            width: active ? 1.3 : 0.8,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w900,
            color: active ? Colors.white : Colors.white70,
          ),
        ),
      ),
    );
  }

  Widget _stageFallbackIcon() {
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: const Color(0xFF1E3A8A),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(Icons.mic_external_on_rounded, color: Colors.amberAccent, size: 24),
    );
  }
}
