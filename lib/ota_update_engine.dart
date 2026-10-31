import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'entry_music_data.dart';

/// 100% Pure In-App Cloud OTA Engine:
/// Updates songs, categories, PIN, and studio config silently inside the app via JSON (`ims_live_ota.json`).
/// NEVER downloads `.apk` files and NEVER opens the Android "Open with / Install APK" popup!
class OtaUpdateEngine {
  static const int currentBuildNumber = 700;
  static const String currentVersionName = 'IMS Pro';
  static const String githubRepoOwner = 'GajananPatagar';
  static const String githubRepoName = 'dj-player';

  static final ValueNotifier<String> otaStatusBanner = ValueNotifier<String>(
    '✨ IMS Pro Studio • 320kbps Original Master & Live Cloud Active',
  );
  static final ValueNotifier<double?> otaDownloadProgress = ValueNotifier<double?>(null);
  static final ValueNotifier<String> dailyRefreshStamp = ValueNotifier<String>('');

  /// Controlled live from `ims_live_ota.json` on GitHub (Never displayed in UI!)
  static final ValueNotifier<String> remoteOtaPin = ValueNotifier<String>('1681');
  static final ValueNotifier<int> remoteRelockToken = ValueNotifier<int>(1);
  static final ValueNotifier<List<String>> remoteTrendingQueries = ValueNotifier<List<String>>([]);

  static Timer? _periodicTimer;
  static bool _isSyncing = false;

  /// Starts silent In-App Cloud OTA & Daily Self-Update (100% inside the app, 0 popups, 0 APK installs!)
  static Future<void> initAutoOtaAndDailySelfUpdate({
    required Future<void> Function() onDailyContentRefresh,
  }) async {
    await syncInAppLiveCloudOta(onContentRefresh: onDailyContentRefresh, forceRefresh: false);
    await _checkAndRunDailySelfUpdate(onDailyContentRefresh);

    _periodicTimer?.cancel();
    _periodicTimer = Timer.periodic(const Duration(hours: 2), (_) async {
      await syncInAppLiveCloudOta(onContentRefresh: onDailyContentRefresh, forceRefresh: false);
      await _checkAndRunDailySelfUpdate(onDailyContentRefresh);
    });
  }

  static String _todayDateKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  /// Syncs `ims_live_ota.json` silently inside the app (Never downloads an APK or asks for permissions!)
  static Future<bool> syncInAppLiveCloudOta({
    Future<void> Function()? onContentRefresh,
    bool forceRefresh = false,
  }) async {
    if (_isSyncing) return false;
    _isSyncing = true;
    try {
      final Map<String, String> headers = {
        'User-Agent': 'IMS-InApp-OTA/700.0 (Android)',
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
          otaStatusBanner.value = '✅ IMS Cloud Synced Live • 320kbps Master Ready';
        } else if (oldHash.isEmpty) {
          await prefs.setString('ims_live_ota_hash', newHash);
        }
        return true;
      }
    } catch (_) {
    } finally {
      _isSyncing = false;
    }
    return false;
  }

  static Future<void> _checkAndRunDailySelfUpdate(
    Future<void> Function() onDailyContentRefresh,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String today = _todayDateKey();
      final String lastUpdatedDay = prefs.getString('v700_last_daily_self_update') ?? '';
      dailyRefreshStamp.value = 'Synced $today';

      if (lastUpdatedDay != today) {
        await onDailyContentRefresh();
        await prefs.setString('v700_last_daily_self_update', today);
        otaStatusBanner.value = '🟢 Daily Auto-Updated ($today) • IMS Pro Studio';
      }
    } catch (_) {}
  }

  /// Silent In-App Cloud Check Only (Never downloads or launches any external .apk installer!)
  static Future<bool> checkAndAutoInstallOtaUpdate({
    bool forceManualCheck = false,
    void Function(String statusText, double? progress)? onProgressCallback,
  }) async {
    onProgressCallback?.call('🔄 Syncing IMS Live Cloud Configuration...', null);
    await syncInAppLiveCloudOta(forceRefresh: forceManualCheck);
    onProgressCallback?.call('✅ IMS Cloud Synced & Ready', 1.0);
    return false;
  }
}
