import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/app_data.dart';
import 'prefs_helper.dart';
import '../config/gas_config.dart';

class ApiService {
  static String get _baseUrl => GasConfig.baseUrl;

  AppData? _parseUsableAppData(String jsonString, String appId) {
    try {
      final decoded = json.decode(jsonString) as Map<String, dynamic>;
      if (decoded.containsKey('error')) {
        debugPrint('ApiService: API returned error for $appId: ${decoded['error']}');
        return null;
      }

      final appData = AppData.fromJson(decoded);
      if (appData.config.appId.isNotEmpty && appData.config.appId != appId) {
        debugPrint(
          'ApiService: App id mismatch. expected=$appId actual=${appData.config.appId}',
        );
        return null;
      }
      if (appData.questions.isEmpty) {
        debugPrint('ApiService: Empty question set for $appId');
        return null;
      }
      return appData;
    } catch (e) {
      debugPrint('ApiService: Parse error - $e');
      return null;
    }
  }

  // キャッシュ優先で即座に返す（asset→ネットワーク順にフォールバック）
  Future<AppData?> loadFromCacheOrFallback(String appId) async {
    // 1. Try cache
    final cachedJson = await PrefsHelper.getAppDataCache();
    if (cachedJson != null) {
      final data = _parseUsableAppData(cachedJson, appId);
      if (data != null) return data;
      debugPrint('ApiService: Cache invalid, trying asset fallback');
    }

    // 2. Try bundled asset (fallback_data.json or initial_data.json)
    for (final path in ['assets/fallback_data.json', 'assets/initial_data.json']) {
      try {
        final assetString = await rootBundle.loadString(path);
        final data = _parseUsableAppData(assetString, appId);
        if (data != null) {
          if (kDebugMode) debugPrint('ApiService: Loaded from asset: $path');
          return data;
        }
      } catch (_) {}
    }

    // 3. Last resort: synchronous network fetch
    debugPrint('ApiService: No cache/asset available, fetching from network for $appId');
    try {
      final url = Uri.parse('$_baseUrl?id=$appId');
      final response = await http.get(url).timeout(const Duration(seconds: 20));
      if (response.statusCode == 200) {
        final data = _parseUsableAppData(response.body, appId);
        if (data != null) {
          await PrefsHelper.saveAppDataCache(response.body);
          debugPrint('ApiService: Network fetch successful for $appId');
          return data;
        }
      }
    } catch (e) {
      debugPrint('ApiService: Network fetch failed - $e');
    }

    return null;
  }

  // バックグラウンドでGASから取得しキャッシュを更新（次回起動に反映）
  void refreshInBackground(String appId) {
    _fetchAndCache(appId);
  }

  Future<void> _fetchAndCache(String appId) async {
    try {
      final url = Uri.parse('$_baseUrl?id=$appId');
      final response = await http.get(url).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final data = _parseUsableAppData(response.body, appId);
        if (data != null) {
          await PrefsHelper.saveAppDataCache(response.body);
          debugPrint('ApiService: Background refresh successful');
        } else {
          debugPrint('ApiService: Background refresh returned invalid data, cache not updated');
        }
      }
    } catch (e) {
      debugPrint('ApiService: Background refresh failed - $e');
    }
  }
}
