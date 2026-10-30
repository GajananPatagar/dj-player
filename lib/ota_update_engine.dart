import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OtaUpdateEngine {
  static const int currentBuildNumber = 505;
  static const String currentVersionName = '505.0.0';
  static const String githubRepoOwner = 'GajananPatagar';
  static const String githubRepoName = 'dj-player';

  static const MethodChannel _nativeChannel = MethodChannel('dj_native_tts');

  static final ValueNotifier<String> otaStatusBanner = ValueNotifier<String>(
    '✨ v505.0 Ultra Pro • Auto-OTA & Daily Self-Update Active',
  );
  static final ValueNotifier<double?> otaDownloadProgress = ValueNotifier<double?>(null);
  static final ValueNotifier<String> dailyRefreshStamp = ValueNotifier<String>('');

  static Timer? _periodicTimer;
  static bool _isCheckingOrDownloading = false;

  static Future<void> initAutoOtaAndDailySelfUpdate({
    required Future<void> Function() onDailyContentRefresh,
  }) async {
    await _checkAndRunDailySelfUpdate(onDailyContentRefresh);
    Future.delayed(const Duration(seconds: 4), () {
      checkAndAutoInstallOtaUpdate();
    });

    _periodicTimer?.cancel();
    _periodicTimer = Timer.periodic(const Duration(hours: 2), (_) async {
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
      final String lastUpdatedDay = prefs.getString('v505_last_daily_self_update') ?? '';
      dailyRefreshStamp.value = 'Synced $today';

      if (lastUpdatedDay != today) {
        otaStatusBanner.value = '🔄 Daily Self-Update: Refreshing $today New Songs & Mixes...';
        await onDailyContentRefresh();
        await prefs.setString('v505_last_daily_self_update', today);
        otaStatusBanner.value = '🟢 Auto-Updated for $today • v$currentVersionName Pro';
      }
    } catch (_) {}
  }

  /// Zero-Button OTA Update Check:
  /// Automatically downloads & installs whenever GitHub has a newer buildNumber than currentBuildNumber.
  static Future<void> checkAndAutoInstallOtaUpdate({bool forceManualCheck = false}) async {
    if (_isCheckingOrDownloading) return;
    _isCheckingOrDownloading = true;

    try {
      int remoteBuild = currentBuildNumber;
      String remoteVersion = currentVersionName;
      String? apkDownloadUrl;

      final Map<String, String> headers = {
        'User-Agent': 'DJPlayer-OTA-Updater/505.0 (Android)',
        'Accept': 'application/json',
        'Cache-Control': 'no-cache',
      };

      // 1. Check raw ota_version.json on GitHub main branch
      try {
        final String rawVersionUrl =
            'https://raw.githubusercontent.com/$githubRepoOwner/$githubRepoName/main/ota_version.json?t=${DateTime.now().millisecondsSinceEpoch}';
        final res = await http.get(Uri.parse(rawVersionUrl), headers: headers).timeout(const Duration(seconds: 7));
        if (res.statusCode == 200) {
          final Map<String, dynamic> data = jsonDecode(res.body);
          remoteBuild = int.tryParse((data['buildNumber'] ?? currentBuildNumber).toString()) ?? currentBuildNumber;
          remoteVersion = (data['versionName'] ?? currentVersionName).toString();
          apkDownloadUrl = data['apkUrl']?.toString();
        }
      } catch (_) {}

      // 2. Also check GitHub Releases Latest API
      try {
        final String relUrl = 'https://api.github.com/repos/$githubRepoOwner/$githubRepoName/releases/latest';
        final relRes = await http.get(Uri.parse(relUrl), headers: headers).timeout(const Duration(seconds: 7));
        if (relRes.statusCode == 200) {
          final Map<String, dynamic> relData = jsonDecode(relRes.body);
          final String tagName = (relData['tag_name'] ?? '').toString();
          final RegExp numReg = RegExp(r'(\d+)');
          final Iterable<Match> matches = numReg.allMatches(tagName);
          if (matches.isNotEmpty) {
            final int firstNum = int.tryParse(matches.first.group(0) ?? '0') ?? 0;
            if (firstNum > remoteBuild) {
              remoteBuild = firstNum;
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
          apkDownloadUrl.startsWith('http')) {
        otaStatusBanner.value = '⚡ New Update v$remoteVersion Found! Auto-Downloading...';
        await _downloadAndInstallApkSilently(apkDownloadUrl, remoteBuild, remoteVersion);
      } else if (forceManualCheck) {
        otaStatusBanner.value = '✅ Latest Version Active (v$currentVersionName Build $currentBuildNumber)';
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
      req.headers['User-Agent'] = 'Mozilla/5.0 (Linux; Android 14) DJPlayerOTA/505.0';
      final http.StreamedResponse response = await client.send(req).timeout(const Duration(seconds: 30));

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
