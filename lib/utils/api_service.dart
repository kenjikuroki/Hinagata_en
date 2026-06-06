import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/app_data.dart';
import '../config/app_config.dart' show AppEnvConfig;
import 'prefs_helper.dart';

class ApiService {
  // ─────────────────────────────────────────────────
  // MASTER CONFIG (GAS or any HTTPS endpoint)
  // ─────────────────────────────────────────────────

  /// Load master config.
  /// Priority: local cache → fetch from masterUrl.
  /// After returning cached value, silently re-fetches in background.
  Future<AppConfig> loadMasterConfig() async {
    if (AppEnvConfig.masterUrl.isEmpty) {
      debugPrint('ApiService: No masterUrl set — template mode');
      return AppConfig.defaults();
    }

    // 1. Return cached immediately if available
    final cached = await PrefsHelper.getMasterConfigCache();
    if (cached != null) {
      final config = _parseMasterConfig(cached);
      if (config != null) {
        _refreshMasterInBackground();
        return config;
      }
    }

    // 2. No cache — fetch synchronously (first launch)
    debugPrint('ApiService: No master cache, fetching...');
    final config = await _fetchMaster();
    return config ?? AppConfig.defaults();
  }

  AppConfig? _parseMasterConfig(String jsonStr) {
    try {
      final decoded = json.decode(jsonStr) as Map<String, dynamic>;
      return AppConfig.fromJson(decoded);
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
  // QUESTIONS (GitHub raw JSON)
  // ─────────────────────────────────────────────────

  /// Load questions.
  /// Priority: local cache → bundled asset → GitHub fetch.
  Future<AppData?> loadFromCacheOrFallback(AppConfig masterConfig) async {
    // 1. Try questions cache
    final cachedJson = await PrefsHelper.getAppDataCache();
    if (cachedJson != null) {
      final data = _parseAppData(cachedJson, masterConfig);
      if (data != null) return data;
      debugPrint('ApiService: Questions cache invalid, trying fallback');
    }

    // 2. Try bundled asset
    for (final path in ['assets/fallback_data.json', 'assets/initial_data.json']) {
      try {
        final assetStr = await rootBundle.loadString(path);
        final data = _parseAppData(assetStr, masterConfig);
        if (data != null) {
          debugPrint('ApiService: Loaded questions from asset: $path');
          return data;
        }
      } catch (_) {}
    }

    // 3. Fetch from GitHub
    if (masterConfig.questionsUrl.isNotEmpty) {
      debugPrint('ApiService: Fetching questions from GitHub...');
      return await _fetchQuestionsFromGithub(masterConfig);
    }

    return null;
  }

  /// Background refresh: re-fetch questions from GitHub and update cache.
  /// New data is used on next launch.
  void refreshInBackground(AppConfig masterConfig) {
    if (masterConfig.questionsUrl.isNotEmpty) {
      _fetchAndCacheQuestions(masterConfig);
    }
  }

  AppData? _parseAppData(String jsonStr, AppConfig masterConfig) {
    try {
      final decoded = json.decode(jsonStr) as Map<String, dynamic>;
      if (decoded.containsKey('error')) return null;

      // Full format (has 'config' key) — backward compat with old GAS format
      if (decoded.containsKey('config')) {
        final data = AppData.fromJson(decoded);
        if (data.questions.isEmpty) return null;
        return data;
      }

      // Questions-only format (GitHub)
      if (decoded.containsKey('questions')) {
        final data = AppData.fromQuestionsJson(decoded, masterConfig);
        if (data.questions.isEmpty) return null;
        return data;
      }

      return null;
    } catch (e) {
      debugPrint('ApiService: Questions parse error — $e');
      return null;
    }
  }

  Future<AppData?> _fetchQuestionsFromGithub(AppConfig masterConfig) async {
    try {
      final url = Uri.parse(masterConfig.questionsUrl);
      final response = await http.get(url).timeout(const Duration(seconds: 20));
      if (response.statusCode == 200) {
        final data = _parseAppData(response.body, masterConfig);
        if (data != null) {
          await PrefsHelper.saveAppDataCache(response.body);
          debugPrint('ApiService: Questions fetched from GitHub');
          return data;
        }
      }
    } catch (e) {
      debugPrint('ApiService: GitHub fetch failed — $e');
    }
    return null;
  }

  Future<void> _fetchAndCacheQuestions(AppConfig masterConfig) async {
    try {
      final url = Uri.parse(masterConfig.questionsUrl);
      final response = await http.get(url).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final data = _parseAppData(response.body, masterConfig);
        if (data != null) {
          await PrefsHelper.saveAppDataCache(response.body);
          debugPrint('ApiService: Background questions refresh successful');
        }
      }
    } catch (e) {
      debugPrint('ApiService: Background refresh failed — $e');
    }
  }
}
