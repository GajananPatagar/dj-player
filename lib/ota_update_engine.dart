import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'entry_music_data.dart';

class OtaUpdateEngine {
  static const int currentBuildNumber = 610;
  static const String currentVersionName = '610.0.0';
  static const String githubRepoOwner = 'GajananPatagar';
  static const String githubRepoName = 'dj-player';

  static const MethodChannel _nativeChannel = MethodChannel('dj_native_tts');

  static final ValueNotifier<String> otaStatusBanner = ValueNotifier<String>(
    '✨ IMS v610.0 Pro • In-App Auto-OTA & Daily Self-Update Active',
  );
  static final ValueNotifier<double?> otaDownloadProgress = ValueNotifier<double?>(null);
  static final ValueNotifier<String> dailyRefreshStamp = ValueNotifier<String>('');
  static final ValueNotifier<String> remoteDefaultPin = ValueNotifier<String>('1681');
  static final ValueNotifier<List<String>> remoteTrendingQueries = ValueNotifier<List<String>>([]);

  static Timer? _periodicTimer;
  static bool _isCheckingOrDownloading = false;

  /// Runs:
  /// 1) True In-App Cloud OTA Sync (ims_live_ota.json) — updates categories, songs, banners & rules 100% INSIDE the app with ZERO APK installer prompts!
  /// 2) Daily Self-Update — refreshes trending songs every calendar day automatically!
  static Future<void> initAutoOtaAndDailySelfUpdate({
    required Future<void> Function() onDailyContentRefresh,
  }) async {
    await syncInAppLiveCloudOta(onContentRefresh: onDailyContentRefresh, forceRefresh: false);
    await _checkAndRunDailySelfUpdate(onDailyContentRefresh);

    _periodicTimer?.cancel();
    _periodicTimer = Timer.periodic(const Duration(hours: 1), (_) async {
      await syncInAppLiveCloudOta(onContentRefresh: onDailyContentRefresh, forceRefresh: false);
      await _checkAndRunDailySelfUpdate(onDailyContentRefresh);
    });
  }

  static String _todayDateKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  /// TRUE IN-APP LIVE OTA ENGINE:
  /// Fetches `ims_live_ota.json` directly from GitHub and applies updates INSIDE the running app
  /// in 0.5 seconds — NO external APK package installer, NO "Allow Unknown Sources" popup!
  static Future<bool> syncInAppLiveCloudOta({
    Future<void> Function()? onContentRefresh,
    bool forceRefresh = false,
  }) async {
    try {
      final Map<String, String> headers = {
        'User-Agent': 'IMS-InApp-OTA/610.0 (Android)',
        'Accept': 'application/json',
        'Cache-Control': 'no-cache',
      };

      final String liveUrl =
          'https://raw.githubusercontent.com/$githubRepoOwner/$githubRepoName/main/ims_live_ota.json?t=${DateTime.now().millisecondsSinceEpoch}';
      final res = await http.get(Uri.parse(liveUrl), headers: headers).timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(res.body);

        // 1. Update Live Banner inside app
        final String? banner = data['liveAnnouncement']?.toString();
        if (banner != null && banner.trim().isNotEmpty) {
          otaStatusBanner.value = banner.trim();
        }

        // 2. Sync Remote Default Activation PIN if configured
        final String? pin = data['defaultActivationPin']?.toString();
        if (pin != null && pin.trim().length >= 4) {
          remoteDefaultPin.value = pin.trim();
        }

        // 3. Dynamically inject any new Offline Categories pushed via OTA!
        if (data['extraOfflineCategories'] is List) {
          for (final rawCat in (data['extraOfflineCategories'] as List)) {
            final String c = rawCat.toString().trim();
            if (c.isNotEmpty) {
              await VaultManager.addCustomCategory(c);
            }
          }
        }

        // 4. Sync Live Trending Boost Queries
        if (data['dailyTrendingBoostQueries'] is List) {
          remoteTrendingQueries.value =
              (data['dailyTrendingBoostQueries'] as List).map((e) => e.toString()).toList();
        }

        final prefs = await SharedPreferences.getInstance();
        final String newHash = res.body.hashCode.toString();
        final String oldHash = prefs.getString('ims_live_ota_hash') ?? '';
        if (forceRefresh || (oldHash.isNotEmpty && oldHash != newHash)) {
          await prefs.setString('ims_live_ota_hash', newHash);
          if (onContentRefresh != null) {
            await onContentRefresh();
          }
          otaStatusBanner.value = '✅ In-App OTA Synced Live (${data['versionLabel'] ?? 'IMS Pro'})!';
        } else if (oldHash.isEmpty) {
          await prefs.setString('ims_live_ota_hash', newHash);
        }
        return true;
      }
    } catch (_) {}
    return false;
  }

  static Future<void> _checkAndRunDailySelfUpdate(
    Future<void> Function() onDailyContentRefresh,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String today = _todayDateKey();
      final String lastUpdatedDay = prefs.getString('v610_last_daily_self_update') ?? '';
      dailyRefreshStamp.value = 'Synced $today';

      if (lastUpdatedDay != today) {
        otaStatusBanner.value = '🔄 Daily Self-Update: Refreshing $today New Songs & Mixes...';
        await onDailyContentRefresh();
        await prefs.setString('v610_last_daily_self_update', today);
        otaStatusBanner.value = '🟢 Auto-Updated for $today • IMS v$currentVersionName Pro';
      }
    } catch (_) {}
  }

  /// Optional Full Binary APK Updater (Only used when user explicitly requests Full Binary APK Upgrade or if native Kotlin code changed)
  static Future<void> checkAndAutoInstallOtaUpdate({bool forceManualCheck = false}) async {
    if (_isCheckingOrDownloading) return;
    _isCheckingOrDownloading = true;

    try {
      await syncInAppLiveCloudOta(forceRefresh: forceManualCheck);
      if (!forceManualCheck) {
        // By default, use 100% Silent In-App Cloud OTA so Android NEVER shows "Allow Unknown Sources" or APK install popups!
        _isCheckingOrDownloading = false;
        return;
      }

      int remoteBuild = currentBuildNumber;
      String remoteVersion = currentVersionName;
      String? apkDownloadUrl;

      final Map<String, String> headers = {
        'User-Agent': 'IMS-OTA-Updater/610.0 (Android)',
        'Accept': 'application/json',
        'Cache-Control': 'no-cache',
      };

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

      if (remoteBuild > currentBuildNumber &&
          apkDownloadUrl != null &&
          apkDownloadUrl.startsWith('http')) {
        otaStatusBanner.value = '⚡ Downloading IMS v$remoteVersion Binary Update...';
        await _downloadAndInstallApkSilently(apkDownloadUrl, remoteBuild, remoteVersion);
      } else {
        otaStatusBanner.value = '✅ In-App OTA Up-To-Date (IMS v$currentVersionName Build $currentBuildNumber)';
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
      req.headers['User-Agent'] = 'Mozilla/5.0 (Linux; Android 14) IMS-OTA/610.0';
      final http.StreamedResponse response = await client.send(req).timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        otaDownloadProgress.value = null;
        client.close();
        return;
      }

      final int totalBytes = response.contentLength ?? 22000000;
      int receivedBytes = 0;

      final Directory dir = await getTemporaryDirectory();
      final File apkFile = File('${dir.path}/ims_ota_update_$targetBuild.apk');
      if (await apkFile.exists()) {
        await apkFile.delete();
      }
      final IOSink sink = apkFile.openWrite();

      await for (final List<int> chunk in response.stream) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        final double pct = (receivedBytes / totalBytes).clamp(0.05, 0.99);
        otaDownloadProgress.value = pct;
        otaStatusBanner.value = '⚡ Updating IMS v$targetVersion... ${(pct * 100).toInt()}%';
      }

      await sink.flush();
      await sink.close();
      client.close();

      if (await apkFile.exists() && await apkFile.length() > 3000000) {
        otaDownloadProgress.value = 1.0;
        otaStatusBanner.value = '🚀 Launching IMS v$targetVersion Update...';
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
