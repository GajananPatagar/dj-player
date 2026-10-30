import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OtaUpdateEngine {
  static const int currentBuildNumber = 500;
  static const String currentVersionName = '500.0.0';
  static const String githubRepoOwner = 'GajananPatagar';
  static const String githubRepoName = 'dj-player';

  static const MethodChannel _nativeChannel = MethodChannel('dj_native_tts');

  static final ValueNotifier<String> otaStatusBanner = ValueNotifier<String>(
    '✨ v500.0 Pro • Auto-OTA & Daily Self-Update Active',
  );
  static final ValueNotifier<double?> otaDownloadProgress = ValueNotifier<double?>(null);
  static final ValueNotifier<String> dailyRefreshStamp = ValueNotifier<String>('');

  static Timer? _periodicTimer;
  static bool _isCheckingOrDownloading = false;

  /// Starts both:
  /// 1) Daily Self-Update (Refreshes charts, categories, and remote config every day automatically)
  /// 2) Zero-Click Silent OTA APK Auto-Update (Automatically downloads & launches installer when a new GitHub build is pushed)
  static Future<void> initAutoOtaAndDailySelfUpdate({
    required Future<void> Function() onDailyContentRefresh,
  }) async {
    await _checkAndRunDailySelfUpdate(onDailyContentRefresh);
    // Run OTA check 4 seconds after startup so UI renders smoothly first
    Future.delayed(const Duration(seconds: 4), () {
      checkAndAutoInstallOtaUpdate();
    });

    _periodicTimer?.cancel();
    _periodicTimer = Timer.periodic(const Duration(hours: 3), (_) async {
      await _checkAndRunDailySelfUpdate(onDailyContentRefresh);
      await checkAndAutoInstallOtaUpdate();
    });
  }

  static String _todayDateKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  static Future<void> _checkAndRunDailySelfUpdate(
    Future<void> Function() onDailyContentRefresh,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String today = _todayDateKey();
      final String lastUpdatedDay = prefs.getString('v500_last_daily_self_update') ?? '';
      dailyRefreshStamp.value = 'Synced $today';

      if (lastUpdatedDay != today) {
        otaStatusBanner.value = '🔄 Daily Self-Update: Refreshing $today New Songs & Mixes...';
        await onDailyContentRefresh();
        await prefs.setString('v500_last_daily_self_update', today);
        otaStatusBanner.value = '🟢 Auto-Updated for $today • v$currentVersionName Pro';
      }
    } catch (_) {}
  }

  /// Zero-Button OTA Update Check:
  /// Checks ota_version.json on main branch + GitHub Releases latest API.
  /// If remote buildNumber > currentBuildNumber, automatically downloads APK and triggers install!
  static Future<void> checkAndAutoInstallOtaUpdate({bool forceManualCheck = false}) async {
    if (_isCheckingOrDownloading) return;
    _isCheckingOrDownloading = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      final int lastInstalledAttempt = prefs.getInt('v500_last_ota_attempt_build') ?? currentBuildNumber;

      int remoteBuild = currentBuildNumber;
      String remoteVersion = currentVersionName;
      String? apkDownloadUrl;
      String releaseNotes = 'Auto-OTA Pro Upgrade';

      final Map<String, String> headers = {
        'User-Agent': 'DJPlayer-OTA-Updater/500.0 (Android)',
        'Accept': 'application/json',
        'Cache-Control': 'no-cache',
      };

      // 1. Check raw ota_version.json on GitHub main branch (instant after git push + workflow build)
      try {
        final String rawVersionUrl =
            'https://raw.githubusercontent.com/$githubRepoOwner/$githubRepoName/main/ota_version.json?t=${DateTime.now().millisecondsSinceEpoch}';
        final res = await http.get(Uri.parse(rawVersionUrl), headers: headers).timeout(const Duration(seconds: 7));
        if (res.statusCode == 200) {
          final Map<String, dynamic> data = jsonDecode(res.body);
          remoteBuild = int.tryParse((data['buildNumber'] ?? currentBuildNumber).toString()) ?? currentBuildNumber;
          remoteVersion = (data['versionName'] ?? currentVersionName).toString();
          apkDownloadUrl = data['apkUrl']?.toString();
          releaseNotes = (data['notes'] ?? releaseNotes).toString();
        }
      } catch (_) {}

      // 2. Also check GitHub Releases Latest API
      try {
        final String relUrl = 'https://api.github.com/repos/$githubRepoOwner/$githubRepoName/releases/latest';
        final relRes = await http.get(Uri.parse(relUrl), headers: headers).timeout(const Duration(seconds: 7));
        if (relRes.statusCode == 200) {
          final Map<String, dynamic> relData = jsonDecode(relRes.body);
          final String tagName = (relData['tag_name'] ?? '').toString();
          // Extract numeric build from tag e.g. v501 or v500.1+502
          final RegExp numReg = RegExp(r'(\d+)');
          final Iterable<Match> matches = numReg.allMatches(tagName);
          if (matches.isNotEmpty) {
            final int tagNum = int.tryParse(matches.last.group(0) ?? '0') ?? 0;
            if (tagNum > remoteBuild) {
              remoteBuild = tagNum;
              remoteVersion = tagName;
            }
          }
          final List assets = (relData['assets'] as List?) ?? [];
          for (final asset in assets) {
            final String name = (asset['name'] ?? '').toString();
            final String dl = (asset['browser_download_url'] ?? '').toString();
            if (name.endsWith('.apk') && dl.startsWith('http')) {
              apkDownloadUrl = dl;
              break;
            }
          }
        }
      } catch (_) {}

      if (remoteBuild > currentBuildNumber &&
          apkDownloadUrl != null &&
          apkDownloadUrl.startsWith('http') &&
          (forceManualCheck || remoteBuild > lastInstalledAttempt)) {
        otaStatusBanner.value = '⚡ New Update v$remoteVersion Found! Auto-Downloading...';
        await _downloadAndInstallApkSilently(apkDownloadUrl, remoteBuild, remoteVersion);
      } else if (forceManualCheck) {
        otaStatusBanner.value = '✅ App is on Latest Version (v$currentVersionName Build $currentBuildNumber)';
      }
    } catch (_) {
    } finally {
      _isCheckingOrDownloading = false;
    }
  }

  static Future<void> _downloadAndInstallApkSilently(
    String apkUrl,
    int targetBuild,
    String targetVersion,
  ) async {
    try {
      otaDownloadProgress.value = 0.02;
      final client = http.Client();
      final req = http.Request('GET', Uri.parse(apkUrl));
      req.headers['User-Agent'] = 'Mozilla/5.0 (Linux; Android 14) DJPlayerOTA/500.0';
      final http.StreamedResponse response = await client.send(req).timeout(const Duration(seconds: 25));

      if (response.statusCode != 200) {
        otaDownloadProgress.value = null;
        client.close();
        return;
      }

      final int totalBytes = response.contentLength ?? 22000000;
      int receivedBytes = 0;

      final Directory dir = await getTemporaryDirectory();
      final File apkFile = File('${dir.path}/dj_player_ota_update_$targetBuild.apk');
      if (await apkFile.exists()) {
        await apkFile.delete();
      }
      final IOSink sink = apkFile.openWrite();

      await for (final List<int> chunk in response.stream) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        final double pct = (receivedBytes / totalBytes).clamp(0.05, 0.99);
        otaDownloadProgress.value = pct;
        otaStatusBanner.value =
            '⚡ Auto-Updating to v$targetVersion... ${(pct * 100).toInt()}%';
      }

      await sink.flush();
      await sink.close();
      client.close();

      if (await apkFile.exists() && await apkFile.length() > 3000000) {
        otaDownloadProgress.value = 1.0;
        otaStatusBanner.value = '🚀 Installing Update v$targetVersion Automatically...';
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('v500_last_ota_attempt_build', targetBuild);
        await _nativeChannel.invokeMethod('installApkOta', {'path': apkFile.path});
      }
    } catch (_) {
    } finally {
      Future.delayed(const Duration(seconds: 3), () {
        otaDownloadProgress.value = null;
      });
    }
  }
}
