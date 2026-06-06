class AppEnvConfig {
  /// ============================================================
  /// NEW APP SETUP: Change these 2 values when copying template
  /// ============================================================

  /// Master GAS URL (共通 — 変更不要)
  static const String _masterGasUrl =
      'https://script.google.com/macros/s/AKfycbz43Z0CrLEsjZWHERQRH_XA8zQzm7Ca0x9YVU1lRRB5TQir_7plJIdt1-Ry0MFiY4xrvw/exec';

  /// App unique ID — スプレッドシートの app_unique_id と一致させる
  static const String appUniqueId = 'APP0001';

  /// 結合URL（変更不要）
  static String get masterUrl => '$_masterGasUrl?id=$appUniqueId';
}
