import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/app_data.dart';
import '../config/app_config.dart' show AppEnvConfig;
import 'prefs_helper.dart';

class ApiService {
  // ─────────────────────────────────────────────────
  // MASTER CONFIG
  // ─────────────────────────────────────────────────

  Future<AppConfig> loadMasterConfig() async {
    final cleared = await PrefsHelper.clearCacheIfAppChanged(AppEnvConfig.appUniqueId);
    if (cleared) debugPrint('ApiService: App changed — cache cleared');

    if (AppEnvConfig.masterUrl.isEmpty) {
      return AppConfig.defaults();
    }

    final cached = await PrefsHelper.getMasterConfigCache();
    if (cached != null) {
      final config = _parseMasterConfig(cached);
      if (config != null) {
        _refreshMasterInBackground();
        return config;
      }
    }

    debugPrint('ApiService: No master cache, fetching...');
    final config = await _fetchMaster();
    return config ?? _localConfig();
  }

  /// ローカル固定値からAppConfigを生成（GAS不要・即時利用可能）
  AppConfig _localConfig() => AppConfig(
    saleEnabled: false,
    adBannerId: AppEnvConfig.iosBannerId,
    adInterstitialId: AppEnvConfig.iosInterId,
    appTitle: AppEnvConfig.appName,
    nextAppText: '',
    nextAppUrl: '',
    regularPrice: 390,
    salePrice: 190,
    nextAppEnabled: false,
    premiumProductId: AppEnvConfig.iosPurchaseId,
    platformAppId: '',
    appId: AppEnvConfig.appUniqueId,
    questionsUrl: AppEnvConfig.questionsUrl,
    githubRepo: '',
  );

  AppConfig? _parseMasterConfig(String jsonStr) {
    try {
      final decoded = json.decode(jsonStr) as Map<String, dynamic>;

      // 新フォーマット: config fields directly
      if (decoded.containsKey('app_id') || decoded.containsKey('app_name')) {
        return AppConfig.fromJson(decoded);
      }

      // 旧フォーマット: { question_bundle, spreadsheet_data }
      if (decoded.containsKey('spreadsheet_data')) {
        final spreadsheet = decoded['spreadsheet_data'] as Map<String, dynamic>;
        final masterRows = spreadsheet['master'] as List<dynamic>?;
        if (masterRows != null && masterRows.length >= 3) {
          final fieldNames = (masterRows[1] as List).map((e) => e.toString()).toList();
          final idCol = fieldNames.indexOf('app_unique_id');
          List<dynamic>? dataRow;
          for (int i = 2; i < masterRows.length; i++) {
            final row = masterRows[i] as List;
            if (idCol >= 0 && row[idCol].toString() == AppEnvConfig.appUniqueId) {
              dataRow = row;
              break;
            }
          }
          dataRow ??= masterRows[2] as List;
          final configMap = <String, dynamic>{};
          for (int i = 0; i < fieldNames.length && i < dataRow.length; i++) {
            configMap[fieldNames[i]] = dataRow[i];
          }
          // フィールド名マッピング（スプレッドシート列名→AppConfig JSONキー）
          final mapped = {
            'app_id':              configMap['app_id'],
            'app_name':            configMap['app_name'],
            'ios_ad_banner':       configMap['ios_banner_ad_id'],
            'ios_ad_inter':        configMap['ios_interstitial_ad_id'],
            'ios_premium_id':      configMap['ios_purchase_id'],
            'android_ad_banner':   configMap['android_banner_ad_id'],
            'android_ad_inter':    configMap['android_interstitial_ad_id'],
            'android_premium_id':  configMap['android_purchase_id'],
            // 問題GASのURLをquestionsUrlとして設定
            'questions_url':       AppEnvConfig.questionsUrl,
            'sale_enabled':        false,
            'regular_price':       390,
            'sale_price':          190,
            'next_app_enabled':    false,
          };
          return AppConfig.fromJson(mapped);
        }
      }

      return null;
    } catch (e) {
      debugPrint('ApiService: Master config parse error — $e');
      return null;
    }
  }

  Future<AppConfig?> _fetchMaster() async {
    try {
      final url = Uri.parse(AppEnvConfig.masterUrl);
      final response = await http.get(url).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final config = _parseMasterConfig(response.body);
        if (config != null) {
          await PrefsHelper.saveMasterConfigCache(response.body);
          debugPrint('ApiService: Master config fetched and cached');
          return config;
        }
      }
    } catch (e) {
      debugPrint('ApiService: Master fetch failed — $e');
    }
    return null;
  }

  void _refreshMasterInBackground() {
    _fetchMaster();
  }

  // ─────────────────────────────────────────────────
  // QUESTIONS
  // ─────────────────────────────────────────────────

  Future<AppData?> loadFromCacheOrFallback(AppConfig masterConfig) async {
    // 1. キャッシュ
    final cachedJson = await PrefsHelper.getAppDataCache();
    if (cachedJson != null) {
      final data = _parseAppData(cachedJson, masterConfig);
      if (data != null) return data;
    }

    // 2. バンドルアセット
    for (final path in ['assets/fallback_data.json', 'assets/initial_data.json']) {
      try {
        final assetStr = await rootBundle.loadString(path);
        final data = _parseAppData(assetStr, masterConfig);
        if (data != null) {
          debugPrint('ApiService: Loaded from asset: $path');
          return data;
        }
      } catch (_) {}
    }

    // 3. GASから取得
    final url = masterConfig.questionsUrl.isNotEmpty
        ? masterConfig.questionsUrl
        : AppEnvConfig.questionsUrl;
    if (url.isNotEmpty) {
      return await _fetchQuestions(url, masterConfig);
    }

    return null;
  }

  /// バックグラウンドで問題を更新（次回起動に反映）
  void refreshInBackground(AppConfig masterConfig) {
    final url = masterConfig.questionsUrl.isNotEmpty
        ? masterConfig.questionsUrl
        : AppEnvConfig.questionsUrl;
    if (url.isNotEmpty) {
      _fetchAndCache(url, masterConfig);
    }
  }

  AppData? _parseAppData(String jsonStr, AppConfig masterConfig) {
    try {
      final decoded = json.decode(jsonStr) as Map<String, dynamic>;
      if (decoded.containsKey('error')) return null;

      // 旧フォーマット: { question_bundle: {..., questions: [...]} }
      if (decoded.containsKey('question_bundle')) {
        final bundle = decoded['question_bundle'] as Map<String, dynamic>;
        if (bundle.containsKey('questions')) {
          final data = AppData.fromQuestionsJson(bundle, masterConfig);
          if (data.questions.isNotEmpty) return data;
        }
      }

      // 旧フォーマット: { config, questions }
      if (decoded.containsKey('config')) {
        final data = AppData.fromJson(decoded);
        if (data.questions.isNotEmpty) return data;
      }

      // 新フォーマット: { questions: [...] }
      if (decoded.containsKey('questions')) {
        final data = AppData.fromQuestionsJson(decoded, masterConfig);
        if (data.questions.isNotEmpty) return data;
      }

      return null;
    } catch (e) {
      debugPrint('ApiService: Questions parse error — $e');
      return null;
    }
  }

  Future<AppData?> _fetchQuestions(String urlStr, AppConfig masterConfig) async {
    try {
      final response = await http.get(Uri.parse(urlStr)).timeout(const Duration(seconds: 20));
      if (response.statusCode == 200) {
        final data = _parseAppData(response.body, masterConfig);
        if (data != null) {
          await PrefsHelper.saveAppDataCache(response.body);
          debugPrint('ApiService: Questions fetched from GAS');
          return data;
        }
      }
    } catch (e) {
      debugPrint('ApiService: Questions fetch failed — $e');
    }
    return null;
  }

  Future<void> _fetchAndCache(String urlStr, AppConfig masterConfig) async {
    try {
      final response = await http.get(Uri.parse(urlStr)).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final data = _parseAppData(response.body, masterConfig);
        if (data != null) {
          await PrefsHelper.saveAppDataCache(response.body);
          debugPrint('ApiService: Background refresh successful');
        }
      }
    } catch (e) {
      debugPrint('ApiService: Background refresh failed — $e');
    }
  }
}
