import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'entry_music_data.dart';
import 'monetization_and_ads_engine.dart';

/// Loop-Free Smart OTA & Live Monetization Config Engine (v10000.0):
class OtaUpdateEngine {
  static const int currentBuildNumber = 10000016;
  static const String currentVersionName = '15.0.0';
  static const String githubRepoOwner = 'GajananPatagar';
  static const String githubRepoName = 'dj-player';

  static const MethodChannel _nativeChannel = MethodChannel('dj_native_tts');

  static final ValueNotifier<String> otaStatusBanner = ValueNotifier<String>(
    '✨ IMS v15.0.0 Pro • AdSense 1-Hr VIP, 18-Bit Encryption & 320K Master Active',
  );
  static final ValueNotifier<double?> otaDownloadProgress = ValueNotifier<double?>(null);
  static final ValueNotifier<String> dailyRefreshStamp = ValueNotifier<String>('');

  /// Controlled live from `ims_live_ota.json` on GitHub (Never displayed in UI!)
  static final ValueNotifier<String> remoteOtaPin = ValueNotifier<String>('1681');
  static final ValueNotifier<int> remoteRelockToken = ValueNotifier<int>(1);
  static final ValueNotifier<List<String>> remoteTrendingQueries = ValueNotifier<List<String>>([]);

  /// Live Monetization & Sponsor Parameters (Controlled remotely from `ims_live_ota.json`)
  static final ValueNotifier<String> merchantUpiId = ValueNotifier<String>('9483776820@ybl');
  static final ValueNotifier<String> merchantWhatsapp = ValueNotifier<String>('919483776820');
  static final ValueNotifier<String> sponsorBannerTitle = ValueNotifier<String>(
    '🔊 Inchara Master Sounds • Pro DJ & Stage Audio (Sirsi)',
  );
  static final ValueNotifier<String> sponsorBannerSub = ValueNotifier<String>(
    'Tap to Book Fire 57 & S8118 Pro Sound or Upgrade to VIP Ad-Free!',
  );
  static final ValueNotifier<String> sponsorActionUrl = ValueNotifier<String>(
    'https://wa.me/919483776820?text=Hi%20Inchara%20Master%20Sounds%2C%20I%20saw%20your%20ad%20in%20IMS%20Pro%20Studio!',
  );

  static Timer? _periodicTimer;
  static bool _isCheckingOrDownloading = false;

  static Future<void> initAutoOtaAndDailySelfUpdate({
    required Future<void> Function() onDailyContentRefresh,
  }) async {
    await syncInAppLiveCloudOta(onContentRefresh: onDailyContentRefresh, forceRefresh: false);
    await _checkAndRunDailySelfUpdate(onDailyContentRefresh);

    Future.delayed(const Duration(seconds: 3), () {
      checkAndAutoInstallOtaUpdate(forceManualCheck: false);
    });

    _periodicTimer?.cancel();
    _periodicTimer = Timer.periodic(const Duration(hours: 1), (_) async {
      await syncInAppLiveCloudOta(onContentRefresh: onDailyContentRefresh, forceRefresh: false);
      await _checkAndRunDailySelfUpdate(onDailyContentRefresh);
      await checkAndAutoInstallOtaUpdate(forceManualCheck: false);
    });
  }

  static String _todayDateKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  static Future<bool> syncInAppLiveCloudOta({
    Future<void> Function()? onContentRefresh,
    bool forceRefresh = false,
  }) async {
    try {
      final Map<String, String> headers = {
        'User-Agent': 'IMS-InApp-OTA/10000.0 (Android)',
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

        final String? pin = (data['activationPin'] ?? data['defaultActivationPin'])?.toString();
        if (pin != null && pin.trim().isNotEmpty) {
          remoteOtaPin.value = pin.trim();
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('ims_cached_ota_pin_v650', pin.trim());
        }

        final int? relockTok = int.tryParse((data['forceRelockToken'] ?? '1').toString());
        if (relockTok != null) {
          remoteRelockToken.value = relockTok;
        }

        if (data['merchantUpiId'] != null && data['merchantUpiId'].toString().trim().isNotEmpty) {
          merchantUpiId.value = data['merchantUpiId'].toString().trim();
        }
        if (data['merchantWhatsapp'] != null && data['merchantWhatsapp'].toString().trim().isNotEmpty) {
          merchantWhatsapp.value = data['merchantWhatsapp'].toString().trim();
        }
        if (data['sponsorBannerTitle'] != null && data['sponsorBannerTitle'].toString().trim().isNotEmpty) {
          sponsorBannerTitle.value = data['sponsorBannerTitle'].toString().trim();
        }
        if (data['sponsorBannerSub'] != null && data['sponsorBannerSub'].toString().trim().isNotEmpty) {
          sponsorBannerSub.value = data['sponsorBannerSub'].toString().trim();
        }
        if (data['sponsorActionUrl'] != null && data['sponsorActionUrl'].toString().trim().isNotEmpty) {
          sponsorActionUrl.value = data['sponsorActionUrl'].toString().trim();
        }

        if (data['admobBannerUnitId'] != null && data['admobBannerUnitId'].toString().trim().isNotEmpty) {
          ImsMonetizationEngine.bannerAdUnitId = data['admobBannerUnitId'].toString().trim();
        }
        if (data['admobInterstitialUnitId'] != null && data['admobInterstitialUnitId'].toString().trim().isNotEmpty) {
          ImsMonetizationEngine.interstitialAdUnitId = data['admobInterstitialUnitId'].toString().trim();
        }
        if (data['admobRewardedUnitId'] != null && data['admobRewardedUnitId'].toString().trim().isNotEmpty) {
          ImsMonetizationEngine.rewardedAdUnitId = data['admobRewardedUnitId'].toString().trim();
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
          otaStatusBanner.value = '✅ IMS Cloud Synced Live (${data['versionLabel'] ?? 'IMS v10000 Pro'})';
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
      final String lastUpdatedDay = prefs.getString('v10000_last_daily_self_update') ?? '';
      dailyRefreshStamp.value = 'Synced $today';

      if (lastUpdatedDay != today) {
        await onDailyContentRefresh();
        await prefs.setString('v10000_last_daily_self_update', today);
        otaStatusBanner.value = '🟢 Auto-Updated for $today • IMS v$currentVersionName Pro';
      }
    } catch (_) {}
  }

  static Future<bool> checkAndAutoInstallOtaUpdate({
    bool forceManualCheck = false,
    void Function(String statusText, double? progress)? onProgressCallback,
  }) async {
    if (_isCheckingOrDownloading) return false;
    _isCheckingOrDownloading = true;

    try {
      onProgressCallback?.call('🔍 Checking IMS Cloud OTA...', null);
      await syncInAppLiveCloudOta(forceRefresh: forceManualCheck);

      final prefs = await SharedPreferences.getInstance();
      final int alreadyAttemptedBuild = prefs.getInt('ims_ota_attempted_build_v10000') ?? currentBuildNumber;

      int remoteBuild = currentBuildNumber;
      String remoteVersion = currentVersionName;
      String? apkDownloadUrl;

      final Map<String, String> headers = {
        'User-Agent': 'IMS-OTA-Updater/10000.0 (Android)',
        'Accept': 'application/json',
        'Cache-Control': 'no-cache',
      };

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

      final bool shouldTriggerApk = remoteBuild > currentBuildNumber &&
          apkDownloadUrl != null &&
          apkDownloadUrl.startsWith('http') &&
          (forceManualCheck || remoteBuild > alreadyAttemptedBuild);

      if (shouldTriggerApk) {
        otaStatusBanner.value = '⚡ Downloading IMS v$remoteVersion Update...';
        onProgressCallback?.call('⚡ Downloading IMS v$remoteVersion Update...', 0.05);
        final bool installed = await _downloadAndInstallApkOnce(
          apkDownloadUrl,
          remoteBuild,
          remoteVersion,
          onProgressCallback: onProgressCallback,
        );
        return installed;
      } else {
        onProgressCallback?.call('✅ IMS v$currentVersionName is Up-To-Date', 1.0);
        if (forceManualCheck) {
          otaStatusBanner.value = '✅ Up-To-Date (IMS v$currentVersionName Build $currentBuildNumber)';
        }
      }
    } catch (_) {
    } finally {
      _isCheckingOrDownloading = false;
    }
    return false;
  }

  static Future<bool> _downloadAndInstallApkOnce(
    String apkUrl,
    int targetBuild,
    String targetVersion, {
    void Function(String statusText, double? progress)? onProgressCallback,
  }) async {
    try {
      otaDownloadProgress.value = 0.02;
      final client = http.Client();
      final req = http.Request('GET', Uri.parse(apkUrl));
      req.headers['User-Agent'] = 'Mozilla/5.0 (Linux; Android 14) IMS-OTA/10000.0';
      final http.StreamedResponse response = await client.send(req).timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        otaDownloadProgress.value = null;
        otaStatusBanner.value = '⏳ IMS v$targetVersion Cloud Build Preparing...';
        client.close();
        return false;
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
        final String msg = '⚡ Updating IMS v$targetVersion... ${(pct * 100).toInt()}%';
        otaStatusBanner.value = msg;
        onProgressCallback?.call(msg, pct);
      }

      await sink.flush();
      await sink.close();
      client.close();

      if (await apkFile.exists() && await apkFile.length() > 3000000) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('ims_ota_attempted_build_v10000', targetBuild);
        otaDownloadProgress.value = null;
        otaStatusBanner.value = '✅ IMS v$targetVersion Ready — Installing...';
        await _nativeChannel.invokeMethod('installApkOta', {'path': apkFile.path});
        return true;
      }
    } catch (_) {
    } finally {
      otaDownloadProgress.value = null;
    }
    return false;
  }
}

