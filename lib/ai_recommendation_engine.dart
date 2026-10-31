import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ============================================================================
/// IMS PRO STUDIO v9999.0 — YOUTUBE & INSTAGRAM STYLE AI RECOMMENDATION ENGINE
/// ============================================================================
/// Tracks:
///   1) Which songs the user plays (`recordSongPlay`)
///   2) How long the user listens (`recordListenDuration` & `recordSongCompletion`)
///   3) Which songs the user replays or skips (`recordReplay` / `recordQuickSkip`)
///   4) Which keywords, movies, and artists the user searches (`recordSearchQuery`)
///   5) Which songs the user likes/favorites or downloads (`recordFavoriteOrDownload`)
///   6) Time-of-day listening habits (Morning / Afternoon / Evening / Late Night)
///
/// Computes:
///   - Real-time Personalized Match Percentage (`85%–99% Match`) per track
///   - Explainable recommendation reason (`"Because you played All Ok"`,
///     `"Matches your search 'Kannada DJ'"`, `"High Replay Favorite"`)
///   - Dynamic JioSaavn 320kbps smart discovery queries updated every day
///   - Interactive "For You (AI Daily Mix)" feed & AI Taste Radar Modal
class AiRecommendationEngine {
  static final AiRecommendationEngine instance = AiRecommendationEngine._internal();
  AiRecommendationEngine._internal();

  static const String _kArtistScoresKey = 'ims_ai_artist_scores_v9999';
  static const String _kGenreScoresKey = 'ims_ai_genre_scores_v9999';
  static const String _kKeywordScoresKey = 'ims_ai_keyword_scores_v9999';
  static const String _kTrackPlaysKey = 'ims_ai_track_plays_v9999';
  static const String _kTrackCompletionsKey = 'ims_ai_track_completions_v9999';
  static const String _kTrackListenSecondsKey = 'ims_ai_track_listen_sec_v9999';
  static const String _kSearchHistoryKey = 'ims_ai_search_history_v9999';
  static const String _kRecentPlayedIdsKey = 'ims_ai_recent_played_ids_v9999';
  static const String _kRecentPlayedTitlesKey = 'ims_ai_recent_played_titles_v9999';
  static const String _kRecentPlayedArtistsKey = 'ims_ai_recent_played_artists_v9999';
  static const String _kTimeOfDayClusterKey = 'ims_ai_time_of_day_v9999';

  final ValueNotifier<int> tasteUpdateNotifier = ValueNotifier<int>(0);

  Map<String, double> _artistScores = {};
  Map<String, double> _genreScores = {};
  Map<String, double> _keywordScores = {};
  Map<String, int> _trackPlayCounts = {};
  Map<String, int> _trackCompletionCounts = {};
  Map<String, int> _trackListenSeconds = {};
  List<String> _searchHistory = [];
  List<String> _recentPlayedIds = [];
  Map<String, String> _recentPlayedTitles = {};
  Map<String, String> _recentPlayedArtists = {};
  Map<String, double> _timeSlotGenreWeights = {};
  bool _initialized = false;

  /// Comprehensive Indian & International Artist Similarity Graph
  /// Maps popular artists to acoustically and stylistically related artists
  /// so playing or searching one artist immediately boosts similar artists
  /// (just like YouTube Music & Instagram Reels audio recommendations).
  static const Map<String, List<String>> artistSimilarityGraph = {
    'all ok': [
      'Chandan Shetty',
      'Rahul Dit-O',
      'MC Bijju',
      'Gubbi',
      'Sanjith Hegde',
      'All Ok Kannada Rap',
      'Dushyant',
      'Navin Sajju',
    ],
    'chandan shetty': [
      'All Ok',
      'Rahul Dit-O',
      'Sanjith Hegde',
      'Vijay Prakash',
      'Arjun Janya',
      'Gurukiran',
      'Kannada Party DJ Hits',
    ],
    'arjun janya': [
      'Vijay Prakash',
      'Sanjith Hegde',
      'Sonu Nigam Kannada',
      'Armaan Malik Kannada',
      'V. Harikrishna',
      'Ajaneesh Loknath',
      'Charan Raj',
      'Ravi Basrur',
    ],
    'sanjith hegde': [
      'Arjun Janya',
      'Charan Raj',
      'Vasuki Vaibhav',
      'Armaan Malik',
      'Sid Sriram Kannada',
      'Nobin Paul',
      'Judah Sandhy',
    ],
    'vijay prakash': [
      'Arjun Janya',
      'Rajesh Krishnan',
      'Hemanth Kumar',
      'Ajaneesh Loknath',
      'V. Harikrishna',
      'A.R. Rahman',
      'S. P. Balasubrahmanyam',
    ],
    'sonu nigam': [
      'Shreya Ghoshal',
      'Rajesh Krishnan',
      'K. S. Chithra',
      'Armaan Malik',
      'Udit Narayan',
      'Kumar Sanu',
      'Arijit Singh',
      'Arjun Janya',
    ],
    'shreya ghoshal': [
      'Sonu Nigam',
      'Arijit Singh',
      'Armaan Malik',
      'K. S. Chithra',
      'Anuradha Bhat',
      'Chinmayi',
      'Sunidhi Chauhan',
    ],
    'a.r. rahman': [
      'Sonu Nigam',
      'Shreya Ghoshal',
      'S. P. Balasubrahmanyam',
      'Sid Sriram',
      'Hariharan',
      'Karthik',
      'Shankar Mahadevan',
      'Ilaiyaraaja',
    ],
    's. p. balasubrahmanyam': [
      'K. S. Chithra',
      'S. Janaki',
      'Ilaiyaraaja',
      'Hamsalekha',
      'Dr. Rajkumar',
      'Rajesh Krishnan',
      'Yesudas',
    ],
    'ravi basrur': [
      'Santosh Venky',
      'Ananya Bhat',
      'Vijay Prakash',
      'Ajaneesh Loknath',
      'KGF Mass BGM',
      'Salaar Mass Track',
      'Ugramm Theme',
    ],
    'ajaneesh loknath': [
      'Vijay Prakash',
      'Kantara Folk Hits',
      'Charan Raj',
      'Vasuki Vaibhav',
      'Arjun Janya',
      'Ananya Bhat',
    ],
    'arijit singh': [
      'Atif Aslam',
      'Jubin Nautiyal',
      'Armaan Malik',
      'Vishal Mishra',
      'Darshan Raval',
      'Shreya Ghoshal',
      'Pritam',
      'Sachin-Jigar',
    ],
    'arman malik': [
      'Sanjith Hegde',
      'Arijit Singh',
      'Sonu Nigam',
      'Darshan Raval',
      'Amaal Mallik',
      'Arjun Janya',
    ],
    'armaan malik': [
      'Sanjith Hegde',
      'Arijit Singh',
      'Sonu Nigam',
      'Darshan Raval',
      'Amaal Mallik',
      'Arjun Janya',
    ],
    'vishal mishra': [
      'Arijit Singh',
      'Jubin Nautiyal',
      'B Praak',
      'Sachet Tandon',
      'Mithoon',
      'Anirudh Ravichander',
    ],
    'anirudh ravichander': [
      'Thaman S',
      'Devi Sri Prasad',
      'Sid Sriram',
      'Ravi Basrur',
      'Vishal Dadlani',
      'Dhee',
    ],
    'thaman s': [
      'Anirudh Ravichander',
      'Devi Sri Prasad',
      'Armaan Malik',
      'Sid Sriram',
      'Nakash Aziz',
    ],
    'devi sri prasad': [
      'Thaman S',
      'Anirudh Ravichander',
      'Nakash Aziz',
      'Sid Sriram',
      'Mika Singh',
    ],
    'sid sriram': [
      'Sanjith Hegde',
      'Armaan Malik',
      'A.R. Rahman',
      'Anirudh Ravichander',
      'Thaman S',
      'Chinmayi',
    ],
    'badshah': [
      'Yo Yo Honey Singh',
      'Raftaar',
      'Diljit Dosanjh',
      'Guru Randhawa',
      'Neha Kakkar',
      'Hardy Sandhu',
    ],
    'diljit dosanjh': [
      'AP Dhillon',
      'Karan Aujla',
      'Guru Randhawa',
      'Badshah',
      'Shubh',
    ],
    'hamsalekha': [
      'S. P. Balasubrahmanyam',
      'K. S. Chithra',
      'Rajesh Krishnan',
      'Mano',
      'L. N. Shastri',
      'Dr. Rajkumar',
    ],
    'v. harikrishna': [
      'Sonu Nigam',
      'Tippu',
      'Vijay Prakash',
      'Rajesh Krishnan',
      'Arjun Janya',
      'Puneeth Rajkumar Hits',
    ],
    'puneeth rajkumar': [
      'V. Harikrishna',
      'Arjun Janya',
      'Puneeth Rajkumar Dance Hits',
      'Power Star Appu Songs',
      'Sonu Nigam Kannada',
    ],
  };

  /// Deep Genre & Mood Classifier Keywords
  static const Map<String, List<String>> genreClassifierKeywords = {
    'Kannada': [
      'kannada', 'sandalwood', 'arjun janya', 'chandan shetty', 'all ok',
      'sanjith hegde', 'vijay prakash', 'rajkumar', 'puneeth', 'appu',
      'sudeep', 'darshan', 'yash', 'upendra', 'rishab', 'kantara', 'kgf',
      'hamsalekha', 'harikrishna', 'rajesh krishnan', 'janapada', 'uttara karnataka'
    ],
    'Hindi': [
      'hindi', 'bollywood', 'arijit', 'pritam', 'jubin', 'armaan malik',
      'vishal mishra', 'badshah', 'shreya ghoshal', 'sonu nigam', 'udit',
      'kumar sanu', 'atif', 'sachin-jigar', 'tanishk', 'nehakakkar', 'diljit'
    ],
    'Marriage & Wedding': [
      'marriage', 'wedding', 'mangala', 'sangeet', 'haldi', 'mehendi',
      'baraat', 'shaadi', 'dulhan', 'dulha', 'kalyana', 'muhurtham',
      'reception', 'jodi', 'lagnada', 'vivaha', 'step', 'family dance'
    ],
    'Fashion Show & Ramp': [
      'fashion', 'ramp', 'walk', 'runway', 'model', 'bass boost',
      'instrumental beat', 'edm', 'trap', 'phonk', 'attitude bgm',
      'couture', 'electro', 'club mix'
    ],
    'DJ Bass & Party': [
      'dj', 'remix', 'mashup', 'party', 'club', 'dance', 'bass',
      'disco', 'beat', 'nonstop', 'electro', 'dhol', 'teenmaar', 'tapori'
    ],
    'Devotional & Bhajan': [
      'devotional', 'bhakti', 'bhajan', 'aarti', 'mantra', 'stotra',
      'suprabhata', 'hanuman', 'shiva', 'krishna', 'ganesha', 'manjunatha',
      'chamundeshwari', 'raghavendra', 'tirupati', 'ayyappa', 'om'
    ],
    'Romantic & Melody': [
      'love', 'romantic', 'melody', 'prema', 'hrudaya', 'dil', 'ishq',
      'mohabbat', 'pyaar', 'soulful', 'unplugged', 'lofi', 'acoustic',
      'neene', 'ninna', 'jotheyali', 'mungaru male'
    ],
    'Mass & Hero Entry': [
      'mass', 'entry', 'hero', 'boss', 'king', 'monster', 'toofan',
      'sultan', 'elevation', 'bgm', 'power', 'fire', 'villain', 'salaga',
      'tagaru', 'kgf', 'salaar', 'pushpa', 'jailer', 'leo', 'toxic'
    ],
    'Janapada & Folk': [
      'janapada', 'folk', 'lavani', 'kolata', 'dollu', 'desi', 'grama',
      'halli', 'chuttu chuttu', 'kuruba', 'madeshwara', 'yellamma'
    ],
    'Rap & Hip-Hop': [
      'rap', 'hip hop', 'all ok', 'mc bijju', 'rahul dit-o', 'badshah',
      'raftaar', 'divine', 'emiway', 'yo yo honey singh', 'cypher'
    ],
  };

  Future<void> ensureInitialized() async {
    if (_initialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _artistScores = _decodeDoubleMap(prefs.getString(_kArtistScoresKey));
      _genreScores = _decodeDoubleMap(prefs.getString(_kGenreScoresKey));
      _keywordScores = _decodeDoubleMap(prefs.getString(_kKeywordScoresKey));
      _trackPlayCounts = _decodeIntMap(prefs.getString(_kTrackPlaysKey));
      _trackCompletionCounts = _decodeIntMap(prefs.getString(_kTrackCompletionsKey));
      _trackListenSeconds = _decodeIntMap(prefs.getString(_kTrackListenSecondsKey));
      _searchHistory = prefs.getStringList(_kSearchHistoryKey) ?? [];
      _recentPlayedIds = prefs.getStringList(_kRecentPlayedIdsKey) ?? [];
      _recentPlayedTitles = _decodeStringMap(prefs.getString(_kRecentPlayedTitlesKey));
      _recentPlayedArtists = _decodeStringMap(prefs.getString(_kRecentPlayedArtistsKey));
      _timeSlotGenreWeights = _decodeDoubleMap(prefs.getString(_kTimeOfDayClusterKey));

      // Seed default smart baseline if brand new profile
      if (_genreScores.isEmpty) {
        _genreScores['Kannada'] = 25.0;
        _genreScores['Hindi'] = 18.0;
        _genreScores['DJ Bass & Party'] = 15.0;
        _genreScores['Marriage & Wedding'] = 15.0;
        _genreScores['Romantic & Melody'] = 14.0;
      }
      _initialized = true;
    } catch (_) {
      _initialized = true;
    }
  }

  Map<String, double> _decodeDoubleMap(String? raw) {
    if (raw == null || raw.isEmpty) return {};
    try {
      final Map<String, dynamic> decoded = jsonDecode(raw);
      return decoded.map((k, v) => MapEntry(k, (v as num).toDouble()));
    } catch (_) {
      return {};
    }
  }

  Map<String, int> _decodeIntMap(String? raw) {
    if (raw == null || raw.isEmpty) return {};
    try {
      final Map<String, dynamic> decoded = jsonDecode(raw);
      return decoded.map((k, v) => MapEntry(k, (v as num).toInt()));
    } catch (_) {
      return {};
    }
  }

  Map<String, String> _decodeStringMap(String? raw) {
    if (raw == null || raw.isEmpty) return {};
    try {
      final Map<String, dynamic> decoded = jsonDecode(raw);
      return decoded.map((k, v) => MapEntry(k, v.toString()));
    } catch (_) {
      return {};
    }
  }

  Future<void> _persistState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kArtistScoresKey, jsonEncode(_artistScores));
      await prefs.setString(_kGenreScoresKey, jsonEncode(_genreScores));
      await prefs.setString(_kKeywordScoresKey, jsonEncode(_keywordScores));
      await prefs.setString(_kTrackPlaysKey, jsonEncode(_trackPlayCounts));
      await prefs.setString(_kTrackCompletionsKey, jsonEncode(_trackCompletionCounts));
      await prefs.setString(_kTrackListenSecondsKey, jsonEncode(_trackListenSeconds));
      await prefs.setStringList(_kSearchHistoryKey, _searchHistory.take(50).toList());
      await prefs.setStringList(_kRecentPlayedIdsKey, _recentPlayedIds.take(60).toList());
      await prefs.setString(_kRecentPlayedTitlesKey, jsonEncode(_recentPlayedTitles));
      await prefs.setString(_kRecentPlayedArtistsKey, jsonEncode(_recentPlayedArtists));
      await prefs.setString(_kTimeOfDayClusterKey, jsonEncode(_timeSlotGenreWeights));
      tasteUpdateNotifier.value++;
    } catch (_) {}
  }

  String _currentDaySlot() {
    final int hr = DateTime.now().hour;
    if (hr >= 5 && hr < 11) return 'MORNING';
    if (hr >= 11 && hr < 17) return 'AFTERNOON';
    if (hr >= 17 && hr < 22) return 'EVENING';
    return 'NIGHT';
  }

  /// Extracts individual artist names from comma/feat/& separated strings
  List<String> extractNormalizedArtists(String rawArtist, String rawTitle) {
    final List<String> out = [];
    final String cleaned = rawArtist
        .replaceAll(RegExp(r'\b(feat\.?|ft\.?|starring|music by|composed by)\b', caseSensitive: false), ',')
        .replaceAll('&', ',')
        .replaceAll('/', ',')
        .replaceAll('-', ',');
    for (final part in cleaned.split(',')) {
      final String p = part.trim();
      if (p.length >= 3 &&
          !p.toLowerCase().contains('unknown') &&
          !p.toLowerCase().contains('various')) {
        out.add(p);
      }
    }
    return out;
  }

  /// Extracts movie/album name from title like `Mangala Sangama (From "Bajarangi")`
  String? extractMovieOrAlbumName(String rawTitle) {
    final RegExp fromRegex = RegExp(r'[Ff]rom\s+"([^"]+)"');
    final match = fromRegex.firstMatch(rawTitle);
    if (match != null && match.group(1) != null) {
      return match.group(1)!.trim();
    }
    final RegExp parenRegex = RegExp(r'\(([^)]+)\)');
    final pMatch = parenRegex.firstMatch(rawTitle);
    if (pMatch != null && pMatch.group(1) != null) {
      final String inside = pMatch.group(1)!.replaceAll('From', '').replaceAll('"', '').trim();
      if (inside.length >= 3) return inside;
    }
    return null;
  }

  /// Classifies a song into one or more genres based on title, artist, and category
  List<String> classifyTrackGenres(String title, String artist, String category) {
    final String combined = '${title.toLowerCase()} ${artist.toLowerCase()} ${category.toLowerCase()}';
    final List<String> matched = [];
    genreClassifierKeywords.forEach((genreName, keywords) {
      for (final kw in keywords) {
        if (combined.contains(kw)) {
          matched.add(genreName);
          break;
        }
      }
    });
    if (matched.isEmpty) {
      if (category.isNotEmpty) matched.add(category);
    }
    return matched;
  }

  /// 1. Called every time a user starts playing a song
  Future<void> recordSongPlay({
    required String trackId,
    required String title,
    required String artist,
    required String category,
    String? activeSearchQuery,
  }) async {
    await ensureInitialized();

    _trackPlayCounts[trackId] = (_trackPlayCounts[trackId] ?? 0) + 1;
    final int playCount = _trackPlayCounts[trackId]!;

    _recentPlayedIds.remove(trackId);
    _recentPlayedIds.insert(0, trackId);
    if (_recentPlayedIds.length > 60) {
      _recentPlayedIds = _recentPlayedIds.sublist(0, 60);
    }
    _recentPlayedTitles[trackId] = title;
    _recentPlayedArtists[trackId] = artist;

    // Replay multiplier: if user plays the same song multiple times, boost heavily!
    final double replayMultiplier = playCount >= 3 ? 2.2 : (playCount == 2 ? 1.5 : 1.0);

    final List<String> artists = extractNormalizedArtists(artist, title);
    for (final a in artists) {
      final String key = a.toLowerCase();
      _artistScores[key] = (_artistScores[key] ?? 0.0) + (14.0 * replayMultiplier);

      // Propagate 35% affinity boost to similar artists in our Knowledge Graph!
      for (final entry in artistSimilarityGraph.entries) {
        if (key.contains(entry.key) || entry.key.contains(key)) {
          for (final simArtist in entry.value) {
            final String simKey = simArtist.toLowerCase();
            _artistScores[simKey] = (_artistScores[simKey] ?? 0.0) + (5.0 * replayMultiplier);
          }
        }
      }
    }

    final String? movie = extractMovieOrAlbumName(title);
    if (movie != null && movie.length >= 3) {
      final String mKey = movie.toLowerCase();
      _keywordScores[mKey] = (_keywordScores[mKey] ?? 0.0) + (12.0 * replayMultiplier);
    }

    // Tokenize meaningful title words
    for (final word in title.toLowerCase().split(RegExp(r'[^a-z0-9]+'))) {
      if (word.length >= 4 &&
          !const {'from', 'song', 'video', 'audio', 'full', 'lyrical', 'official', 'feat', 'with'}.contains(word)) {
        _keywordScores[word] = (_keywordScores[word] ?? 0.0) + (6.0 * replayMultiplier);
      }
    }

    final List<String> genres = classifyTrackGenres(title, artist, category);
    final String slot = _currentDaySlot();
    for (final g in genres) {
      _genreScores[g] = (_genreScores[g] ?? 0.0) + (10.0 * replayMultiplier);
      final String slotKey = '${slot}_$g';
      _timeSlotGenreWeights[slotKey] = (_timeSlotGenreWeights[slotKey] ?? 0.0) + 8.0;
    }

    if (activeSearchQuery != null && activeSearchQuery.trim().length >= 2) {
      await recordSearchQuery(activeSearchQuery.trim(), persistImmediately: false);
    }

    await _persistState();
  }

  /// 2. Called when a user listens to a song for significant duration or completes it
  /// (YouTube Watch-Time & Instagram Loop Retention signal)
  Future<void> recordListenRetention({
    required String trackId,
    required String title,
    required String artist,
    required String category,
    required int listenedSeconds,
    required bool completedFullSong,
  }) async {
    await ensureInitialized();

    _trackListenSeconds[trackId] = (_trackListenSeconds[trackId] ?? 0) + max(0, listenedSeconds);

    if (completedFullSong) {
      _trackCompletionCounts[trackId] = (_trackCompletionCounts[trackId] ?? 0) + 1;
    }

    // Quick skip (< 8 seconds) without completion -> reduce score slightly
    if (!completedFullSong && listenedSeconds < 8 && (_trackPlayCounts[trackId] ?? 0) <= 1) {
      final List<String> artists = extractNormalizedArtists(artist, title);
      for (final a in artists) {
        final String key = a.toLowerCase();
        _artistScores[key] = max(0.0, (_artistScores[key] ?? 5.0) - 3.0);
      }
      await _persistState();
      return;
    }

    // High retention (> 40s or full completion) -> massive positive reinforcement!
    if (completedFullSong || listenedSeconds >= 40) {
      final double retentionBoost = completedFullSong ? 28.0 : 16.0;
      final List<String> artists = extractNormalizedArtists(artist, title);
      for (final a in artists) {
        final String key = a.toLowerCase();
        _artistScores[key] = (_artistScores[key] ?? 0.0) + retentionBoost;
      }
      final List<String> genres = classifyTrackGenres(title, artist, category);
      for (final g in genres) {
        _genreScores[g] = (_genreScores[g] ?? 0.0) + (retentionBoost * 0.7);
      }
      await _persistState();
    }
  }

  /// 3. Called whenever a user searches for any song, artist, movie, or vibe
  Future<void> recordSearchQuery(String rawQuery, {bool persistImmediately = true}) async {
    await ensureInitialized();
    final String q = rawQuery.trim();
    if (q.length < 2) return;

    _searchHistory.removeWhere((item) => item.toLowerCase() == q.toLowerCase());
    _searchHistory.insert(0, q);
    if (_searchHistory.length > 50) {
      _searchHistory = _searchHistory.sublist(0, 50);
    }

    final String qLower = q.toLowerCase();
    _keywordScores[qLower] = (_keywordScores[qLower] ?? 0.0) + 24.0;
    _artistScores[qLower] = (_artistScores[qLower] ?? 0.0) + 22.0;

    for (final token in qLower.split(RegExp(r'\s+'))) {
      if (token.length >= 3) {
        _keywordScores[token] = (_keywordScores[token] ?? 0.0) + 12.0;
      }
    }

    // Boost matching genres from search query
    for (final g in classifyTrackGenres(q, q, '')) {
      _genreScores[g] = (_genreScores[g] ?? 0.0) + 16.0;
    }

    // Boost similar artists from knowledge graph if user searched an artist
    for (final entry in artistSimilarityGraph.entries) {
      if (qLower.contains(entry.key) || entry.key.contains(qLower)) {
        _artistScores[entry.key] = (_artistScores[entry.key] ?? 0.0) + 25.0;
        for (final sim in entry.value) {
          final String simKey = sim.toLowerCase();
          _artistScores[simKey] = (_artistScores[simKey] ?? 0.0) + 10.0;
        }
      }
    }

    if (persistImmediately) {
      await _persistState();
    }
  }

  /// 4. Called when a user favorites (hearts) or downloads a song for offline use
  Future<void> recordFavoriteOrDownload({
    required String trackId,
    required String title,
    required String artist,
    required String category,
    required bool isDownload,
  }) async {
    await ensureInitialized();
    final double superBoost = isDownload ? 45.0 : 38.0;

    _trackCompletionCounts[trackId] = (_trackCompletionCounts[trackId] ?? 0) + 2;
    for (final a in extractNormalizedArtists(artist, title)) {
      final String key = a.toLowerCase();
      _artistScores[key] = (_artistScores[key] ?? 0.0) + superBoost;
    }
    for (final g in classifyTrackGenres(title, artist, category)) {
      _genreScores[g] = (_genreScores[g] ?? 0.0) + (superBoost * 0.6);
    }
    await _persistState();
  }

  /// Computes a raw relevance score for any candidate track
  double computeTrackAffinityScore({
    required String trackId,
    required String title,
    required String artist,
    required String category,
    required bool isFavorited,
  }) {
    double score = 15.0; // Base score

    // 1. Direct Track Play & Completion History (High Replay Value)
    final int plays = _trackPlayCounts[trackId] ?? 0;
    final int completions = _trackCompletionCounts[trackId] ?? 0;
    final int listenSecs = _trackListenSeconds[trackId] ?? 0;

    if (plays > 0) {
      score += min(55.0, plays * 14.0);
    }
    if (completions > 0) {
      score += min(65.0, completions * 22.0);
    }
    if (listenSecs >= 60) {
      score += min(35.0, (listenSecs / 60.0) * 8.0);
    }
    if (isFavorited) {
      score += 48.0;
    }

    // 2. Artist Affinity Score
    final String artistLower = artist.toLowerCase();
    final String titleLower = title.toLowerCase();
    for (final entry in _artistScores.entries) {
      if (entry.value <= 0) continue;
      if (artistLower.contains(entry.key) || titleLower.contains(entry.key)) {
        score += min(70.0, entry.value * 1.35);
      }
    }

    // 3. Search History & Keyword Match Score
    for (int i = 0; i < min(15, _searchHistory.length); i++) {
      final String q = _searchHistory[i].toLowerCase();
      final double recencyWeight = max(0.35, 1.0 - (i * 0.05));
      if (titleLower.contains(q) || artistLower.contains(q)) {
        score += 45.0 * recencyWeight;
      } else {
        for (final tok in q.split(RegExp(r'\s+'))) {
          if (tok.length >= 3 && (titleLower.contains(tok) || artistLower.contains(tok))) {
            score += 18.0 * recencyWeight;
          }
        }
      }
    }

    for (final entry in _keywordScores.entries) {
      if (entry.value <= 0) continue;
      if (titleLower.contains(entry.key) || artistLower.contains(entry.key)) {
        score += min(35.0, entry.value * 0.8);
      }
    }

    // 4. Genre & Time-of-Day Contextual Score
    final List<String> genres = classifyTrackGenres(title, artist, category);
    final String slot = _currentDaySlot();
    for (final g in genres) {
      score += min(30.0, (_genreScores[g] ?? 0.0) * 0.45);
      final double slotBonus = _timeSlotGenreWeights['${slot}_$g'] ?? 0.0;
      score += min(18.0, slotBonus * 0.5);
    }

    return score;
  }

  /// Converts raw affinity score into a YouTube/Netflix style `84%–99% Match` badge
  int computeMatchPercentage({
    required String trackId,
    required String title,
    required String artist,
    required String category,
    required bool isFavorited,
  }) {
    final double raw = computeTrackAffinityScore(
      trackId: trackId,
      title: title,
      artist: artist,
      category: category,
      isFavorited: isFavorited,
    );
    if (raw >= 140) return 99;
    if (raw >= 110) return 97;
    if (raw >= 85) return 95;
    if (raw >= 65) return 93;
    if (raw >= 45) return 90;
    if (raw >= 30) return 87;
    return 84;
  }

  /// Returns an explainable YouTube/Instagram recommendation badge reason for a track
  String getRecommendationReason({
    required String trackId,
    required String title,
    required String artist,
    required String category,
    required bool isFavorited,
  }) {
    final int plays = _trackPlayCounts[trackId] ?? 0;
    final int completions = _trackCompletionCounts[trackId] ?? 0;

    if (isFavorited) {
      return '❤️ In Your Favorites • High Affinity';
    }
    if (completions >= 2 || plays >= 3) {
      return '🔥 On Repeat (${plays}x Played)';
    }

    final String titleLower = title.toLowerCase();
    final String artistLower = artist.toLowerCase();

    // Check recent search match
    for (final q in _searchHistory.take(10)) {
      final String qLow = q.toLowerCase();
      if (titleLower.contains(qLow) || artistLower.contains(qLow)) {
        return '🔎 Because you searched "$q"';
      }
      for (final tok in qLow.split(RegExp(r'\s+'))) {
        if (tok.length >= 4 && (titleLower.contains(tok) || artistLower.contains(tok))) {
          return '🔎 Matches your search "$q"';
        }
      }
    }

    // Check top artist match
    final List<MapEntry<String, double>> topArtists = getTopArtists(limit: 8);
    for (final entry in topArtists) {
      if (artistLower.contains(entry.key) || titleLower.contains(entry.key)) {
        final String displayArtist = _capitalizeWords(entry.key);
        return '🎧 Because you listen to $displayArtist';
      }
    }

    if (plays == 1) {
      return '✨ Recently Played by You';
    }

    // Top genre match
    final List<MapEntry<String, double>> topGenres = getTopGenres(limit: 3);
    final List<String> trackGenres = classifyTrackGenres(title, artist, category);
    for (final g in topGenres) {
      if (trackGenres.contains(g.key)) {
        return '🎯 Top Pick in ${g.key}';
      }
    }

    return '⚡ Recommended for Your Daily Mix';
  }

  String _capitalizeWords(String input) {
    return input
        .split(' ')
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  List<MapEntry<String, double>> getTopArtists({int limit = 10}) {
    final entries = _artistScores.entries.where((e) => e.value > 2.0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.take(limit).toList();
  }

  List<MapEntry<String, double>> getTopGenres({int limit = 6}) {
    final entries = _genreScores.entries.where((e) => e.value > 1.0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.take(limit).toList();
  }

  List<String> getRecentSearches({int limit = 10}) {
    return _searchHistory.take(limit).toList();
  }

  int getTotalSongsPlayedCount() {
    int sum = 0;
    for (final v in _trackPlayCounts.values) {
      sum += v;
    }
    return sum;
  }

  int getTotalListenMinutes() {
    int secs = 0;
    for (final v in _trackListenSeconds.values) {
      secs += v;
    }
    return max(1, (secs / 60).round());
  }

  /// Generates personalized JioSaavn 320kbps search queries every day based on:
  /// 1) User's recent searches
  /// 2) User's top-played artists + similar artists from the Knowledge Graph
  /// 3) User's most-listened genres & current time-of-day vibe
  List<String> generatePersonalizedDailyQueries({int maxQueries = 10}) {
    final List<String> queries = [];

    // 1. Top recent user searches (direct intent!)
    for (final s in _searchHistory.take(3)) {
      if (!queries.contains(s)) queries.add(s);
    }

    // 2. Top played artists + 1 related artist from Knowledge Graph
    final topArtists = getTopArtists(limit: 4);
    for (final a in topArtists) {
      final String cleanArtist = _capitalizeWords(a.key);
      final String hitQuery = '$cleanArtist Superhit Songs';
      if (!queries.contains(hitQuery)) queries.add(hitQuery);

      for (final entry in artistSimilarityGraph.entries) {
        if (a.key.contains(entry.key) || entry.key.contains(a.key)) {
          if (entry.value.isNotEmpty) {
            final String sim = entry.value.first;
            if (!queries.contains(sim)) queries.add(sim);
          }
          break;
        }
      }
    }

    // 3. Top genre + time-of-day queries
    final topGenres = getTopGenres(limit: 3);
    for (final g in topGenres) {
      if (g.key == 'Kannada') {
        queries.add('Kannada 2026 Superhit Melody & Mass Songs');
      } else if (g.key == 'Hindi') {
        queries.add('Bollywood 2026 Top Trending Chartbusters');
      } else if (g.key == 'Marriage & Wedding') {
        queries.add('Kannada Hindi Marriage Sangeet Dance Hits');
      } else if (g.key == 'DJ Bass & Party') {
        queries.add('Kannada Hindi DJ Remix High Bass Party Hits');
      } else if (g.key == 'Mass & Hero Entry') {
        queries.add('Kannada South Mass Hero Entry BGM & Songs');
      } else if (g.key == 'Devotional & Bhajan') {
        queries.add('Kannada Bhakti Devotional Morning Songs');
      }
    }

    // 4. Time-of-day smart discovery fallback
    final String slot = _currentDaySlot();
    if (slot == 'MORNING') {
      queries.add('Kannada Morning Melody & Suprabhata Hits');
    } else if (slot == 'EVENING' || slot == 'NIGHT') {
      queries.add('Kannada Hindi Top DJ Party & Trending Hits');
    } else {
      queries.add('Kannada Evergreen & Latest Superhit Songs');
    }

    final List<String> deduplicated = [];
    for (final q in queries) {
      if (!deduplicated.any((x) => x.toLowerCase() == q.toLowerCase())) {
        deduplicated.add(q);
      }
      if (deduplicated.length >= maxQueries) break;
    }
    return deduplicated;
  }

  /// Resets taste profile if requested by user
  Future<void> resetTasteProfile() async {
    _artistScores.clear();
    _genreScores.clear();
    _keywordScores.clear();
    _trackPlayCounts.clear();
    _trackCompletionCounts.clear();
    _trackListenSeconds.clear();
    _searchHistory.clear();
    _recentPlayedIds.clear();
    _recentPlayedTitles.clear();
    _recentPlayedArtists.clear();
    _timeSlotGenreWeights.clear();
    await _persistState();
  }
}

