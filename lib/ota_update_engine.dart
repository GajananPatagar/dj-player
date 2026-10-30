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
  static const int currentBuildNumber = 650;
  static const String currentVersionName = '650.0.0';
  static const String githubRepoOwner = 'GajananPatagar';
  static const String githubRepoName = 'dj-player';

  static const MethodChannel _nativeChannel = MethodChannel('dj_native_tts');

  static final ValueNotifier<String> otaStatusBanner = ValueNotifier<String>(
    '✨ IMS v650.0 Pro • Pure Original Master & Full Auto-OTA Active',
  );
  static final ValueNotifier<double?> otaDownloadProgress = ValueNotifier<double?>(null);
  static final ValueNotifier<String> dailyRefreshStamp = ValueNotifier<String>('');

  /// Controlled live from `ims_live_ota.json` on GitHub (Never displayed in UI!)
  static final ValueNotifier<String> remoteOtaPin = ValueNotifier<String>('1681');
  static final ValueNotifier<int> remoteRelockToken = ValueNotifier<int>(1);
  static final ValueNotifier<List<String>> remoteTrendingQueries = ValueNotifier<List<String>>([]);

  static Timer? _periodicTimer;
  static bool _isCheckingOrDownloading = false;

  /// Runs BOTH:
  /// 1) Live Cloud OTA Sync (`ims_live_ota.json`) — syncs remote OTA PIN, categories, announcements & song pools
  /// 2) Full Automatic Binary APK OTA (`ota_version.json` + GitHub Releases) — automatically downloads & updates the app whenever a new build is pushed!
  /// 3) Daily Self-Update — refreshes trending songs every calendar day automatically!
  static Future<void> initAutoOtaAndDailySelfUpdate({
    required Future<void> Function() onDailyContentRefresh,
  }) async {
    await syncInAppLiveCloudOta(onContentRefresh: onDailyContentRefresh, forceRefresh: false);
    await _checkAndRunDailySelfUpdate(onDailyContentRefresh);

    // Automatically check for new APK build 2 seconds after startup
    Future.delayed(const Duration(seconds: 2), () {
      checkAndAutoInstallOtaUpdate();
    });

    _periodicTimer?.cancel();
    _periodicTimer = Timer.periodic(const Duration(minutes: 30), (_) async {
      await syncInAppLiveCloudOta(onContentRefresh: onDailyContentRefresh, forceRefresh: false);
      await _checkAndRunDailySelfUpdate(onDailyContentRefresh);
      await checkAndAutoInstallOtaUpdate();
    });
  }

  static String _todayDateKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  /// Syncs `ims_live_ota.json` from GitHub (Controls remote PIN, remote relock token, live categories & announcements)
  static Future<bool> syncInAppLiveCloudOta({
    Future<void> Function()? onContentRefresh,
    bool forceRefresh = false,
  }) async {
    try {
      final Map<String, String> headers = {
        'User-Agent': 'IMS-InApp-OTA/650.0 (Android)',
        'Accept': 'application/json',
        'Cache-Control': 'no-cache',
      };

      final String liveUrl =
          'https://raw.githubusercontent.com/$githubRepoOwner/$githubRepoName/main/ims_live_ota.json?t=${DateTime.now().millisecondsSinceEpoch}';
      final res = await http.get(Uri.parse(liveUrl), headers: headers).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(res.body);

        final String? banner = data['liveAnnouncement']?.toString();
        if (banner != null && banner.trim().isNotEmpty) {
          otaStatusBanner.value = banner.trim();
        }

        // Sync OTA-controlled PIN (supports both 'activationPin' and 'defaultActivationPin' keys)
        final String? pin = (data['activationPin'] ?? data['defaultActivationPin'])?.toString();
        if (pin != null && pin.trim().isNotEmpty) {
          remoteOtaPin.value = pin.trim();
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('ims_cached_ota_pin_v650', pin.trim());
        }

        // Sync remote forceRelockToken so admin can remotely re-lock apps if needed
        final int? relockTok = int.tryParse((data['forceRelockToken'] ?? '1').toString());
        if (relockTok != null) {
          remoteRelockToken.value = relockTok;
        }

        if (data['extraOfflineCategories'] is List) {
          for (final rawCat in (data['extraOfflineCategories'] as List)) {
            final String c = rawCat.toString().trim();
            if (c.isNotEmpty) {
              await VaultManager.addCustomCategory(c);
            }
          }
        }

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
          otaStatusBanner.value = '✅ Live OTA Synced (${data['versionLabel'] ?? 'IMS Pro'})';
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
      final String lastUpdatedDay = prefs.getString('v650_last_daily_self_update') ?? '';
      dailyRefreshStamp.value = 'Synced $today';

      if (lastUpdatedDay != today) {
        otaStatusBanner.value = '🔄 Daily Self-Update: Refreshing $today New Songs & Mixes...';
        await onDailyContentRefresh();
        await prefs.setString('v650_last_daily_self_update', today);
        otaStatusBanner.value = '🟢 Auto-Updated for $today • IMS v$currentVersionName Pro';
      }
    } catch (_) {}
  }

  /// First-Time Install & Startup Automatic OTA Scanner:
  /// Checks `ota_version.json` AND GitHub Releases `latest`.
  /// Returns `true` if a newer APK build was found and started auto-updating!
  static Future<bool> checkAndAutoInstallOtaUpdate({
    bool forceManualCheck = false,
    void Function(String statusText, double? progress)? onProgressCallback,
  }) async {
    if (_isCheckingOrDownloading) return false;
    _isCheckingOrDownloading = true;

    try {
      onProgressCallback?.call('🔍 Scanning IMS OTA Server for Latest Version...', null);
      await syncInAppLiveCloudOta(forceRefresh: forceManualCheck);

      int remoteBuild = currentBuildNumber;
      String remoteVersion = currentVersionName;
      String? apkDownloadUrl;

      final Map<String, String> headers = {
        'User-Agent': 'IMS-OTA-Updater/650.0 (Android)',
        'Accept': 'application/json',
        'Cache-Control': 'no-cache',
      };

      // 1. Check raw ota_version.json on GitHub main branch
      try {
        final String rawVersionUrl =
            'https://raw.githubusercontent.com/$githubRepoOwner/$githubRepoName/main/ota_version.json?t=${DateTime.now().millisecondsSinceEpoch}';
        final res = await http.get(Uri.parse(rawVersionUrl), headers: headers).timeout(const Duration(seconds: 6));
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
        final relRes = await http.get(Uri.parse(relUrl), headers: headers).timeout(const Duration(seconds: 6));
        if (relRes.statusCode == 200) {
          final Map<String, dynamic> relData = jsonDecode(relRes.body);
          final String tagName = (relData['tag_name'] ?? '').toString();
          final RegExp numReg = RegExp(r'(\d+)');
          final Iterable<Match> matches = numReg.allMatches(tagName);
          if (matches.isNotEmpty) {
            final int firstNum = int.tryParse(matches.first.group(0) ?? '0') ?? 0;
            final int lastNum = int.tryParse(matches.last.group(0) ?? '0') ?? 0;
            final int candidateBuild = (firstNum >= 500 && matches.length > 1) ? (firstNum + lastNum) : firstNum;
            if (candidateBuild > remoteBuild) {
              remoteBuild = candidateBuild;
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
        otaStatusBanner.value = '⚡ New IMS Update v$remoteVersion Found! Auto-Updating...';
        onProgressCallback?.call('⚡ Downloading Latest IMS v$remoteVersion Update...', 0.05);
        await _downloadAndInstallApkSilently(
          apkDownloadUrl,
          remoteBuild,
          remoteVersion,
          onProgressCallback: onProgressCallback,
        );
        return true;
      } else {
        onProgressCallback?.call('✅ IMS is on the Latest Version (v$currentVersionName)', 1.0);
        if (forceManualCheck) {
          otaStatusBanner.value = '✅ Latest Version Active (IMS v$currentVersionName Build $currentBuildNumber)';
        }
      }
    } catch (_) {
    } finally {
      _isCheckingOrDownloading = false;
    }
    return false;
  }

  static Future<void> _downloadAndInstallApkSilently(
    String apkUrl,
    int targetBuild,
    String targetVersion, {
    void Function(String statusText, double? progress)? onProgressCallback,
  }) async {
    try {
      otaDownloadProgress.value = 0.02;
      final client = http.Client();
      final req = http.Request('GET', Uri.parse(apkUrl));
      req.headers['User-Agent'] = 'Mozilla/5.0 (Linux; Android 14) IMS-OTA/650.0';
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
        final String msg = '⚡ Auto-Updating IMS v$targetVersion... ${(pct * 100).toInt()}%';
        otaStatusBanner.value = msg;
        onProgressCallback?.call(msg, pct);
      }

      await sink.flush();
      await sink.close();
      client.close();

      if (await apkFile.exists() && await apkFile.length() > 3000000) {
        otaDownloadProgress.value = 1.0;
        otaStatusBanner.value = '🚀 Installing IMS v$targetVersion Update Automatically...';
        onProgressCallback?.call('🚀 Launching IMS v$targetVersion Update...', 1.0);
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
